import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/inbox/presentation/inbox_screen.dart';
import '../../features/notes/presentation/notes_screen.dart';
import '../../features/planning/presentation/planning_screen.dart';
import '../../features/varys_chat/presentation/varys_chat_screen.dart';
import '../../shared/responsive_scaffold.dart';

part 'app_router.g.dart';

@riverpod
GoRouter router(RouterRef ref) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ResponsiveScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inbox',
                name: 'inbox',
                builder: (context, state) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/planning',
                name: 'planning',
                builder: (context, state) => const PlanningScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/notes',
                name: 'notes',
                builder: (context, state) => const NotesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/varys-chat',
                name: 'varys-chat',
                builder: (context, state) => const VarysChatScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

enum AppDestination {
  home('Home', Icons.home_outlined, Icons.home, '/home'),
  inbox('Inbox', Icons.inbox_outlined, Icons.inbox, '/inbox'),
  planning('Planning', Icons.calendar_today_outlined, Icons.calendar_today, '/planning'),
  notes('Notes', Icons.note_outlined, Icons.note, '/notes'),
  varysChat('Varys', Icons.chat_outlined, Icons.chat, '/varys-chat');

  const AppDestination(
    this.label,
    this.icon,
    this.selectedIcon,
    this.route,
  );

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
}