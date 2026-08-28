import 'package:flutter_test/flutter_test.dart';
import 'package:resqmesh/main.dart';

void main() {
  testWidgets('App shows login screen when not authenticated',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ResqMeshApp());

    // Login screen should render its primary title and button.
    expect(find.text('ResQMesh'), findsOneWidget);
    expect(find.text('LOG IN'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });
}
