import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The image files of progress photos, in a folder only this app can see.
/// Rows refer to them by file name; nothing else knows where they live.
class PhotoStorage {
  /// [locate] finds the folder on first use, so building this costs nothing.
  PhotoStorage(this._locate);

  PhotoStorage.at(Directory dir) : this(() async => dir);

  /// `photos` inside the app's private files folder (never the gallery).
  PhotoStorage.appPrivate()
    : this(() async {
        final base = await getApplicationSupportDirectory();
        return Directory('${base.path}${Platform.pathSeparator}photos');
      });

  final Future<Directory> Function() _locate;
  Future<Directory>? _dir;
  static final _random = Random.secure();

  Future<Directory> get _root => _dir ??= _prepare();

  Future<Directory> _prepare() async {
    final dir = await _locate();
    await dir.create(recursive: true);
    return dir;
  }

  /// Plain file names only: anything with a separator can't be ours.
  static bool _plain(String name) =>
      name.isNotEmpty &&
      !name.startsWith('.') &&
      !name.contains(RegExp(r'[/\\]'));

  Future<File?> _file(String name) async {
    if (!_plain(name)) return null;
    return File('${(await _root).path}${Platform.pathSeparator}$name');
  }

  /// Writes [bytes] to a new uniquely named file and returns its name.
  Future<String> save(Uint8List bytes, {String ext = 'jpg'}) async {
    final dir = await _root;
    for (;;) {
      final name =
          'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
          '${_random.nextInt(1 << 32).toRadixString(36)}.$ext';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (file.existsSync()) continue;
      await file.writeAsBytes(bytes, flush: true);
      return name;
    }
  }

  /// The file called [name], or null when it's gone.
  Future<File?> file(String name) async {
    final f = await _file(name);
    return f != null && await f.exists() ? f : null;
  }

  Future<Uint8List?> read(String name) async {
    try {
      return await (await file(name))?.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<int?> length(String name) async {
    try {
      return await (await file(name))?.length();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> delete(String name) async {
    try {
      await (await file(name))?.delete();
    } on FileSystemException {
      // Already gone.
    }
  }

  /// Deletes files not in [keep] that are older than [minAge], so a file
  /// that is just being added isn't taken for an orphan. Returns how many.
  Future<int> prune(
    Set<String> keep, {
    Duration minAge = const Duration(minutes: 10),
  }) async {
    final cutoff = DateTime.now().subtract(minAge);
    var removed = 0;
    await for (final e in (await _root).list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (keep.contains(name) || e.lastModifiedSync().isAfter(cutoff)) continue;
      try {
        await e.delete();
        removed++;
      } on FileSystemException {
        // Try again next time.
      }
    }
    return removed;
  }

  /// Deletes every file.
  Future<void> clear() async {
    final dir = await _root;
    if (await dir.exists()) await dir.delete(recursive: true);
    _dir = null;
  }
}
