import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(historyProvider).value;
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));

    Widget body;
    if (list == null) {
      body = const SizedBox.shrink();
    } else if (list.isEmpty) {
      body = const EmptyState(
        icon: AppIcons.history,
        title: 'No workouts yet',
        message: 'Finished workouts show up here.',
      );
    } else {
      final monthFmt = DateFormat('MMMM y');
      final rows = <Object>[];
      String? month;
      for (final w in list) {
        final m = monthFmt.format(w.startedAt);
        if (m != month) {
          rows.add(m);
          month = m;
        }
        rows.add(w);
      }
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          if (r is String) return SectionLabel(r);
          final w = r as Workout;
          return Padding(
            key: ValueKey(w.id),
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: WorkoutSummaryCard(
              workout: w,
              unit: unit,
              onTap: () => context.go('/history/${w.id}'),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: body,
    );
  }
}

class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({
    super.key,
    required this.workout,
    required this.unit,
    this.onTap,
  });

  final Workout workout;
  final WeightUnit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final w = workout;
    final duration = (w.endedAt ?? w.startedAt).difference(w.startedAt);
    final parts = [
      fmtDuration(duration),
      '${w.totalSets} ${w.totalSets == 1 ? 'set' : 'sets'}',
      if (w.totalVolumeKg > 0) fmtVolume(w.totalVolumeKg, unit),
    ];
    return FlatCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  DateFormat('EEE').format(w.startedAt).toUpperCase(),
                  style: t.labelSmall?.copyWith(color: muted),
                ),
                Text(
                  '${w.startedAt.day}',
                  style: t.headlineSmall?.copyWith(fontFeatures: Fonts.tabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(
                  parts.join(' · '),
                  style: t.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          AppIcon(AppIcons.chevronRight, color: muted),
        ],
      ),
    );
  }
}
