#include "flutter_window.h"

#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

double GetNumberArgument(const flutter::EncodableMap& map,
                         const std::string& key,
                         double fallback) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  const auto& value = iterator->second;
  if (const auto* double_value = std::get_if<double>(&value)) {
    return *double_value;
  }
  if (const auto* int_value = std::get_if<int32_t>(&value)) {
    return static_cast<double>(*int_value);
  }
  if (const auto* long_value = std::get_if<int64_t>(&value)) {
    return static_cast<double>(*long_value);
  }
  return fallback;
}

std::string GetStringArgument(const flutter::EncodableMap& map,
                              const std::string& key,
                              const std::string& fallback) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return fallback;
}

bool GetBoolArgument(const flutter::EncodableMap& map,
                     const std::string& key,
                     bool fallback) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&iterator->second)) {
    return *value;
  }
  return fallback;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (size <= 0) {
    return std::wstring(value.begin(), value.end());
  }
  std::wstring wide_value(size - 1, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, wide_value.data(), size);
  return wide_value;
}

std::wstring TrayPaperLabel(const flutter::EncodableMap& map) {
  const std::string type = GetStringArgument(map, "type", "todo");
  const bool is_visible = GetBoolArgument(map, "isVisible", false);
  std::wstring title = Utf8ToWide(GetStringArgument(map, "title", "Untitled"));
  if (title.empty()) {
    title = L"Untitled";
  }
  std::wstring label = type == "note" ? L"Note - " : L"Todo - ";
  label += title;
  if (!is_visible) {
    label += L" (hidden)";
  }
  return label;
}

bool SetStartupAtLogin(bool enabled) {
  HKEY run_key;
  const wchar_t* key_path =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
  if (RegCreateKeyExW(HKEY_CURRENT_USER, key_path, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &run_key,
                      nullptr) != ERROR_SUCCESS) {
    return false;
  }

  const wchar_t* value_name = L"RePaperTodo";
  bool succeeded = true;
  if (enabled) {
    wchar_t module_path[MAX_PATH];
    const DWORD module_path_length =
        GetModuleFileNameW(nullptr, module_path, MAX_PATH);
    if (module_path_length == 0 || module_path_length >= MAX_PATH) {
      succeeded = false;
    } else {
      const std::wstring command =
          std::wstring(L"\"") + module_path + std::wstring(L"\"");
      succeeded = RegSetValueExW(
                      run_key, value_name, 0, REG_SZ,
                      reinterpret_cast<const BYTE*>(command.c_str()),
                      static_cast<DWORD>((command.size() + 1) *
                                         sizeof(wchar_t))) == ERROR_SUCCESS;
    }
  } else {
    const LONG delete_result = RegDeleteValueW(run_key, value_name);
    succeeded =
        delete_result == ERROR_SUCCESS || delete_result == ERROR_FILE_NOT_FOUND;
  }

  RegCloseKey(run_key);
  return succeeded;
}

void SetHideFromWindowSwitcher(HWND window, bool enabled) {
  LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  if (enabled) {
    extended_style |= WS_EX_TOOLWINDOW;
    extended_style &= ~WS_EX_APPWINDOW;
  } else {
    extended_style &= ~WS_EX_TOOLWINDOW;
    extended_style |= WS_EX_APPWINDOW;
  }
  SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

bool IsForegroundFullscreen(HWND own_window) {
  HWND foreground_window = GetForegroundWindow();
  if (!foreground_window || foreground_window == own_window ||
      IsIconic(foreground_window)) {
    return false;
  }

  RECT foreground_bounds;
  if (!GetWindowRect(foreground_window, &foreground_bounds)) {
    return false;
  }

  HMONITOR monitor =
      MonitorFromWindow(foreground_window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info;
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfoW(monitor, &monitor_info)) {
    return false;
  }

  const RECT& monitor_bounds = monitor_info.rcMonitor;
  return foreground_bounds.left <= monitor_bounds.left &&
         foreground_bounds.top <= monitor_bounds.top &&
         foreground_bounds.right >= monitor_bounds.right &&
         foreground_bounds.bottom >= monitor_bounds.bottom;
}

flutter::EncodableValue WindowBoundsValue(HWND window) {
  RECT bounds;
  GetWindowRect(window, &bounds);
  flutter::EncodableMap result_map;
  result_map[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<int32_t>(bounds.left));
  result_map[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<int32_t>(bounds.top));
  result_map[flutter::EncodableValue("width")] = flutter::EncodableValue(
      static_cast<int32_t>(bounds.right - bounds.left));
  result_map[flutter::EncodableValue("height")] = flutter::EncodableValue(
      static_cast<int32_t>(bounds.bottom - bounds.top));
  return flutter::EncodableValue(result_map);
}

}  // namespace

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kTrayShowCommand = 40001;
constexpr UINT kTrayHideCommand = 40002;
constexpr UINT kTrayExitCommand = 40003;
constexpr UINT kTrayPaperCommandBase = 41000;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "repapertodo/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HWND window = GetHandle();
        if (!window) {
          result->Error("window_unavailable", "The main window is unavailable.");
          return;
        }

        const std::string& method = call.method_name();
        if (method == "show") {
          ShowWindow(window, SW_SHOWNORMAL);
          SetForegroundWindow(window);
          result->Success();
          return;
        }
        if (method == "hide") {
          ShowWindow(window, SW_HIDE);
          result->Success();
          return;
        }
        if (method == "setAlwaysOnTop") {
          bool enabled = false;
          if (call.arguments()) {
            if (const auto* value =
                    std::get_if<bool>(call.arguments())) {
              enabled = *value;
            }
          }
          const bool should_apply_topmost =
              enabled &&
              !(avoid_fullscreen_topmost_ && IsForegroundFullscreen(window));
          SetWindowPos(window, should_apply_topmost ? HWND_TOPMOST : HWND_NOTOPMOST,
                       0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          result->Success();
          return;
        }
        if (method == "setTitle") {
          std::string title = "RePaperTodo";
          if (call.arguments()) {
            if (const auto* value =
                    std::get_if<std::string>(call.arguments())) {
              title = *value;
            }
          }
          SetWindowTextW(window, Utf8ToWide(title).c_str());
          result->Success();
          return;
        }
        if (method == "setTrayMenu") {
          tray_papers_.clear();
          if (call.arguments()) {
            if (const auto* papers =
                    std::get_if<flutter::EncodableList>(call.arguments())) {
              for (const auto& paper : *papers) {
                if (const auto* paper_map =
                        std::get_if<flutter::EncodableMap>(&paper)) {
                  const std::string id =
                      GetStringArgument(*paper_map, "id", "");
                  if (!id.empty()) {
                    tray_papers_.push_back(
                        std::make_pair(id, TrayPaperLabel(*paper_map)));
                  }
                }
              }
            }
          }
          result->Success();
          return;
        }
        if (method == "setStartupAtLogin") {
          bool enabled = false;
          if (call.arguments()) {
            if (const auto* value = std::get_if<bool>(call.arguments())) {
              enabled = *value;
            }
          }
          if (!SetStartupAtLogin(enabled)) {
            result->Error("startup_at_login_failed",
                          "Unable to update the Windows startup entry.");
            return;
          }
          result->Success();
          return;
        }
        if (method == "setHideFromWindowSwitcher") {
          bool enabled = false;
          if (call.arguments()) {
            if (const auto* value = std::get_if<bool>(call.arguments())) {
              enabled = *value;
            }
          }
          SetHideFromWindowSwitcher(window, enabled);
          result->Success();
          return;
        }
        if (method == "setFullscreenTopmostMode") {
          avoid_fullscreen_topmost_ = true;
          if (call.arguments()) {
            if (const auto* value = std::get_if<std::string>(call.arguments())) {
              avoid_fullscreen_topmost_ = *value != "stayOnTop";
            }
          }
          result->Success();
          return;
        }
        if (method == "isForegroundFullscreen") {
          result->Success(flutter::EncodableValue(IsForegroundFullscreen(window)));
          return;
        }
        if (method == "setBounds") {
          RECT current_bounds;
          GetWindowRect(window, &current_bounds);
          double x = static_cast<double>(current_bounds.left);
          double y = static_cast<double>(current_bounds.top);
          double width =
              static_cast<double>(current_bounds.right - current_bounds.left);
          double height =
              static_cast<double>(current_bounds.bottom - current_bounds.top);
          if (call.arguments()) {
            if (const auto* bounds =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              x = GetNumberArgument(*bounds, "x", x);
              y = GetNumberArgument(*bounds, "y", y);
              width = GetNumberArgument(*bounds, "width", width);
              height = GetNumberArgument(*bounds, "height", height);
            }
          }
          SetWindowPos(window, nullptr, static_cast<int>(x),
                       static_cast<int>(y), static_cast<int>(width),
                       static_cast<int>(height),
                       SWP_NOZORDER | SWP_NOACTIVATE);
          result->Success();
          return;
        }
        if (method == "getBounds") {
          result->Success(WindowBoundsValue(window));
          return;
        }

        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_) {
    return;
  }
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_data_.hWnd = window;
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_icon_data_.szTip, L"RePaperTodo");
  tray_icon_added_ = Shell_NotifyIcon(NIM_ADD, &tray_icon_data_) == TRUE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void FlutterWindow::ShowTrayMenu() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  POINT cursor_position;
  GetCursorPos(&cursor_position);
  HMENU menu = CreatePopupMenu();
  AppendMenu(menu, MF_STRING, kTrayShowCommand, L"Show");
  AppendMenu(menu, MF_STRING, kTrayHideCommand, L"Hide");
  if (!tray_papers_.empty()) {
    AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenu(menu, MF_STRING | MF_DISABLED, 0, L"Papers");
    for (size_t index = 0; index < tray_papers_.size(); index++) {
      AppendMenu(menu, MF_STRING,
                 kTrayPaperCommandBase + static_cast<UINT>(index),
                 tray_papers_[index].second.c_str());
    }
  }
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayExitCommand, L"Exit");

  SetForegroundWindow(window);
  UINT command = TrackPopupMenu(menu,
                                TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
                                cursor_position.x, cursor_position.y, 0,
                                window, nullptr);
  DestroyMenu(menu);

  switch (command) {
    case kTrayShowCommand:
      SendWindowEvent("showRequested");
      ShowWindow(window, SW_SHOWNORMAL);
      SetForegroundWindow(window);
      break;
    case kTrayHideCommand:
      SendWindowEvent("hideRequested");
      ShowWindow(window, SW_HIDE);
      break;
    case kTrayExitCommand:
      RemoveTrayIcon();
      DestroyWindow(window);
      break;
    default:
      if (command >= kTrayPaperCommandBase &&
          command < kTrayPaperCommandBase + tray_papers_.size()) {
        SendPaperRequested(tray_papers_[command - kTrayPaperCommandBase].first);
      }
      break;
  }
}

void FlutterWindow::SendBoundsChanged() {
  HWND window = GetHandle();
  if (!window_channel_ || !window) {
    return;
  }
  window_channel_->InvokeMethod(
      "boundsChanged", std::make_unique<flutter::EncodableValue>(
                           WindowBoundsValue(window)));
}

void FlutterWindow::SendCloseRequested() {
  SendWindowEvent("closeRequested");
}

void FlutterWindow::SendPaperRequested(const std::string& paper_id) {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(
      "paperRequested", std::make_unique<flutter::EncodableValue>(paper_id));
}

void FlutterWindow::SendWindowEvent(const char* method) {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(method,
                                std::make_unique<flutter::EncodableValue>());
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  if (flutter_controller_) {
    window_channel_ = nullptr;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_MOVE:
    case WM_SIZE:
      SendBoundsChanged();
      break;
    case WM_CLOSE:
      SendCloseRequested();
      ShowWindow(hwnd, SW_HIDE);
      return 0;
    case kTrayIconMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          SendWindowEvent("showRequested");
          ShowWindow(hwnd, SW_SHOWNORMAL);
          SetForegroundWindow(hwnd);
          return 0;
        case WM_RBUTTONUP:
          ShowTrayMenu();
          return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
