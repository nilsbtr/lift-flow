import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/enums.dart';
import 'package:lift_flow/domain/stats.dart';
import 'package:lift_flow/features/settings/balance_band_dialog.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:lift_flow/widgets/bodyweight_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// Pumps a button that runs [open]; the result lands in the returned holder.
Future<List<T?>> pumpOpener<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext) open, {
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final result = <T?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result.add(await open(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';

    testWidgets('weigh-in dialog defaults to today ($theme)', (tester) async {
      final result = await pumpOpener<Weighin>(
        tester,
        (c) => askBodyweight(c, unit: WeightUnit.kg),
        dark: dark,
      );
      expect(find.text('Log body weight'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Replaces the entry for this day.'), findsNothing);

      await tester.enterText(find.byType(TextField), '5');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter a realistic body weight'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '81,5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result.single?.kg, 81.5);
      expect(result.single?.date, dayOf(DateTime.now()));
    });

    testWidgets('weigh-in dialog backdates, never into the future ($theme)', (
      tester,
    ) async {
      final day = DateTime(2025, 3, 1);
      final result = await pumpOpener<Weighin>(
        tester,
        (c) => askBodyweight(
          c,
          unit: WeightUnit.kg,
          initialKg: 80,
          initialDate: day,
          taken: {day},
        ),
        dark: dark,
      );
      expect(find.text('Sat, 1 Mar 2025'), findsOneWidget);
      expect(find.text('Replaces the entry for this day.'), findsOneWidget);

      await tester.tap(find.text('Sat, 1 Mar 2025'));
      await tester.pumpAndSettle();
      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.lastDate, dayOf(DateTime.now()));
      expect(picker.initialDate, day);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result.single, (kg: 80.0, date: day));
    });

    testWidgets('editing a weigh-in does not warn about its own day ($theme)', (
      tester,
    ) async {
      final day = DateTime(2025, 3, 1);
      await pumpOpener<Weighin>(
        tester,
        (c) => askBodyweight(
          c,
          unit: WeightUnit.kg,
          initialKg: 80,
          initialDate: day,
          editing: true,
          taken: {day},
        ),
        dark: dark,
      );
      expect(find.text('Edit weigh-in'), findsOneWidget);
      expect(find.text('Replaces the entry for this day.'), findsNothing);
    });

    testWidgets('balance band dialog validates ($theme)', (tester) async {
      final result = await pumpOpener<(int, int)>(
        tester,
        (c) => askBalanceBand(c, min: 10, max: 20),
        dark: dark,
      );
      Future<void> save(String lo, String hi) async {
        await tester.enterText(find.byType(TextField).first, lo);
        await tester.enterText(find.byType(TextField).last, hi);
        await tester.tap(find.text('Save'));
        await tester.pump();
      }

      await save('20', '10');
      expect(
        find.text('The minimum must be below the maximum'),
        findsOneWidget,
      );
      await save('0', '10');
      expect(find.text('Use 1–50 sets'), findsOneWidget);
      await save('', '10');
      expect(find.text('Enter whole numbers'), findsOneWidget);
      expect(result, isEmpty);

      await save('8', '16');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(result.single, (8, 16));
    });
  }

  testWidgets('balance band dialog resets to the default', (tester) async {
    final result = await pumpOpener<(int, int)>(
      tester,
      (c) => askBalanceBand(c, min: 3, max: 6),
    );
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(result.single, kBalanceDefault);
  });
}
