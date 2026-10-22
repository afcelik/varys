import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';

/// Main scaffold that provides responsive navigation.
///
/// Uses NavigationRail for widths > 800px (desktop/tablet landscape)
/// and NavigationBar for widths <= 800px (mobile/tablet portrait).
///
/// Wraps a StatefulNavigationShell to preserve state across tab switches.
class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({
    super.key,
    required this.navigationShell,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 800;

        return Scaffold(
          body: isWideScreen
              ? _buildWideLayout(context)
              : _buildNarrowLayout(context),
        );
      },
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      children: [
        // Navigation Rail (Left side)
        NavigationRail(
          extended: false,
          minWidth: 72,
          minExtendedWidth: 200,
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: NavigationDestinations.navigationRailDestinations,
          trailing: const _NavigationRailUserSection(),
        ),
        // Vertical divider
        const VerticalDivider(
          thickness: 1,
          width: 1,
        ),
        // Main content area
        Expanded(
          child: navigationShell,
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: NavigationDestinations.navigationDestinations,
      ),
    );
  }

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// User section at the bottom of the navigation rail
class _NavigationRailUserSection extends StatelessWidget {
  const _NavigationRailUserSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            title: Text(
              'Kullanıcı',
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'kullanici@varys.app',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            dense: true,
            onTap: () {
              context.go(AppRouter.settingsPath);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              Icons.settings_outlined,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            title: Text(
              'Ayarlar',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            dense: true,
            onTap: () {
              context.go(AppRouter.settingsPath);
            },
          ),
        ],
      ),
    );
  }
}