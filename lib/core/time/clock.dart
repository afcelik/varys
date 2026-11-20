import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the current local wall-clock time.
typedef Clock = DateTime Function();

/// The app's clock. Widgets that show time-dependent state (e.g. the "Şimdi"
/// marker on the schedule card) read it here so tests can inject a fake one.
final nowProvider = Provider<Clock>((ref) => DateTime.now);
