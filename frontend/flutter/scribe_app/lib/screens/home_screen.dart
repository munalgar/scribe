import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/transcription_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
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
    _conn!.connect();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const TranscriptionScreen(),
      const JobsScreen(),
      const SettingsScreen(),
    ];

    final theme = Theme.of(context);
    final sidebarBg = ScribeTheme.sidebarBackground(context);
    final selectedBg = ScribeTheme.sidebarSelectedItem(context);

    return Scaffold(
      body: Row(
        children: [
          // Claude-style sidebar
          Container(
            width: 240,
            color: sidebarBg,
            child: SafeArea(
              child: Column(
                children: [
                  // Logo / branding
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.mic_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Scribe',
                          style: GoogleFonts.instrumentSerif(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Navigation items
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        _SidebarItem(
                          icon: Icons.add_circle_outline_rounded,
                          selectedIcon: Icons.add_circle_rounded,
                          label: 'New Transcription',
                          isSelected: _selectedIndex == 0,
                          onTap: () => setState(() => _selectedIndex = 0),
                          selectedBg: selectedBg,
                        ),
                        const SizedBox(height: 4),
                        _SidebarItem(
                          icon: Icons.history_rounded,
                          selectedIcon: Icons.history_rounded,
                          label: 'History',
                          isSelected: _selectedIndex == 1,
                          onTap: () {
                            setState(() => _selectedIndex = 1);
                            // Auto-refresh jobs when navigating to History
                            final conn = context.read<ConnectionProvider>();
                            if (conn.state == BackendConnectionState.connected) {
                              context.read<TranscriptionProvider>().loadJobs();
                            }
                          },
                          selectedBg: selectedBg,
                        ),
                        const SizedBox(height: 4),
                        _SidebarItem(
                          icon: Icons.tune_rounded,
                          selectedIcon: Icons.tune_rounded,
                          label: 'Settings',
                          isSelected: _selectedIndex == 2,
                          onTap: () => setState(() => _selectedIndex = 2),
                          selectedBg: selectedBg,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),

          // Content area
          Expanded(
            child: Container(
              color: theme.scaffoldBackgroundColor,
              child: screens[_selectedIndex],
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

  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.selectedBg,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                size: 20,
                color: isSelected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
