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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ScribeApp(preferences: AppPreferences(prefs)));
}

class ScribeApp extends StatelessWidget {
  final AppPreferences preferences;

  const ScribeApp({super.key, required this.preferences});

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
      child: MaterialApp(
        title: 'Scribe',
        debugShowCheckedModeBanner: false,
        theme: ScribeTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
