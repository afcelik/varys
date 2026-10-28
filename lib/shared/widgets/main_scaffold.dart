import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/breakpoints.dart';
import 'package:varys/core/router/app_router.dart';

/// Main scaffold that provides responsive navigation.
///
/// Uses extended NavigationRail for widths > 800px (desktop/tablet landscape)
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
        final isWideScreen = constraints.maxWidth > Breakpoints.mobileMaxWidth;

        // Handler for rail destination selection (wide screen)
        void onRailDestinationSelected(int index) {
          // Rail only shows shell destinations, so index maps directly
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        }

        // Handler for bottom nav bar destination selection (narrow screen)
        void onNavBarDestinationSelected(int index) {
          final destination = NavigationDestinations.allDestinations[index];
          if (destination.isExternalRoute) {
            context.go(destination.routePath);
          } else {
            navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            );
          }
        }

        return Scaffold(
          body: isWideScreen
              ? _buildWideLayout(context, onRailDestinationSelected)
              : _buildNarrowLayout(context),
          bottomNavigationBar: isWideScreen
              ? null
              : _buildBottomNavigationBar(context, onNavBarDestinationSelected),
        );
      },
    );
  }

  Widget _buildWideLayout(BuildContext context, void Function(int) onDestinationSelected) {
    return Row(
      children: [
        // Navigation Rail (Left side) - Extended to show labels
        NavigationRail(
          extended: true,
          minWidth: Breakpoints.railExtendedWidth,
          minExtendedWidth: Breakpoints.railExtendedWidth,
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: NavigationDestinations.navigationRailDestinations,
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: Breakpoints.railExtendedWidth,
                child: const _NavigationRailUserSection(),
              ),
            ),
          ),
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
    return navigationShell;
  }

  Widget? _buildBottomNavigationBar(
      BuildContext context, void Function(int) onDestinationSelected) {
    return NavigationBar(
      selectedIndex: _getSelectedNavBarIndex(),
      onDestinationSelected: onDestinationSelected,
      destinations: NavigationDestinations.navigationDestinations,
    );
  }

  /// Maps the shell's current index to the bottom nav bar destination index.
  /// Bottom nav bar includes all destinations (shell + external).
  int _getSelectedNavBarIndex() {
    return navigationShell.currentIndex;
  }
}

/// Navigation rail user section at the bottom (Settings only)
class _NavigationRailUserSection extends StatelessWidget {
  const _NavigationRailUserSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ListTile(
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
    );
  }
}