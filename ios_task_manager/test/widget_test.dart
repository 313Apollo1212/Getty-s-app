import 'package:flutter_test/flutter_test.dart';

import 'package:ios_task_manager/main.dart';

void main() {
  testWidgets('shows setup help when Supabase config is missing', (
    tester,
  ) async {
    await tester.pumpWidget(const TaskManagerApp());

    expect(find.text('Setup Required'), findsOneWidget);
    expect(
      find.textContaining('Missing Supabase configuration'),
      findsOneWidget,
    );
  });
}
