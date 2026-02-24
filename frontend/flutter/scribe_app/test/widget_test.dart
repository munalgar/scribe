import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scribe_app/providers/connection_provider.dart';
import 'package:scribe_app/providers/settings_provider.dart';
import 'package:scribe_app/providers/transcription_provider.dart';
import 'package:scribe_app/screens/settings_screen.dart';
import 'package:scribe_app/services/app_preferences.dart';
import 'package:scribe_app/services/backend_process.dart';
import 'package:scribe_app/theme.dart';

void main() {
  testWidgets('SettingsScreen renders without crashing', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        theme: ScribeTheme.dark(),
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: AppPreferences(prefs)),
              ChangeNotifierProvider(create: (_) => ConnectionProvider()),
              ChangeNotifierProvider(create: (_) => TranscriptionProvider()),
              ChangeNotifierProvider(create: (_) => SettingsProvider()),
              ChangeNotifierProvider(create: (_) => BackendProcessManager()),
            ],
            child: const SettingsScreen(),
          ),
        ),
      ),
    );
    expect(find.text('Settings'), findsWidgets);
  });
}
