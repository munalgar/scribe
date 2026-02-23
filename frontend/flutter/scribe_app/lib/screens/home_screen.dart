import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/transcription_provider.dart';
import '../providers/settings_provider.dart';
import '../services/app_preferences.dart';
import '../services/backend_process.dart';
import '../theme.dart';
import '../widgets/connection_status_banner.dart';
import 'transcription_screen.dart';
import 'jobs_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _isNavSidebarCollapsed = false;
  ConnectionProvider? _conn;
  VoidCallback? _connListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initProviders();
    });
  }

  @override
  void dispose() {
    if (_conn != null && _connListener != null) {
      _conn!.removeListener(_connListener!);
    }
    super.dispose();
  }

  void _initProviders() {
    _conn = context.read<ConnectionProvider>();
    final transcription = context.read<TranscriptionProvider>();
    final settings = context.read<SettingsProvider>();
    final prefs = context.read<AppPreferences>();
    final backendProcess = context.read<BackendProcessManager>();

    _connListener = () {
      if (_conn!.state == BackendConnectionState.connected) {
        transcription.updateClient(_conn!.client);
        settings.updateClient(_conn!.client);
        transcription.loadJobs();
        settings.loadSettings();
        settings.loadModels();
      } else {
        transcription.updateClient(null);
        settings.updateClient(null);
      }
    };

    _conn!.addListener(_connListener!);

    if (prefs.backendMode == BackendMode.managed) {
      // Auto-start the bundled backend and connect once it's ready.
      _startManagedBackend(backendProcess, prefs);
    } else {
      // External mode: connect to whatever host/port is configured.
      _conn!.connect(host: prefs.serverHost, port: prefs.serverPort);
    }
  }

  Future<void> _startManagedBackend(
    BackendProcessManager process,
    AppPreferences prefs,
  ) async {
    try {
      final port = await process.start();
      // Connect to the backend on the port it chose.
      _conn!.connect(host: '127.0.0.1', port: port);
    } catch (e) {
      // If the bundled binary isn't found, fall back to external mode
      // (the user is probably a developer who hasn't built it yet).
      debugPrint(
        '[home] Managed backend failed: $e — falling back to external',
      );
      _conn!.connect(host: prefs.serverHost, port: prefs.serverPort);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const TranscriptionScreen(),
      JobsScreen(onJobOpened: () => setState(() => _selectedIndex = 0)),
      const SettingsScreen(),
    ];

    final theme = Theme.of(context);
    final sidebarBg = ScribeTheme.sidebarBackground(context);
    final selectedBg = ScribeTheme.sidebarSelectedItem(context);

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: _isNavSidebarCollapsed ? 76 : 252,
            decoration: BoxDecoration(
              color: sidebarBg,
              border: Border(
                right: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final canShowFullHeader = constraints.maxWidth >= 180;
                      if (!canShowFullHeader) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: IconButton(
                              tooltip: 'Expand navigation sidebar',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _isNavSidebarCollapsed = false);
                              },
                              icon: const Icon(Icons.menu_rounded, size: 22),
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.asset(
                                'assets/images/scribe-logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Scribe',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Collapse navigation sidebar',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() => _isNavSidebarCollapsed = true);
                              },
                              icon: const Icon(
                                Icons.menu_open_rounded,
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  SizedBox(height: _isNavSidebarCollapsed ? 6 : 14),

                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: _isNavSidebarCollapsed ? 8 : 12,
                    ),
                    child: Column(
                      children: [
                        _SidebarItem(
                          icon: Icons.add_circle_outline_rounded,
                          selectedIcon: Icons.add_circle_rounded,
                          label: 'New Transcription',
                          isSelected: _selectedIndex == 0,
                          onTap: () => setState(() => _selectedIndex = 0),
                          selectedBg: selectedBg,
                          isCollapsed: _isNavSidebarCollapsed,
                        ),
                        const SizedBox(height: 6),
                        _SidebarItem(
                          icon: Icons.history_rounded,
                          selectedIcon: Icons.history_rounded,
                          label: 'History',
                          isSelected: _selectedIndex == 1,
                          onTap: () {
                            setState(() => _selectedIndex = 1);
                            // Auto-refresh jobs when navigating to History
                            final conn = context.read<ConnectionProvider>();
                            if (conn.state ==
                                BackendConnectionState.connected) {
                              context.read<TranscriptionProvider>().loadJobs();
                            }
                          },
                          selectedBg: selectedBg,
                          isCollapsed: _isNavSidebarCollapsed,
                        ),
                        const SizedBox(height: 6),
                        _SidebarItem(
                          icon: Icons.tune_rounded,
                          selectedIcon: Icons.tune_rounded,
                          label: 'Settings',
                          isSelected: _selectedIndex == 2,
                          onTap: () => setState(() => _selectedIndex = 2),
                          selectedBg: selectedBg,
                          isCollapsed: _isNavSidebarCollapsed,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Connection status indicator
                  _SidebarConnectionStatus(
                    isCollapsed: _isNavSidebarCollapsed,
                    onTap: () => setState(() => _selectedIndex = 2),
                  ),

                  SizedBox(height: _isNavSidebarCollapsed ? 12 : 8),
                ],
              ),
            ),
          ),

          // Content area
          Expanded(
            child: Container(
              color: theme.scaffoldBackgroundColor,
              child: Column(
                children: [
                  ConnectionStatusBanner(
                    onOpenSettings: () => setState(() => _selectedIndex = 2),
                  ),
                  Expanded(child: screens[_selectedIndex]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color selectedBg;
  final bool isCollapsed;

  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.selectedBg,
    required this.isCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final canShowLabel = !isCollapsed && constraints.maxWidth >= 96;
              final horizontalPadding = canShowLabel ? 14.0 : 6.0;

              return Container(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? selectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: canShowLabel
                    ? Row(
                        children: [
                          Icon(
                            isSelected ? selectedIcon : icon,
                            size: 19,
                            color: isSelected
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Icon(
                          isSelected ? selectedIcon : icon,
                          size: 19,
                          color: isSelected
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Always-visible connection indicator at the bottom of the sidebar.
class _SidebarConnectionStatus extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback onTap;

  const _SidebarConnectionStatus({
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final theme = Theme.of(context);

    final (Color dotColor, String label) = switch (conn.state) {
      BackendConnectionState.connected => (Colors.green, 'Connected'),
      BackendConnectionState.connecting => (Colors.orange, 'Connecting…'),
      BackendConnectionState.error => (theme.colorScheme.error, 'Disconnected'),
      BackendConnectionState.disconnected => (
        theme.colorScheme.onSurfaceVariant,
        'Offline',
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final showExpanded = !isCollapsed && constraints.maxWidth >= 140;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: showExpanded ? 12 : 8),
          child: Tooltip(
            message: conn.statusMessage,
            waitDuration: const Duration(milliseconds: 400),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: showExpanded ? 14 : 6,
                    vertical: 10,
                  ),
                  child: showExpanded
                      ? Row(
                          children: [
                            _AnimatedDot(color: dotColor, size: 8),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(child: _AnimatedDot(color: dotColor, size: 10)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A pulsing dot for the "connecting" state, static otherwise.
class _AnimatedDot extends StatefulWidget {
  final Color color;
  final double size;

  const _AnimatedDot({required this.color, required this.size});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _maybeAnimate();
  }

  @override
  void didUpdateWidget(covariant _AnimatedDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeAnimate();
  }

  void _maybeAnimate() {
    // Pulse when orange (connecting).
    if (widget.color == Colors.orange) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withAlpha(
              (255 * (0.4 + 0.6 * _controller.value)).toInt(),
            ),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
