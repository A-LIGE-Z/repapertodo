import 'package:flutter_test/flutter_test.dart';
import 'package:repapertodo/repapertodo.dart';

void main() {
  test('new papers inherit deep capsule defaults', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.left,
        deepCapsuleMonitorDeviceName: '  Primary monitor  ',
        deepCapsuleStartTopMargin: 72,
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.capsuleSide, DeepCapsuleSides.left);
    expect(paper.capsuleMonitorDeviceName, 'Primary monitor');
    expect(paper.y, 72);
  });

  test('new papers skip deep capsule defaults when disabled', () {
    final controller = RePaperTodoController(
      initialState: AppState(
        deepCapsuleSide: DeepCapsuleSides.left,
        useDeepCapsuleMode: false,
      ),
      platform: NoopPlatformServices(),
    );

    final paper = controller.createPaper(PaperTypes.note);

    expect(paper.capsuleSide, isEmpty);
    expect(paper.capsuleMonitorDeviceName, isEmpty);
    expect(paper.y, 120);
  });
}
