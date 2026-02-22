import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scribe_app/main.dart';
import 'package:scribe_app/services/app_preferences.dart';

void main() {
  testWidgets('ScribeApp renders without crashing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ScribeApp(preferences: AppPreferences(prefs)));
    expect(find.text('Scribe'), findsWidgets);
  });
}
