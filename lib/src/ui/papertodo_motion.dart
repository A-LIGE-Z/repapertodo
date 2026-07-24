import 'package:flutter/animation.dart';

/// Shared visual motion tokens used by paper, todo, settings and capsule
/// surfaces.  The native Windows runner mirrors these timings where a HWND
/// owns the animation, so a state refresh never introduces a second rhythm.
abstract final class PaperTodoMotion {
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve quickCurve = Curves.easeOutQuad;

  static const Duration fadeIn = Duration(milliseconds: 200);
  static const Duration fadeOut = Duration(milliseconds: 180);
  static const Duration move = Duration(milliseconds: 200);
  static const Duration moveLong = Duration(milliseconds: 220);
}
