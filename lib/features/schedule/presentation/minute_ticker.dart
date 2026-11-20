import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';

/// Rebuilds [builder] with the current time from [nowProvider] at every
/// minute boundary (a one-shot Timer aligned to the next minute, re-armed on
/// each tick).
///
/// When a tick sees that the calendar day changed since the previous tick
/// (e.g. 23:59 -> 00:00), it moves [todayProvider] to the new day, so every
/// card that follows today loads the new day. It never syncs on start: a
/// differing day at mount time is left to the existing resume handling.
/// The timer is cancelled on dispose.
class MinuteTicker extends ConsumerStatefulWidget {
  const MinuteTicker({super.key, required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  ConsumerState<MinuteTicker> createState() => _MinuteTickerState();
}

class _MinuteTickerState extends ConsumerState<MinuteTicker> {
  Timer? _timer;
  late DateTime _now;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  void initState() {
    super.initState();
    _now = ref.read(nowProvider)();
    _schedule(_now);
  }

  /// Arms the timer for the next minute boundary after [from].
  void _schedule(DateTime from) {
    final untilNextMinute =
        const Duration(minutes: 1) -
        Duration(
          seconds: from.second,
          milliseconds: from.millisecond,
          microseconds: from.microsecond,
        );
    _timer = Timer(untilNextMinute, _tick);
  }

  void _tick() {
    if (!mounted) return;
    final now = ref.read(nowProvider)();
    final dayChanged = _day(now) != _day(_now);
    setState(() => _now = now);
    if (dayChanged) ref.read(todayProvider.notifier).syncDate(now);
    _schedule(now);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
