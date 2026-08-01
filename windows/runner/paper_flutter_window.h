#ifndef RUNNER_PAPER_FLUTTER_WINDOW_H_
#define RUNNER_PAPER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <functional>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "win32_window.h"

class PaperFlutterWindow : public Win32Window {
 public:
  using EventCallback = std::function<void(
      const std::string&, const flutter::EncodableValue&)>;

  PaperFlutterWindow(const flutter::DartProject& project,
                     std::string paper_id, EventCallback event_callback);
  ~PaperFlutterWindow() override;

  const std::string& paper_id() const { return paper_id_; }

  void ApplyState(const flutter::EncodableValue& state);
  void ApplyPaper(const flutter::EncodableValue& paper);
  void ApplySurface(const flutter::EncodableMap& surface,
                    ULONGLONG animation_epoch = 0);
  bool IsCollapsed() const { return collapsed_; }
  bool IsInCapsuleQueue(const std::string& monitor_device_name,
                        const std::string& side) const;
  void BeginQueueDrag();
  bool PrepareQueueDragOffset(int delta_y, RECT* target_bounds);
  void SetQueueDragBoundsApplying(bool applying);
  void ApplyQueueDragOffset(int delta_y);
  void FinishQueueDrag(bool commit);
  void SetAlwaysOnTop(bool enabled);
  void SetPinnedToDesktop(bool pinned);
  void SetPaperTitle(const std::string& title);
  flutter::EncodableValue BoundsValue() const;
  bool IsVisible() const;
  bool ShowPaper(bool activate);
  void HidePaper();
  void SetHideFromWindowSwitcher(bool hidden);
  void SetAvoidFullscreenTopmost(bool avoid);
  void RefreshZOrder();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SendBoundsChanged();
  void SendEvent(const std::string& method,
                 const flutter::EncodableValue& arguments);
  void FlushInitialState();
  void ApplyNativeStyle();
  void EnsurePaperShadowWindow();
  void UpdatePaperShadowWindow(bool redraw);
  void PreparePaperSurfaceShapeChange();
  void DeferPaperShadowRefreshUntilNextFrame(bool reveal_surface = false);
  void HidePaperShadowWindow();
  void DestroyPaperShadowWindow();
  static LRESULT CALLBACK PaperShadowWindowProc(HWND window, UINT message,
                                                 WPARAM wparam,
                                                 LPARAM lparam) noexcept;
  int ResizeBorderHitTest(LPARAM lparam) const;
  void SetCapsuleHovered(bool hovered);
  void ResetCapsuleHoverAnimationForHiddenState();
  void StartCapsuleDockAnimation(double target_visible_width, int duration_ms);
  void UpdateCapsuleDockAnimation();
  void ApplyCapsuleHorizontalPosition();
  void StartMasterCapsuleTransition(int target_top, bool target_hidden,
                                    int move_duration_ms,
                                    int fade_duration_ms,
                                    ULONGLONG animation_epoch = 0);
  void UpdateMasterCapsuleTransition();
  void CompleteMasterCapsuleTransitionAtTarget();
  void PauseMasterTransitionForQueueDrag();
  void ResumeMasterTransitionAfterQueueDrag();
  void ApplyMasterCapsuleAlpha(int alpha);
  int MasterCapsuleTopPhysical() const;
  int DockedCapsuleTopPhysical() const;
  int EffectiveMasterCapsuleTopPhysical() const;
  int QueueDragModelOffsetY() const;
  void CaptureQueueDragModelAnchors();
  void ReconcileCommittedQueueModel(int docked_top, int master_top);
  void ClearCommittedQueueDrag();
  void StartQueueDragAnimation(int target_top, int duration_ms);
  void CompleteQueueDragAnimationAtTarget();
  void UpdateQueueDragAnimation();
  void ApplyQueueDragTop(int top);
  void SendCapsuleDropped();
  void ShowReminderBubble(const flutter::EncodableMap& reminder);
  void HideReminderBubble();
  void PlaceReminderBubble();
  std::optional<std::string> ShowContextMenu(
      const flutter::EncodableMap& arguments);
  bool MeasureContextMenuItem(MEASUREITEMSTRUCT* measure) const;
  bool DrawContextMenuItem(const DRAWITEMSTRUCT* draw) const;
  LRESULT ReminderBubbleMessageHandler(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam) noexcept;
  static LRESULT CALLBACK ReminderBubbleWindowProc(HWND window, UINT message,
                                                    WPARAM wparam,
                                                    LPARAM lparam) noexcept;

  enum class ContextMenuItemKind { padding, header, command, separator };

  struct ContextMenuItem {
    ContextMenuItemKind kind = ContextMenuItemKind::command;
    std::wstring text;
    std::string value;
    UINT command_id = 0;
    int logical_height = 0;
    bool enabled = false;
  };

  struct ContextMenuPalette {
    COLORREF background = RGB(255, 250, 239);
    COLORREF border = RGB(218, 198, 161);
    COLORREF text = RGB(54, 47, 39);
    COLORREF header_text = RGB(113, 100, 83);
    COLORREF disabled_text = RGB(113, 100, 83);
    COLORREF hover = RGB(238, 229, 211);
    bool dark = false;
  };

  flutter::DartProject project_;
  std::string paper_id_;
  EventCallback event_callback_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  flutter::EncodableValue latest_state_;
  flutter::EncodableValue latest_paper_;
  bool child_ready_ = false;
  bool applying_bounds_ = false;
  // A queue drag is applied by the coordinator's DeferWindowPos transaction.
  // Keep that marker separate from the paper's own SetWindowPos guards so a
  // nested native transaction cannot clear an already-active bounds update.
  bool queue_drag_bounds_applying_ = false;
  bool surface_initialized_ = false;
  bool always_on_top_ = false;
  bool pinned_to_desktop_ = false;
  bool hide_from_window_switcher_ = false;
  bool avoid_fullscreen_topmost_ = true;
  bool fullscreen_blocked_ = false;
  bool intended_visible_ = false;
  bool capsule_hidden_by_master_ = false;
  bool capsule_master_top_is_work_area_relative_ = true;
  double capsule_master_top_ = 48.0;
  bool master_capsule_transition_initialized_ = false;
  bool master_capsule_transition_active_ = false;
  bool master_capsule_transition_target_hidden_ = false;
  bool master_capsule_retracted_ = false;
  double master_capsule_transition_start_top_ = 0.0;
  double master_capsule_transition_target_top_ = 0.0;
  int master_capsule_transition_start_alpha_ = 255;
  int master_capsule_transition_target_alpha_ = 255;
  ULONGLONG master_capsule_transition_started_at_ = 0;
  int master_capsule_transition_move_duration_ms_ = 0;
  int master_capsule_transition_fade_duration_ms_ = 0;
  int capsule_alpha_ = 255;
  int applied_window_alpha_ = 255;
  int64_t surface_generation_ = -1;
  bool collapsed_ = false;
  bool deep_capsule_mode_ = false;
  std::string paper_type_ = "todo";
  bool script_capsule_ = false;
  std::string capsule_font_family_ = "Microsoft YaHei UI";
  bool capsule_hovered_ = false;
  bool capsule_animations_enabled_ = true;
  std::string capsule_side_ = "right";
  std::string capsule_monitor_device_name_;
  RECT capsule_work_area_ = {};
  int capsule_docked_top_ = 0;
  double capsule_width_ = 92.0;
  double capsule_resting_visible_width_ = 54.0;
  double capsule_hover_visible_width_ = 73.0;
  double capsule_current_visible_width_ = 0.0;
  double capsule_animation_start_width_ = 0.0;
  double capsule_animation_target_width_ = 0.0;
  ULONGLONG capsule_animation_started_at_ = 0;
  int capsule_animation_duration_ms_ = 0;
  bool capsule_animation_active_ = false;
  bool hide_when_covered_ = false;
  bool hide_when_fullscreen_ = false;
  bool paper_resize_start_pending_ = false;
  bool in_size_move_ = false;
  bool queue_drag_offset_active_ = false;
  int queue_drag_base_top_ = 0;
  int queue_drag_target_top_ = 0;
  int queue_drag_last_delta_y_ = 0;
  bool queue_drag_master_transition_coupled_ = false;
  ULONGLONG queue_drag_master_transition_paused_at_ = 0;
  bool queue_drag_commit_pending_ = false;
  int queue_drag_committed_delta_y_ = 0;
  int queue_drag_model_base_docked_top_ = 0;
  int queue_drag_model_base_master_top_ = 0;
  double queue_drag_animation_start_top_ = 0.0;
  double queue_drag_animation_target_top_ = 0.0;
  ULONGLONG queue_drag_animation_started_at_ = 0;
  int queue_drag_animation_duration_ms_ = 0;
  bool queue_drag_animation_active_ = false;
  bool z_order_initialized_ = false;
  bool z_order_pinned_ = false;
  bool z_order_topmost_ = false;
  HWND paper_shadow_window_ = nullptr;
  int paper_shadow_width_ = 0;
  int paper_shadow_height_ = 0;
  LONG paper_shadow_left_ = 0;
  LONG paper_shadow_top_ = 0;
  bool paper_shadow_visible_ = false;
  bool paper_shadow_z_order_dirty_ = true;
  bool paper_shadow_refresh_pending_ = false;
  bool paper_surface_reveal_pending_ = false;
  uint64_t paper_shadow_refresh_generation_ = 0;
  bool paper_shadow_dark_ = false;
  bool rendered_paper_shadow_dark_ = false;
  HWND reminder_bubble_ = nullptr;
  std::wstring reminder_title_;
  std::wstring reminder_message_;
  int reminder_duration_seconds_ = 5;
  COLORREF reminder_background_color_ = RGB(255, 250, 239);
  COLORREF reminder_border_color_ = RGB(218, 198, 161);
  int reminder_border_alpha_ = 150;
  COLORREF reminder_icon_background_color_ = RGB(238, 229, 211);
  COLORREF reminder_accent_color_ = RGB(151, 122, 82);
  COLORREF reminder_text_color_ = RGB(54, 47, 39);
  COLORREF reminder_weak_text_color_ = RGB(113, 100, 83);
  std::vector<std::unique_ptr<ContextMenuItem>> active_context_menu_items_;
  ContextMenuPalette context_menu_palette_;
  std::wstring context_menu_font_family_ = L"Segoe UI";
  int context_menu_logical_width_ = 0;
};

#endif  // RUNNER_PAPER_FLUTTER_WINDOW_H_
