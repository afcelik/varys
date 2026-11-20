import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier for today's date that updates when the app returns to foreground
class TodayNotifier extends Notifier<DateTime> with WidgetsBindingObserver {
  @override
  DateTime build() {
    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Return current date at midnight (date only, no time)
    return dateOnly(DateTime.now());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final newDate = dateOnly(DateTime.now());
      if (newDate != this.state) {
        // Date has changed, notify listeners
        this.state = newDate;
      }
    }
  }

  /// Moves to the calendar day of [now] (e.g. after midnight, seen by the
  /// schedule card's minute ticker). State changes only when the day really
  /// differs, so listeners are not notified for a later time on the same day.
  /// Returns whether the day changed.
  bool syncDate(DateTime now) {
    final newDate = dateOnly(now);
    if (newDate == state) return false;
    state = newDate;
    return true;
  }

  /// Returns date at midnight (00:00:00.000)
  /// Public for testing
  DateTime dateOnly(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }
}

/// Provider for today's date (device local date, date only)
final todayProvider = NotifierProvider<TodayNotifier, DateTime>(() {
  return TodayNotifier();
});