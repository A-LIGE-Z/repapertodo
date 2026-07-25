import 'package:flutter/animation.dart';

/// Shared visual motion tokens used by paper, todo, settings and capsule
/// surfaces.  The native Windows runner mirrors these timings where a HWND
/// owns the animation, so a state refresh never introduces a second rhythm.
abstract final class PaperTodoMotion {
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve quickCurve = Curves.easeOutQuad;

  /// The short state transition used for controls and row opacity. Keeping
  /// this in the same token set as the paper/capsule transitions prevents a
  /// content edit from acquiring a second, subtly different rhythm.
  static const Duration quick = Duration(milliseconds: 150);
  static const Duration fadeIn = Duration(milliseconds: 200);
  static const Duration fadeOut = Duration(milliseconds: 180);
  static const Duration move = Duration(milliseconds: 200);
  static const Duration moveLong = Duration(milliseconds: 220);

  // Native Windows capsule surfaces mirror these exact values in
  // windows/runner/paper_motion.h. They remain part of the Dart motion
  // contract even though the HWND animation itself is driven natively.
  static const Duration capsuleSlideOut = Duration(milliseconds: 220);
  static const Duration capsuleSlideIn = Duration(milliseconds: 180);
  static const Duration capsuleQueueMove = Duration(milliseconds: 200);
  static const Duration capsuleMasterMove = Duration(milliseconds: 200);
  static const Duration capsuleMasterFade = Duration(milliseconds: 160);

  /// PaperTodo's new-row entrance is intentionally a little longer than a
  /// normal move so the row has time to settle without a visible jump.
  static const Duration rowEntrance = Duration(milliseconds: 250);
  static const Duration todoPasteDelayUnit = Duration(milliseconds: 40);
  static const Duration todoCompletionDelayUnit = Duration(milliseconds: 30);
  static const Duration todoTransitionDelay = Duration(milliseconds: 20);

  static Duration stagger(Duration unit, int index) {
    if (index <= 0) {
      return Duration.zero;
    }
    return Duration(microseconds: unit.inMicroseconds * index);
  }
}
