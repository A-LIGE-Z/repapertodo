#ifndef RUNNER_PAPER_FLUTTER_WINDOW_H_
#define RUNNER_PAPER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <functional>
#include <memory>
#include <string>

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
  void ApplySurface(const flutter::EncodableMap& surface);
  bool IsCollapsed() const { return collapsed_; }
  void SetAlwaysOnTop(bool enabled);
  void SetPinnedToDesktop(bool pinned);
  void SetPaperTitle(const std::string& title);
  flutter::EncodableValue BoundsValue() const;
  bool IsVisible() const;
  void ShowPaper(bool activate);
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
  int ResizeBorderHitTest(LPARAM lparam) const;
  void SetCapsuleHovered(bool hovered);
  void ApplyCapsuleHorizontalPosition();
  void SendCapsuleDropped();
  void ShowReminderBubble(const flutter::EncodableMap& reminder);
  void HideReminderBubble();
  void PlaceReminderBubble();
  LRESULT ReminderBubbleMessageHandler(HWND window, UINT message,
                                       WPARAM wparam, LPARAM lparam) noexcept;
  static LRESULT CALLBACK ReminderBubbleWindowProc(HWND window, UINT message,
                                                    WPARAM wparam,
                                                    LPARAM lparam) noexcept;

  flutter::DartProject project_;
  std::string paper_id_;
  EventCallback event_callback_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  flutter::EncodableValue latest_state_;
  flutter::EncodableValue latest_paper_;
  bool child_ready_ = false;
  bool applying_bounds_ = false;
  bool surface_initialized_ = false;
  bool always_on_top_ = false;
  bool pinned_to_desktop_ = false;
  bool hide_from_window_switcher_ = false;
  bool avoid_fullscreen_topmost_ = true;
  bool fullscreen_blocked_ = false;
  bool intended_visible_ = false;
  bool collapsed_ = false;
  bool deep_capsule_mode_ = false;
  bool capsule_hovered_ = false;
  std::string capsule_side_ = "right";
  RECT capsule_work_area_ = {};
  double capsule_width_ = 92.0;
  double capsule_resting_visible_width_ = 54.0;
  double capsule_hover_visible_width_ = 73.0;
  bool hide_when_covered_ = false;
  bool hide_when_fullscreen_ = false;
  bool in_size_move_ = false;
  HWND reminder_bubble_ = nullptr;
  std::wstring reminder_title_;
  std::wstring reminder_message_;
  int reminder_duration_seconds_ = 5;
  COLORREF reminder_background_color_ = RGB(255, 250, 239);
  COLORREF reminder_border_color_ = RGB(218, 198, 161);
  COLORREF reminder_accent_color_ = RGB(151, 122, 82);
  COLORREF reminder_text_color_ = RGB(54, 47, 39);
  COLORREF reminder_weak_text_color_ = RGB(113, 100, 83);
};

#endif  // RUNNER_PAPER_FLUTTER_WINDOW_H_
