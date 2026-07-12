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
  bool hide_when_covered_ = false;
  bool hide_when_fullscreen_ = false;
  HWND desktop_parent_ = nullptr;
};

#endif  // RUNNER_PAPER_FLUTTER_WINDOW_H_
