import 'package:flutter_test/flutter_test.dart';
import 'package:resqmesh/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App shows login screen when not authenticated',
      (WidgetTester tester) async {
    // No persisted token — user must see the login screen.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ResqMeshApp());

    // restoreSession() is async; pump enough frames for it to finish. Keep
    // durations bounded because the loading splash animates indefinitely and
    // pumpAndSettle would never settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Login screen should render its primary title and button.
    expect(find.text('ResQMesh'), findsOneWidget);
    expect(find.text('LOG IN'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });
}
