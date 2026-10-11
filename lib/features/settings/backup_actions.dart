import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import '../../widgets/common.dart';

/// Saves a JSON backup through the system file picker and records the date.
/// Shared by Settings and the Home nudge.
Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  try {
    final bytes = await ref.read(backupProvider).export();
    final name =
        'lift_flow_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save backup',
      fileName: name,
      bytes: bytes,
      mimeType: 'application/json',
    );
    if (uri == null) return;
    await ref.read(settingsProvider.notifier).markBackedUp();
    if (context.mounted) toast(context, 'Backup saved');
  } catch (e) {
    if (context.mounted) toast(context, 'Export failed');
  }
}
