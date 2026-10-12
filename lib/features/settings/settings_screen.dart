import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/backup_service.dart';
import '../../data/database.dart';
import '../../domain/reminders.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../services/app_lock.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/bodyweight_dialog.dart';
import '../../widgets/common.dart';
import '../photos/photo_archive_actions.dart';
import 'backup_actions.dart';
import 'balance_band_dialog.dart';
import 'barbell_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool? _exact;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExact();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkExact();
  }

  Future<void> _checkExact() async {
    final v = await ref.read(notificationsProvider).canScheduleExact();
    if (mounted) setState(() => _exact = v);
  }

  SettingsController get _ctrl => ref.read(settingsProvider.notifier);

  Future<void> _editBodyweight(UserSettings s) async {
    final w = await askBodyweight(
      context,
      unit: s.weightUnit,
      initialKg: s.bodyweightKg,
    );
    if (w != null) await _ctrl.logBodyweight(w.kg, date: w.date);
  }

  Future<void> _editBalanceBand(UserSettings s) async {
    final band = await askBalanceBand(
      context,
      min: s.balanceMin,
      max: s.balanceMax,
    );
    if (band == null) return;
    await _ctrl.update(
      AppSettingsCompanion(
        balanceMin: Value(band.$1),
        balanceMax: Value(band.$2),
      ),
    );
  }

  Future<void> _setAppLock(bool on) async {
    final result = await ref.read(appLockProvider.notifier).setEnabled(on);
    if (!mounted || result != AuthResult.unavailable) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set a screen lock first'),
        content: const Text(
          'App lock unlocks with your phone’s fingerprint, PIN, pattern or '
          'password. Set one up in your phone’s settings, then try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _dayChip(UserSettings s, int weekday) => ChoiceChip(
    label: Text(DateFormat.E().format(DateTime(2024, 1, weekday))),
    selected: reminderOn(s.reminderDays, weekday),
    onSelected: (_) => _toggleReminderDay(s, weekday),
  );

  Future<void> _toggleReminderDay(UserSettings s, int weekday) async {
    final days = toggleReminderDay(s.reminderDays, weekday);
    if (s.reminderDays == 0 &&
        !await ref.read(notificationsProvider).requestPermission()) {
      if (mounted) {
        toast(context, 'Allow notifications in system settings for reminders');
      }
      return;
    }
    await _ctrl.setReminders(days: days);
  }

  Future<void> _editReminderTime(UserSettings s) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: s.reminderMinutes ~/ 60,
        minute: s.reminderMinutes % 60,
      ),
    );
    if (t != null) await _ctrl.setReminders(minutes: t.hour * 60 + t.minute);
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    await exportBackup(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    await exportSetsCsv(context, ref);
    if (mounted) setState(() => _busy = false);
  }

  /// Import and delete-all would orphan the running workout.
  bool _blockedByWorkout() {
    final blocked = ref.read(liveWorkoutProvider) != null;
    if (blocked) toast(context, BackupBlockedException.message);
    return blocked;
  }

  Future<void> _import() async {
    if (_blockedByWorkout()) return;
    final ok = await confirm(
      context,
      title: 'Import backup?',
      message:
          'This replaces all current data, including history. Photos stay as '
          'they are.',
      action: 'Choose file',
      destructive: true,
    );
    if (!ok) return;
    final file = await FilePicker.pickFile(dialogTitle: 'Choose backup');
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final size = file.lengthSync() ?? await file.length();
      if (size != null && size > kMaxBackupBytes) {
        throw const BackupFormatException('Backup file is too large.');
      }
      final bytes = await file.readAsBytes();
      await ref.read(backupProvider).import(bytes);
      await resetAppState(ref);
      if (mounted) toast(context, 'Backup imported');
    } on BackupFormatException catch (e) {
      if (mounted) toast(context, e.message);
    } on BackupBlockedException catch (e) {
      if (mounted) toast(context, e.toString());
    } catch (e) {
      if (mounted) toast(context, 'Import failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs a photo archive action with the screen locked, like the backup ones.
  Future<void> _photoArchive(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAll() async {
    if (_blockedByWorkout()) return;
    final ok = await confirm(
      context,
      title: 'Delete all data?',
      message:
          'Exercises, templates, history, photos and settings will be removed. '
          'This can’t be undone.',
      action: 'Delete everything',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(backupProvider).deleteAll();
      await ref.read(photoServiceProvider).deleteAll();
      await resetAppState(ref);
      if (mounted) toast(context, 'All data deleted');
    } on BackupBlockedException catch (e) {
      if (mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final pkg = ref.watch(initialPackageInfoProvider);
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final darkActive =
        s.themeMode == ThemePref.dark ||
        (s.themeMode == ThemePref.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: Space.xxl),
          children: [
            const SectionLabel('Units & body'),
            _SegmentTile<WeightUnit>(
              title: 'Weight unit',
              values: WeightUnit.values,
              selected: s.weightUnit,
              label: (v) => v.label,
              onChanged: (v) =>
                  _ctrl.update(AppSettingsCompanion(weightUnit: Value(v))),
            ),
            ListTile(
              title: const Text('Body weight'),
              subtitle: const Text('Logged per day, charted in Progress'),
              trailing: Text(
                s.bodyweightKg == null
                    ? 'Not set'
                    : '${fmtWeight(s.bodyweightKg!, s.weightUnit)} ${s.weightUnit.label}',
                style: t.bodyLarge?.copyWith(
                  color: s.bodyweightKg == null ? muted : null,
                  fontWeight: s.bodyweightKg == null ? null : FontWeight.w600,
                ),
              ),
              onTap: () => _editBodyweight(s),
            ),
            const SectionLabel('Rest timer'),
            ListTile(
              title: const Text('Default rest'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Shorter',
                    onPressed: s.defaultRestSeconds > 15
                        ? () => _ctrl.update(
                            AppSettingsCompanion(
                              defaultRestSeconds: Value(
                                s.defaultRestSeconds - 15,
                              ),
                            ),
                          )
                        : null,
                    icon: const AppIcon(AppIcons.minus),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      fmtClock(s.defaultRestSeconds),
                      textAlign: TextAlign.center,
                      style: t.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Longer',
                    onPressed: s.defaultRestSeconds < 600
                        ? () => _ctrl.update(
                            AppSettingsCompanion(
                              defaultRestSeconds: Value(
                                s.defaultRestSeconds + 15,
                              ),
                            ),
                          )
                        : null,
                    icon: const AppIcon(AppIcons.plus),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Start rest after each set'),
              value: s.autoStartRest,
              onChanged: (v) =>
                  _ctrl.update(AppSettingsCompanion(autoStartRest: Value(v))),
            ),
            SwitchListTile(
              title: const Text('Alert when rest is over'),
              subtitle: const Text('Notification while the phone is locked'),
              value: s.restAlerts,
              onChanged: (v) async {
                if (v) {
                  await ref.read(notificationsProvider).requestPermission();
                }
                await _ctrl.update(AppSettingsCompanion(restAlerts: Value(v)));
              },
            ),
            if (s.restAlerts && _exact == false)
              ListTile(
                title: const Text('Allow precise alerts'),
                subtitle: const Text(
                  'Without this, Android may deliver the alert a bit late.',
                ),
                trailing: const AppIcon(AppIcons.openExternal),
                onTap: () =>
                    ref.read(notificationsProvider).requestExactAlarms(),
              ),
            SwitchListTile(
              title: const Text('Sound when rest is over'),
              subtitle: const Text('While the app is open'),
              value: s.restSound,
              onChanged: (v) async {
                // The sound is a notification, so Android 13+ asks first.
                if (v) {
                  await ref.read(notificationsProvider).requestPermission();
                }
                await _ctrl.update(AppSettingsCompanion(restSound: Value(v)));
              },
            ),
            const SectionLabel('Workout'),
            ListTile(
              title: const Text('Weekly goal'),
              subtitle: const Text('Workouts per week'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Fewer',
                    onPressed: s.weeklyGoal == null
                        ? null
                        : () => _ctrl.setWeeklyGoal(
                            s.weeklyGoal == 1 ? null : s.weeklyGoal! - 1,
                          ),
                    icon: const AppIcon(AppIcons.minus),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      s.weeklyGoal?.toString() ?? 'Off',
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(
                        color: s.weeklyGoal == null ? muted : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'More',
                    onPressed: (s.weeklyGoal ?? 0) < 7
                        ? () => _ctrl.setWeeklyGoal((s.weeklyGoal ?? 0) + 1)
                        : null,
                    icon: const AppIcon(AppIcons.plus),
                  ),
                ],
              ),
            ),
            _SegmentTile<int>(
              title: 'First day of week',
              values: const [
                DateTime.monday,
                DateTime.sunday,
                DateTime.saturday,
              ],
              selected: s.firstDayOfWeek,
              label: (v) => switch (v) {
                DateTime.sunday => 'Sun',
                DateTime.saturday => 'Sat',
                _ => 'Mon',
              },
              onChanged: (v) =>
                  _ctrl.update(AppSettingsCompanion(firstDayOfWeek: Value(v))),
            ),
            _SegmentTile<EffortMode>(
              title: 'Set effort',
              values: EffortMode.values,
              selected: s.effortMode,
              label: (v) => v.label,
              onChanged: (v) =>
                  _ctrl.update(AppSettingsCompanion(effortMode: Value(v))),
            ),
            SwitchListTile(
              title: const Text('Keep screen on'),
              subtitle: const Text('While a workout is running'),
              value: s.keepScreenOn,
              onChanged: (v) =>
                  _ctrl.update(AppSettingsCompanion(keepScreenOn: Value(v))),
            ),
            const SectionLabel('Barbell'),
            const BarbellSettings(),
            const SectionLabel('Reminders'),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Training days', style: t.titleMedium),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (var i = 0; i < 7; i++)
                        _dayChip(s, (s.firstDayOfWeek - 1 + i) % 7 + 1),
                    ],
                  ),
                ],
              ),
            ),
            ListTile(
              title: const Text('Reminder time'),
              subtitle: s.reminderDays == 0
                  ? const Text('Pick a training day first')
                  : const Text('Local time, repeats weekly'),
              trailing: Text(
                TimeOfDay(
                  hour: s.reminderMinutes ~/ 60,
                  minute: s.reminderMinutes % 60,
                ).format(context),
                style: t.bodyLarge?.copyWith(
                  color: s.reminderDays == 0 ? muted : null,
                  fontWeight: s.reminderDays == 0 ? null : FontWeight.w600,
                ),
              ),
              enabled: s.reminderDays != 0,
              onTap: () => _editReminderTime(s),
            ),
            const SectionLabel('Appearance'),
            _SegmentTile<ThemePref>(
              title: 'Theme',
              values: ThemePref.values,
              selected: s.themeMode,
              label: (v) => v.label,
              onChanged: (v) =>
                  _ctrl.update(AppSettingsCompanion(themeMode: Value(v))),
            ),
            if (ref.watch(dynamicSchemesProvider) != null)
              SwitchListTile(
                title: const Text('Material You'),
                subtitle: const Text('Use your wallpaper colors'),
                value: s.dynamicColor,
                onChanged: (v) =>
                    _ctrl.update(AppSettingsCompanion(dynamicColor: Value(v))),
              ),
            SwitchListTile(
              title: const Text('Pure black'),
              subtitle: const Text('Dark theme on a black background'),
              value: s.pureBlack,
              onChanged: darkActive
                  ? (v) =>
                        _ctrl.update(AppSettingsCompanion(pureBlack: Value(v)))
                  : null,
            ),
            const SectionLabel('Progress'),
            ListTile(
              title: const Text('Muscle balance band'),
              subtitle: const Text('Weekly sets per muscle on target'),
              trailing: Text(
                '${s.balanceMin}–${s.balanceMax} sets',
                style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: () => _editBalanceBand(s),
            ),
            const SectionLabel('Privacy'),
            SwitchListTile(
              title: const Text('App lock'),
              subtitle: const Text('Unlock with your fingerprint or screen lock'),
              value: s.appLock,
              onChanged: _setAppLock,
            ),
            const SectionLabel('Data'),
            ListTile(
              leading: const AppIcon(AppIcons.exportFile),
              title: const Text('Export backup'),
              subtitle: Text(
                s.lastBackupAt == null
                    ? 'All data as a JSON file · never backed up'
                    : 'All data as a JSON file · last backup '
                          '${DateFormat('d MMM yyyy').format(s.lastBackupAt!)}',
              ),
              onTap: _export,
            ),
            ListTile(
              leading: const AppIcon(AppIcons.exportFile),
              title: const Text('Export sets as CSV'),
              subtitle: const Text('One row per set, for spreadsheets'),
              onTap: _exportCsv,
            ),
            ListTile(
              leading: const AppIcon(AppIcons.importFile),
              title: const Text('Import backup'),
              subtitle: const Text('Replace all data from a file'),
              onTap: _import,
            ),
            ListTile(
              leading: const AppIcon(AppIcons.exportFile),
              title: const Text('Export photos'),
              subtitle: const Text(
                'Save all photos as one archive. The regular backup leaves '
                'them out.',
              ),
              onTap: () => _photoArchive(() => exportPhotos(context, ref)),
            ),
            ListTile(
              leading: const AppIcon(AppIcons.importFile),
              title: const Text('Import photos'),
              subtitle: const Text('Add photos from an archive. Yours are kept.'),
              onTap: () => _photoArchive(() => importPhotos(context, ref)),
            ),
            ListTile(
              leading: AppIcon(
                AppIcons.trash,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete all data',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: _deleteAll,
            ),
            const SectionLabel('About'),
            ListTile(
              title: const Text('Version'),
              trailing: Text(
                '${pkg.version} (${pkg.buildNumber})',
                style: t.bodyLarge?.copyWith(color: muted),
              ),
            ),
            ListTile(
              title: const Text('Licenses'),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Lift Flow',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(
                'All data stays on this device.',
                style: t.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentTile<T> extends StatelessWidget {
  const _SegmentTile({
    required this.title,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          SegmentedButton<T>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              minimumSize: WidgetStatePropertyAll(Size(0, kCompactTap)),
            ),
            segments: [
              for (final v in values)
                ButtonSegment(value: v, label: Text(label(v))),
            ],
            selected: {selected},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}
