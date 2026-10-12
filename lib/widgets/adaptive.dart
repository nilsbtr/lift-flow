import 'package:material_ui/material_ui.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Adaptive layout, by window width only (never device type or orientation).
///
/// - From [kMediumWidth] `AppShell` swaps the bottom bar for a rail.
/// - From [kExpandedWidth] a tab with a list shows it beside its detail. The
///   route tree is the same at every width: the tab's routes sit in a
///   `ShellRoute` whose builder is a [ListDetail], and the tab root is a
///   [ListRoot]. Wide, the list is built in the left pane instead of the root
///   page, and the nested navigator, now starting at a placeholder, fills the
///   right pane. The list is a new widget on each side of the breakpoint, so
///   state that should survive the crossing lives in a provider.
/// - Every route body is wrapped in [ReadableWidth], which caps it at
///   [kMaxContentWidth].
///
/// Everything else keeps its place in the widget tree at every width, so
/// crossing a breakpoint never rebuilds a detail or a full-screen route.
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= kExpandedWidth
        ? expanded
        : width >= kMediumWidth
        ? medium
        : compact;
  }

  /// Navigation rail instead of the bottom bar.
  bool get hasRail => this != compact;

  /// List and detail side by side.
  bool get twoPane => this == expanded;
}

const kMediumWidth = 600.0;
const kExpandedWidth = 840.0;

/// Widest a single column of content gets.
const kMaxContentWidth = 640.0;

/// Centers a screen and caps its width. Does nothing on a phone.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: child,
      ),
    ),
  );
}

bool _twoPane(BuildContext context, bool enabled) =>
    enabled && WindowSize.of(context).twoPane;

/// Shell of a list tab: [list] beside [detail] (the nested navigator) on an
/// expanded window, [detail] alone otherwise. Turn it off with [enabled] where
/// the list leads to no detail.
class ListDetail extends StatelessWidget {
  const ListDetail({
    super.key,
    required this.list,
    required this.detail,
    this.enabled = true,
  });
  final Widget list;
  final Widget detail;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        if (_twoPane(context, enabled)) ...[
          SizedBox(width: (width * 0.36).clamp(320, 400), child: list),
          const VerticalDivider(),
        ],
        Expanded(child: detail),
      ],
    );
  }
}

/// Root page of a list tab: the [list], or [placeholder] while a [ListDetail]
/// with the same [enabled] shows the list beside it.
class ListRoot extends StatelessWidget {
  const ListRoot({
    super.key,
    required this.list,
    required this.placeholder,
    this.enabled = true,
  });
  final Widget list;
  final Widget placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      _twoPane(context, enabled) ? placeholder : ReadableWidth(child: list);
}

/// Fills the detail pane while nothing is selected.
class DetailPlaceholder extends StatelessWidget {
  const DetailPlaceholder({super.key, required this.icon, required this.text});
  final AppIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = LiftColors.of(context).muted;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: IconSizes.lg, color: muted),
              const SizedBox(height: Space.md),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
