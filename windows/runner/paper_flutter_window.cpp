#include "paper_flutter_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <utility>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

double NumberValue(const flutter::EncodableMap& map, const char* key,
                   double fallback) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<double>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  return fallback;
}

bool BoolValue(const flutter::EncodableMap& map, const char* key,
               bool fallback) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&iterator->second)) {
    return *value;
  }
  return fallback;
}

std::string StringValue(const flutter::EncodableMap& map, const char* key,
                        const std::string& fallback) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return fallback;
}

std::wstring Utf8WindowTitle(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) {
    return L"RePaperTodo";
  }
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

BOOL CALLBACK FindDesktopWorkerCallback(HWND window, LPARAM parameter) {
  HWND shell_view = FindWindowExW(window, nullptr, L"SHELLDLL_DefView", nullptr);
  if (!shell_view) {
    return TRUE;
  }
  HWND* result = reinterpret_cast<HWND*>(parameter);
  *result = FindWindowExW(nullptr, window, L"WorkerW", nullptr);
  return *result == nullptr;
}

HWND FindDesktopWorkerWindow() {
  HWND program_manager = FindWindowW(L"Progman", nullptr);
  if (program_manager) {
    SendMessageTimeoutW(program_manager, 0x052C, 0, 0, SMTO_NORMAL, 1000,
                        nullptr);
  }
  HWND worker = nullptr;
  EnumWindows(FindDesktopWorkerCallback, reinterpret_cast<LPARAM>(&worker));
  return worker ? worker : program_manager;
}

bool IsExternalFullscreenWindow(HWND app_window) {
  HWND foreground = GetForegroundWindow();
  if (!foreground || foreground == app_window || IsIconic(foreground)) {
    return false;
  }
  const LONG_PTR style = GetWindowLongPtrW(foreground, GWL_STYLE);
  if ((style & WS_CHILD) != 0) {
    return false;
  }
  RECT bounds = {};
  if (!GetWindowRect(foreground, &bounds)) {
    return false;
  }
  HMONITOR monitor = MonitorFromWindow(foreground, MONITOR_DEFAULTTONULL);
  if (!monitor) {
    return false;
  }
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) {
    return false;
  }
  constexpr LONG tolerance = 2;
  return std::abs(bounds.left - info.rcMonitor.left) <= tolerance &&
         std::abs(bounds.top - info.rcMonitor.top) <= tolerance &&
         std::abs(bounds.right - info.rcMonitor.right) <= tolerance &&
         std::abs(bounds.bottom - info.rcMonitor.bottom) <= tolerance;
}

bool IsCoveredByAnotherWindow(HWND app_window) {
  RECT bounds = {};
  if (!GetWindowRect(app_window, &bounds)) {
    return false;
  }
  const POINT points[] = {
      {(bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2},
      {bounds.left + 2, bounds.top + 2},
      {bounds.right - 2, bounds.top + 2},
      {bounds.left + 2, bounds.bottom - 2},
      {bounds.right - 2, bounds.bottom - 2},
  };
  for (const POINT point : points) {
    HWND hit = WindowFromPoint(point);
    HWND root = hit ? GetAncestor(hit, GA_ROOT) : nullptr;
    if (root && root != app_window && IsWindowVisible(root) &&
        root != GetShellWindow() && root != GetDesktopWindow()) {
      return true;
    }
  }
  return false;
}

struct MonitorWorkAreaLookup {
  std::wstring device_name;
  RECT work_area = {};
  bool found = false;
};

BOOL CALLBACK FindMonitorWorkArea(HMONITOR monitor, HDC, LPRECT,
                                  LPARAM parameter) {
  auto* lookup = reinterpret_cast<MonitorWorkAreaLookup*>(parameter);
  if (!lookup) {
    return TRUE;
  }
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&info))) {
    return TRUE;
  }
  const bool primary = lookup->device_name.empty() &&
                       (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  if (primary || (!lookup->device_name.empty() &&
                  lookup->device_name == info.szDevice)) {
    lookup->work_area = info.rcWork;
    lookup->found = true;
    return FALSE;
  }
  return TRUE;
}

RECT WorkAreaForWindow(HWND window, const std::string& device_name) {
  MonitorWorkAreaLookup lookup;
  lookup.device_name = Utf8WindowTitle(device_name);
  EnumDisplayMonitors(nullptr, nullptr, FindMonitorWorkArea,
                      reinterpret_cast<LPARAM>(&lookup));
  if (lookup.found) {
    return lookup.work_area;
  }
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (monitor && GetMonitorInfoW(monitor, &info)) {
    return info.rcWork;
  }
  RECT fallback = {};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &fallback, 0);
  return fallback;
}

}  // namespace

PaperFlutterWindow::PaperFlutterWindow(const flutter::DartProject& project,
                                       std::string paper_id,
                                       EventCallback event_callback)
    : project_(project),
      paper_id_(std::move(paper_id)),
      event_callback_(std::move(event_callback)) {}

PaperFlutterWindow::~PaperFlutterWindow() = default;

bool PaperFlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  ApplyNativeStyle();
  const RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      std::max<LONG>(1, frame.right - frame.left),
      std::max<LONG>(1, frame.bottom - frame.top), project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "repapertodo/paper_window",
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "ready") {
          child_ready_ = true;
          FlushInitialState();
          result->Success();
          return;
        }
        if (call.method_name() == "paperChanged") {
          if (call.arguments()) {
            SendEvent("paperSurfaceChanged", *call.arguments());
          }
          result->Success();
          return;
        }
        if (call.method_name() == "deleteRequested") {
          SendEvent("paperDeleteRequested", flutter::EncodableMap{
                                                {flutter::EncodableValue(
                                                     "paperId"),
                                                 flutter::EncodableValue(
                                                     paper_id_)},
                                            });
          result->Success();
          return;
        }
        if (call.method_name() == "openRequested") {
          if (call.arguments()) {
            SendEvent("paperRequested", *call.arguments());
          }
          result->Success();
          return;
        }
        if (call.method_name() == "actionRequested") {
          if (call.arguments()) {
            SendEvent("paperActionRequested", *call.arguments());
          }
          result->Success();
          return;
        }
        if (call.method_name() == "startDrag") {
          if (HWND window = GetHandle()) {
            POINT cursor = {};
            GetCursorPos(&cursor);
            ReleaseCapture();
            SendMessageW(window, WM_SYSCOMMAND, SC_MOVE | HTCAPTION,
                         MAKELPARAM(cursor.x, cursor.y));
          }
          result->Success();
          return;
        }
        if (call.method_name() == "startResize") {
          int hit_test = 0;
          if (call.arguments()) {
            if (const auto* direction =
                    std::get_if<std::string>(call.arguments())) {
              if (*direction == "left") hit_test = HTLEFT;
              if (*direction == "right") hit_test = HTRIGHT;
              if (*direction == "top") hit_test = HTTOP;
              if (*direction == "bottom") hit_test = HTBOTTOM;
              if (*direction == "topLeft") hit_test = HTTOPLEFT;
              if (*direction == "topRight") hit_test = HTTOPRIGHT;
              if (*direction == "bottomLeft") hit_test = HTBOTTOMLEFT;
              if (*direction == "bottomRight") hit_test = HTBOTTOMRIGHT;
            }
          }
          if (hit_test != 0) {
            if (HWND window = GetHandle()) {
              POINT cursor = {};
              GetCursorPos(&cursor);
              ReleaseCapture();
              SendMessageW(window, WM_NCLBUTTONDOWN, hit_test,
                           MAKELPARAM(cursor.x, cursor.y));
            }
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (GetHandle()) {
      RedrawWindow(GetHandle(), nullptr, nullptr, RDW_INVALIDATE);
    }
  });
  flutter_controller_->ForceRedraw();
  return true;
}

void PaperFlutterWindow::OnDestroy() {
  channel_.reset();
  if (flutter_controller_) {
    flutter_controller_.reset();
  }
  Win32Window::OnDestroy();
}

LRESULT PaperFlutterWindow::MessageHandler(HWND window, UINT const message,
                                           WPARAM const wparam,
                                           LPARAM const lparam) noexcept {
  switch (message) {
    case WM_CLOSE:
      HidePaper();
      SendEvent("closeRequested", flutter::EncodableMap{
                                      {flutter::EncodableValue("paperId"),
                                       flutter::EncodableValue(paper_id_)},
                                  });
      return 0;
    case WM_MOVE:
    case WM_SIZE:
      if (surface_initialized_ && !applying_bounds_ && !in_size_move_ &&
          wparam != SIZE_MINIMIZED) {
        SendBoundsChanged();
      }
      break;
    case WM_ENTERSIZEMOVE:
      in_size_move_ = true;
      break;
    case WM_EXITSIZEMOVE:
      in_size_move_ = false;
      if (surface_initialized_) {
        SendBoundsChanged();
      }
      break;
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      if (info) {
        info->ptMinTrackSize.x = collapsed_ ? 92 : 220;
        info->ptMinTrackSize.y = collapsed_ ? 46 : 160;
        return 0;
      }
      break;
    }
    case WM_NCCALCSIZE:
      if (wparam == TRUE) {
        return 0;
      }
      break;
    case WM_NCHITTEST: {
      RECT rect = {};
      GetWindowRect(window, &rect);
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      const UINT dpi = GetDpiForWindow(window);
      const int edge = std::max(
          10, static_cast<int>(std::lround(
                  10.0 * static_cast<double>(dpi ? dpi : 96) / 96.0)));
      const bool left = x < rect.left + edge;
      const bool right = x >= rect.right - edge;
      const bool top = y < rect.top + edge;
      const bool bottom = y >= rect.bottom - edge;
      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
      break;
    }
  }
  return Win32Window::MessageHandler(window, message, wparam, lparam);
}

void PaperFlutterWindow::ApplyState(const flutter::EncodableValue& state) {
  latest_state_ = state;
  if (child_ready_ && channel_) {
    channel_->InvokeMethod(
        "applyState", std::make_unique<flutter::EncodableValue>(latest_state_));
  }
}

void PaperFlutterWindow::ApplyPaper(const flutter::EncodableValue& paper) {
  latest_paper_ = paper;
  if (child_ready_ && channel_) {
    channel_->InvokeMethod(
        "applyPaper", std::make_unique<flutter::EncodableValue>(latest_paper_));
  }
}

void PaperFlutterWindow::FlushInitialState() {
  if (!channel_) {
    return;
  }
  if (!std::holds_alternative<std::monostate>(latest_state_)) {
    channel_->InvokeMethod(
        "applyState", std::make_unique<flutter::EncodableValue>(latest_state_));
  }
  if (!std::holds_alternative<std::monostate>(latest_paper_)) {
    channel_->InvokeMethod(
        "applyPaper", std::make_unique<flutter::EncodableValue>(latest_paper_));
  }
}

void PaperFlutterWindow::ApplySurface(const flutter::EncodableMap& surface) {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  RECT current = {};
  GetWindowRect(window, &current);
  const double x = NumberValue(surface, "x", current.left);
  const double y = NumberValue(surface, "y", current.top);
  const double width = NumberValue(
      surface, "width", std::max<LONG>(1, current.right - current.left));
  const double height = NumberValue(
      surface, "height", std::max<LONG>(1, current.bottom - current.top));
  collapsed_ = BoolValue(surface, "isCollapsed", collapsed_);
  hide_when_covered_ =
      BoolValue(surface, "hideWhenCovered", hide_when_covered_);
  hide_when_fullscreen_ =
      BoolValue(surface, "hideWhenFullscreen", hide_when_fullscreen_);
  SetHideFromWindowSwitcher(BoolValue(
      surface, "hideFromWindowSwitcher", hide_from_window_switcher_));
  const double native_width = collapsed_ ? 92.0 : width;
  const double native_height = collapsed_ ? 46.0 : height;
  double native_x = x;
  double native_y = y;
  if (collapsed_) {
    const std::string monitor_name =
        StringValue(surface, "capsuleMonitorDeviceName", "");
    const RECT work_area = WorkAreaForWindow(window, monitor_name);
    const std::string side = StringValue(surface, "capsuleSide", "right");
    native_x = side == "left"
                   ? static_cast<double>(work_area.left)
                   : static_cast<double>(work_area.right) - native_width;
    native_y = std::clamp(
        y, static_cast<double>(work_area.top),
        std::max(static_cast<double>(work_area.top),
                 static_cast<double>(work_area.bottom) - native_height));
  }
  if (!in_size_move_) {
    applying_bounds_ = true;
    SetWindowPos(window, nullptr, static_cast<int>(std::round(native_x)),
                 static_cast<int>(std::round(native_y)),
                 std::max(1, static_cast<int>(std::round(native_width))),
                 std::max(1, static_cast<int>(std::round(native_height))),
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    applying_bounds_ = false;
  }
  surface_initialized_ = true;
  const std::string title = StringValue(surface, "title", "RePaperTodo");
  SetWindowTextW(window, Utf8WindowTitle(title).c_str());
  always_on_top_ = BoolValue(surface, "alwaysOnTop", always_on_top_);
  pinned_to_desktop_ =
      BoolValue(surface, "isPinnedToDesktop", pinned_to_desktop_);
  RefreshZOrder();
  const auto visibility =
      surface.find(flutter::EncodableValue("isVisible"));
  if (visibility != surface.end()) {
    if (const auto* visible = std::get_if<bool>(&visibility->second)) {
      intended_visible_ = *visible;
      RefreshZOrder();
    }
  }
}

flutter::EncodableValue PaperFlutterWindow::BoundsValue() const {
  RECT bounds = {};
  HWND window = const_cast<PaperFlutterWindow*>(this)->GetHandle();
  if (!window || !GetWindowRect(window, &bounds)) {
    return flutter::EncodableValue();
  }
  return flutter::EncodableMap{
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(bounds.left))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(bounds.top))},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(
           static_cast<double>(bounds.right - bounds.left))},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(
           static_cast<double>(bounds.bottom - bounds.top))},
  };
}

bool PaperFlutterWindow::IsVisible() const {
  HWND window = const_cast<PaperFlutterWindow*>(this)->GetHandle();
  return window && IsWindowVisible(window);
}

void PaperFlutterWindow::ShowPaper(bool activate) {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  intended_visible_ = true;
  RefreshZOrder();
  if (activate && IsWindowVisible(window)) {
    SetForegroundWindow(window);
  }
}

void PaperFlutterWindow::HidePaper() {
  intended_visible_ = false;
  if (HWND window = GetHandle()) {
    ShowWindow(window, SW_HIDE);
  }
}

void PaperFlutterWindow::SetHideFromWindowSwitcher(bool hidden) {
  hide_from_window_switcher_ = hidden;
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  if (hidden || pinned_to_desktop_) {
    extended_style = (extended_style | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
  } else {
    extended_style = (extended_style | WS_EX_APPWINDOW) & ~WS_EX_TOOLWINDOW;
  }
  SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void PaperFlutterWindow::SetAvoidFullscreenTopmost(bool avoid) {
  avoid_fullscreen_topmost_ = avoid;
  RefreshZOrder();
}

void PaperFlutterWindow::RefreshZOrder() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  fullscreen_blocked_ =
      avoid_fullscreen_topmost_ && IsExternalFullscreenWindow(window);
  const bool policy_hidden = collapsed_ &&
                             ((hide_when_fullscreen_ &&
                               IsExternalFullscreenWindow(window)) ||
                              (hide_when_covered_ &&
                               IsCoveredByAnotherWindow(window)));
  if (!intended_visible_ || policy_hidden) {
    ShowWindow(window, SW_HIDE);
    return;
  }
  if (!IsWindowVisible(window)) {
    ShowWindow(window,
               pinned_to_desktop_ ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL);
  }
  if (pinned_to_desktop_) {
    if (!desktop_parent_) {
      RECT screen_bounds = {};
      GetWindowRect(window, &screen_bounds);
      desktop_parent_ = FindDesktopWorkerWindow();
      if (desktop_parent_) {
        SetParent(window, desktop_parent_);
        SetWindowLongPtrW(window, GWL_STYLE,
                          WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN);
        POINT points[2] = {{screen_bounds.left, screen_bounds.top},
                           {screen_bounds.right, screen_bounds.bottom}};
        MapWindowPoints(HWND_DESKTOP, desktop_parent_, points, 2);
        SetWindowPos(window, HWND_BOTTOM, points[0].x, points[0].y,
                     points[1].x - points[0].x,
                     points[1].y - points[0].y,
                     SWP_NOACTIVATE | SWP_FRAMECHANGED);
      }
    }
    const bool configured_hidden = hide_from_window_switcher_;
    SetHideFromWindowSwitcher(true);
    hide_from_window_switcher_ = configured_hidden;
    SetWindowPos(window, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
    return;
  }
  if (desktop_parent_) {
    RECT screen_bounds = {};
    GetWindowRect(window, &screen_bounds);
    SetParent(window, nullptr);
    desktop_parent_ = nullptr;
    SetWindowLongPtrW(window, GWL_STYLE,
                      WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN);
    SetHideFromWindowSwitcher(hide_from_window_switcher_);
    SetWindowPos(window, nullptr, screen_bounds.left, screen_bounds.top,
                 screen_bounds.right - screen_bounds.left,
                 screen_bounds.bottom - screen_bounds.top,
                 SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
  const HWND z_order =
      always_on_top_ && !fullscreen_blocked_ ? HWND_TOPMOST : HWND_NOTOPMOST;
  SetWindowPos(window, z_order, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void PaperFlutterWindow::SendBoundsChanged() {
  flutter::EncodableMap arguments = {
      {flutter::EncodableValue("paperId"),
       flutter::EncodableValue(paper_id_)},
  };
  const auto bounds = BoundsValue();
  if (const auto* map = std::get_if<flutter::EncodableMap>(&bounds)) {
    arguments.insert(map->begin(), map->end());
  }
  SendEvent("boundsChanged", flutter::EncodableValue(arguments));
}

void PaperFlutterWindow::SendEvent(
    const std::string& method, const flutter::EncodableValue& arguments) {
  if (event_callback_) {
    event_callback_(method, arguments);
  }
}

void PaperFlutterWindow::ApplyNativeStyle() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  const LONG_PTR style = WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN;
  SetWindowLongPtrW(window, GWL_STYLE, style);
  MARGINS margins = {-1};
  DwmExtendFrameIntoClientArea(window, &margins);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}
