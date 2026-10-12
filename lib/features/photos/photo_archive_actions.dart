import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/photo_service.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Saves all photos as one archive file, the way the JSON backup is saved.
Future<void> exportPhotos(BuildContext context, WidgetRef ref) async {
  final service = ref.read(photoServiceProvider);
  try {
    final bytes = await service.export();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save photos',
      fileName: 'lift_flow_photos_$stamp.zip',
      bytes: bytes,
      mimeType: 'application/zip',
    );
    if (context.mounted && uri != null) toast(context, 'Photos saved');
  } on PhotoArchiveException catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (_) {
    if (context.mounted) toast(context, 'Export failed');
  }
}

/// Adds the photos of an archive file to the ones here.
Future<void> importPhotos(BuildContext context, WidgetRef ref) async {
  final service = ref.read(photoServiceProvider);
  final file = await FilePicker.pickFile(dialogTitle: 'Choose photo archive');
  if (file == null || !context.mounted) return;
  try {
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > kMaxPhotoArchiveBytes) {
      throw const PhotoArchiveException('Photo archive is too large.');
    }
    final r = await service.import(await file.readAsBytes());
    if (!context.mounted) return;
    final added = '${r.added} photo${r.added == 1 ? '' : 's'}';
    toast(
      context,
      r.added == 0
          ? 'No new photos'
          : r.skipped == 0
          ? 'Added $added'
          : 'Added $added, ${r.skipped} already here',
    );
  } on PhotoArchiveException catch (e) {
    if (context.mounted) toast(context, e.message);
  } catch (_) {
    if (context.mounted) toast(context, 'Import failed');
  }
}
