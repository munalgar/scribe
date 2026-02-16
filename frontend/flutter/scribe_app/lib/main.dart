import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/connection_provider.dart';
import 'providers/transcription_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const ScribeApp());
}

class ScribeApp extends StatelessWidget {
  const ScribeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        ChangeNotifierProvider(create: (_) => TranscriptionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        title: 'Scribe',
        debugShowCheckedModeBanner: false,
        theme: ScribeTheme.light(),
        darkTheme: ScribeTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
