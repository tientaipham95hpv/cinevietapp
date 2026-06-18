import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/platform_detector.dart';
import '../theme/cineviet_colors.dart';
import '../theme/cineviet_dimensions.dart';
import '../../features/search/search_browse_screen.dart';
import 'cineviet_logo.dart';
import 'tv_focus.dart';

class CineVietDestination {
  const CineVietDestination({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

const cineVietDestinations = [
  CineVietDestination(icon: Icons.home_rounded, label: 'Trang chủ'),
  CineVietDestination(icon: Icons.groups_rounded, label: 'Xem chung'),
  CineVietDestination(icon: Icons.favorite_rounded, label: 'Yêu thích'),
  CineVietDestination(icon: Icons.playlist_play_rounded, label: 'Playlist'),
  CineVietDestination(icon: Icons.person_rounded, label: 'Cá nhân'),
];

class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({super.key, required this.children});
  final List<Widget> children;

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  int _index = 0;
  bool _tabletSidebarOpen = false;

  void _select(int value) {
    if (value == _index) return;
    setState(() => _index = value);
  }

  // IndexedStack keeps every tab alive in the tree and only hides the inactive
  // ones from painting. Their focusable widgets, however, still accept D-pad /
  // keyboard focus, so on Android TV focus silently lands on an invisible tab:
  // the user can't cross into the sidebar, the search button seems dead, and
  // the home rail scrolls on its own. Wrapping each page in ExcludeFocus keeps
  // focus confined to the visible tab.
  Widget _pages() {
    return IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          ExcludeFocus(excluding: i != _index, child: widget.children[i]),
      ],
    );
  }

  void _openSearch() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SearchBrowseScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final platform = PlatformDetector.of(context);
    return switch (platform.type) {
      CineVietPlatform.mobile => _mobile(context),
      CineVietPlatform.tablet => _mobile(context),
      CineVietPlatform.tv => _tv(context, platform),
      CineVietPlatform.desktop => _desktop(context, platform),
    };
  }

  Widget _mobile(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _pages(),
          if (_index == 0)
            Positioned(
              right: CineVietSpacing.md,
              top: MediaQuery.of(context).padding.top + CineVietSpacing.sm,
              child: _glassButton(
                icon: Icons.search_rounded,
                onTap: _openSearch,
              ),
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: CineVietColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 20,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: _select,
          items: [
            for (final d in cineVietDestinations)
              BottomNavigationBarItem(icon: Icon(d.icon), label: d.label),
          ],
        ),
      ),
    );
  }

  // Tablet intentionally reuses mobile bottom navigation; kept for future sidebar mode.
  // ignore: unused_element
  Widget _tablet(BuildContext context, PlatformInfo platform) {
    const sidebarWidth = 250.0;
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 220) setState(() => _tabletSidebarOpen = true);
        if (velocity < -220) setState(() => _tabletSidebarOpen = false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: _tabletSidebarOpen ? sidebarWidth : 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: _pages(),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: _tabletSidebarOpen ? 0 : -sidebarWidth,
              width: sidebarWidth,
              top: 0,
              bottom: 0,
              child: _sidePanel(expanded: true, tvMode: false),
            ),
            if (_tabletSidebarOpen)
              Positioned.fill(
                left: sidebarWidth,
                child: GestureDetector(
                  onTap: () => setState(() => _tabletSidebarOpen = false),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.34),
                  ),
                ),
              ),
            Positioned(
              left: CineVietSpacing.md,
              top: MediaQuery.of(context).padding.top + CineVietSpacing.sm,
              child: _glassButton(
                icon: _tabletSidebarOpen
                    ? Icons.menu_open_rounded
                    : Icons.menu_rounded,
                onTap: () =>
                    setState(() => _tabletSidebarOpen = !_tabletSidebarOpen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tv(BuildContext context, PlatformInfo platform) {
    const railWidth = 128.0;
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: railWidth,
            child: _sidePanel(expanded: false, tvMode: true),
          ),
          Expanded(
            child: Stack(
              children: [
                _pages(),
                Positioned(
                  right: CineVietSpacing.lg,
                  top: MediaQuery.of(context).padding.top + CineVietSpacing.lg,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_index == 0) ...[
                        _glassButton(
                          icon: Icons.search_rounded,
                          onTap: _openSearch,
                          tvFocusable: true,
                        ),
                        const SizedBox(width: CineVietSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktop(BuildContext context, PlatformInfo platform) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: _sidePanel(expanded: true, tvMode: false),
          ),
          Expanded(
            child: Stack(
              children: [
                _pages(),
                if (_index == 0)
                  Positioned(
                    right: CineVietSpacing.lg,
                    top:
                        MediaQuery.of(context).padding.top + CineVietSpacing.lg,
                    child: _glassButton(
                      icon: Icons.search_rounded,
                      onTap: _openSearch,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidePanel({required bool expanded, required bool tvMode}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CineVietColors.card,
        border: Border(right: BorderSide(color: CineVietColors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(CineVietSpacing.lg),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [CineVietLogo(size: 34, showText: expanded)],
              ),
            ),
            const SizedBox(height: CineVietSpacing.md),
            for (var i = 0; i < cineVietDestinations.length; i++)
              _NavTile(
                destination: cineVietDestinations[i],
                selected: i == _index,
                expanded: expanded,
                tvMode: tvMode,
                onTap: () => _select(i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _glassButton({
    required IconData icon,
    required VoidCallback onTap,
    bool tvFocusable = false,
  }) {
    // On TV the glass buttons (search / expand rail) must be reachable by the
    // D-pad; a bare InkWell is not focusable, so wrap with TvFocus there.
    return TvFocus(
      enabled: tvFocusable,
      onTap: onTap,
      borderRadius: BorderRadius.circular(CineVietRadius.full),
      child: Material(
        color: CineVietColors.card.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(CineVietRadius.full),
        child: InkWell(
          borderRadius: BorderRadius.circular(CineVietRadius.full),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(CineVietSpacing.sm),
            decoration: BoxDecoration(
              border: Border.all(color: CineVietColors.borderLight),
              borderRadius: BorderRadius.circular(CineVietRadius.full),
            ),
            child: Icon(icon, color: CineVietColors.accent),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.tvMode,
    required this.onTap,
  });
  final CineVietDestination destination;
  final bool selected;
  final bool expanded;
  final bool tvMode;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    // On TV, TvFocus below owns the D-pad focus node. Keep this outer Focus
    // non-focusable there so the two don't compete and trap navigation when
    // moving into the sidebar. On desktop TvFocus is disabled, so this Focus
    // handles keyboard activation instead.
    return Focus(
      canRequestFocus: !widget.tvMode,
      skipTraversal: widget.tvMode,
      onKeyEvent: (node, event) {
        if (!widget.tvMode &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (value) => setState(() => focused = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CineVietSpacing.sm,
          vertical: CineVietSpacing.xs,
        ),
        child: TvFocus(
          enabled: widget.tvMode,
          scale: 1.04,
          borderRadius: BorderRadius.circular(CineVietRadius.lg),
          onTap: widget.onTap,
          builder: (context, tvFocused, child) {
            final tileActive = widget.selected || focused || tvFocused;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: widget.expanded
                    ? CineVietSpacing.md
                    : CineVietSpacing.sm,
                vertical: widget.tvMode
                    ? CineVietSpacing.md
                    : CineVietSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: tileActive
                    ? (widget.tvMode && tvFocused
                          ? CineVietColors.cardHover
                          : CineVietColors.accentSoft)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(CineVietRadius.lg),
                border: focused && !widget.tvMode
                    ? Border.all(color: CineVietColors.accent, width: 2)
                    : null,
              ),
              child: widget.expanded
                  ? Row(
                      children: [
                        Icon(
                          widget.destination.icon,
                          color: tileActive
                              ? CineVietColors.accent
                              : CineVietColors.textSoft,
                        ),
                        const SizedBox(width: CineVietSpacing.md),
                        Text(
                          widget.destination.label,
                          style: TextStyle(
                            color: tileActive
                                ? CineVietColors.accent
                                : CineVietColors.textSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.destination.icon,
                          size: widget.tvMode ? 30 : 24,
                          color: tileActive
                              ? CineVietColors.accent
                              : CineVietColors.textSoft,
                        ),
                        const SizedBox(height: CineVietSpacing.xs),
                        Text(
                          widget.destination.label,
                          style: TextStyle(
                            color: tileActive
                                ? CineVietColors.accent
                                : CineVietColors.textSoft,
                            fontSize: widget.tvMode ? 12 : 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            );
          },
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }
}
