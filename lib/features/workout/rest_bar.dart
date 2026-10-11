import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/periodic_builder.dart';

/// Bottom rest countdown with ±15s and Skip. Animates in/out.
class RestBar extends ConsumerWidget {
  const RestBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rest = ref.watch(restTimerProvider);
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.curve,
      alignment: Alignment.bottomCenter,
      child: rest == null
          ? const SizedBox(width: double.infinity)
          : _RestPanel(rest: rest),
    );
  }
}

class _RestPanel extends ConsumerWidget {
  const _RestPanel({required this.rest});
  final RestTimerState rest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ctrl = ref.read(restTimerProvider.notifier);

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PeriodicBuilder(
              period: const Duration(seconds: 1),
              anchor: rest.endsAt,
              builder: (_) => LinearProgressIndicator(
                value: rest.progress(),
                minHeight: 4,
                color: lift.rest,
                backgroundColor: lift.raised,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.sm,
                Space.sm,
              ),
              child: Row(
                children: [
                  AppIcon(AppIcons.timer, color: lift.rest),
                  const SizedBox(width: Space.sm),
                  PeriodicBuilder(
                    period: const Duration(seconds: 1),
                    anchor: rest.endsAt,
                    builder: (_) => Text(
                      fmtClock(rest.remainingSeconds()),
                      style: t.headlineMedium?.copyWith(color: lift.rest),
                      semanticsLabel:
                          'Rest, ${rest.remainingSeconds()} seconds left',
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => ctrl.adjust(-15),
                    child: const Text('${kMinus}15'),
                  ),
                  TextButton(
                    onPressed: () => ctrl.adjust(15),
                    child: const Text('+15'),
                  ),
                  TextButton(onPressed: ctrl.skip, child: const Text('Skip')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
