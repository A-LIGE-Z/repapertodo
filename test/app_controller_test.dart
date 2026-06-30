import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('new papers inherit deep capsule defaults', () {
    final controller = RePaperTodoController(
      initialState: AppState(deepCapsuleSide: DeepCapsuleSides.left),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.capsuleSide, DeepCapsuleSides.left);
  });
}
