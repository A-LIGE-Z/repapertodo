#ifndef RUNNER_PAPER_MOTION_H_
#define RUNNER_PAPER_MOTION_H_

#include <cstdint>

// Native HWND animations mirror the Dart PaperTodoMotion contract. Keep the
// values here instead of duplicating them in each native surface so paper and
// capsule windows cannot silently drift to different motion rhythms.
namespace repapertodo::motion {

inline constexpr int kCapsuleSlideOutMilliseconds = 220;
inline constexpr int kCapsuleSlideInMilliseconds = 180;
inline constexpr int kCapsuleQueueMoveMilliseconds = 200;
inline constexpr int kCapsuleMasterMoveMilliseconds = 200;
inline constexpr int kCapsuleMasterFadeMilliseconds = 160;
inline constexpr int kAnimationFrameMilliseconds = 16;

// Keep the native easing curve byte-for-byte equivalent to PaperTodo's shared
// CubicEase(EaseOut) and Flutter's Curves.easeOutCubic. The original applies
// the same curve to slot movement, hover reveal and opacity in both directions.
inline constexpr double EaseOutCubic(double progress) noexcept {
  const double clamped = progress < 0.0 ? 0.0 :
                         (progress > 1.0 ? 1.0 : progress);
  const double inverse = 1.0 - clamped;
  return 1.0 - inverse * inverse * inverse;
}

inline constexpr double AnimationProgress(std::uint64_t elapsed_ms,
                                          int duration_ms) noexcept {
  if (duration_ms <= 0) {
    return 1.0;
  }
  return static_cast<double>(elapsed_ms) /
         static_cast<double>(duration_ms);
}

}  // namespace repapertodo::motion

#endif  // RUNNER_PAPER_MOTION_H_
