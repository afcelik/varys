/// Application breakpoints for responsive layouts.
class Breakpoints {
  /// Breakpoint for switching between mobile (bottom nav) and desktop (side rail) layouts.
  ///
  /// - Width <= [mobileMaxWidth]: Bottom NavigationBar
  /// - Width > [mobileMaxWidth]: Extended NavigationRail
  static const double mobileMaxWidth = 800.0;

  /// Extended width of the NavigationRail (used for both the rail and the trailing section).
  static const double railExtendedWidth = 200.0;

  /// Private constructor to prevent instantiation.
  Breakpoints._();
}