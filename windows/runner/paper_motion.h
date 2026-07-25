#ifndef RUNNER_PAPER_MOTION_H_
#define RUNNER_PAPER_MOTION_H_

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

}  // namespace repapertodo::motion

#endif  // RUNNER_PAPER_MOTION_H_
