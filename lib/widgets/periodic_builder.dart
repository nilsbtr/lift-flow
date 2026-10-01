import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Rebuilds [builder] on a fixed [period], only while tickers are enabled
/// (the route is visible). Aligns ticks to [anchor] so e.g. elapsed minutes
/// flip exactly on the minute.
class PeriodicBuilder extends StatefulWidget {
  const PeriodicBuilder({
    super.key,
    required this.period,
    required this.builder,
    this.anchor,
  });

  final Duration period;
  final DateTime? anchor;
  final WidgetBuilder builder;

  @override
  State<PeriodicBuilder> createState() => _PeriodicBuilderState();
}

class _PeriodicBuilderState extends State<PeriodicBuilder> {
  Timer? _timer;
  bool _enabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled != _enabled || _timer == null) {
      _enabled = enabled;
      _schedule();
    }
  }

  @override
  void didUpdateWidget(PeriodicBuilder old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period || old.anchor != widget.anchor) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_enabled) return;
    final periodMs = widget.period.inMilliseconds;
    final anchorMs = (widget.anchor ?? DateTime.now()).millisecondsSinceEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    var delay = periodMs - ((nowMs - anchorMs) % periodMs);
    if (delay <= 0) delay = periodMs;
    _timer = Timer(Duration(milliseconds: delay + 5), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
