import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/domain/stats.dart';
import 'package:lift_flow/domain/units.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:lift_flow/widgets/charts/balance_bars.dart';
import 'package:lift_flow/widgets/charts/dot_calendar.dart';
import 'package:lift_flow/widgets/charts/scale.dart';
import 'package:lift_flow/widgets/charts/scatter_chart.dart';
import 'package:lift_flow/widgets/charts/session_timeline.dart';
import 'package:lift_flow/widgets/charts/sparkline.dart';
import 'package:lift_flow/widgets/charts/split_bar.dart';
import 'package:lift_flow/widgets/charts/trend_chart.dart';
import 'package:lift_flow/widgets/charts/week_bar_chart.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  home: Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [child],
    ),
  ),
);

List<TrendPoint> trend(int n) => [
  for (var i = 0; i < n; i++)
    TrendPoint(
      DateTime(2025, 1, 1 + i * 3),
      100 + (i % 5) * 2.5,
      best: 100 + (i < 5 ? i : 4) * 2.5,
      isRecord: i > 0 && i < 5,
    ),
];

void main() {
  group('NiceScale', () {
    test('round steps', () {
      final s = NiceScale(3, 97);
      expect(s.min, 0);
      expect(s.max, 100);
      expect(s.step, 25);
      expect(s.ticks, [0, 25, 50, 75, 100]);
      expect(NiceScale(101, 109).step, 2);
      expect(NiceScale(100, 110).step, 2.5);
      expect(NiceScale(0.1, 0.9).ticks.last, 1);
    });

    test('flat and empty ranges', () {
      final s = NiceScale(80, 80);
      expect(s.min, lessThan(80));
      expect(s.max, greaterThan(80));
      final z = NiceScale(0, 0, zero: true);
      expect(z.min, 0);
      expect(z.max, greaterThan(0));
      expect(NiceScale(5, 12, zero: true).min, 0);
    });
  });

  test('fmtCompact and fmtDelta', () {
    expect(fmtCompact(950), '950');
    expect(fmtCompact(12500), '12.5K');
    expect(fmtCompact(1200), '1.2K');
    expect(fmtDelta(2.5), '+2.5');
    expect(fmtDelta(-5), '${kMinus}5');
    expect(fmtDelta(0.001), '±0');
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    for (final n in [0, 1, 60]) {
      testWidgets('trend chart with $n points ($theme)', (tester) async {
        await tester.pumpWidget(
          host(
            TrendChart(points: trend(n), semanticLabel: 'Trend'),
            dark: dark,
          ),
          duration: Duration.zero,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Trend'), findsOneWidget);
      });
    }

    testWidgets('other charts render ($theme)', (tester) async {
      final now = DateTime(2025, 3, 12, 18);
      final start = DateTime(2025, 3, 12, 9);
      await tester.pumpWidget(
        host(
          Column(
            children: [
              ScatterChart(
                points: [
                  for (var i = 0; i < 20; i++)
                    ScatterPoint(DateTime(2025, 1, 1 + i), 60.0 + i, 3 + i % 8),
                ],
                semanticLabel: 'Sets',
              ),
              WeekBarChart(
                weeks: [
                  for (var i = 0; i < 12; i++)
                    addDays(weekStart(now), -7 * (11 - i)),
                ],
                values: [for (var i = 0; i < 12; i++) (i % 4).toDouble()],
                goal: 3,
                semanticLabel: 'Weeks',
              ),
              DotCalendar(
                activity: dayActivity([
                  Workout(
                    id: 1,
                    name: 'A',
                    startedAt: start,
                    endedAt: now,
                    totalSets: 12,
                    totalVolumeKg: 0,
                    exerciseCount: 1,
                  ),
                ]),
                now: now,
                semanticLabel: 'Calendar',
              ),
              const Sparkline([1, 3, 2, 5]),
              const Sparkline([4]),
              SessionTimeline(
                marks: [
                  TimelineMark(start.add(const Duration(minutes: 5)), 0),
                  TimelineMark(start.add(const Duration(minutes: 9)), 1),
                ],
                start: start,
                end: start.add(const Duration(hours: 1)),
                lanes: 2,
                semanticLabel: 'Timeline',
              ),
              const BalanceBars(
                sets: {MuscleGroup.chest: 12, MuscleGroup.back: 4},
              ),
              const SplitBar(
                split: {MuscleGroup.chest: 8, MuscleGroup.arms: 3},
              ),
            ],
          ),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Sets', 'Weeks', 'Calendar', 'Timeline']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Chest: 12 sets a week'), findsOneWidget);
    });
  }

  testWidgets('dragging shows a tooltip until release', (tester) async {
    int? selected;
    final points = trend(10);
    await tester.pumpWidget(
      host(
        TrendChart(
          points: points,
          semanticLabel: 'Trend',
          tooltip: (i) => 'Point $i',
          onSelect: (i) => selected = i,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chart = find.byType(TrendChart);
    final gesture = await tester.startGesture(tester.getCenter(chart));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    expect(selected, isNotNull);
    expect(find.text('Point $selected'), findsOneWidget);

    await gesture.moveBy(Offset(tester.getSize(chart).width, 0));
    await tester.pump();
    expect(selected, points.length - 1);
    expect(find.text('Point ${points.length - 1}'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(selected, isNull);
    expect(find.textContaining('Point'), findsNothing);
  });

  testWidgets('tapping toggles a pinned tooltip', (tester) async {
    await tester.pumpWidget(
      host(
        TrendChart(
          points: trend(3),
          semanticLabel: 'Trend',
          tooltip: (i) => 'Point $i',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final right = tester.getTopRight(find.byType(TrendChart)) +
        const Offset(-4, 60);
    await tester.tapAt(right);
    await tester.pump();
    expect(find.text('Point 2'), findsOneWidget);
    await tester.tapAt(right);
    await tester.pump();
    expect(find.text('Point 2'), findsNothing);
  });
}
