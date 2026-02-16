import 'package:flutter_test/flutter_test.dart';

import 'package:scribe_app/main.dart';

void main() {
  testWidgets('ScribeApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ScribeApp());
    expect(find.text('Scribe'), findsWidgets);
  });
}
