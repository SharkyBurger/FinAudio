import 'package:flutter_test/flutter_test.dart';

import 'package:finaudio/main.dart';

void main() {
  testWidgets('App renders player tab', (WidgetTester tester) async {
    await tester.pumpWidget(const FinAudioApp());
    await tester.pumpAndSettle();

    // Verify that the player tab is shown by default.
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
  });
}
