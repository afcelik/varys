import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';
import 'package:varys/features/auth/domain/auth_state.dart';
import 'package:varys/features/auth/presentation/login_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/inbox/presentation/inbox_screen.dart';
import 'package:varys/features/notes/presentation/notes_screen.dart';
import 'package:varys/features/planning/presentation/planning_screen.dart';
import 'package:varys/features/settings/presentation/settings_screen.dart';
import 'package:varys/features/varys_chat/presentation/varys_chat_screen.dart';
import 'package:varys/shared/widgets/main_scaffold.dart';

/// Application router configuration using GoRouter with StatefulShellRoute.
///
/// Implements a responsive navigation pattern:
/// - NavigationRail (left side) for widths > 800px
/// - NavigationBar (bottom) for widths <= 800px
///
/// Uses StatefulShellRoute to preserve state across tab switches.
/// Uses a provider-based approach for synchronous auth-based redirects.
class AppRouter {
  static const String homePath = '/home';
  static const String inboxPath = '/inbox';
  static const String planningPath = '/planning';
  static const String notesPath = '/notes';
  static const String varysChatPath = '/varys-chat';
  static const String settingsPath = '/settings';
  static const String loginPath = '/login';
  static const String focusTaskSelectionPath = '/focus-task-selection';

  static GoRouter createRouter(Ref ref) {
    // Get the initial auth state
    // Note: We don't use initial state here, redirect reads current state on each call
    ref.read(authNotifierProvider);

    // Build shell branches dynamically from shared destinations (only 3: Home, Planning, Varys)
    final shellBranches = NavigationDestinations.shellDestinations.map((dest) {
      Widget screen;
      switch (dest.routePath) {
        case homePath:
          screen = const HomeScreen();
          break;
        case planningPath:
          screen = const PlanningScreen();
          break;
        case varysChatPath:
          screen = const VarysChatScreen();
          break;
        default:
          screen = const HomeScreen();
      }

      return StatefulShellBranch(
        routes: [
          GoRoute(
            path: dest.routePath,
            name: dest.routePath.replaceAll('/', ''),
            pageBuilder: (context, state) => NoTransitionPage(
              child: screen,
            ),
          ),
        ],
      );
    }).toList();

    // Create a list of redirect logic that will be evaluated on each navigation
    // We use a simple approach: listen to auth state changes and refresh the router
    final router = GoRouter(
      initialLocation: homePath,
      // We'll use a simple redirect that reads from the provider
      // The router will be refreshed when authNotifierProvider changes
      refreshListenable: _RouterRefreshListenable(ref, authNotifierProvider),
      redirect: (context, state) {
        // Read current auth state from provider
        final currentAuthState = ref.read(authNotifierProvider);

        final isLoginRoute = state.matchedLocation == loginPath;

        // Allow access to login without auth
        if (isLoginRoute) {
          // If already authenticated and trying to access login, redirect to home
          if (currentAuthState is AuthAuthenticated) {
            return homePath;
          }
          return null;
        }

        // For all other routes, require authentication
        if (currentAuthState is! AuthAuthenticated) {
          // Not authenticated - redirect to login
          return loginPath;
        }

        // Authenticated - allow access
        return null;
      },
      routes: [
        // Login route (outside the shell - full screen)
        GoRoute(
          path: loginPath,
          name: 'login',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LoginPage(),
          ),
        ),
        // Full-screen pages outside the shell (accessed via push from Home)
        GoRoute(
          path: notesPath,
          name: 'notes',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: NotesScreen(),
          ),
        ),
        GoRoute(
          path: inboxPath,
          name: 'inbox',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: InboxScreen(),
          ),
        ),
        GoRoute(
          path: settingsPath,
          name: 'settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
        // Focus task selection page (outside shell, full screen, accessed via push)
        GoRoute(
          path: focusTaskSelectionPath,
          name: 'focus-task-selection',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: FocusTaskSelectionPage(),
          ),
        ),
        // Main app shell with navigation (3 tabs: Home, Planning, Varys)
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return MainScaffold(navigationShell: navigationShell);
          },
          branches: shellBranches,
        ),
      ],
      // Error handling
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Page Not Found',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                state.error?.toString() ?? 'Unknown error',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    return router;
  }
}

/// A Listenable that listens to a Riverpod provider and notifies when it changes.
///
/// This allows GoRouter to refresh its redirect logic when auth state changes.
class _RouterRefreshListenable extends ChangeNotifier {
  final Ref _ref;
  final StateNotifierProvider<AuthNotifier, AuthState> _provider;

  _RouterRefreshListenable(this._ref, this._provider) {
    // Listen to provider changes
    _ref.listen<AuthState>(_provider, (previous, next) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    // Note: In Riverpod 2.x, we can't easily unsubscribe from ref.listen
    // The listener will be cleaned up when the ref is disposed
    super.dispose();
  }
}

/// Navigation destination model
class NavigationDestinationItem {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final String routePath;

  const NavigationDestinationItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.routePath,
  });
}

/// Navigation destinations configuration
class NavigationDestinations {
  // Shell destinations (managed by StatefulShellRoute) - Only 3: Home, Planning, Varys
  static const List<NavigationDestinationItem> _shellDestinations = [
    NavigationDestinationItem(
      label: 'Ana Sayfa',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      routePath: AppRouter.homePath,
    ),
    NavigationDestinationItem(
      label: 'Planlama',
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today,
      routePath: AppRouter.planningPath,
    ),
    NavigationDestinationItem(
      label: 'Varys',
      icon: Icons.smart_toy_outlined,
      selectedIcon: Icons.smart_toy,
      routePath: AppRouter.varysChatPath,
    ),
  ];

  /// Only shell destinations (for StatefulShellRoute branches)
  static List<NavigationDestinationItem> get shellDestinations => _shellDestinations;

  static List<NavigationDestination> get navigationDestinations => shellDestinations
      .map((d) => NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: d.selectedIcon != null ? Icon(d.selectedIcon!) : null,
            label: d.label,
          ))
      .toList();

  static List<NavigationRailDestination> get navigationRailDestinations =>
      shellDestinations
          .map((d) => NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: d.selectedIcon != null ? Icon(d.selectedIcon!) : null,
                label: Text(d.label),
              ))
          .toList();
}