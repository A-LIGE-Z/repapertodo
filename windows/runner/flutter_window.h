#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <map>
#include <memory>
#include <shellapi.h>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "win32_window.h"

struct TrayMenuLabels {
  std::wstring new_todo = L"+ New todo paper";
  std::wstring new_note = L"+ New note paper";
  std::wstring settings = L"Settings";
  std::wstring show_all = L"Show all papers";
  std::wstring hide_all = L"Hide all papers";
  std::wstring toggle_all = L"Toggle all papers";
  std::wstring papers = L"Papers";
  std::wstring delete_paper = L"Delete paper...";
  std::wstring delete_confirm_title = L"Delete paper?";
  std::wstring delete_confirm_message = L"Delete \"{0}\"?";
  std::wstring inline_confirm_delete = L"Delete";
  std::wstring inline_confirm_action = L"Confirm";
  std::wstring cancel = L"Cancel";
  std::wstring exit = L"Exit";
  std::wstring todo_paper = L"Todo";
  std::wstring note_paper = L"Note";
  std::wstring script_paper = L"Script";
  std::wstring hidden = L"hidden";
  std::wstring collapsed = L"collapsed";
  std::wstring desktop = L"desktop";
  std::wstring topmost = L"topmost";
};

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  void StartSingleInstanceListener();
  void StopSingleInstanceListener();
  void SendBoundsChanged();
  void SendCloseRequested();
  void SendPaperRequested(const std::string& paper_id);
  void SendPaperDeleteRequested(const std::string& paper_id);
  void SendStartupCommandRequested(const std::string& command);
  void SendWindowEvent(const char* method);
  void RememberActivePaperId(const flutter::EncodableValue* arguments);
  void RememberActivePaperBounds(HWND window);
  void ApplyActivePaperBounds(HWND window);
  void RememberPaperBounds(const std::string& paper_id, const RECT& bounds);
  void RememberPaperVisibility(const std::string& paper_id, bool is_visible);
  void RememberPaperPinnedToDesktop(const std::string& paper_id, bool enabled);
  void RememberPaperAlwaysOnTop(const std::string& paper_id, bool enabled);
  void RefreshActivePaperZOrder(HWND window);
  bool ActivePaperPinnedToDesktop() const;
  bool ActivePaperAlwaysOnTop() const;
  flutter::EncodableValue BoundsValueForPaper(
      HWND window, const std::string& paper_id) const;
  flutter::EncodableValue WindowEventArguments() const;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  NOTIFYICONDATA tray_icon_data_ = {};
  HICON tray_icon_handle_ = nullptr;
  bool tray_icon_handle_is_custom_ = false;
  bool tray_icon_added_ = false;
  UINT taskbar_created_message_ = 0;
  bool avoid_fullscreen_topmost_ = true;
  bool pinned_to_desktop_ = false;
  bool z_order_state_initialized_ = false;
  bool z_order_pinned_to_desktop_ = false;
  bool z_order_topmost_applied_ = false;
  bool z_order_fullscreen_blocked_ = false;
  bool todo_hotkey_registered_ = false;
  bool note_hotkey_registered_ = false;
  std::string active_paper_id_;
  std::atomic<bool> single_instance_listener_running_ = false;
  std::thread single_instance_listener_thread_;
  struct TrayPaperMenuItem {
    std::string id;
    std::wstring label;
    bool is_visible = false;
  };
  std::vector<TrayPaperMenuItem> tray_papers_;
  TrayMenuLabels tray_labels_;
  struct PaperSurfaceState {
    RECT bounds = {};
    bool has_bounds = false;
    bool is_visible = false;
    bool pinned_to_desktop = false;
    bool always_on_top = false;
  };
  std::map<std::string, PaperSurfaceState> paper_surfaces_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
