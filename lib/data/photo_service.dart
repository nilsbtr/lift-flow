import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../domain/photos.dart';
import 'database.dart';
import 'photo_repository.dart';
import 'photo_storage.dart';

const int kPhotoArchiveVersion = 1;
const int kMaxPhotoArchiveBytes = 256 * 1024 * 1024;
const int _maxPhotoBytes = 25 * 1024 * 1024;
const _manifestName = 'photos.json';

class PhotoArchiveException implements Exception {
  const PhotoArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The extension for the image format [b] starts with, or null when it isn't
/// a JPEG, PNG or WebP.
String? imageExt(Uint8List b) {
  bool at(int i, List<int> magic) {
    if (b.length < i + magic.length) return false;
    for (var k = 0; k < magic.length; k++) {
      if (b[i + k] != magic[k]) return false;
    }
    return true;
  }

  if (at(0, [0xFF, 0xD8, 0xFF])) return 'jpg';
  if (at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) return 'png';
  if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
    return 'webp';
  }
  return null;
}

/// Progress photos as one unit: a row and its file are added and removed
/// together, and all photos can be exported to and merged from a zip archive.
///
/// The archive holds `photos.json` (app, version, and per photo the entry
/// name, UTC `takenAt` and `note`) next to the images in `photos/`. The JSON
/// backup knows nothing about photos.
class PhotoService {
  PhotoService(this._repo, this._storage);
  final PhotoRepository _repo;
  final PhotoStorage _storage;

  /// Stores [bytes] (an already downscaled image) as a photo taken at
  /// [takenAt], now by default and never later.
  Future<ProgressPhoto> add(
    Uint8List bytes, {
    DateTime? takenAt,
    String? note,
  }) async {
    final now = DateTime.now();
    final name = await _storage.save(bytes, ext: imageExt(bytes) ?? 'jpg');
    try {
      return await _repo.add(
        takenAt: takenAt == null || takenAt.isAfter(now) ? now : takenAt,
        fileName: name,
        note: note,
      );
    } catch (_) {
      await _storage.delete(name);
      rethrow;
    }
  }

  Future<void> remove(ProgressPhoto photo) async {
    await _repo.delete(photo.id);
    await _storage.delete(photo.fileName);
  }

  /// Rows and files, orphans included.
  Future<void> deleteAll() async {
    await _repo.deleteAll();
    await _storage.clear();
  }

  /// Deletes files no row points to, e.g. after a delete that was cut short.
  Future<int> sweep({Duration minAge = const Duration(minutes: 10)}) async =>
      _storage.prune({
        for (final p in await _repo.all()) p.fileName,
      }, minAge: minAge);

  // ------------------------------------------------------------- archive

  /// All photos with their dates and notes as a zip, oldest first. Rows whose
  /// file is gone are left out.
  Future<Uint8List> export() async {
    final day = DateFormat('yyyy-MM-dd');
    final files = <(String, Uint8List)>[];
    final entries = <Map<String, Object?>>[];
    for (final p in (await _repo.all()).reversed) {
      final bytes = await _storage.read(p.fileName);
      if (bytes == null) continue;
      final entry = 'photos/${day.format(p.takenAt)}_${p.fileName}';
      files.add((entry, bytes));
      entries.add({
        'file': entry,
        'takenAt': p.takenAt.toUtc().toIso8601String(),
        'note': p.note,
      });
    }
    if (files.isEmpty) {
      throw const PhotoArchiveException('There are no photos to export.');
    }
    return Isolate.run(
      _encoder({
        'app': 'lift_flow_photos',
        'version': kPhotoArchiveVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'photos': entries,
      }, files),
    );
  }

  // Static, so the isolate closures don't capture this (and the database).
  static Uint8List Function() _encoder(
    Map<String, Object?> manifest,
    List<(String, Uint8List)> files,
  ) => () {
    final zip = Archive()
      ..addFile(ArchiveFile.string(_manifestName, jsonEncode(manifest)));
    // Photos are compressed already.
    for (final (name, bytes) in files) {
      zip.addFile(ArchiveFile.noCompress(name, bytes.length, bytes));
    }
    return ZipEncoder().encodeBytes(zip);
  };

  static List<ParsedPhoto> Function() _parser(Uint8List bytes, DateTime now) =>
      () => parsePhotoArchive(bytes, now);

  /// Adds the photos of an archive that aren't here yet. A photo counts as
  /// present when a stored image has the very same bytes, whatever its date.
  Future<({int added, int skipped})> import(Uint8List bytes) async {
    if (bytes.length > kMaxPhotoArchiveBytes) {
      throw const PhotoArchiveException('Photo archive is too large.');
    }
    final parsed = await Isolate.run(_parser(bytes, DateTime.now()));

    final bySize = <int, List<String>>{};
    for (final p in await _repo.all()) {
      final size = await _storage.length(p.fileName);
      if (size != null) (bySize[size] ??= []).add(p.fileName);
    }
    Future<bool> present(Uint8List b) async {
      for (final name in bySize[b.length] ?? const <String>[]) {
        final other = await _storage.read(name);
        if (other != null && const ListEquality<int>().equals(other, b)) {
          return true;
        }
      }
      return false;
    }

    final saved = <String>[];
    final rows = <({DateTime takenAt, String fileName, String? note})>[];
    try {
      for (final p in parsed) {
        if (await present(p.bytes)) continue;
        final name = await _storage.save(p.bytes, ext: p.ext);
        saved.add(name);
        (bySize[p.bytes.length] ??= []).add(name);
        rows.add((takenAt: p.takenAt, fileName: name, note: p.note));
      }
      rows.sortBy((r) => r.takenAt);
      await _repo.addAll(rows);
    } catch (_) {
      for (final name in saved) {
        await _storage.delete(name);
      }
      rethrow;
    }
    return (added: rows.length, skipped: parsed.length - rows.length);
  }
}

// ---------------------------------------------------------------- parsing

typedef ParsedPhoto = ({
  DateTime takenAt,
  String? note,
  String ext,
  Uint8List bytes,
});

Never _notArchive() => throw const PhotoArchiveException(
  'This file is not a Lift Flow photo archive.',
);

Never _fail(String msg) =>
    throw PhotoArchiveException('Invalid photo archive: $msg');

/// Pure parser and validator (runs in a background isolate). Dates after
/// [now] are moved back to it.
List<ParsedPhoto> parsePhotoArchive(Uint8List bytes, DateTime now) {
  final Archive zip;
  final Object? root;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
    root = jsonDecode(utf8.decode(zip.find(_manifestName)!.readBytes()!));
  } catch (_) {
    _notArchive();
  }
  if (root is! Map<String, Object?> || root['app'] != 'lift_flow_photos') {
    _notArchive();
  }
  final version = root['version'];
  if (version is! int) _fail('“version” must be an integer');
  if (version > kPhotoArchiveVersion) {
    throw const PhotoArchiveException(
      'This archive was made with a newer version of the app.',
    );
  }
  final list = root['photos'];
  if (list is! List<Object?>) _fail('“photos” must be a list');
  final photos = <ParsedPhoto>[];
  for (final raw in list) {
    if (raw is! Map<String, Object?>) _fail('a photo must be an object');
    final entry = raw['file'];
    final at = raw['takenAt'];
    final note = raw['note'];
    if (entry is! String || entry.length > 300) _fail('“file” must be a name');
    final takenAt = at is String ? DateTime.tryParse(at) : null;
    if (takenAt == null) _fail('“takenAt” must be a date');
    if (note != null && (note is! String || note.length > kMaxPhotoNote)) {
      _fail('“note” must be text of at most $kMaxPhotoNote characters');
    }
    final file = zip.find(entry);
    if (file == null || !file.isFile) _fail('missing photo “$entry”');
    if (file.size > _maxPhotoBytes) _fail('“$entry” is too large');
    final data = file.readBytes();
    final ext = data == null ? null : imageExt(data);
    if (data == null || ext == null) _fail('“$entry” is not a photo');
    final local = takenAt.toLocal();
    photos.add((
      takenAt: local.isAfter(now) ? now : local,
      note: cleanNote(note as String?),
      ext: ext,
      bytes: data,
    ));
  }
  return photos;
}
