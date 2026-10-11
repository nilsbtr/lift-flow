import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/features/gym/exercise_editor_sheet.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

Widget host() => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => unawaited(showExerciseEditor(context)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('new exercise needs a muscle group (narrow, large text)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Squat');
    expect(find.text('Pick a muscle group'), findsNothing);
    // Nothing is preselected.
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .where((c) => c.selected)
          .length,
      1, // Only the default equipment, None.
    );

    await tester.ensureVisible(find.text('Create'));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a muscle group'), findsOneWidget);
    expect(find.text('New exercise'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Quads'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quads'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a muscle group'), findsNothing);
    // The primary group is not offered as a secondary one.
    expect(find.widgetWithText(FilterChip, 'Quads'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Hamstrings'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Glutes'));
    await tester.tap(find.widgetWithText(FilterChip, 'Glutes'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Glutes'))
          .selected,
      isTrue,
    );

    expect(find.text('Per dumbbell'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Dumbbell'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dumbbell'));
    await tester.pumpAndSettle();
    expect(find.text('Per side'), findsOneWidget);
    expect(find.text('Per dumbbell'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
