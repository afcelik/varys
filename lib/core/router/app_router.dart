import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/storage/secure_storage.dart';
import 'package:varys/features/auth/presentation/change_password_screen.dart';
import 'package:varys/features/auth/presentation/lock_screen.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
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
class AppRouter {
  static const String homePath = '/home';
  static const String inboxPath = '/inbox';
  static const String planningPath = '/planning';
  static const String notesPath = '/notes';
  static const String varysChatPath = '/varys-chat';
  static const String settingsPath = '/settings';
  static const String lockPath = '/lock';
  static const String changePasswordPath = '/change-password';

  static GoRouter createRouter() {
    // Build shell branches dynamically from shared destinations
    final shellBranches = NavigationDestinations.shellDestinations.map((dest) {
      Widget screen;
      switch (dest.routePath) {
        case homePath:
          screen = const HomeScreen();
          break;
        case inboxPath:
          screen = const InboxScreen();
          break;
        case planningPath:
          screen = const PlanningScreen();
          break;
        case notesPath:
          screen = const NotesScreen();
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

    return GoRouter(
      initialLocation: homePath,
      // debugLogDiagnostics: true,
      // Redirect to lock screen if app password is set but not authenticated
      redirect: (context, state) async {
        // debugPrint('=== Router redirect called ===');
        // debugPrint('  Location: ${state.matchedLocation}');
        // debugPrint('  TopRoute: ${state.topRoute?.path}');
        // debugPrint('  FullPath: ${state.fullPath}');

        final hasAppPassword = await SecureStorage.hasAppPassword();
        final isLockRoute = state.matchedLocation == lockPath;
        final isChangePasswordRoute = state.matchedLocation == changePasswordPath;
        final isAuthRoute = isLockRoute || isChangePasswordRoute;
        // debugPrint('  hasAppPassword: $hasAppPassword, isAuthRoute: $isAuthRoute');

        // If has app password and not on auth pages, redirect to lock
        if (hasAppPassword && !isAuthRoute) {
          // debugPrint('  >>> Redirecting to lock (has app password)');
          return lockPath;
        }

        // If no app password and on auth pages, redirect to home
        if (!hasAppPassword && isAuthRoute) {
          // debugPrint('  >>> Redirecting to home (no app password)');
          return homePath;
        }

        // debugPrint('  >>> Allowing navigation');
        return null;
      },
      routes: [
        // Lock route (outside the shell - full screen)
        GoRoute(
          path: lockPath,
          name: 'lock',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LockScreen(),
          ),
        ),
        // Change Password route (outside the shell - full screen)
        GoRoute(
          path: changePasswordPath,
          name: 'change-password',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ChangePasswordScreen(),
          ),
        ),
        // Settings route (outside the shell - full screen)
        GoRoute(
          path: settingsPath,
          name: 'settings',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SettingsScreen(),
          ),
        ),
        // Main app shell with navigation
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
  }
}

/// Navigation destination model
class NavigationDestinationItem {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final String routePath;
  final bool isExternalRoute; // Route outside the StatefulShellRoute (e.g., Settings)

  const NavigationDestinationItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.routePath,
    this.isExternalRoute = false,
  });
}

/// Navigation destinations configuration
class NavigationDestinations {
  // Shell destinations (managed by StatefulShellRoute)
  static const List<NavigationDestinationItem> _shellDestinations = [
    NavigationDestinationItem(
      label: 'Ana Sayfa',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      routePath: AppRouter.homePath,
    ),
    NavigationDestinationItem(
      label: 'Gelen Kutusu',
      icon: Icons.inbox_outlined,
      selectedIcon: Icons.inbox,
      routePath: AppRouter.inboxPath,
    ),
    NavigationDestinationItem(
      label: 'Planlama',
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today,
      routePath: AppRouter.planningPath,
    ),
    NavigationDestinationItem(
      label: 'Notlar',
      icon: Icons.note_outlined,
      selectedIcon: Icons.note,
      routePath: AppRouter.notesPath,
    ),
    NavigationDestinationItem(
      label: 'Varys',
      icon: Icons.smart_toy_outlined,
      selectedIcon: Icons.smart_toy,
      routePath: AppRouter.varysChatPath,
    ),
  ];

  // External destinations (full-screen routes outside the shell)
  static const List<NavigationDestinationItem> _externalDestinations = [
    NavigationDestinationItem(
      label: 'Ayarlar',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      routePath: AppRouter.settingsPath,
      isExternalRoute: true,
    ),
  ];

  /// All destinations combined (shell + external)
  static List<NavigationDestinationItem> get allDestinations => [
        ..._shellDestinations,
        ..._externalDestinations,
      ];

  /// Only shell destinations (for StatefulShellRoute branches)
  static List<NavigationDestinationItem> get shellDestinations => _shellDestinations;

  /// Only external destinations (for bottom rail trailing, etc.)
  static List<NavigationDestinationItem> get externalDestinations => _externalDestinations;

  static List<NavigationDestination> get navigationDestinations => allDestinations
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