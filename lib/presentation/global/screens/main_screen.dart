import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:purevideo/core/services/watched_service.dart';
import 'package:purevideo/di/injection_container.dart';
import 'package:purevideo/presentation/global/widgets/tv_focusable.dart';

/// Android TV main scaffold.
///
/// On TV the primary navigation lives on the LEFT edge of the screen as a
/// vertical rail. The bottom bar pattern from the mobile version is replaced
/// because:
///   * 16:9 screens have far more horizontal than vertical room,
///   * focus traversal with a D-Pad is more natural from a side rail
///     (LEFT/RIGHT cycles menu, UP/DOWN moves inside the current page).
class MainScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScreen({super.key, required this.navigationShell});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // Dispose resources when app is terminated
      getIt<WatchedService>().dispose();
      // getIt<VideoSourceRepository>().dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Row(
            children: [
              _TvSideNav(
                currentIndex: widget.navigationShell.currentIndex,
                onSelect: (index) {
                  if (index == widget.navigationShell.currentIndex) return;
                  widget.navigationShell.goBranch(
                    index,
                    initialLocation: false,
                  );
                },
              ),
              Expanded(
                child: FocusTraversalGroup(
                  policy: ReadingOrderTraversalPolicy(),
                  child: widget.navigationShell,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _TvNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

const _navItems = <_TvNavItem>[
  _TvNavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
    label: 'Główna',
  ),
  _TvNavItem(
    icon: Icons.search_outlined,
    activeIcon: Icons.search,
    label: 'Szukaj',
  ),
  _TvNavItem(
    icon: Icons.history_outlined,
    activeIcon: Icons.history,
    label: 'Oglądane',
  ),
  _TvNavItem(
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    label: 'Ustawienia',
  ),
];

class _TvSideNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _TvSideNav({
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 220,
      // Slightly darker panel so the rail visually separates from content.
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            child: Text(
              'PureVideo',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (var i = 0; i < _navItems.length; i++)
            _TvNavRailItem(
              item: _navItems[i],
              isSelected: currentIndex == i,
              // Only the first rail item auto-grabs focus when the app starts
              // so the user is never landed on a screen with no focused
              // widget.
              autofocus: i == 0,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _TvNavRailItem extends StatelessWidget {
  final _TvNavItem item;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;

  const _TvNavRailItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    final unselectedColor = theme.colorScheme.onSurface.withAlpha(170);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TvFocusable(
        onTap: onTap,
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(12),
        focusScale: 1.04,
        backgroundColor: isSelected
            ? selectedColor.withAlpha(40)
            : Colors.transparent,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Icon(
                isSelected ? item.activeIcon : item.icon,
                color: isSelected ? selectedColor : unselectedColor,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? selectedColor : unselectedColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
