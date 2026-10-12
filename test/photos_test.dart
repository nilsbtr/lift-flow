import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lift_flow/data/backup_service.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/photo_repository.dart';
import 'package:lift_flow/data/photo_service.dart';
import 'package:lift_flow/data/photo_storage.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/domain/photos.dart';
import 'package:lift_flow/features/photos/photo_compare_screen.dart';
import 'package:lift_flow/features/photos/photo_image.dart';
import 'package:lift_flow/features/photos/photo_viewer_screen.dart';
import 'package:lift_flow/features/photos/photos_card.dart';
import 'package:lift_flow/features/photos/photos_screen.dart';
import 'package:lift_flow/features/settings/settings_screen.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/router.dart';
import 'package:lift_flow/services/photo_picker.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Bytes that pass for a JPEG; [seed] makes them differ.
Uint8List fakeJpeg(int seed) => Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  seed,
  ...List.generate(40, (i) => (i * 7 + seed) & 0xFF),
]);

Finder _photoFrom(String day) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == 'Photo from $day',
);

/// A real, tiny PNG for widget tests. Needs `tester.runAsync`.
Future<Uint8List> tinyPng(int shade) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(
    const ui.Rect.fromLTWH(0, 0, 6, 8),
    ui.Paint()..color = ui.Color.fromARGB(255, shade, 80, 160),
  );
  final image = await rec.endRecording().toImage(6, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// An in-memory database with the photo storage in a temp directory.
class Lib {
  Lib()
    : db = AppDatabase(NativeDatabase.memory()),
      dir = Directory.systemTemp.createTempSync('lift_flow_photos_') {
    storage = PhotoStorage.at(dir);
    repo = PhotoRepository(db);
    service = PhotoService(repo, storage);
  }

  final AppDatabase db;
  final Directory dir;
  late final PhotoStorage storage;
  late final PhotoRepository repo;
  late final PhotoService service;

  /// File names currently on disk.
  List<String> get files => dir.existsSync()
      ? [for (final e in dir.listSync()) e.uri.pathSegments.last]
      : [];

  void dispose() {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows keeps image files open for a while; the OS clears the temp.
    }
  }

  Future<void> close() async {
    await db.close();
    dispose();
  }
}

Uint8List zipOf(Map<String, Object?> manifest, Map<String, Uint8List> files) {
  final zip = Archive()
    ..addFile(ArchiveFile.string('photos.json', jsonEncode(manifest)));
  files.forEach((name, bytes) => zip.addFile(ArchiveFile.bytes(name, bytes)));
  return ZipEncoder().encodeBytes(zip);
}

Map<String, Object?> manifestOf(
  List<Map<String, Object?>> photos, {
  String app = 'lift_flow_photos',
  int version = 1,
}) => {'app': app, 'version': version, 'photos': photos};

/// A widget test that ends by removing the tree. The database stays open:
/// closing it waits on stream cleanup that never runs in the test zone.
void photoTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('photo domain', () {
    ProgressPhoto photo(int id, DateTime at) =>
        ProgressPhoto(id: id, takenAt: at, fileName: 'p$id.jpg');

    test('groups by month, newest first', () {
      final months = groupByMonth([
        photo(4, DateTime(2024, 3, 20)),
        photo(3, DateTime(2024, 3, 2)),
        photo(2, DateTime(2024, 2, 28)),
        photo(1, DateTime(2023, 12, 31)),
      ]);
      expect(months.map((m) => m.month), [
        DateTime(2024, 3),
        DateTime(2024, 2),
        DateTime(2023, 12),
      ]);
      expect(months.map((m) => m.photos.map((p) => p.id).toList()), [
        [4, 3],
        [2],
        [1],
      ]);
      expect(groupByMonth(const []), isEmpty);
    });

    test('compare starts with the earliest and the latest', () {
      final photos = [
        photo(3, DateTime(2024, 3, 1)),
        photo(2, DateTime(2024, 2, 1)),
        photo(1, DateTime(2024, 1, 1)),
      ];
      expect(comparePair(photos.take(1).toList()), isNull);
      expect(comparePair(const []), isNull);
      var (l, r) = comparePair(photos)!;
      expect((l.id, r.id), (1, 3));
      // A chosen photo stays; the other side falls back to the latest.
      (l, r) = comparePair(photos, a: 2)!;
      expect((l.id, r.id), (2, 3));
      // The latest one is paired with the earliest, never with itself.
      (l, r) = comparePair(photos, a: 3)!;
      expect((l.id, r.id), (3, 1));
      (l, r) = comparePair(photos, b: 1)!;
      expect((l.id, r.id), (3, 1));
      (l, r) = comparePair(photos, a: 2, b: 1)!;
      expect((l.id, r.id), (2, 1));
      // Unknown ids are ignored.
      (l, r) = comparePair(photos, a: 99, b: 98)!;
      expect((l.id, r.id), (1, 3));
    });

    test('a new date keeps the time and never lies ahead', () {
      final now = DateTime(2024, 6, 10, 12);
      expect(
        redate(DateTime(2024, 3, 5, 18, 30, 15), DateTime(2024, 2, 1), now),
        DateTime(2024, 2, 1, 18, 30, 15),
      );
      // Today at a later time of day than now: clamped to now.
      expect(redate(DateTime(2024, 3, 5, 18), DateTime(2024, 6, 10), now), now);
      expect(
        redate(DateTime(2024, 3, 5, 9), DateTime(2024, 6, 10), now),
        DateTime(2024, 6, 10, 9),
      );
      expect(redate(now, DateTime(2030), now), now);
    });

    test('formats the time between two dates', () {
      String span(DateTime a, DateTime b) => fmtSpan(a, b);
      final d = DateTime(2024, 1, 31);
      expect(span(d, d), 'Same day');
      expect(span(d, DateTime(2024, 2, 1)), '1 day');
      expect(span(d, DateTime(2024, 2, 9)), '9 days');
      expect(span(d, DateTime(2024, 2, 14)), '2 weeks');
      expect(span(DateTime(2024, 1, 1), DateTime(2024, 1, 30)), '4 weeks');
      expect(span(DateTime(2024, 1, 1), DateTime(2024, 2, 1)), '1 month');
      expect(span(DateTime(2024, 1, 31), DateTime(2024, 2, 29)), '4 weeks');
      expect(span(DateTime(2024, 1, 15), DateTime(2024, 5, 20)), '4 months');
      expect(span(DateTime(2023, 3, 1), DateTime(2024, 3, 1)), '1 year');
      expect(
        span(DateTime(2023, 3, 1), DateTime(2024, 5, 9)),
        '1 year 2 months',
      );
      expect(span(DateTime(2021, 3, 1), DateTime(2024, 3, 2)), '3 years');
      // Order doesn't matter, and the time of day doesn't count.
      expect(
        span(DateTime(2024, 5, 20, 23), DateTime(2024, 1, 15, 1)),
        '4 months',
      );
    });

    test('blank notes are stored as nothing', () {
      expect(cleanNote(null), isNull);
      expect(cleanNote('  \n'), isNull);
      expect(cleanNote('  Week 4 '), 'Week 4');
    });
  });

  group('PhotoRepository', () {
    late Lib lib;
    setUp(() => lib = Lib());
    tearDown(() => lib.close());

    test('lists newest first and follows a new date', () async {
      final a = await lib.repo.add(
        takenAt: DateTime(2024, 1, 1),
        fileName: 'a.jpg',
      );
      final b = await lib.repo.add(
        takenAt: DateTime(2024, 2, 1),
        fileName: 'b.jpg',
      );
      final c = await lib.repo.add(
        takenAt: DateTime(2024, 3, 1),
        fileName: 'c.jpg',
      );
      expect((await lib.repo.all()).map((p) => p.id), [c.id, b.id, a.id]);

      await lib.repo.setTakenAt(a.id, DateTime(2024, 4, 1));
      expect((await lib.repo.all()).map((p) => p.id), [a.id, c.id, b.id]);
      expect((await lib.repo.watchAll().first).map((p) => p.id), [
        a.id,
        c.id,
        b.id,
      ]);
    });

    test('notes are trimmed and blank ones cleared', () async {
      final p = await lib.repo.add(
        takenAt: DateTime(2024, 1, 1),
        fileName: 'a.jpg',
        note: ' Start ',
      );
      expect(p.note, 'Start');
      await lib.repo.setNote(p.id, 'Week 4');
      expect((await lib.repo.all()).single.note, 'Week 4');
      await lib.repo.setNote(p.id, '   ');
      expect((await lib.repo.all()).single.note, isNull);
    });

    test('deletes one photo or all', () async {
      final a = await lib.repo.add(
        takenAt: DateTime(2024, 1, 1),
        fileName: 'a.jpg',
      );
      await lib.repo.add(takenAt: DateTime(2024, 2, 1), fileName: 'b.jpg');
      await lib.repo.delete(a.id);
      expect((await lib.repo.all()).map((p) => p.fileName), ['b.jpg']);
      await lib.repo.deleteAll();
      expect(await lib.repo.all(), isEmpty);
    });
  });

  group('PhotoStorage', () {
    late Lib lib;
    setUp(() => lib = Lib());
    tearDown(() => lib.close());

    test('saves unique files and reads them back', () async {
      final a = await lib.storage.save(fakeJpeg(1));
      final b = await lib.storage.save(fakeJpeg(1));
      final c = await lib.storage.save(fakeJpeg(2), ext: 'png');
      expect({a, b, c}, hasLength(3));
      expect(a, endsWith('.jpg'));
      expect(c, endsWith('.png'));
      expect(await lib.storage.read(a), fakeJpeg(1));
      expect(await lib.storage.length(c), fakeJpeg(2).length);
      expect((await lib.storage.file(a))!.existsSync(), isTrue);
      expect(lib.files, unorderedEquals([a, b, c]));
    });

    test('a missing file is null, not an error', () async {
      expect(await lib.storage.file('nope.jpg'), isNull);
      expect(await lib.storage.read('nope.jpg'), isNull);
      expect(await lib.storage.length('nope.jpg'), isNull);
      await lib.storage.delete('nope.jpg');
    });

    test('only plain file names reach the folder', () async {
      final outside = File('${lib.dir.parent.path}/outside_${lib.dir.hashCode}')
        ..writeAsBytesSync(fakeJpeg(9));
      addTearDown(outside.deleteSync);
      final name = '../${outside.uri.pathSegments.last}';
      expect(await lib.storage.file(name), isNull);
      expect(await lib.storage.read(name), isNull);
      await lib.storage.delete(name);
      expect(outside.existsSync(), isTrue);
      expect(await lib.storage.file(r'..\x.jpg'), isNull);
      expect(await lib.storage.file('.hidden'), isNull);
      expect(await lib.storage.file(''), isNull);
    });

    test('prunes files nothing refers to, but not fresh ones', () async {
      final keep = await lib.storage.save(fakeJpeg(1));
      final orphan = await lib.storage.save(fakeJpeg(2));
      // Just written: could still be on its way into the database.
      expect(await lib.storage.prune({keep}), 0);
      expect(lib.files, hasLength(2));
      // Older than the minimum age.
      File(
        '${lib.dir.path}/$orphan',
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      expect(await lib.storage.prune({keep}), 1);
      expect(lib.files, [keep]);
      expect(await lib.storage.prune({}, minAge: Duration.zero), 1);
      expect(lib.files, isEmpty);
    });

    test('clear removes everything and storage keeps working', () async {
      await lib.storage.save(fakeJpeg(1));
      await lib.storage.save(fakeJpeg(2));
      await lib.storage.clear();
      expect(lib.files, isEmpty);
      await lib.storage.clear();
      final again = await lib.storage.save(fakeJpeg(3));
      expect(lib.files, [again]);
    });
  });

  group('PhotoService', () {
    late Lib lib;
    setUp(() => lib = Lib());
    tearDown(() => lib.close());

    test('adds a row and its file', () async {
      final p = await lib.service.add(
        fakeJpeg(1),
        takenAt: DateTime(2024, 3, 5, 18),
        note: ' Day one ',
      );
      expect(p.takenAt, DateTime(2024, 3, 5, 18));
      expect(p.note, 'Day one');
      expect(p.fileName, endsWith('.jpg'));
      expect(await lib.storage.read(p.fileName), fakeJpeg(1));
      expect(lib.files, [p.fileName]);
    });

    test('a photo is never from the future', () async {
      final p = await lib.service.add(
        fakeJpeg(1),
        takenAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(p.takenAt.isAfter(DateTime.now()), isFalse);
      final q = await lib.service.add(fakeJpeg(2));
      expect(DateTime.now().difference(q.takenAt).inMinutes, lessThan(1));
    });

    test('the file goes when the row can’t be added', () async {
      final service = PhotoService(_FailingRepo(lib.db), lib.storage);
      await expectLater(service.add(fakeJpeg(1)), throwsStateError);
      expect(lib.files, isEmpty);
    });

    test('removing deletes row and file, even with the file gone', () async {
      final a = await lib.service.add(fakeJpeg(1));
      final b = await lib.service.add(fakeJpeg(2));
      await lib.service.remove(a);
      expect((await lib.repo.all()).map((p) => p.id), [b.id]);
      expect(lib.files, [b.fileName]);

      await lib.storage.delete(b.fileName);
      expect(await lib.storage.file(b.fileName), isNull);
      await lib.service.remove(b);
      expect(await lib.repo.all(), isEmpty);
    });

    test('sweeping deletes orphan files and nothing else', () async {
      final p = await lib.service.add(fakeJpeg(1));
      File('${lib.dir.path}/orphan.jpg').writeAsBytesSync(fakeJpeg(2));
      expect(await lib.service.sweep(), 0);
      expect(await lib.service.sweep(minAge: Duration.zero), 1);
      expect(lib.files, [p.fileName]);
      expect(await lib.repo.all(), hasLength(1));
    });

    test('delete all clears rows, files and orphans', () async {
      await lib.service.add(fakeJpeg(1));
      await lib.service.add(fakeJpeg(2));
      File('${lib.dir.path}/orphan.jpg').writeAsBytesSync(fakeJpeg(3));
      await lib.service.deleteAll();
      expect(await lib.repo.all(), isEmpty);
      expect(lib.files, isEmpty);
      // Still usable afterwards.
      await lib.service.add(fakeJpeg(4));
      expect(lib.files, hasLength(1));
    });
  });

  group('JSON backup and photos', () {
    late Lib lib;
    setUp(() async {
      lib = Lib();
      await SettingsRepository(lib.db).get();
    });
    tearDown(() => lib.close());

    test('the backup holds no photos and import keeps them', () async {
      final p = await lib.service.add(fakeJpeg(1), note: 'Secret');
      final backup = BackupService(lib.db);
      final json = await backup.export();
      final text = utf8.decode(json);
      expect(text.toLowerCase(), isNot(contains('photo')));
      expect(text, isNot(contains(p.fileName)));
      expect(text, isNot(contains('Secret')));

      await backup.import(json);
      expect((await lib.repo.all()).single.id, p.id);
      expect(lib.files, [p.fileName]);

      // Delete all in the backup service leaves them; Settings clears them
      // through the photo service.
      await backup.deleteAll();
      expect(await lib.repo.all(), hasLength(1));
      await lib.service.deleteAll();
      expect(await lib.repo.all(), isEmpty);
      expect(lib.files, isEmpty);
    });
  });

  group('photo archive', () {
    late Lib src;
    late Lib dst;
    setUp(() {
      src = Lib();
      dst = Lib();
    });
    tearDown(() async {
      await src.close();
      await dst.close();
    });

    Future<void> seed(Lib lib) async {
      await lib.service.add(
        fakeJpeg(1),
        takenAt: DateTime(2024, 1, 10, 8),
        note: 'Start',
      );
      await lib.service.add(fakeJpeg(2), takenAt: DateTime(2024, 3, 5, 18, 30));
      await lib.service.add(
        fakeJpeg(3),
        takenAt: DateTime(2024, 2, 1, 9),
        note: 'Week 4',
      );
    }

    test('is a zip with a manifest and the images, oldest first', () async {
      await seed(src);
      final zip = ZipDecoder().decodeBytes(await src.service.export());
      expect(zip.files.map((f) => f.name).first, 'photos.json');
      final manifest = jsonDecode(
        utf8.decode(zip.find('photos.json')!.readBytes()!),
      ) as Map<String, Object?>;
      expect(manifest['app'], 'lift_flow_photos');
      expect(manifest['version'], 1);
      final photos = (manifest['photos']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        photos.map((p) => p['takenAt']),
        [
          DateTime(2024, 1, 10, 8),
          DateTime(2024, 2, 1, 9),
          DateTime(2024, 3, 5, 18, 30),
        ].map((d) => d.toUtc().toIso8601String()),
      );
      expect(photos.map((p) => p['note']), ['Start', 'Week 4', null]);
      for (final p in photos) {
        final entry = p['file']! as String;
        expect(entry, startsWith('photos/'));
        expect(zip.find(entry)!.readBytes(), isNotEmpty);
      }
      expect(photos.first['file'], contains('2024-01-10_'));
      expect(
        zip.find(photos.first['file']! as String)!.readBytes(),
        fakeJpeg(1),
      );
    });

    test('round trip keeps dates, notes and images', () async {
      await seed(src);
      final result = await dst.service.import(await src.service.export());
      expect(result, (added: 3, skipped: 0));
      final rows = await dst.repo.all();
      expect(rows.map((r) => r.takenAt), [
        DateTime(2024, 3, 5, 18, 30),
        DateTime(2024, 2, 1, 9),
        DateTime(2024, 1, 10, 8),
      ]);
      expect(rows.map((r) => r.note), [null, 'Week 4', 'Start']);
      expect(
        [for (final r in rows) await dst.storage.read(r.fileName)],
        [fakeJpeg(2), fakeJpeg(3), fakeJpeg(1)],
      );
      expect(dst.files, hasLength(3));
    });

    test('merging never duplicates, whatever the date', () async {
      await seed(src);
      final archive = await src.service.export();

      // The same image is here already, re-dated with another note.
      await dst.service.add(
        fakeJpeg(3),
        takenAt: DateTime(2024, 2, 20),
        note: 'Mine',
      );
      await dst.service.add(fakeJpeg(9), takenAt: DateTime(2024, 4, 1));

      expect(await dst.service.import(archive), (added: 2, skipped: 1));
      final rows = await dst.repo.all();
      expect(rows, hasLength(4));
      final mine = rows.singleWhere((r) => r.note == 'Mine');
      expect(mine.takenAt, DateTime(2024, 2, 20));

      // Importing again changes nothing.
      expect(await dst.service.import(archive), (added: 0, skipped: 3));
      expect(await dst.repo.all(), hasLength(4));
      expect(dst.files, hasLength(4));
    });

    test('skips rows whose file is gone and needs a photo to export', () async {
      await expectLater(
        src.service.export(),
        throwsA(isA<PhotoArchiveException>()),
      );
      final a = await src.service.add(
        fakeJpeg(1),
        takenAt: DateTime(2024, 1, 1),
      );
      await src.service.add(fakeJpeg(2), takenAt: DateTime(2024, 1, 2));
      await src.storage.delete(a.fileName);
      expect(await dst.service.import(await src.service.export()), (
        added: 1,
        skipped: 0,
      ));
      for (final r in await src.repo.all()) {
        await src.storage.delete(r.fileName);
      }
      await expectLater(
        src.service.export(),
        throwsA(isA<PhotoArchiveException>()),
      );
    });

    Future<void> rejects(Uint8List bytes, Matcher message) async {
      await expectLater(
        dst.service.import(bytes),
        throwsA(
          isA<PhotoArchiveException>().having(
            (e) => e.message,
            'message',
            message,
          ),
        ),
      );
      expect(await dst.repo.all(), isEmpty);
      expect(dst.files, isEmpty);
    }

    Map<String, Object?> entry({
      String file = 'photos/a.jpg',
      Object? takenAt = '2024-01-01T10:00:00.000Z',
      Object? note,
    }) => {'file': file, 'takenAt': takenAt, 'note': note};

    test('refuses anything that is not a photo archive', () async {
      final image = {'photos/a.jpg': fakeJpeg(1)};
      await rejects(Uint8List.fromList([1, 2, 3]), contains('not a Lift Flow'));
      await rejects(
        Uint8List.fromList(utf8.encode('{"app":"lift_flow"}')),
        contains('not a Lift Flow'),
      );
      final noManifest = Archive()
        ..addFile(ArchiveFile.bytes('photos/a.jpg', fakeJpeg(1)));
      await rejects(
        ZipEncoder().encodeBytes(noManifest),
        contains('not a Lift Flow'),
      );
      await rejects(
        zipOf(manifestOf([entry()], app: 'lift_flow'), image),
        contains('not a Lift Flow'),
      );
      await rejects(
        zipOf(manifestOf([entry()], version: 2), image),
        contains('newer version'),
      );
    });

    test('checks every entry', () async {
      final image = {'photos/a.jpg': fakeJpeg(1)};
      await rejects(
        zipOf(manifestOf([entry(takenAt: 'yesterday')]), image),
        contains('takenAt'),
      );
      await rejects(
        zipOf(manifestOf([entry(takenAt: 5)]), image),
        contains('takenAt'),
      );
      await rejects(
        zipOf(manifestOf([entry(file: 'photos/missing.jpg')]), image),
        contains('missing photo'),
      );
      await rejects(
        zipOf(manifestOf([entry(note: 'x' * 501)]), image),
        contains('note'),
      );
      await rejects(
        zipOf(manifestOf([entry(note: 7)]), image),
        contains('note'),
      );
      await rejects(
        zipOf(manifestOf([entry()]), {
          'photos/a.jpg': Uint8List.fromList(utf8.encode('<html></html>')),
        }),
        contains('not a photo'),
      );
      // One bad entry spoils the whole import.
      await rejects(
        zipOf(manifestOf([entry(), entry(file: 'photos/b.jpg')]), image),
        contains('missing photo'),
      );
    });

    test(
      'future dates are moved back and entry names are not trusted',
      () async {
        final future = DateTime.now().add(const Duration(days: 400));
        final evil = '../../outside_${src.dir.hashCode}.jpg';
        final bytes = zipOf(
          manifestOf([
            entry(takenAt: future.toUtc().toIso8601String()),
            entry(file: evil, takenAt: '2024-01-01T10:00:00.000Z'),
          ]),
          {'photos/a.jpg': fakeJpeg(1), evil: fakeJpeg(2)},
        );
        expect(await dst.service.import(bytes), (added: 2, skipped: 0));
        final rows = await dst.repo.all();
        expect(rows.first.takenAt.isAfter(DateTime.now()), isFalse);
        for (final r in rows) {
          expect(r.fileName, matches(RegExp(r'^p[a-z0-9]+\.jpg$')));
        }
        expect(dst.files, hasLength(2));
        expect(
          dst.dir.parent.listSync().map((e) => e.path),
          isNot(contains(contains('outside_'))),
        );
      },
    );
  });

  group('routes', () {
    test('photos nest in the Progress tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final config = container.read(routerProvider).configuration;
      Uri uri(String s) => Uri.parse(s);
      expect(config.findMatch(uri('/progress/photos')).isError, isFalse);
      expect(config.findMatch(uri('/progress/photos/7')).isError, isFalse);
      expect(config.findMatch(uri('/progress/photos/7')).pathParameters, {
        'photoId': '7',
      });
      final compare = config.findMatch(uri('/progress/photos/compare?a=1&b=2'));
      expect(compare.isError, isFalse);
      expect(compare.pathParameters, isEmpty);
      expect(config.findMatch(uri('/gym/photos')).isError, isTrue);
    });
  });

  group('widgets', () {
    Future<void> settle(WidgetTester tester) async {
      // Each hop of real file IO needs a turn of the real event loop.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
      }
    }

    void narrow(WidgetTester tester, {double height = 640}) {
      tester.view.physicalSize = Size(320, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// A library with one real image per entry, oldest first by date.
    Future<(Lib, UserSettings)> library(
      WidgetTester tester,
      List<(DateTime, String?)> photos,
    ) async {
      final lib = Lib();
      addTearDown(lib.dispose);
      final settings = await tester.runAsync(() async {
        var shade = 40;
        for (final (at, note) in photos) {
          await lib.service.add(
            await tinyPng(shade += 20),
            takenAt: at,
            note: note,
          );
        }
        return SettingsRepository(lib.db).get();
      });
      return (lib, settings!);
    }

    List<Override> overrides(Lib lib, UserSettings settings) => [
      databaseProvider.overrideWithValue(lib.db),
      photoStorageProvider.overrideWithValue(lib.storage),
      initialSettingsProvider.overrideWithValue(settings),
    ];

    Widget host(
      Lib lib,
      UserSettings settings,
      Widget home, {
      bool dark = false,
      double textScale = 1,
      List<Override> extra = const [],
    }) => ProviderScope(
      overrides: [...overrides(lib, settings), ...extra],
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

    final marchFifth = DateTime(2024, 3, 5, 18);
    final photos = <(DateTime, String?)>[
      (DateTime(2024, 1, 10, 8), 'Start'),
      (DateTime(2024, 2, 20, 9), null),
      (marchFifth, null),
    ];

    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';

      photoTest('card invites the first photo at 320 dp ($theme)', (
        tester,
      ) async {
        narrow(tester);
        final (lib, settings) = await library(tester, const []);
        await tester.pumpWidget(
          host(
            lib,
            settings,
            const Scaffold(body: SingleChildScrollView(child: PhotosCard())),
            dark: dark,
          ),
        );
        await settle(tester);
        expect(find.text('Photos'), findsOneWidget);
        expect(find.textContaining('See how you change'), findsOneWidget);
        expect(find.text('Add photo'), findsOneWidget);
        expect(find.byType(PhotoImage), findsNothing);
        expect(tester.takeException(), isNull);
      });

      photoTest('card shows the latest photos and a count ($theme)', (
        tester,
      ) async {
        narrow(tester);
        final (lib, settings) = await library(tester, photos);
        await tester.pumpWidget(
          host(
            lib,
            settings,
            const Scaffold(body: SingleChildScrollView(child: PhotosCard())),
            dark: dark,
          ),
        );
        await settle(tester);
        expect(find.text('3 photos · latest 5 Mar 2024'), findsOneWidget);
        expect(find.byType(PhotoImage), findsNWidgets(3));
        expect(find.byType(Image), findsNWidgets(3));
        expect(find.text('Add'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      photoTest('grid is grouped by month at 320 dp ($theme)', (tester) async {
        narrow(tester, height: 1400);
        final (lib, settings) = await library(tester, [
          ...photos,
          (DateTime(2024, 3, 20, 7), 'Later'),
          (DateTime(2023, 12, 31), null),
        ]);
        await tester.pumpWidget(
          host(lib, settings, const PhotosScreen(), dark: dark),
        );
        await settle(tester);
        expect(find.text('MARCH 2024'), findsOneWidget);
        expect(find.text('FEBRUARY 2024'), findsOneWidget);
        expect(find.text('JANUARY 2024'), findsOneWidget);
        expect(find.text('DECEMBER 2023'), findsOneWidget);
        // Newest month first.
        expect(
          tester.getTopLeft(find.text('MARCH 2024')).dy,
          lessThan(tester.getTopLeft(find.text('FEBRUARY 2024')).dy),
        );
        expect(find.byType(PhotoImage), findsNWidgets(5));
        expect(find.text('20 Mar'), findsOneWidget);
        expect(find.text('Compare'), findsOneWidget);
        expect(find.textContaining('regular backup leaves'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    photoTest('grid: empty state, and compare needs two photos', (
      tester,
    ) async {
      narrow(tester);
      final (empty, settings) = await library(tester, const []);
      await tester.pumpWidget(host(empty, settings, const PhotosScreen()));
      await settle(tester);
      expect(find.text('No photos yet'), findsOneWidget);
      expect(find.text('Compare'), findsNothing);

      final (one, settings1) = await library(tester, [photos.first]);
      await tester.pumpWidget(host(one, settings1, const PhotosScreen()));
      await settle(tester);
      expect(find.byType(PhotoImage), findsOneWidget);
      expect(find.text('Compare'), findsNothing);
    });

    photoTest('a missing file shows a placeholder, not an error', (
      tester,
    ) async {
      narrow(tester);
      final (lib, settings) = await library(tester, photos);
      await tester.runAsync(() async {
        final rows = await lib.repo.all();
        await lib.storage.delete(rows.first.fileName);
        File('${lib.dir.path}/${rows.last.fileName}')
            .writeAsBytesSync([1, 2, 3]);
      });
      await tester.pumpWidget(host(lib, settings, const PhotosScreen()));
      await settle(tester);
      expect(find.byType(PhotoImage), findsNWidgets(3));
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Photo unavailable',
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    photoTest('adding a photo from the gallery with a date and note', (
      tester,
    ) async {
      narrow(tester);
      final (lib, settings) = await library(tester, const []);
      final png = (await tester.runAsync(() => tinyPng(120)))!;
      await tester.pumpWidget(
        host(
          lib,
          settings,
          const Scaffold(body: SingleChildScrollView(child: PhotosCard())),
          extra: [photoPickerProvider.overrideWithValue(_FakePicker(png))],
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      expect(find.text('Take photo'), findsOneWidget);
      await tester.tap(find.text('Choose from gallery'));
      await settle(tester);
      expect(find.text('New photo'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Before photo');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('New photo'), findsNothing);
      expect(find.text('Photo added'), findsOneWidget);
      final rows = await tester.runAsync(lib.repo.all);
      expect(rows!.single.note, 'Before photo');
      expect(lib.files, [rows.single.fileName]);
      expect(
        find.text('1 photo · latest ${photoDay.format(rows.single.takenAt)}'),
        findsOneWidget,
      );
    });

    photoTest('a cancelled pick adds nothing and a lost photo is offered', (
      tester,
    ) async {
      narrow(tester);
      final (lib, settings) = await library(tester, const []);
      final png = (await tester.runAsync(() => tinyPng(120)))!;
      await tester.pumpWidget(
        host(
          lib,
          settings,
          const Scaffold(body: SingleChildScrollView(child: PhotosCard())),
          extra: [photoPickerProvider.overrideWithValue(_FakePicker(null))],
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take photo'));
      await settle(tester);
      expect(find.text('New photo'), findsNothing);
      expect(await tester.runAsync(lib.repo.all), isEmpty);

      // The camera result Android lost comes back with its own date.
      await tester.pumpWidget(const SizedBox());
      final taken = DateTime(2024, 5, 4, 10);
      await tester.pumpWidget(
        host(
          lib,
          settings,
          const Scaffold(body: SingleChildScrollView(child: PhotosCard())),
          extra: [
            photoPickerProvider.overrideWithValue(
              _FakePicker(null, lostPhoto: (bytes: png, takenAt: taken)),
            ),
          ],
        ),
      );
      await settle(tester);
      expect(find.text('New photo'), findsOneWidget);
      expect(find.text('4 May 2024'), findsOneWidget);
    });

    for (final scale in [1.0, 1.6]) {
      photoTest('compare defaults to earliest and latest at 320 dp '
          '(text ×$scale)', (tester) async {
        narrow(tester, height: 900);
        final (lib, settings) = await library(tester, photos);
        await tester.pumpWidget(
          host(lib, settings, const PhotoCompareScreen(), textScale: scale),
        );
        await settle(tester);
        expect(find.text('10 Jan 2024'), findsOneWidget);
        expect(find.text('5 Mar 2024'), findsOneWidget);
        expect(find.text('20 Feb 2024'), findsNothing);
        expect(find.text('1 month apart'), findsOneWidget);
        expect(find.text('Start'), findsOneWidget);
        expect(find.text('Change'), findsNWidgets(2));
        expect(find.byType(PhotoImage), findsNWidgets(2));
        // The two panes sit side by side, inside the screen.
        final left = tester.getRect(find.byType(PhotoImage).first);
        final right = tester.getRect(find.byType(PhotoImage).last);
        expect(left.right, lessThan(right.left));
        expect(left.left, greaterThanOrEqualTo(0));
        expect(right.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      });
    }

    photoTest('compare: either side can be changed', (tester) async {
      narrow(tester, height: 900);
      final (lib, settings) = await library(tester, photos);
      await tester.pumpWidget(host(lib, settings, const PhotoCompareScreen()));
      await settle(tester);

      await tester.tap(find.text('Change').first);
      await settle(tester);
      expect(find.text('Choose photo'), findsOneWidget);
      expect(find.byType(PhotoImage), findsNWidgets(2 + 3));
      await tester.tap(_photoFrom('20 Feb 2024'));
      await settle(tester);
      expect(find.text('Choose photo'), findsNothing);
      expect(find.text('20 Feb 2024'), findsOneWidget);
      expect(find.text('10 Jan 2024'), findsNothing);
      expect(find.text('5 Mar 2024'), findsOneWidget);
      expect(find.text('2 weeks apart'), findsOneWidget);

      await tester.tap(find.text('Change').last);
      await settle(tester);
      await tester.tap(_photoFrom('10 Jan 2024'));
      await settle(tester);
      expect(find.text('20 Feb 2024'), findsOneWidget);
      expect(find.text('10 Jan 2024'), findsOneWidget);
      expect(find.text('5 Mar 2024'), findsNothing);
      expect(find.text('1 month apart'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    photoTest('compare needs two photos', (tester) async {
      narrow(tester);
      final (lib, settings) = await library(tester, [photos.first]);
      await tester.pumpWidget(host(lib, settings, const PhotoCompareScreen()));
      await settle(tester);
      expect(find.text('Nothing to compare yet'), findsOneWidget);
    });

    photoTest('viewer: swipe, zoom, edit the note and the date', (
      tester,
    ) async {
      narrow(tester);
      final (lib, settings) = await library(tester, [
        (DateTime(2024, 2, 10, 8), null),
        (DateTime(2024, 2, 20, 9), null),
        (marchFifth, null),
      ]);
      final newest = (await tester.runAsync(lib.repo.all))!.first;
      await tester.pumpWidget(
        host(lib, settings, PhotoViewerScreen(photoId: newest.id)),
      );
      await settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('5 Mar 2024'), findsOneWidget);
      expect(find.text('Add a note'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await settle(tester);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text('20 Feb 2024'), findsOneWidget);

      // Double-tap zooms in and locks the swipe; again resets.
      PageView pageView() => tester.widget(find.byType(PageView));
      final photo = find.byType(InteractiveViewer);
      InteractiveViewer viewer() => tester.widget(photo);
      expect(pageView().physics, isNull);
      await tester.tapAt(tester.getCenter(photo));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tester.getCenter(photo));
      await tester.pumpAndSettle();
      expect(viewer().transformationController!.value.getMaxScaleOnAxis(), 2.5);
      expect(pageView().physics, isA<NeverScrollableScrollPhysics>());
      await tester.tapAt(tester.getCenter(photo));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tester.getCenter(photo));
      await tester.pumpAndSettle();
      expect(viewer().transformationController!.value.getMaxScaleOnAxis(), 1);
      expect(pageView().physics, isNull);

      await tester.tap(find.text('Add a note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bulking');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Bulking'), findsOneWidget);

      // An earlier day in the same month moves the photo down the list; the
      // viewer follows it.
      await tester.tap(find.text('20 Feb 2024'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect(find.text('3 of 3'), findsOneWidget);
      expect(find.text('5 Feb 2024'), findsOneWidget);
      expect(find.text('Bulking'), findsOneWidget);
      final moved = (await tester.runAsync(lib.repo.all))!.last;
      expect(moved.note, 'Bulking');
      expect(moved.takenAt, DateTime(2024, 2, 5, 9));
      expect(tester.takeException(), isNull);
    });

    photoTest('viewer: a deleted photo says so', (tester) async {
      narrow(tester);
      final (lib, settings) = await library(tester, photos);
      await tester.pumpWidget(
        host(lib, settings, const PhotoViewerScreen(photoId: 999)),
      );
      await settle(tester);
      expect(find.text('Photo not found'), findsOneWidget);
    });

    Future<GoRouter> pumpApp(
      WidgetTester tester,
      Lib lib,
      UserSettings s,
    ) async {
      final container = ProviderContainer(overrides: overrides(lib, s));
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await settle(tester);
      return router;
    }

    photoTest('open a photo from the grid, compare from the viewer', (
      tester,
    ) async {
      narrow(tester, height: 900);
      final (lib, settings) = await library(tester, photos);
      final router = await pumpApp(tester, lib, settings);

      router.go('/progress/photos');
      await settle(tester);
      expect(find.text('MARCH 2024'), findsOneWidget);
      await tester.tap(find.byType(PhotoImage).first, warnIfMissed: false);
      await settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);

      await tester.tap(find.text('Compare'));
      await settle(tester);
      expect(find.text('Change'), findsNWidgets(2));
      // Starts with the photo it was opened from, paired with the earliest.
      expect(find.text('5 Mar 2024'), findsOneWidget);
      expect(find.text('10 Jan 2024'), findsOneWidget);

      // Back lands on the grid, still in the Progress tab.
      router.pop();
      await settle(tester);
      expect(find.text('MARCH 2024'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    photoTest('the Progress tab leads to the photos', (tester) async {
      narrow(tester, height: 1400);
      final (lib, settings) = await library(tester, photos);
      final router = await pumpApp(tester, lib, settings);
      router.go('/progress');
      await settle(tester);
      // Only photos and body weight exist, so the card sits in the list.
      expect(find.text('3 photos · latest 5 Mar 2024'), findsOneWidget);
      await tester.tap(find.text('3 photos · latest 5 Mar 2024'));
      await settle(tester);
      expect(find.text('MARCH 2024'), findsOneWidget);
    });

    photoTest('deleting a photo asks first, then removes row and file', (
      tester,
    ) async {
      narrow(tester, height: 900);
      final (lib, settings) = await library(tester, photos);
      final router = await pumpApp(tester, lib, settings);
      router.go('/progress/photos');
      await settle(tester);
      await tester.tap(find.byType(PhotoImage).first, warnIfMissed: false);
      await settle(tester);

      await tester.tap(find.byTooltip('Delete photo'));
      await tester.pumpAndSettle();
      expect(find.text('Delete photo?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(await tester.runAsync(lib.repo.all), hasLength(3));

      await tester.tap(find.byTooltip('Delete photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);
      final left = (await tester.runAsync(lib.repo.all))!;
      expect(left.map((p) => p.takenAt), [photos[1].$1, photos[0].$1]);
      expect(lib.files, unorderedEquals(left.map((p) => p.fileName)));
      // Back on the grid with the two that are left.
      expect(find.byType(PhotoImage), findsNWidgets(2));
      expect(find.text('MARCH 2024'), findsNothing);
    });

    photoTest('settings: backup copy, photo archive actions, delete all', (
      tester,
    ) async {
      // Wider than the rest: the existing theme row overflows at 320 dp.
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (lib, settings) = await library(tester, photos);
      await tester.pumpWidget(host(lib, settings, const SettingsScreen()));
      await settle(tester);

      await tester.scrollUntilVisible(
        find.text('Delete all data'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Export photos'), findsOneWidget);
      expect(find.text('Import photos'), findsOneWidget);
      expect(find.textContaining('regular backup leaves'), findsOneWidget);

      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      expect(find.textContaining('photos and settings'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await tester.runAsync(lib.repo.all), hasLength(3));

      await tester.tap(find.text('Delete all data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await settle(tester);
      expect(await tester.runAsync(lib.repo.all), isEmpty);
      expect(lib.files, isEmpty);
    });
  });
}

class _FailingRepo extends PhotoRepository {
  _FailingRepo(super.db);

  @override
  Future<ProgressPhoto> add({
    required DateTime takenAt,
    required String fileName,
    String? note,
  }) => throw StateError('no');
}

class _FakePicker implements PhotoPicker {
  _FakePicker(this.bytes, {this.lostPhoto});
  final Uint8List? bytes;
  final PickedPhoto? lostPhoto;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async =>
      bytes == null ? null : (bytes: bytes!, takenAt: null);

  @override
  Future<PickedPhoto?> lost() async => lostPhoto;
}
