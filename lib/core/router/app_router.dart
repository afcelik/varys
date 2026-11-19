import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';
import 'package:varys/features/auth/domain/auth_state.dart';
import 'package:varys/features/auth/presentation/login_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/domain/focus_candidates.dart';
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/inbox/presentation/inbox_screen.dart';
import 'package:varys/features/notes/presentation/notes_screen.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/presentation/planning_screen.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/presentation/project_edit_screen.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/presentation/routine_edit_screen.dart';
import 'package:varys/features/routines/presentation/routines_screen.dart';
import 'package:varys/features/settings/presentation/settings_screen.dart';
import 'package:varys/features/varys_chat/presentation/varys_chat_screen.dart';
import 'package:varys/shared/widgets/back_arrow.dart';
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
  static const String routinesPath = '/routines';
  static const String routinesNewPath = '/routines/new';
  static const String routinesEditPath = '/routines/edit';
  static const String projectsPath = '/projects';
  static const String projectsNewPath = '/projects/new';
  static const String projectsEditPath = '/projects/edit';
  static const String tasksNewPath = '/tasks/new';
  static const String tasksEditPath = '/tasks/edit';

  /// Router error page (unknown path) texts.
  static const String errorTitle = 'Sayfa bulunamadı';
  static const String errorMessage = 'Aradığınız sayfa mevcut değil.';
  static const String errorHomeButton = 'Ana sayfaya dön';

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
          path: routinesPath,
          name: 'routines',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: RoutinesScreen(),
          ),
        ),
        // Projects page: opened by push from the Home card.
        GoRoute(
          path: projectsPath,
          name: 'projects',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProjectsScreen(),
          ),
        ),
        // Project create form: needs no extra.
        GoRoute(
          path: projectsNewPath,
          name: 'projects-new',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ProjectEditScreen(),
          ),
        ),
        // Project edit form: the Project must come as extra. Anything else
        // shows an error page; no fallback to create and no redirect (a
        // redirect on push adds a second /home).
        GoRoute(
          path: projectsEditPath,
          name: 'projects-edit',
          pageBuilder: (context, state) {
            final extra = state.extra;
            return NoTransitionPage(
              child: extra is Project
                  ? ProjectEditScreen(key: ValueKey('project-edit-${extra.id}'), project: extra)
                  : const ProjectEditUnavailablePage(),
            );
          },
        ),
        // Task create form: opened by push from Planning; needs no extra and
        // has no redirect. Not a menu destination.
        GoRoute(
          path: tasksNewPath,
          name: 'tasks-new',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TaskEditScreen(),
          ),
        ),
        // Task edit form: the Task must come as extra (pushed from a Planning
        // row). Anything else (null, wrong type) shows an error page; no
        // fallback to create and no redirect (a redirect on push adds a
        // second /home). Not a menu destination.
        GoRoute(
          path: tasksEditPath,
          name: 'tasks-edit',
          pageBuilder: (context, state) {
            final extra = state.extra;
            return NoTransitionPage(
              child: extra is Task
                  ? TaskEditScreen(key: ValueKey('task-edit-${extra.id}'), task: extra)
                  : const TaskEditUnavailablePage(),
            );
          },
        ),
        // Create form: needs no extra.
        GoRoute(
          path: routinesNewPath,
          name: 'routines-new',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: RoutineEditScreen(),
          ),
        ),
        // Edit form: the Routine must come as extra. Anything else (null,
        // wrong type) shows an error page; no silent fallback to create and
        // no redirect (a redirect on push adds a second /home).
        GoRoute(
          path: routinesEditPath,
          name: 'routines-edit',
          pageBuilder: (context, state) {
            final extra = state.extra;
            return NoTransitionPage(
              child: extra is Routine
                  ? RoutineEditScreen(key: ValueKey('routine-edit-${extra.id}'), routine: extra)
                  : const RoutineEditUnavailablePage(),
            );
          },
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
          // The slot must come as extra (from the focus cards). Without it
          // (deep link, notification, wrong type) show an error page, no
          // silent default. Not a redirect: go_router's redirect on push adds
          // a second /home to the stack.
          pageBuilder: (context, state) {
            final extra = state.extra;
            return NoTransitionPage(
              child: extra is FocusSlot
                  ? FocusTaskSelectionPage(slot: extra)
                  : const FocusSelectionUnavailablePage(),
            );
          },
        ),
        // Main app shell with navigation (3 tabs: Home, Planning, Varys)
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return MainScaffold(navigationShell: navigationShell);
          },
          branches: shellBranches,
        ),
      ],
      // Error handling: fixed Turkish text only; the error detail is never
      // shown, only printed in debug builds.
      errorBuilder: (context, state) {
        if (kDebugMode) debugPrint('Router error: ${state.error}');
        return const _RouterErrorPage();
      },
    );

    return router;
  }
}

/// Shown for an unknown path (deep link, notification, push). Leaves with
/// BackArrow (pop, or /home when nothing to pop) or the home button.
class _RouterErrorPage extends StatelessWidget {
  const _RouterErrorPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  AppRouter.errorTitle,
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppRouter.errorMessage,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go(AppRouter.homePath),
                  child: const Text(AppRouter.errorHomeButton),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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