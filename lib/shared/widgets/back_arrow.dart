import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A back arrow widget for use in AppBars of full-screen pages outside the shell.
///
/// When pressed:
/// - If [context.canPop()] is true, performs a [Navigator.pop()]
/// - Otherwise, navigates to [fallbackRoute] using [context.go()] (e.g., for direct
///   navigation from notifications where there's no history to pop to).
class BackArrow extends StatelessWidget {
  /// The route to navigate to if there's no history to pop to.
  /// Defaults to the home route.
  final String fallbackRoute;

  /// Optional tooltip text for the back button.
  final String? tooltip;

  const BackArrow({
    super.key,
    this.fallbackRoute = '/home',
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(fallbackRoute);
        }
      },
    );
  }
}

/// Extension to provide a standardized leading AppBar widget with back navigation.
extension BackArrowAppBar on BuildContext {
  /// Returns a BackArrow widget suitable for use as [AppBar.leading].
  ///
  /// [fallbackRoute] is the route to navigate to if there's no history to pop to.
  Widget backArrowLeading({String fallbackRoute = '/home'}) {
    return BackArrow(fallbackRoute: fallbackRoute);
  }
}