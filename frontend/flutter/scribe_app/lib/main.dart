import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/connection_provider.dart';
import 'providers/transcription_provider.dart';
import 'providers/settings_provider.dart';
import 'services/app_preferences.dart';
import 'services/backend_process.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ScribeApp());
}

class ScribeApp extends StatefulWidget {
  const ScribeApp({super.key});

  @override
  State<ScribeApp> createState() => _ScribeAppState();
}

class _ScribeAppState extends State<ScribeApp> {
  static const Duration _minSplashDuration = Duration(milliseconds: 1000);

  late final Future<AppPreferences> _preferencesFuture = _loadPreferences();

  Future<AppPreferences> _loadPreferences() async {
    final stopwatch = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    final remaining = _minSplashDuration - stopwatch.elapsed;
    if (!remaining.isNegative) {
      await Future<void>.delayed(remaining);
    }
    return AppPreferences(prefs);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppPreferences>(
      future: _preferencesFuture,
      builder: (context, snapshot) {
        return MaterialApp(
          title: 'Scribe',
          debugShowCheckedModeBanner: false,
          theme: ScribeTheme.dark(),
          home: switch (snapshot.connectionState) {
            ConnectionState.done when snapshot.hasData => _AppShell(
              preferences: snapshot.data!,
            ),
            ConnectionState.done when snapshot.hasError => _StartupErrorScreen(
              error: snapshot.error.toString(),
            ),
            _ => const LaunchSplashScreen(),
          },
        );
      },
    );
  }
}

class _AppShell extends StatelessWidget {
  final AppPreferences preferences;

  const _AppShell({required this.preferences});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: preferences),
        ChangeNotifierProvider(create: (_) => BackendProcessManager()),
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => TranscriptionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const HomeScreen(),
    );
  }
}

class LaunchSplashScreen extends StatelessWidget {
  const LaunchSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerLow,
            ],
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: 1,
                child: child,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/images/scribe-logo.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Scribe',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Preparing transcription workspace',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final String error;

  const _StartupErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  'Unable to initialize Scribe',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
