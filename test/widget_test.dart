import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/src/app.dart';
import 'package:repapertodo/src/app_controller.dart';
import 'package:repapertodo/src/core/model/app_state.dart';
import 'package:repapertodo/src/core/model/paper_constants.dart';
import 'package:repapertodo/src/core/model/paper_data.dart';
import 'package:repapertodo/src/core/model/paper_item.dart';
import 'package:repapertodo/src/core/storage/state_store.dart';
import 'package:repapertodo/src/platform/noop_platform_services.dart';

void main() {
  testWidgets('renders the initial paper board', (tester) async {
    final controller = RePaperTodoController(
      initialState: AppState(
        papers: [
          PaperData(
            id: 'welcome-todo',
            type: PaperTypes.todo,
            title: 'Windows parity',
            items: [
              PaperItem(id: 'todo-1', text: 'Build compatible data core'),
            ],
          ),
        ],
      ),
      platform: NoopPlatformServices(),
    );
    final store = StateStore(filePath: 'build/test-widget-data.json');

    await tester.pumpWidget(
      RePaperTodoApp(
        controller: controller,
        store: store,
      ),
    );

    expect(find.text('RePaperTodo'), findsWidgets);
    expect(find.text('Windows parity'), findsOneWidget);
    expect(find.text('Build compatible data core'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('welcome-todo-title')), 'Edited title');
    await tester.pump();

    expect(controller.state.papers.single.title, 'Edited title');

    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isCollapsed, true);
    expect(find.text('Build compatible data core'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isCollapsed, false);
    expect(find.text('Build compatible data core'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isVisible, false);
    expect(find.text('Edited title'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(controller.state.papers.single.isVisible, true);
    expect(find.text('Edited title'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.sync_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Sync is disabled.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('WebDAV sync'), findsOneWidget);
    expect(find.text('Jianguoyun'), findsOneWidget);
    expect(find.text('Generic'), findsOneWidget);
  });
}
