import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/storage/secure_storage.dart';
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

  static GoRouter createRouter(WidgetRef ref) {
    return GoRouter(
      initialLocation: homePath,
      // Redirect to settings if no token is present
      redirect: (context, state) async {
        final hasToken = await SecureStorage.hasApiToken();
        final isSettingsRoute = state.matchedLocation == settingsPath;

        // If no token and not on settings page, redirect to settings
        if (!hasToken && !isSettingsRoute) {
          return settingsPath;
        }

        // If has token and on settings page, allow (user may want to change settings)
        return null;
      },
      routes: [
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
          branches: [
            // Home branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: homePath,
                  name: 'home',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: HomeScreen(),
                  ),
                ),
              ],
            ),
            // Inbox branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: inboxPath,
                  name: 'inbox',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: InboxScreen(),
                  ),
                ),
              ],
            ),
            // Planning branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: planningPath,
                  name: 'planning',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: PlanningScreen(),
                  ),
                ),
              ],
            ),
            // Notes branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: notesPath,
                  name: 'notes',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: NotesScreen(),
                  ),
                ),
              ],
            ),
            // Varys Chat branch
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: varysChatPath,
                  name: 'varys-chat',
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: VarysChatScreen(),
                  ),
                ),
              ],
            ),
          ],
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

  const NavigationDestinationItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    required this.routePath,
  });
}

/// Navigation destinations configuration
class NavigationDestinations {
  static const List<NavigationDestinationItem> destinations = [
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

  static List<NavigationDestination> get navigationDestinations => destinations
      .map((d) => NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: d.selectedIcon != null ? Icon(d.selectedIcon!) : null,
            label: d.label,
          ))
      .toList();

  static List<NavigationRailDestination> get navigationRailDestinations =>
      destinations
          .map((d) => NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: d.selectedIcon != null ? Icon(d.selectedIcon!) : null,
                label: Text(d.label),
              ))
          .toList();
}