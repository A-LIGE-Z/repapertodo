import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';

void main() {
  testWidgets('renders the initial paper board', (tester) async {
    await tester.pumpWidget(const RePaperTodoApp());

    expect(find.text('RePaperTodo'), findsWidgets);
    expect(find.text('Windows parity'), findsOneWidget);
    expect(find.text('Build compatible data core'), findsOneWidget);
  });
}
