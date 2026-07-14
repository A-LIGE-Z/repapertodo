#include "native_capsule_window.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cwctype>
#include <string>
#include <utility>

#include <dwmapi.h>

namespace {

double NumberValue(const flutter::EncodableMap& map, const char* key,
                   double fallback) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) return fallback;
  if (const auto* value = std::get_if<double>(&iterator->second)) return *value;
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
  if (iterator == map.end()) return fallback;
  if (const auto* value = std::get_if<bool>(&iterator->second)) return *value;
  return fallback;
}

std::string StringValue(const flutter::EncodableMap& map, const char* key,
                        const std::string& fallback) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) return fallback;
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return fallback;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) return L"RePaperTodo";
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  const int length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) return std::string();
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

bool IsWideCharacter(wchar_t value) {
  const unsigned int code = static_cast<unsigned int>(value);
  return code >= 0x1100 &&
         (code <= 0x115F || (code >= 0x2E80 && code <= 0xA4CF) ||
          (code >= 0xAC00 && code <= 0xD7A3) ||
          (code >= 0xF900 && code <= 0xFAFF) ||
          (code >= 0xFF00 && code <= 0xFF60));
}

int TextWidthEstimate(const std::wstring& value) {
  double width = 0;
  for (const wchar_t character : value) {
    width += IsWideCharacter(character) ? 11.0 : 6.2;
  }
  return static_cast<int>(std::ceil(width));
}

struct MonitorLookup {
  std::wstring requested;
  HMONITOR monitor = nullptr;
  RECT work_area = {};
};

BOOL CALLBACK FindMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM parameter) {
  auto* lookup = reinterpret_cast<MonitorLookup*>(parameter);
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(info);
  if (!lookup || !GetMonitorInfoW(
                     monitor, reinterpret_cast<MONITORINFO*>(&info))) {
    return TRUE;
  }
  if (!lookup->requested.empty() &&
      _wcsicmp(lookup->requested.c_str(), info.szDevice) == 0) {
    lookup->monitor = monitor;
    lookup->work_area = info.rcWork;
    return FALSE;
  }
  return TRUE;
}

bool IsSystemDarkMode() {
  DWORD light_mode = 1;
  DWORD size = sizeof(light_mode);
  const LSTATUS status = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light_mode, &size);
  return status == ERROR_SUCCESS && light_mode == 0;
}

COLORREF Mix(COLORREF first, COLORREF second, int second_weight) {
  const int weight = std::clamp(second_weight, 0, 100);
  const int first_weight = 100 - weight;
  return RGB((GetRValue(first) * first_weight + GetRValue(second) * weight) /
                 100,
             (GetGValue(first) * first_weight + GetGValue(second) * weight) /
                 100,
             (GetBValue(first) * first_weight + GetBValue(second) * weight) /
                 100);
}

bool ParseHexColor(const std::string& value, COLORREF* color) {
  if (!color) return false;
  std::string hex = value;
  if (!hex.empty() && hex.front() == '#') hex.erase(hex.begin());
  if (hex.size() != 6) return false;
  try {
    const unsigned long rgb = std::stoul(hex, nullptr, 16);
    *color = RGB((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
    return true;
  } catch (...) {
    return false;
  }
}

}  // namespace

NativeCapsuleWindow::NativeCapsuleWindow(EventCallback event_callback)
    : event_callback_(std::move(event_callback)) {}

NativeCapsuleWindow::~NativeCapsuleWindow() = default;

bool NativeCapsuleWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  ApplyNativeStyle();
  return true;
}

void NativeCapsuleWindow::ApplyNativeStyle() {
  HWND window = GetHandle();
  if (!window) return;
  SetWindowLongPtrW(window, GWL_STYLE, WS_POPUP | WS_CLIPCHILDREN);
  SetWindowLongPtrW(window, GWL_EXSTYLE,
                    WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void NativeCapsuleWindow::ApplySurface(
    const flutter::EncodableMap& surface) {
  surface_id_ = StringValue(surface, "surfaceId", surface_id_);
  kind_ = StringValue(surface, "kind", kind_);
  master_ = kind_ == "master";
  paper_id_ = StringValue(surface, "paperId", paper_id_);
  paper_type_ = StringValue(surface, "paperType", paper_type_);
  title_ = StringValue(surface, "title", title_);
  label_en_ = StringValue(surface, "labelEn", label_en_);
  label_zh_ = StringValue(surface, "labelZh", label_zh_);
  count_label_en_ =
      StringValue(surface, "countLabelEn", count_label_en_);
  count_label_zh_ =
      StringValue(surface, "countLabelZh", count_label_zh_);
  capsule_side_ = StringValue(surface, "capsuleSide", capsule_side_) == "left"
                      ? "left"
                      : "right";
  monitor_device_name_ = StringValue(
      surface, "capsuleMonitorDeviceName", monitor_device_name_);
  top_margin_ = NumberValue(surface, "top", top_margin_);
  active_ = BoolValue(surface, "isActive", active_);
  collapse_on_click_ =
      BoolValue(surface, "collapseOnClick", collapse_on_click_);
  intended_visible_ = BoolValue(surface, "isVisible", intended_visible_);
  hide_when_covered_ =
      BoolValue(surface, "hideWhenCovered", hide_when_covered_);
  hide_when_fullscreen_ =
      BoolValue(surface, "hideWhenFullscreen", hide_when_fullscreen_);
  theme_ = StringValue(surface, "theme", theme_);
  color_scheme_ = StringValue(surface, "colorScheme", color_scheme_);
  custom_theme_color_hex_ = StringValue(
      surface, "customThemeColorHex", custom_theme_color_hex_);

  const std::wstring label = EffectiveLabel();
  const int label_width = TextWidthEstimate(label);
  full_width_ = std::clamp((master_ ? 48 : 73) + label_width, 76, 260);
  resting_visible_width_ = master_
                               ? std::clamp(36 + (label.empty() ? 0 :
                                                  TextWidthEstimate(
                                                      label.substr(0, 1))),
                                            38, full_width_)
                               : std::clamp(33 + label_width, 42,
                                            std::max(42, full_width_ - 28));
  hover_visible_width_ = master_
                             ? resting_visible_width_
                             : std::clamp(resting_visible_width_ +
                                              (full_width_ -
                                               resting_visible_width_) /
                                                  2,
                                          std::min(58, full_width_),
                                          full_width_);

  ResolveWorkArea();
  ApplyWindowRegion();
  ApplyDockedPosition();
  if (HWND window = GetHandle()) {
    const std::wstring window_title =
        L"RePaperTodo Native Capsule [" + Utf8ToWide(surface_id_) + L"]";
    SetWindowTextW(window, window_title.c_str());
    InvalidateRect(window, nullptr, FALSE);
  }
  RefreshVisibility();
}

void NativeCapsuleWindow::ResolveWorkArea() {
  MonitorLookup lookup;
  lookup.requested = Utf8ToWide(monitor_device_name_);
  if (!lookup.requested.empty()) {
    EnumDisplayMonitors(nullptr, nullptr, FindMonitor,
                        reinterpret_cast<LPARAM>(&lookup));
  }
  if (!lookup.monitor) {
    POINT point = {0, 0};
    lookup.monitor = MonitorFromPoint(point, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFOEXW info = {};
    info.cbSize = sizeof(info);
    if (lookup.monitor &&
        GetMonitorInfoW(lookup.monitor,
                        reinterpret_cast<MONITORINFO*>(&info))) {
      lookup.work_area = info.rcWork;
      monitor_device_name_ = WideToUtf8(info.szDevice);
    }
  }
  work_area_ = lookup.work_area;
}

void NativeCapsuleWindow::ApplyWindowRegion() {
  HWND window = GetHandle();
  if (!window) return;
  const int radius = std::max(12, height_ / 2);
  HRGN region = CreateRoundRectRgn(0, 0, full_width_ + 1, height_ + 1,
                                   radius, radius);
  SetWindowRgn(window, region, TRUE);
}

void NativeCapsuleWindow::ApplyDockedPosition() {
  HWND window = GetHandle();
  if (!window || dragging_) return;
  const int visible_width = hovered_ ? hover_visible_width_
                                     : resting_visible_width_;
  const int x = capsule_side_ == "left"
                    ? work_area_.left - (full_width_ - visible_width)
                    : work_area_.right - visible_width;
  const int work_area_top = static_cast<int>(work_area_.top);
  const int work_area_bottom = static_cast<int>(work_area_.bottom);
  const int minimum_top = work_area_top + 8;
  const int maximum_top =
      std::max(minimum_top, work_area_bottom - height_ - 8);
  const int y = std::clamp(
      work_area_top + static_cast<int>(std::lround(top_margin_)),
      minimum_top, maximum_top);
  SetWindowPos(window, nullptr, x, y, full_width_, height_,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void NativeCapsuleWindow::SetHovered(bool hovered) {
  if (hovered_ == hovered || dragging_) return;
  hovered_ = hovered;
  ApplyDockedPosition();
  if (HWND window = GetHandle()) InvalidateRect(window, nullptr, FALSE);
}

void NativeCapsuleWindow::SetAvoidFullscreenTopmost(bool avoid) {
  avoid_fullscreen_topmost_ = avoid;
  RefreshVisibility();
}

bool NativeCapsuleWindow::IsVisible() const {
  HWND window = const_cast<NativeCapsuleWindow*>(this)->GetHandle();
  return window && IsWindowVisible(window);
}

bool NativeCapsuleWindow::IsChineseLocale() const {
  wchar_t locale_name[LOCALE_NAME_MAX_LENGTH] = {};
  if (GetUserDefaultLocaleName(locale_name, LOCALE_NAME_MAX_LENGTH) <= 0) {
    return false;
  }
  return std::towlower(locale_name[0]) == L'z' &&
         std::towlower(locale_name[1]) == L'h';
}

std::wstring NativeCapsuleWindow::EffectiveLabel() const {
  if (!master_) return Utf8ToWide(title_);
  if (active_) {
    return Utf8ToWide(IsChineseLocale() ? count_label_zh_ : count_label_en_);
  }
  return Utf8ToWide(IsChineseLocale() ? label_zh_ : label_en_);
}

void NativeCapsuleWindow::SendClick() {
  if (!event_callback_ || paper_id_.empty()) return;
  const std::string kind = master_
                               ? "toggleCollapseAll"
                               : (collapse_on_click_ ? "collapsePaper"
                                                     : "openPaper");
  event_callback_(
      "paperActionRequested",
      flutter::EncodableMap{
          {flutter::EncodableValue("paperId"),
           flutter::EncodableValue(paper_id_)},
          {flutter::EncodableValue("kind"), flutter::EncodableValue(kind)},
          {flutter::EncodableValue("value"),
           flutter::EncodableValue(master_ ? std::string() : paper_id_)},
      });
}

void NativeCapsuleWindow::SendDrop() {
  if (!event_callback_ || paper_id_.empty()) return;
  HWND window = GetHandle();
  POINT cursor = {};
  RECT bounds = {};
  if (!window || !GetCursorPos(&cursor) || !GetWindowRect(window, &bounds)) {
    return;
  }
  HMONITOR monitor = master_
                         ? MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST)
                         : MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(info);
  if (!monitor ||
      !GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&info))) {
    return;
  }
  const LONG center =
      info.rcWork.left + (info.rcWork.right - info.rcWork.left) / 2;
  const std::string side =
      master_ ? capsule_side_ : (cursor.x < center ? "left" : "right");
  event_callback_(
      "capsuleDropped",
      flutter::EncodableMap{
          {flutter::EncodableValue("paperId"),
           flutter::EncodableValue(paper_id_)},
          {flutter::EncodableValue("surfaceId"),
           flutter::EncodableValue(surface_id_)},
          {flutter::EncodableValue("monitorDeviceName"),
           flutter::EncodableValue(WideToUtf8(info.szDevice))},
          {flutter::EncodableValue("side"), flutter::EncodableValue(side)},
          {flutter::EncodableValue("dropTop"),
           flutter::EncodableValue(static_cast<double>(bounds.top))},
          {flutter::EncodableValue("workAreaTop"),
           flutter::EncodableValue(static_cast<double>(info.rcWork.top))},
          {flutter::EncodableValue("isMasterCapsule"),
           flutter::EncodableValue(master_)},
      });
}

bool NativeCapsuleWindow::IsExternalFullscreenWindow() const {
  HWND window = const_cast<NativeCapsuleWindow*>(this)->GetHandle();
  HWND foreground = GetForegroundWindow();
  if (!window || !foreground || foreground == window ||
      IsIconic(foreground) || !IsWindowVisible(foreground)) {
    return false;
  }
  DWORD own_process = 0;
  DWORD foreground_process = 0;
  GetWindowThreadProcessId(window, &own_process);
  GetWindowThreadProcessId(foreground, &foreground_process);
  if (own_process == foreground_process) return false;
  RECT bounds = {};
  if (!GetWindowRect(foreground, &bounds)) return false;
  HMONITOR monitor =
      MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (!monitor || !GetMonitorInfoW(monitor, &info)) return false;
  constexpr LONG tolerance = 2;
  return bounds.left <= info.rcMonitor.left + tolerance &&
         bounds.top <= info.rcMonitor.top + tolerance &&
         bounds.right >= info.rcMonitor.right - tolerance &&
         bounds.bottom >= info.rcMonitor.bottom - tolerance;
}

bool NativeCapsuleWindow::IsCoveredByHigherWindow() const {
  HWND window = const_cast<NativeCapsuleWindow*>(this)->GetHandle();
  if (!window) return false;
  RECT visible = {};
  if (!GetWindowRect(window, &visible)) return false;
  if (capsule_side_ == "left") {
    visible.right = std::min(visible.right,
                             work_area_.left + resting_visible_width_);
  } else {
    visible.left = std::max(visible.left,
                            work_area_.right - resting_visible_width_);
  }
  DWORD own_process = 0;
  GetWindowThreadProcessId(window, &own_process);
  for (HWND candidate = GetWindow(window, GW_HWNDPREV); candidate;
       candidate = GetWindow(candidate, GW_HWNDPREV)) {
    if (!IsWindowVisible(candidate) || IsIconic(candidate)) continue;
    DWORD process = 0;
    GetWindowThreadProcessId(candidate, &process);
    if (process == own_process) continue;
    RECT candidate_bounds = {};
    RECT intersection = {};
    if (GetWindowRect(candidate, &candidate_bounds) &&
        IntersectRect(&intersection, &visible, &candidate_bounds)) {
      return true;
    }
  }
  return false;
}

void NativeCapsuleWindow::RefreshVisibility() {
  HWND window = GetHandle();
  if (!window) return;
  const bool fullscreen = IsExternalFullscreenWindow();
  const bool policy_hidden =
      fullscreen || (hide_when_covered_ && IsCoveredByHigherWindow());
  if (!intended_visible_ || policy_hidden) {
    ShowWindow(window, SW_HIDE);
    return;
  }
  if (!IsWindowVisible(window)) ShowWindow(window, SW_SHOWNOACTIVATE);
  const HWND z_order =
      avoid_fullscreen_topmost_ && fullscreen ? HWND_NOTOPMOST : HWND_TOPMOST;
  SetWindowPos(window, z_order, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER);
}

void NativeCapsuleWindow::Paint(HWND window) {
  PAINTSTRUCT paint = {};
  HDC target = BeginPaint(window, &paint);
  RECT bounds = {};
  GetClientRect(window, &bounds);
  HDC buffer = CreateCompatibleDC(target);
  HBITMAP bitmap = CreateCompatibleBitmap(
      target, std::max(1L, bounds.right), std::max(1L, bounds.bottom));
  HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);

  const bool dark = theme_ == "dark" ||
                    (theme_ == "system" && IsSystemDarkMode());
  COLORREF background = dark ? RGB(54, 48, 42) : RGB(255, 248, 227);
  COLORREF border = dark ? RGB(112, 98, 82) : RGB(218, 198, 161);
  COLORREF text = dark ? RGB(244, 235, 220) : RGB(54, 47, 39);
  COLORREF weak = dark ? RGB(202, 188, 168) : RGB(113, 100, 83);
  if (color_scheme_ == "forest") {
    background = dark ? RGB(40, 55, 46) : RGB(239, 248, 232);
    border = dark ? RGB(83, 112, 90) : RGB(178, 204, 166);
  } else if (color_scheme_ == "rose") {
    background = dark ? RGB(62, 43, 48) : RGB(255, 239, 237);
    border = dark ? RGB(128, 82, 94) : RGB(225, 183, 178);
  } else if (color_scheme_ == "ink") {
    background = dark ? RGB(39, 42, 47) : RGB(247, 246, 242);
    border = dark ? RGB(88, 94, 104) : RGB(199, 198, 192);
  }
  COLORREF custom = 0;
  if (ParseHexColor(custom_theme_color_hex_, &custom)) {
    background = Mix(custom, dark ? RGB(28, 28, 28) : RGB(255, 255, 255),
                     dark ? 58 : 82);
    border = Mix(custom, dark ? RGB(235, 235, 235) : RGB(70, 70, 70), 35);
  }
  if (hovered_) background = Mix(background, text, dark ? 10 : 6);
  if (active_ && master_) border = Mix(border, text, 28);

  HBRUSH background_brush = CreateSolidBrush(background);
  HPEN border_pen = CreatePen(PS_SOLID, 1, border);
  HGDIOBJ old_brush = SelectObject(buffer, background_brush);
  HGDIOBJ old_pen = SelectObject(buffer, border_pen);
  const int radius = std::max(12, height_ / 2);
  RoundRect(buffer, 0, 0, bounds.right, bounds.bottom, radius, radius);

  SetBkMode(buffer, TRANSPARENT);
  const std::wstring glyph = master_
                                 ? (active_ ? L"\u25B8" : L"\u25BE")
                                 : (paper_type_ == "note" ? L"\u2261" : L"\u2713");
  const std::wstring label = EffectiveLabel();
  HFONT glyph_font = CreateFontW(-13, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE,
                                 FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                 CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                 DEFAULT_PITCH, L"Segoe UI Symbol");
  HFONT text_font = CreateFontW(-12, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                DEFAULT_PITCH, L"Segoe UI");
  const bool left = capsule_side_ == "left";
  RECT glyph_rect = left ? RECT{bounds.right - 25, 0, bounds.right - 7,
                                bounds.bottom}
                         : RECT{7, 0, 25, bounds.bottom};
  RECT text_rect = left ? RECT{9, 0, bounds.right - 28, bounds.bottom}
                        : RECT{28, 0, bounds.right - 9, bounds.bottom};
  SetTextColor(buffer, text);
  HGDIOBJ old_font = SelectObject(buffer, glyph_font);
  DrawTextW(buffer, glyph.c_str(), static_cast<int>(glyph.size()), &glyph_rect,
            DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_NOPREFIX);
  SelectObject(buffer, text_font);
  SetTextColor(buffer, weak);
  DrawTextW(buffer, label.c_str(), static_cast<int>(label.size()), &text_rect,
            DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX |
                (left ? DT_RIGHT : DT_LEFT));

  BitBlt(target, 0, 0, bounds.right, bounds.bottom, buffer, 0, 0, SRCCOPY);
  SelectObject(buffer, old_font);
  SelectObject(buffer, old_pen);
  SelectObject(buffer, old_brush);
  SelectObject(buffer, old_bitmap);
  DeleteObject(text_font);
  DeleteObject(glyph_font);
  DeleteObject(border_pen);
  DeleteObject(background_brush);
  DeleteObject(bitmap);
  DeleteDC(buffer);
  EndPaint(window, &paint);
}

LRESULT NativeCapsuleWindow::MessageHandler(HWND window, UINT const message,
                                            WPARAM const wparam,
                                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      Paint(window);
      return 0;
    case WM_NCHITTEST:
      return HTCLIENT;
    case WM_SETCURSOR:
      SetCursor(LoadCursor(nullptr, pointer_down_ ? IDC_SIZEALL : IDC_HAND));
      return TRUE;
    case WM_MOUSEMOVE: {
      if (!tracking_mouse_leave_) {
        TRACKMOUSEEVENT tracking = {};
        tracking.cbSize = sizeof(tracking);
        tracking.dwFlags = TME_LEAVE;
        tracking.hwndTrack = window;
        tracking_mouse_leave_ = TrackMouseEvent(&tracking) == TRUE;
      }
      if (!pointer_down_) {
        SetHovered(true);
        return 0;
      }
      POINT cursor = {};
      if (!GetCursorPos(&cursor)) return 0;
      const int delta_x = cursor.x - drag_start_cursor_.x;
      const int delta_y = cursor.y - drag_start_cursor_.y;
      if (!dragging_ && std::abs(delta_x) < GetSystemMetrics(SM_CXDRAG) &&
          std::abs(delta_y) < GetSystemMetrics(SM_CYDRAG)) {
        return 0;
      }
      dragging_ = true;
      const int width = drag_start_bounds_.right - drag_start_bounds_.left;
      const int height = drag_start_bounds_.bottom - drag_start_bounds_.top;
      if (master_) {
        const int work_area_top = static_cast<int>(work_area_.top);
        const int work_area_bottom = static_cast<int>(work_area_.bottom);
        const int minimum_top = work_area_top + 8;
        const int maximum_top =
            std::max(minimum_top, work_area_bottom - height - 8);
        const int target_top =
            std::clamp(static_cast<int>(drag_start_bounds_.top) + delta_y,
                       minimum_top,
                       maximum_top);
        SetWindowPos(window, nullptr, drag_start_bounds_.left, target_top,
                     width, height, SWP_NOZORDER | SWP_NOACTIVATE);
      } else {
        SetWindowPos(window, HWND_TOPMOST,
                     drag_start_bounds_.left + delta_x,
                     drag_start_bounds_.top + delta_y, width, height,
                     SWP_NOACTIVATE);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      tracking_mouse_leave_ = false;
      if (!pointer_down_) SetHovered(false);
      return 0;
    case WM_LBUTTONDOWN:
      pointer_down_ = true;
      dragging_ = false;
      GetCursorPos(&drag_start_cursor_);
      GetWindowRect(window, &drag_start_bounds_);
      SetCapture(window);
      return 0;
    case WM_LBUTTONUP: {
      if (!pointer_down_) return 0;
      const bool was_dragging = dragging_;
      pointer_down_ = false;
      dragging_ = false;
      if (GetCapture() == window) ReleaseCapture();
      if (was_dragging) {
        SendDrop();
      } else {
        SendClick();
      }
      SetHovered(false);
      return 0;
    }
    case WM_CAPTURECHANGED:
      pointer_down_ = false;
      dragging_ = false;
      return 0;
    case WM_CLOSE:
      ShowWindow(window, SW_HIDE);
      return 0;
  }
  return Win32Window::MessageHandler(window, message, wparam, lparam);
}
