#include "paper_flutter_window.h"

#include <dwmapi.h>
#include <commctrl.h>
#include <shobjidl.h>
#include <windowsx.h>

#include <flutter_windows.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
#include <utility>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
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

int64_t IntegerValue(const flutter::EncodableMap& map, const char* key,
                     int64_t fallback) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
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

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) {
    return std::string();
  }
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

COLORREF ColorRefFromArgb(int64_t value, COLORREF fallback) {
  if (value < 0 || value > 0xFFFFFFFFLL) {
    return fallback;
  }
  const uint32_t argb = static_cast<uint32_t>(value);
  return RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
}

int ScaleForDpi(HWND window, int logical_pixels) {
  const UINT dpi = window ? GetDpiForWindow(window) : 96;
  return MulDiv(logical_pixels, dpi ? static_cast<int>(dpi) : 96, 96);
}

UINT DpiForPhysicalPoint(HWND window, double x, double y) {
  const POINT point = {static_cast<LONG>(std::lround(x)),
                       static_cast<LONG>(std::lround(y))};
  const HMONITOR monitor =
      MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
  const UINT monitor_dpi = monitor ? FlutterDesktopGetDpiForMonitor(monitor) : 0;
  if (monitor_dpi > 0) {
    return monitor_dpi;
  }
  const UINT window_dpi = window ? GetDpiForWindow(window) : 96;
  return window_dpi > 0 ? window_dpi : 96;
}

double ScaleLogicalValue(double value, UINT dpi) {
  return value * static_cast<double>(dpi > 0 ? dpi : 96) / 96.0;
}

double UnscalePhysicalValue(double value, UINT dpi) {
  return value * 96.0 / static_cast<double>(dpi > 0 ? dpi : 96);
}

constexpr wchar_t kReminderBubbleWindowClass[] =
    L"RePaperTodo.ReminderBubble";
constexpr wchar_t kPaperShadowWindowClass[] = L"RePaperTodo.PaperShadow";
constexpr UINT_PTR kReminderBubbleTimerId = 1;
constexpr UINT_PTR kCapsuleSlideTimerId = 0xCA52;
constexpr UINT_PTR kCapsuleQueueFollowTimerId = 0xCA53;
constexpr UINT_PTR kCapsuleMasterTransitionTimerId = 0xCA56;
constexpr int kCapsuleSlideOutMilliseconds = 220;
constexpr int kCapsuleSlideInMilliseconds = 180;
constexpr int kCapsuleQueueFollowMilliseconds = 64;
constexpr int kCapsuleQueueMoveMilliseconds = 200;
constexpr int kCapsuleMasterMoveMilliseconds = 200;
constexpr int kCapsuleMasterFadeMilliseconds = 160;

// A deep capsule is deliberately a WS_EX_NOACTIVATE window.  When its click
// is delivered through the native proxy, Windows does not always grant the
// RePaperTodo process the foreground permission that a real mouse click would
// grant.  Activating the paper through SetForegroundWindow alone therefore
// occasionally leaves another application in front even though the paper was
// successfully unpinned.  Temporarily joining the foreground input queue
// makes the activation deterministic without changing the paper's normal
// task-switcher or z-order policy.
void ActivatePaperWindow(HWND window, bool always_on_top) {
  if (!window || !IsWindow(window)) return;

  HWND foreground = GetForegroundWindow();
  DWORD foreground_thread = 0;
  if (foreground) {
    foreground_thread = GetWindowThreadProcessId(foreground, nullptr);
  }
  const DWORD current_thread = GetCurrentThreadId();
  const bool attached = foreground_thread != 0 &&
                        foreground_thread != current_thread &&
                        AttachThreadInput(foreground_thread, current_thread,
                                          TRUE) == TRUE;

  // The call is harmless when the process already owns the foreground lock,
  // and permits the activation path when the click came from a synthetic
  // WM_LBUTTON sequence (as used by the Windows policy smoke test).
  AllowSetForegroundWindow(ASFW_ANY);
  SetWindowPos(window, always_on_top ? HWND_TOPMOST : HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  BringWindowToTop(window);
  SetActiveWindow(window);
  SetForegroundWindow(window);
  SetFocus(window);

  if (attached) {
    AttachThreadInput(foreground_thread, current_thread, FALSE);
  }
}
constexpr UINT kDeferredPaperActionMessage = WM_APP + 0x351;
constexpr UINT kDeferredPaperShadowRefreshMessage = WM_APP + 0x352;

bool IsSystemPaperThemeDark() {
  DWORD light_mode = 1;
  DWORD size = sizeof(light_mode);
  const LSTATUS result = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light_mode, &size);
  return result == ERROR_SUCCESS && light_mode == 0;
}

double RoundedRectSignedDistance(double x, double y, double left, double top,
                                 double right, double bottom,
                                 double radius) {
  const double center_x = (left + right) * 0.5;
  const double center_y = (top + bottom) * 0.5;
  const double half_width = std::max(0.0, (right - left) * 0.5);
  const double half_height = std::max(0.0, (bottom - top) * 0.5);
  const double safe_radius =
      std::clamp(radius, 0.0, std::min(half_width, half_height));
  const double qx = std::abs(x - center_x) - (half_width - safe_radius);
  const double qy = std::abs(y - center_y) - (half_height - safe_radius);
  const double outside =
      std::hypot(std::max(qx, 0.0), std::max(qy, 0.0));
  const double inside = std::min(std::max(qx, qy), 0.0);
  return outside + inside - safe_radius;
}

bool IsWideCapsuleCharacter(wchar_t value) {
  const unsigned int code = static_cast<unsigned int>(value);
  return code >= 0x1100 &&
         (code <= 0x115F || code == 0x2329 || code == 0x232A ||
          (code >= 0x2E80 && code <= 0xA4CF) ||
          (code >= 0xAC00 && code <= 0xD7A3) ||
          (code >= 0xF900 && code <= 0xFAFF) ||
          (code >= 0xFE10 && code <= 0xFE6F) ||
          (code >= 0xFF00 && code <= 0xFF60) ||
          (code >= 0xFFE0 && code <= 0xFFE6) ||
          (code >= 0xD800 && code <= 0xDBFF));
}

double CapsuleTextWidthEstimate(const std::wstring& text) {
  double width = 0.0;
  for (size_t index = 0; index < text.size(); ++index) {
    const wchar_t value = text[index];
    if (value >= 0xDC00 && value <= 0xDFFF) {
      continue;
    }
    width += IsWideCapsuleCharacter(value) ? 11.0 : 6.2;
  }
  return width;
}

std::wstring CapsuleFontFamily(const std::string& family) {
  std::wstring result = Utf8WindowTitle(family);
  if (result.empty()) {
    result = L"Segoe UI";
  }
  if (result.size() >= LF_FACESIZE) {
    result.resize(LF_FACESIZE - 1);
  }
  return result;
}

double MeasureCapsuleTextWidth(const std::wstring& text,
                               int logical_font_size,
                               int font_weight,
                               const std::wstring& font_family,
                               UINT dpi) {
  if (text.empty()) {
    return 0.0;
  }
  HDC dc = GetDC(nullptr);
  if (!dc) {
    return CapsuleTextWidthEstimate(text);
  }
  const int physical_font_size = std::max(
      1, static_cast<int>(std::lround(
             ScaleLogicalValue(logical_font_size, dpi))));
  HFONT font = CreateFontW(
      -physical_font_size, 0, 0, 0, font_weight, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH, font_family.c_str());
  if (!font) {
    ReleaseDC(nullptr, dc);
    return CapsuleTextWidthEstimate(text);
  }
  const HGDIOBJ old_font = SelectObject(dc, font);
  SIZE measured = {};
  const bool measured_ok =
      GetTextExtentPoint32W(dc, text.c_str(), static_cast<int>(text.size()),
                            &measured) == TRUE;
  SelectObject(dc, old_font);
  DeleteObject(font);
  ReleaseDC(nullptr, dc);
  return measured_ok
             ? UnscalePhysicalValue(measured.cx, dpi)
             : CapsuleTextWidthEstimate(text);
}

double CapsuleWpfMetricCorrection(const std::string& paper_type,
                                  bool script_capsule) {
  // WPF FormattedText and GDI differ by a small glyph-specific advance at
  // 11/13/15 logical pixels. These values match PaperTodo v2.27 captures.
  return paper_type == "note" || script_capsule ? -2.0 : -3.0;
}

double CapsuleWindowWidth(const std::string& title,
                          bool deep,
                          const std::string& paper_type,
                          bool script_capsule,
                          const std::string& font_family,
                          UINT dpi) {
  const std::wstring icon = script_capsule
                                ? L"\u26A1"
                                : (paper_type == "note" ? L"\u270E"
                                                        : L"\u2713");
  const int icon_size = script_capsule ? 15 : 13;
  const double icon_width = MeasureCapsuleTextWidth(
      icon, icon_size, FW_SEMIBOLD, L"Segoe UI Symbol", dpi);
  const double title_width = MeasureCapsuleTextWidth(
      Utf8WindowTitle(title), 11, FW_NORMAL,
      CapsuleFontFamily(font_family), dpi);
  const double metric_correction =
      CapsuleWpfMetricCorrection(paper_type, script_capsule);
  const double fixed_width = deep ? 62.0 : 53.0;
  const double minimum_width = deep ? 92.0 : 76.0;
  return std::ceil(
      std::max(minimum_width,
               fixed_width + icon_width + title_width + metric_correction));
}

double CapsuleRestingVisibleWidth(const std::string& title,
                                  const std::string& paper_type,
                                  bool script_capsule,
                                  const std::string& font_family,
                                  UINT dpi,
                                  double capsule_width) {
  const std::wstring icon = script_capsule
                                ? L"\u26A1"
                                : (paper_type == "note" ? L"\u270E"
                                                        : L"\u2713");
  const double icon_width = MeasureCapsuleTextWidth(
      icon, script_capsule ? 15 : 13, FW_SEMIBOLD,
      L"Segoe UI Symbol", dpi);
  const double title_width = MeasureCapsuleTextWidth(
      Utf8WindowTitle(title), 11, FW_NORMAL,
      CapsuleFontFamily(font_family), dpi);
  const double metric_correction =
      CapsuleWpfMetricCorrection(paper_type, script_capsule);
  const double desired =
      22.0 + icon_width + title_width + metric_correction;
  return std::clamp(desired, 34.0,
                    std::max(34.0, capsule_width - 32.0));
}

double CapsuleHoverVisibleWidth(double capsule_width,
                                double resting_visible_width) {
  const double halfway = resting_visible_width +
                         ((capsule_width - resting_visible_width) * 0.5);
  return std::clamp(halfway, std::min(54.0, capsule_width), capsule_width);
}

bool IsExternalFullscreenWindow(HWND app_window) {
  HWND foreground = GetForegroundWindow();
  if (!foreground || foreground == app_window || IsIconic(foreground) ||
      !IsWindowVisible(foreground)) {
    return false;
  }
  DWORD app_process = 0;
  DWORD foreground_process = 0;
  GetWindowThreadProcessId(app_window, &app_process);
  GetWindowThreadProcessId(foreground, &foreground_process);
  if (app_process == foreground_process || foreground == GetShellWindow()) {
    return false;
  }
  const LONG_PTR style = GetWindowLongPtrW(foreground, GWL_STYLE);
  if ((style & WS_CHILD) != 0) {
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
  const auto covers_monitor = [&info, tolerance](const RECT& bounds) {
    return bounds.right > bounds.left && bounds.bottom > bounds.top &&
           bounds.left <= info.rcMonitor.left + tolerance &&
           bounds.top <= info.rcMonitor.top + tolerance &&
           bounds.right >= info.rcMonitor.right - tolerance &&
           bounds.bottom >= info.rcMonitor.bottom - tolerance;
  };
  RECT bounds = {};
  if (SUCCEEDED(DwmGetWindowAttribute(foreground,
                                      DWMWA_EXTENDED_FRAME_BOUNDS, &bounds,
                                      sizeof(bounds))) &&
      covers_monitor(bounds)) {
    return true;
  }
  return GetWindowRect(foreground, &bounds) && covers_monitor(bounds);
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
    wchar_t class_name[64] = {};
    if (root) {
      GetClassNameW(root, class_name,
                    static_cast<int>(std::size(class_name)));
    }
    if (wcscmp(class_name, kPaperShadowWindowClass) == 0) {
      continue;
    }
    if (root && root != app_window && IsWindowVisible(root) &&
        root != GetShellWindow() && root != GetDesktopWindow()) {
      return true;
    }
  }
  return false;
}

bool IsPointerInsideWindow(HWND window) {
  if (!window || !IsWindowVisible(window)) {
    return false;
  }
  POINT cursor = {};
  RECT bounds = {};
  return GetCursorPos(&cursor) && GetWindowRect(window, &bounds) &&
         PtInRect(&bounds, cursor) == TRUE;
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

void RemoveTaskbarButton(HWND window) {
  ITaskbarList* taskbar = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                 CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&taskbar))) &&
      taskbar) {
    if (SUCCEEDED(taskbar->HrInit())) {
      taskbar->DeleteTab(window);
    }
    taskbar->Release();
  }
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

struct DateTimePickerDialogState {
  HWND dialog = nullptr;
  HWND date = nullptr;
  HWND date_surface = nullptr;
  HWND hour = nullptr;
  HWND hour_surface = nullptr;
  HWND minute = nullptr;
  HWND minute_surface = nullptr;
  HWND clear_button = nullptr;
  HWND cancel_button = nullptr;
  HWND ok_button = nullptr;
  SYSTEMTIME initial = {};
  SYSTEMTIME selected = {};
  std::wstring title;
  std::wstring message;
  std::wstring clear_label;
  std::wstring cancel_label;
  std::wstring ok_label;
  std::wstring font_family = L"Segoe UI";
  std::wstring numeric_font_family = L"Segoe UI";
  COLORREF background = RGB(255, 249, 234);
  COLORREF border = RGB(224, 206, 167);
  COLORREF accent = RGB(140, 115, 80);
  COLORREF primary_text = RGB(255, 255, 255);
  COLORREF text = RGB(51, 41, 30);
  COLORREF weak_text = RGB(138, 122, 99);
  COLORREF input_background = RGB(249, 241, 225);
  COLORREF secondary_button_background = RGB(238, 230, 211);
  HBRUSH background_brush = nullptr;
  HBRUSH input_background_brush = nullptr;
  HFONT title_font = nullptr;
  HFONT body_font = nullptr;
  HFONT control_font = nullptr;
  HFONT numeric_font = nullptr;
  HFONT button_font = nullptr;
  bool open_calendar = false;
  bool date_text_selected = false;
  bool dark = false;
  bool date_hovered = false;
  bool hour_hovered = false;
  bool minute_hovered = false;
  bool clear_hovered = false;
  bool cancel_hovered = false;
  bool ok_hovered = false;
  bool accepted = false;
  bool clear = false;
};

constexpr int kDatePickerDateId = 1001;
constexpr int kDatePickerHourId = 1002;
constexpr int kDatePickerMinuteId = 1006;
constexpr int kDatePickerDateSurfaceId = 1007;
constexpr int kDatePickerHourSurfaceId = 1008;
constexpr int kDatePickerMinuteSurfaceId = 1009;
constexpr int kDatePickerClearId = 1003;
constexpr int kDatePickerCancelId = 1004;
constexpr int kDatePickerOkId = 1005;
constexpr wchar_t kDatePickerClass[] = L"RePaperTodo.DateTimePicker";

COLORREF BlendColor(COLORREF background, COLORREF foreground,
                    int foreground_alpha) {
  const int alpha = std::clamp(foreground_alpha, 0, 255);
  const int inverse = 255 - alpha;
  return RGB((GetRValue(background) * inverse + GetRValue(foreground) * alpha) /
                 255,
             (GetGValue(background) * inverse + GetGValue(foreground) * alpha) /
                 255,
             (GetBValue(background) * inverse + GetBValue(foreground) * alpha) /
                 255);
}

bool PointInsideRoundedRect(double x, double y, double left, double top,
                            double right, double bottom, double radius) {
  if (x < left || x >= right || y < top || y >= bottom) {
    return false;
  }
  const double normalized_radius = std::max(
      0.0, std::min(radius, std::min(right - left, bottom - top) / 2.0));
  const double nearest_x =
      std::clamp(x, left + normalized_radius, right - normalized_radius);
  const double nearest_y =
      std::clamp(y, top + normalized_radius, bottom - normalized_radius);
  const double dx = x - nearest_x;
  const double dy = y - nearest_y;
  return dx * dx + dy * dy <= normalized_radius * normalized_radius;
}

double RoundedRectPixelCoverage(int x, int y, double left, double top,
                                double right, double bottom, double radius) {
  constexpr int kSamplesPerAxis = 4;
  int inside = 0;
  for (int sample_y = 0; sample_y < kSamplesPerAxis; ++sample_y) {
    for (int sample_x = 0; sample_x < kSamplesPerAxis; ++sample_x) {
      const double point_x =
          x + (static_cast<double>(sample_x) + 0.5) / kSamplesPerAxis;
      const double point_y =
          y + (static_cast<double>(sample_y) + 0.5) / kSamplesPerAxis;
      if (PointInsideRoundedRect(point_x, point_y, left, top, right, bottom,
                                 radius)) {
        ++inside;
      }
    }
  }
  return static_cast<double>(inside) /
         (kSamplesPerAxis * kSamplesPerAxis);
}

double CirclePixelCoverage(int x, int y, double left, double top,
                           double diameter) {
  constexpr int kSamplesPerAxis = 4;
  const double radius = diameter / 2.0;
  const double center_x = left + radius;
  const double center_y = top + radius;
  int inside = 0;
  for (int sample_y = 0; sample_y < kSamplesPerAxis; ++sample_y) {
    for (int sample_x = 0; sample_x < kSamplesPerAxis; ++sample_x) {
      const double point_x =
          x + (static_cast<double>(sample_x) + 0.5) / kSamplesPerAxis;
      const double point_y =
          y + (static_cast<double>(sample_y) + 0.5) / kSamplesPerAxis;
      const double dx = point_x - center_x;
      const double dy = point_y - center_y;
      if (dx * dx + dy * dy <= radius * radius) {
        ++inside;
      }
    }
  }
  return static_cast<double>(inside) /
         (kSamplesPerAxis * kSamplesPerAxis);
}

bool IsDarkColor(COLORREF color) {
  const int luminance = GetRValue(color) * 299 + GetGValue(color) * 587 +
                        GetBValue(color) * 114;
  return luminance < 128000;
}

bool* DateTimePickerButtonHoverState(DateTimePickerDialogState* state,
                                     int control_id) {
  if (!state) return nullptr;
  switch (control_id) {
    case kDatePickerDateSurfaceId:
      return &state->date_hovered;
    case kDatePickerHourSurfaceId:
      return &state->hour_hovered;
    case kDatePickerMinuteSurfaceId:
      return &state->minute_hovered;
    case kDatePickerClearId:
      return &state->clear_hovered;
    case kDatePickerCancelId:
      return &state->cancel_hovered;
    case kDatePickerOkId:
      return &state->ok_hovered;
    default:
      return nullptr;
  }
}

LRESULT CALLBACK DateTimePickerButtonSubclassProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference_data) noexcept {
  auto* state = reinterpret_cast<DateTimePickerDialogState*>(reference_data);
  bool* hovered = DateTimePickerButtonHoverState(state, GetDlgCtrlID(window));
  switch (message) {
    case WM_MOUSEMOVE: {
      if (hovered && !*hovered) {
        *hovered = true;
        TRACKMOUSEEVENT tracking = {};
        tracking.cbSize = sizeof(tracking);
        tracking.dwFlags = TME_LEAVE;
        tracking.hwndTrack = window;
        TrackMouseEvent(&tracking);
        InvalidateRect(window, nullptr, TRUE);
      }
      break;
    }
    case WM_MOUSELEAVE:
      if (hovered && *hovered) {
        *hovered = false;
        InvalidateRect(window, nullptr, TRUE);
      }
      break;
    case WM_SETFOCUS:
    case WM_KILLFOCUS:
      InvalidateRect(window, nullptr, TRUE);
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(window, DateTimePickerButtonSubclassProc,
                           subclass_id);
      break;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

bool IsChineseUserLocale() {
  wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
  return GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH) > 1 &&
         (locale[0] == L'z' || locale[0] == L'Z') &&
         (locale[1] == L'h' || locale[1] == L'H');
}

std::wstring NativeDialogFontFamily(
    const flutter::EncodableMap& arguments,
    bool chinese) {
  std::wstring family =
      Utf8WindowTitle(StringValue(arguments, "fontFamily", ""));
  if (family.empty()) {
    family = chinese ? L"Microsoft YaHei UI" : L"Segoe UI";
  } else if (_wcsicmp(family.c_str(), L"serif") == 0) {
    family = L"Georgia";
  } else if (_wcsicmp(family.c_str(), L"monospace") == 0) {
    family = L"Consolas";
  }
  if (family.size() >= LF_FACESIZE) {
    family.resize(LF_FACESIZE - 1);
  }
  return family;
}

std::wstring DateTimePickerDateLabel(const SYSTEMTIME& value) {
  wchar_t label[80] = {};
  if (GetDateFormatW(LOCALE_USER_DEFAULT, DATE_SHORTDATE, &value, nullptr,
                     label, static_cast<int>(std::size(label))) > 0) {
    return label;
  }
  swprintf_s(label, L"%04u/%u/%u", value.wYear, value.wMonth, value.wDay);
  return label;
}

void DrawDateTimePickerInputFrame(const DRAWITEMSTRUCT* draw,
                                  DateTimePickerDialogState* state,
                                  bool hovered, bool system_combo) {
  if (!draw || !state) return;
  const bool light_system_combo = system_combo && !state->dark;
  const bool light_date_input = !system_combo && !state->dark;
  const COLORREF background =
      light_system_combo
          ? (hovered ? RGB(244, 244, 244) : RGB(237, 237, 237))
      : light_date_input
          ? state->input_background
          : (hovered ? BlendColor(state->input_background, state->accent, 12)
                     : state->input_background);
  const COLORREF border =
      light_system_combo
          ? (hovered ? RGB(122, 122, 122) : RGB(172, 172, 172))
      : light_date_input
          ? (hovered ? RGB(172, 172, 172) : RGB(213, 200, 176))
          : BlendColor(state->background, state->accent,
                       hovered ? 108 : 80);
  HBRUSH background_brush = CreateSolidBrush(background);
  HPEN border_pen = CreatePen(PS_SOLID, 1, border);
  const HGDIOBJ old_brush = SelectObject(draw->hDC, background_brush);
  const HGDIOBJ old_pen = SelectObject(draw->hDC, border_pen);
  if (light_system_combo && !hovered) {
    for (int y = draw->rcItem.top + 1; y < draw->rcItem.bottom - 1; ++y) {
      const int span = std::max(
          1, static_cast<int>(draw->rcItem.bottom - draw->rcItem.top - 3));
      const int offset = y - draw->rcItem.top - 1;
      const int shade = 240 - ((11 * offset + span / 2) / span);
      RECT row = {draw->rcItem.left + 1, y, draw->rcItem.right - 1, y + 1};
      HBRUSH row_brush = CreateSolidBrush(RGB(shade, shade, shade));
      FillRect(draw->hDC, &row, row_brush);
      DeleteObject(row_brush);
    }
    SelectObject(draw->hDC, GetStockObject(NULL_BRUSH));
  }
  Rectangle(draw->hDC, draw->rcItem.left, draw->rcItem.top,
            draw->rcItem.right, draw->rcItem.bottom);
  SelectObject(draw->hDC, old_brush);
  SelectObject(draw->hDC, old_pen);
  DeleteObject(background_brush);
  DeleteObject(border_pen);
}

void DrawDateTimePickerCalendarIcon(HDC context, const RECT& bounds,
                                    DateTimePickerDialogState* state) {
  if (!context || !state) return;
  const int scale = std::max(1, ScaleForDpi(state->dialog, 1));
  const int icon_height = ScaleForDpi(state->dialog, 18);
  const int icon_top = static_cast<int>(bounds.top) + std::max(
      scale,
      (static_cast<int>(bounds.bottom - bounds.top) - icon_height) / 2);
  RECT icon = {
      bounds.right - ScaleForDpi(state->dialog, 31),
      icon_top,
      bounds.right - ScaleForDpi(state->dialog, 11),
      icon_top + icon_height};
  if (!state->dark) {
    HBITMAP bitmap = static_cast<HBITMAP>(LoadImageW(
        GetModuleHandleW(nullptr),
        MAKEINTRESOURCEW(IDB_DATE_PICKER_CALENDAR_LIGHT), IMAGE_BITMAP, 0, 0,
        LR_CREATEDIBSECTION));
    if (bitmap) {
      HDC source = CreateCompatibleDC(context);
      const HGDIOBJ old_bitmap = SelectObject(source, bitmap);
      SetStretchBltMode(context, HALFTONE);
      SetBrushOrgEx(context, 0, 0, nullptr);
      StretchBlt(context, icon.left, icon.top, icon.right - icon.left,
                 icon.bottom - icon.top, source, 0, 0, 20, 18, SRCCOPY);
      SelectObject(source, old_bitmap);
      DeleteDC(source);
      DeleteObject(bitmap);
      return;
    }
  }
  HBRUSH icon_background = CreateSolidBrush(
      state->dark
          ? BlendColor(state->input_background, RGB(255, 255, 255), 118)
          : RGB(240, 240, 240));
  HPEN icon_border = CreatePen(
      PS_SOLID, scale,
      state->dark ? BlendColor(state->weak_text, state->text, 72)
                  : RGB(116, 116, 116));
  const HGDIOBJ old_brush = SelectObject(context, icon_background);
  const HGDIOBJ old_pen = SelectObject(context, icon_border);
  Rectangle(context, icon.left, icon.top, icon.right, icon.bottom);
  HBRUSH header_brush = CreateSolidBrush(state->dark
                                             ? RGB(93, 137, 176)
                                             : RGB(113, 165, 209));
  RECT header = {icon.left + scale, icon.top + ScaleForDpi(state->dialog, 2),
                 icon.right - scale,
                 icon.top + ScaleForDpi(state->dialog, 6)};
  FillRect(context, &header, header_brush);
  SetBkMode(context, TRANSPARENT);
  SetTextColor(context, state->text);
  SelectObject(context, state->numeric_font);
  RECT day = {icon.left + scale, icon.top + ScaleForDpi(state->dialog, 5),
              icon.right - scale, icon.bottom - scale};
  DrawTextW(context, L"15", -1, &day,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(context, old_brush);
  SelectObject(context, old_pen);
  DeleteObject(header_brush);
  DeleteObject(icon_background);
  DeleteObject(icon_border);
}

void DrawDateTimePickerDropChevron(HDC context, const RECT& bounds,
                                   DateTimePickerDialogState* state) {
  if (!context || !state) return;
  const int center_x = bounds.right - ScaleForDpi(state->dialog, 10);
  const int center_y = (bounds.top + bounds.bottom) / 2;
  const COLORREF color =
      state->dark ? state->weak_text : RGB(102, 102, 102);
  POINT points[] = {
      {center_x - ScaleForDpi(state->dialog, 2),
       center_y - ScaleForDpi(state->dialog, 3)},
      {center_x + ScaleForDpi(state->dialog, 3),
       center_y - ScaleForDpi(state->dialog, 3)},
      {center_x, center_y + ScaleForDpi(state->dialog, 2)}};
  HBRUSH brush = CreateSolidBrush(color);
  const HGDIOBJ old_brush = SelectObject(context, brush);
  const HGDIOBJ old_pen = SelectObject(context, GetStockObject(NULL_PEN));
  Polygon(context, points, static_cast<int>(std::size(points)));
  SelectObject(context, old_brush);
  SelectObject(context, old_pen);
  DeleteObject(brush);
}

LRESULT CALLBACK DateTimePickerWindowProc(HWND window, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) noexcept {
  auto* state = reinterpret_cast<DateTimePickerDialogState*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    state = create ? static_cast<DateTimePickerDialogState*>(create->lpCreateParams)
                   : nullptr;
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(state));
    if (state) state->dialog = window;
  }
  if (!state) return DefWindowProcW(window, message, wparam, lparam);
  switch (message) {
    case WM_CREATE: {
      const auto scaled = [window](int value) {
        return ScaleForDpi(window, value);
      };
      state->background_brush = CreateSolidBrush(state->background);
      state->input_background_brush =
          CreateSolidBrush(state->input_background);
      state->title_font = CreateFontW(
          -scaled(14), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());
      state->body_font = CreateFontW(
          -scaled(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());
      state->control_font = CreateFontW(
          -scaled(13), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());
      state->numeric_font = CreateFontW(
          -scaled(13), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->numeric_font_family.c_str());
      state->button_font = CreateFontW(
          -scaled(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());
      state->date = CreateWindowExW(
          0, DATETIMEPICK_CLASSW, L"", WS_CHILD | WS_VISIBLE |
          WS_TABSTOP | DTS_SHORTDATEFORMAT, scaled(17), scaled(71),
          scaled(158), scaled(29), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerDateId)), GetModuleHandleW(nullptr),
          nullptr);
      state->hour = CreateWindowExW(
          0, WC_COMBOBOXW, L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP |
          WS_VSCROLL | CBS_DROPDOWNLIST, scaled(183), scaled(71),
          scaled(74), scaled(259), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerHourId)), GetModuleHandleW(nullptr),
          nullptr);
      state->minute = CreateWindowExW(
          0, WC_COMBOBOXW, L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP |
          WS_VSCROLL | CBS_DROPDOWNLIST, scaled(263), scaled(71),
          scaled(74), scaled(419), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerMinuteId)), GetModuleHandleW(nullptr),
          nullptr);
      state->date_surface = CreateWindowW(
          L"BUTTON", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
          scaled(17), scaled(71), scaled(158), scaled(29), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerDateSurfaceId)),
          GetModuleHandleW(nullptr), nullptr);
      state->hour_surface = CreateWindowW(
          L"BUTTON", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
          scaled(183), scaled(71), scaled(74), scaled(29), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerHourSurfaceId)),
          GetModuleHandleW(nullptr), nullptr);
      state->minute_surface = CreateWindowW(
          L"BUTTON", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
          scaled(263), scaled(71), scaled(74), scaled(29), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerMinuteSurfaceId)),
          GetModuleHandleW(nullptr), nullptr);
      state->date_text_selected = true;
      state->cancel_button = CreateWindowW(
          L"BUTTON", state->cancel_label.c_str(),
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
          scaled(133), scaled(116), scaled(64), scaled(26), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerCancelId)),
          GetModuleHandleW(nullptr), nullptr);
      state->clear_button = CreateWindowW(
          L"BUTTON", state->clear_label.c_str(),
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
          scaled(203), scaled(116), scaled(64), scaled(26), window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerClearId)),
          GetModuleHandleW(nullptr), nullptr);
      state->ok_button = CreateWindowW(
          L"BUTTON", state->ok_label.c_str(),
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW |
          BS_DEFPUSHBUTTON, scaled(273), scaled(116), scaled(64), scaled(26),
          window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerOkId)),
          GetModuleHandleW(nullptr), nullptr);
      for (int value = 0; value < 24; ++value) {
        wchar_t label[3] = {};
        swprintf_s(label, L"%02d", value);
        SendMessageW(state->hour, CB_ADDSTRING, 0,
                     reinterpret_cast<LPARAM>(label));
      }
      for (int value = 0; value < 60; ++value) {
        wchar_t label[3] = {};
        swprintf_s(label, L"%02d", value);
        SendMessageW(state->minute, CB_ADDSTRING, 0,
                     reinterpret_cast<LPARAM>(label));
      }
      for (HWND child : {state->date, state->hour, state->minute}) {
        SendMessageW(child, WM_SETFONT,
                     reinterpret_cast<WPARAM>(state->numeric_font), TRUE);
      }
      for (HWND button : {state->clear_button, state->cancel_button,
                          state->ok_button, state->date_surface,
                          state->hour_surface, state->minute_surface}) {
        SendMessageW(button, WM_SETFONT,
                     reinterpret_cast<WPARAM>(
                         button == state->date_surface ||
                                 button == state->hour_surface ||
                                 button == state->minute_surface
                             ? state->numeric_font
                             : state->button_font),
                     TRUE);
        SetWindowSubclass(button, DateTimePickerButtonSubclassProc, 1,
                          reinterpret_cast<DWORD_PTR>(state));
      }
      DateTime_SetSystemtime(state->date, GDT_VALID, &state->initial);
      SendMessageW(state->hour, CB_SETCURSEL, state->initial.wHour, 0);
      SendMessageW(state->minute, CB_SETCURSEL, state->initial.wMinute, 0);
      SetWindowRgn(window,
                   CreateRoundRectRgn(0, 0, scaled(354) + 1,
                                      scaled(242) + 1, scaled(24), scaled(24)),
                   TRUE);
      const BOOL dark_mode = state->dark ? TRUE : FALSE;
      DwmSetWindowAttribute(window, 20, &dark_mode, sizeof(dark_mode));
      SetFocus(state->date);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC context = BeginPaint(window, &paint);
      RECT bounds = {};
      GetClientRect(window, &bounds);
      const int radius = ScaleForDpi(window, 12);
      const HGDIOBJ old_brush =
          SelectObject(context, state->background_brush);
      const HGDIOBJ old_pen = SelectObject(context, GetStockObject(NULL_PEN));
      RoundRect(context, bounds.left, bounds.top, bounds.right, bounds.bottom,
                radius * 2, radius * 2);
      HPEN border_pen = CreatePen(PS_SOLID, 1, state->border);
      SelectObject(context, GetStockObject(NULL_BRUSH));
      SelectObject(context, border_pen);
      RoundRect(context, bounds.left, bounds.top, bounds.right,
                bounds.bottom, radius * 2, radius * 2);
      SetBkMode(context, TRANSPARENT);
      SetTextColor(context, state->text);
      SelectObject(context, state->title_font);
      RECT title_bounds = {ScaleForDpi(window, 17), ScaleForDpi(window, 14),
                           ScaleForDpi(window, 338), ScaleForDpi(window, 39)};
      DrawTextW(context, state->title.c_str(), -1, &title_bounds,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      SetTextColor(context, state->weak_text);
      SelectObject(context, state->body_font);
      RECT message_bounds = {ScaleForDpi(window, 17), ScaleForDpi(window, 45),
                             ScaleForDpi(window, 338),
                             ScaleForDpi(window, 80)};
      DrawTextW(context, state->message.c_str(), -1, &message_bounds,
                DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS);
      SelectObject(context, old_brush);
      SelectObject(context, old_pen);
      DeleteObject(border_pen);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_DRAWITEM: {
      const auto* draw = reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
      if (!draw || draw->CtlType != ODT_BUTTON) break;
      bool hovered = false;
      if (bool* value = DateTimePickerButtonHoverState(
              state, static_cast<int>(draw->CtlID))) {
        hovered = *value;
      }
      if (draw->CtlID == kDatePickerDateSurfaceId ||
          draw->CtlID == kDatePickerHourSurfaceId ||
          draw->CtlID == kDatePickerMinuteSurfaceId) {
        const bool pressed = (draw->itemState & ODS_SELECTED) != 0;
        DrawDateTimePickerInputFrame(
            draw, state, hovered || pressed,
            draw->CtlID != kDatePickerDateSurfaceId);
        SetBkMode(draw->hDC, TRANSPARENT);
        SetTextColor(draw->hDC, state->text);
        SelectObject(draw->hDC, state->numeric_font);
        if (draw->CtlID == kDatePickerDateSurfaceId) {
          SYSTEMTIME date = state->initial;
          DateTime_GetSystemtime(state->date, &date);
          const std::wstring label = DateTimePickerDateLabel(date);
          if (!state->dark) {
            RECT editor_surface = {
                draw->rcItem.left + ScaleForDpi(state->dialog, 8),
                draw->rcItem.top + ScaleForDpi(state->dialog, 5),
                draw->rcItem.right - ScaleForDpi(state->dialog, 34),
                draw->rcItem.bottom - ScaleForDpi(state->dialog, 5)};
            HBRUSH editor_brush = CreateSolidBrush(RGB(255, 255, 255));
            FillRect(draw->hDC, &editor_surface, editor_brush);
            DeleteObject(editor_brush);
          }
          RECT text_bounds = draw->rcItem;
          text_bounds.left += ScaleForDpi(state->dialog, 10);
          text_bounds.right -= ScaleForDpi(state->dialog, 34);
          text_bounds.top -= ScaleForDpi(state->dialog, 1);
          text_bounds.bottom -= ScaleForDpi(state->dialog, 1);
          if (state->date_text_selected) {
            RECT selection = text_bounds;
            selection.right = selection.left;
            DrawTextW(draw->hDC, label.c_str(), -1, &selection,
                      DT_LEFT | DT_SINGLELINE | DT_CALCRECT);
            selection.right = std::min(text_bounds.right, selection.right);
            selection.top = draw->rcItem.top + ScaleForDpi(state->dialog, 5);
            selection.bottom =
                draw->rcItem.bottom - ScaleForDpi(state->dialog, 7);
            const COLORREF selection_base =
                state->dark ? state->input_background : RGB(255, 255, 255);
            HBRUSH selection_brush = CreateSolidBrush(
                state->dark
                    ? BlendColor(selection_base, GetSysColor(COLOR_HIGHLIGHT),
                                 88)
                    : RGB(153, 201, 238));
            FillRect(draw->hDC, &selection, selection_brush);
            DeleteObject(selection_brush);
          }
          DrawTextW(draw->hDC, label.c_str(), -1, &text_bounds,
                    DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
          DrawDateTimePickerCalendarIcon(draw->hDC, draw->rcItem, state);
        } else {
          const HWND combo = draw->CtlID == kDatePickerHourSurfaceId
                                 ? state->hour
                                 : state->minute;
          wchar_t label[8] = {};
          const LRESULT selected = SendMessageW(combo, CB_GETCURSEL, 0, 0);
          if (selected != CB_ERR) {
            SendMessageW(combo, CB_GETLBTEXT, selected,
                         reinterpret_cast<LPARAM>(label));
          }
          RECT text_bounds = draw->rcItem;
          text_bounds.right -= ScaleForDpi(state->dialog, 18);
          OffsetRect(&text_bounds, 0, -ScaleForDpi(state->dialog, 3));
          const int old_numeric_character_extra =
              SetTextCharacterExtra(draw->hDC,
                                    ScaleForDpi(state->dialog, 1));
          DrawTextW(draw->hDC, label, -1, &text_bounds,
                    DT_CENTER | DT_VCENTER | DT_SINGLELINE);
          SetTextCharacterExtra(draw->hDC, old_numeric_character_extra);
          DrawDateTimePickerDropChevron(draw->hDC, draw->rcItem, state);
        }
        return TRUE;
      }
      const bool primary = draw->CtlID == kDatePickerOkId;
      const bool pressed = (draw->itemState & ODS_SELECTED) != 0;
      COLORREF button_background = primary
                                       ? state->accent
                                       : state->secondary_button_background;
      if (hovered) {
        button_background =
            primary ? BlendColor(state->accent, state->primary_text, 28)
                    : BlendColor(state->background, state->accent, 30);
      }
      if (pressed) {
        button_background =
            BlendColor(button_background, state->text, 28);
      }
      HBRUSH brush = CreateSolidBrush(button_background);
      const HGDIOBJ old_brush = SelectObject(draw->hDC, brush);
      const HGDIOBJ old_pen =
          SelectObject(draw->hDC, GetStockObject(NULL_PEN));
      FillRect(draw->hDC, &draw->rcItem, brush);
      SetBkMode(draw->hDC, TRANSPARENT);
      SetTextColor(draw->hDC,
                   primary ? state->primary_text : state->text);
      SelectObject(draw->hDC, state->button_font);
      wchar_t label[128] = {};
      GetWindowTextW(draw->hwndItem, label, 128);
      RECT text_bounds = draw->rcItem;
      OffsetRect(&text_bounds, 0, ScaleForDpi(state->dialog, 1));
      DrawTextW(draw->hDC, label, -1, &text_bounds,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      if ((draw->itemState & ODS_FOCUS) != 0) {
        RECT focus_bounds = draw->rcItem;
        InflateRect(&focus_bounds, -ScaleForDpi(draw->hwndItem, 4),
                    -ScaleForDpi(draw->hwndItem, 4));
        DrawFocusRect(draw->hDC, &focus_bounds);
      }
      SelectObject(draw->hDC, old_brush);
      SelectObject(draw->hDC, old_pen);
      DeleteObject(brush);
      return TRUE;
    }
    case WM_CTLCOLORLISTBOX:
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORSTATIC: {
      HDC context = reinterpret_cast<HDC>(wparam);
      SetTextColor(context, state->text);
      SetBkColor(context, state->input_background);
      return reinterpret_cast<LRESULT>(state->input_background_brush);
    }
    case WM_NOTIFY: {
      const auto* notification = reinterpret_cast<NMHDR*>(lparam);
      if (notification && notification->hwndFrom == state->date) {
        if (notification->code == DTN_DROPDOWN) {
          state->date_text_selected = true;
        } else if (notification->code == DTN_CLOSEUP) {
          state->date_text_selected = false;
        }
        if (notification->code == DTN_DROPDOWN ||
            notification->code == DTN_CLOSEUP ||
            notification->code == DTN_DATETIMECHANGE) {
          InvalidateRect(state->date_surface, nullptr, TRUE);
        }
      }
      break;
    }
    case WM_COMMAND: {
      const int command = LOWORD(wparam);
      const int notification = HIWORD(wparam);
      if (command == kDatePickerDateSurfaceId && notification == BN_CLICKED) {
        state->date_text_selected = true;
        InvalidateRect(state->date_surface, nullptr, TRUE);
        SetFocus(state->date);
        PostMessageW(state->date, WM_KEYDOWN, VK_F4, 0);
        return 0;
      }
      if (command == kDatePickerHourSurfaceId && notification == BN_CLICKED) {
        SetFocus(state->hour);
        SendMessageW(state->hour, CB_SHOWDROPDOWN, TRUE, 0);
        return 0;
      }
      if (command == kDatePickerMinuteSurfaceId && notification == BN_CLICKED) {
        SetFocus(state->minute);
        SendMessageW(state->minute, CB_SHOWDROPDOWN, TRUE, 0);
        return 0;
      }
      if (command == kDatePickerHourId && notification == CBN_SELCHANGE) {
        InvalidateRect(state->hour_surface, nullptr, TRUE);
        return 0;
      }
      if (command == kDatePickerMinuteId && notification == CBN_SELCHANGE) {
        InvalidateRect(state->minute_surface, nullptr, TRUE);
        return 0;
      }
      if (command == kDatePickerCancelId) {
        DestroyWindow(window);
        return 0;
      }
      if (command == kDatePickerClearId) {
        state->clear = true;
        state->accepted = true;
        DestroyWindow(window);
        return 0;
      }
      if (command == kDatePickerOkId) {
        SYSTEMTIME date = {};
        const LRESULT hour = SendMessageW(state->hour, CB_GETCURSEL, 0, 0);
        const LRESULT minute =
            SendMessageW(state->minute, CB_GETCURSEL, 0, 0);
        if (DateTime_GetSystemtime(state->date, &date) == GDT_VALID &&
            hour != CB_ERR && minute != CB_ERR) {
          state->selected = date;
          state->selected.wHour = static_cast<WORD>(hour);
          state->selected.wMinute = static_cast<WORD>(minute);
          state->selected.wSecond = 0;
          state->accepted = true;
        }
        DestroyWindow(window);
        return 0;
      }
      break;
    }
    case WM_NCHITTEST: {
      const LRESULT hit = DefWindowProcW(window, message, wparam, lparam);
      if (hit == HTCLIENT) {
        POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ScreenToClient(window, &point);
        if (point.y < ScaleForDpi(window, 43)) return HTCAPTION;
      }
      return hit;
    }
    case WM_CLOSE:
      DestroyWindow(window);
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        DestroyWindow(window);
        return 0;
      }
      if (wparam == VK_RETURN) {
        SendMessageW(window, WM_COMMAND, kDatePickerOkId, 0);
        return 0;
      }
      break;
    case WM_DESTROY:
      if (state->background_brush) DeleteObject(state->background_brush);
      if (state->input_background_brush)
        DeleteObject(state->input_background_brush);
      if (state->title_font) DeleteObject(state->title_font);
      if (state->body_font) DeleteObject(state->body_font);
      if (state->control_font) DeleteObject(state->control_font);
      if (state->numeric_font) DeleteObject(state->numeric_font);
      if (state->button_font) DeleteObject(state->button_font);
      state->background_brush = nullptr;
      state->input_background_brush = nullptr;
      state->title_font = nullptr;
      state->body_font = nullptr;
      state->control_font = nullptr;
      state->numeric_font = nullptr;
      state->button_font = nullptr;
      return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

std::optional<flutter::EncodableMap> ShowNativeDateTimePicker(
    HWND owner, const flutter::EncodableMap& arguments) {
  INITCOMMONCONTROLSEX controls = {sizeof(controls), ICC_DATE_CLASSES};
  InitCommonControlsEx(&controls);
  static bool registered = false;
  if (!registered) {
    WNDCLASSW klass = {};
    klass.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
    klass.lpfnWndProc = DateTimePickerWindowProc;
    klass.hInstance = GetModuleHandleW(nullptr);
    klass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    klass.hbrBackground = nullptr;
    klass.lpszClassName = kDatePickerClass;
    registered = RegisterClassW(&klass) != 0 || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
  }
  if (!registered) return std::nullopt;

  DateTimePickerDialogState state;
  state.initial.wYear = static_cast<WORD>(std::clamp<int64_t>(IntegerValue(arguments, "year", 2026), 1601, 9999));
  state.initial.wMonth = static_cast<WORD>(std::clamp<int64_t>(IntegerValue(arguments, "month", 1), 1, 12));
  state.initial.wDay = static_cast<WORD>(std::clamp<int64_t>(IntegerValue(arguments, "day", 1), 1, 31));
  state.initial.wHour = static_cast<WORD>(std::clamp<int64_t>(IntegerValue(arguments, "hour", 0), 0, 23));
  state.initial.wMinute = static_cast<WORD>(std::clamp<int64_t>(IntegerValue(arguments, "minute", 0), 0, 59));
  state.open_calendar = BoolValue(arguments, "openCalendar", false);
  const bool chinese = IsChineseUserLocale();
  state.font_family = NativeDialogFontFamily(arguments, chinese);
  state.numeric_font_family = state.font_family == L"Microsoft YaHei UI"
                                  ? L"Segoe UI"
                                  : state.font_family;
  const std::string title = StringValue(arguments, "title", "");
  const std::string picker_message = StringValue(arguments, "message", "");
  const std::string clear_label = StringValue(arguments, "clearLabel", "");
  const std::string cancel_label = StringValue(arguments, "cancelLabel", "");
  const std::string ok_label = StringValue(arguments, "okLabel", "");
  state.title =
      title.empty()
          ? (chinese ? L"\u8BBE\u7F6E\u65F6\u95F4\u8282\u70B9" : L"Set time")
          : Utf8WindowTitle(title);
  state.message =
      picker_message.empty()
          ? (chinese ? L"\u9009\u62E9\u8FD9\u4E2A\u5F85\u529E\u4E8B\u9879\u7684\u672C\u5730\u65E5\u671F\u548C\u65F6\u95F4\u3002"
                     : L"Choose the local date and time for this todo item.")
          : Utf8WindowTitle(picker_message);
  state.clear_label = clear_label.empty()
                          ? (chinese ? L"\u6E05\u9664" : L"Clear")
                          : Utf8WindowTitle(clear_label);
  state.cancel_label = cancel_label.empty()
                           ? (chinese ? L"\u53D6\u6D88" : L"Cancel")
                           : Utf8WindowTitle(cancel_label);
  state.ok_label = ok_label.empty()
                       ? (chinese ? L"\u786E\u5B9A" : L"OK")
                       : Utf8WindowTitle(ok_label);
  state.background = ColorRefFromArgb(
      IntegerValue(arguments, "backgroundColor", 0xFFFFF9EA),
      RGB(255, 249, 234));
  state.border = ColorRefFromArgb(
      IntegerValue(arguments, "borderColor", 0xFFE0CEA7),
      RGB(224, 206, 167));
  state.accent = ColorRefFromArgb(
      IntegerValue(arguments, "accentColor", 0xFF8C7350),
      RGB(140, 115, 80));
  state.primary_text = ColorRefFromArgb(
      IntegerValue(arguments, "primaryTextColor", 0xFFFFFFFF),
      RGB(255, 255, 255));
  state.text = ColorRefFromArgb(
      IntegerValue(arguments, "textColor", 0xFF33291E), RGB(51, 41, 30));
  state.weak_text = ColorRefFromArgb(
      IntegerValue(arguments, "weakTextColor", 0xFF8A7A63),
      RGB(138, 122, 99));
  state.dark = IsDarkColor(state.background);
  state.input_background = ColorRefFromArgb(
      IntegerValue(arguments, "inputBackgroundColor", 0xFFF9F1E1),
      RGB(249, 241, 225));
  state.secondary_button_background = ColorRefFromArgb(
      IntegerValue(arguments, "secondaryButtonColor", 0xFFEEE6D3),
      RGB(238, 230, 211));
  RECT owner_bounds = {};
  if (!owner || !GetWindowRect(owner, &owner_bounds)) {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &owner_bounds, 0);
  }
  const UINT dpi = owner ? GetDpiForWindow(owner) : 96;
  const int dialog_width = MulDiv(354, static_cast<int>(dpi), 96);
  const int dialog_height = MulDiv(242, static_cast<int>(dpi), 96);
  int left = owner_bounds.left +
             ((owner_bounds.right - owner_bounds.left - dialog_width) / 2);
  int top = owner_bounds.top +
            ((owner_bounds.bottom - owner_bounds.top - dialog_height) / 2);
  HMONITOR monitor = MonitorFromRect(&owner_bounds, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  if (monitor && GetMonitorInfoW(monitor, &monitor_info)) {
    const int work_left = static_cast<int>(monitor_info.rcWork.left);
    const int work_top = static_cast<int>(monitor_info.rcWork.top);
    const int work_right = static_cast<int>(monitor_info.rcWork.right);
    const int work_bottom = static_cast<int>(monitor_info.rcWork.bottom);
    left = std::clamp(left, work_left,
                      std::max(work_left, work_right - dialog_width));
    top = std::clamp(top, work_top,
                     std::max(work_top, work_bottom - dialog_height));
  }
  HWND dialog = CreateWindowExW(
      WS_EX_TOOLWINDOW, kDatePickerClass, state.title.c_str(),
      WS_POPUP | WS_CLIPCHILDREN, left, top, dialog_width, dialog_height, owner,
      nullptr,
      GetModuleHandleW(nullptr), &state);
  if (!dialog) return std::nullopt;
  if (owner) EnableWindow(owner, FALSE);
  ShowWindow(dialog, SW_SHOW);
  UpdateWindow(dialog);
  if (state.open_calendar && state.date) {
    SetFocus(state.date);
    PostMessageW(state.date, WM_KEYDOWN, VK_F4, 0);
  }
  MSG message = {};
  while (IsWindow(dialog) && GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (message.message == WM_KEYDOWN && message.wParam == VK_ESCAPE) {
      SendMessageW(dialog, WM_CLOSE, 0, 0);
      continue;
    }
    if (message.message == WM_KEYDOWN && message.wParam == VK_RETURN) {
      SendMessageW(dialog, WM_COMMAND, kDatePickerOkId, 0);
      continue;
    }
    if (!IsDialogMessageW(dialog, &message)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }
  if (owner) {
    EnableWindow(owner, TRUE);
    SetForegroundWindow(owner);
  }
  if (!state.accepted) return std::nullopt;
  if (state.clear) {
    return flutter::EncodableMap{
        {flutter::EncodableValue("clear"), flutter::EncodableValue(true)}};
  }
  return flutter::EncodableMap{
      {flutter::EncodableValue("year"), flutter::EncodableValue(static_cast<int32_t>(state.selected.wYear))},
      {flutter::EncodableValue("month"), flutter::EncodableValue(static_cast<int32_t>(state.selected.wMonth))},
      {flutter::EncodableValue("day"), flutter::EncodableValue(static_cast<int32_t>(state.selected.wDay))},
      {flutter::EncodableValue("hour"), flutter::EncodableValue(static_cast<int32_t>(state.selected.wHour))},
      {flutter::EncodableValue("minute"), flutter::EncodableValue(static_cast<int32_t>(state.selected.wMinute))},
  };
}

struct ReminderIntervalDialogState {
  HWND dialog = nullptr;
  HWND value = nullptr;
  HWND unit = nullptr;
  HWND unit_surface = nullptr;
  HWND cancel_button = nullptr;
  HWND global_button = nullptr;
  HWND ok_button = nullptr;
  int initial_value = 10;
  int selected_value = 10;
  int initial_unit_index = 0;
  int selected_unit_index = 0;
  std::wstring title;
  std::wstring message;
  std::wstring minutes_label;
  std::wstring hours_label;
  std::wstring global_label;
  std::wstring cancel_label;
  std::wstring ok_label;
  std::wstring font_family = L"Segoe UI";
  std::wstring numeric_font_family = L"Segoe UI";
  COLORREF background = RGB(255, 249, 234);
  COLORREF border = RGB(224, 206, 167);
  COLORREF accent = RGB(140, 115, 80);
  COLORREF primary_text = RGB(255, 255, 255);
  COLORREF text = RGB(51, 41, 30);
  COLORREF weak_text = RGB(138, 122, 99);
  COLORREF input_background = RGB(249, 241, 225);
  COLORREF secondary_button_background = RGB(238, 230, 211);
  HBRUSH background_brush = nullptr;
  HBRUSH input_background_brush = nullptr;
  HFONT title_font = nullptr;
  HFONT body_font = nullptr;
  HFONT control_font = nullptr;
  HFONT numeric_font = nullptr;
  HFONT button_font = nullptr;
  bool dark = false;
  bool value_focused = false;
  bool unit_hovered = false;
  bool cancel_hovered = false;
  bool global_hovered = false;
  bool ok_hovered = false;
  bool accepted = false;
  bool clear = false;
};

constexpr int kReminderIntervalValueId = 1101;
constexpr int kReminderIntervalUnitId = 1102;
constexpr int kReminderIntervalCancelId = 1103;
constexpr int kReminderIntervalGlobalId = 1104;
constexpr int kReminderIntervalOkId = 1105;
constexpr int kReminderIntervalUnitSurfaceId = 1106;
constexpr wchar_t kReminderIntervalClass[] =
    L"RePaperTodo.ReminderIntervalPicker";

bool* ReminderIntervalButtonHoverState(ReminderIntervalDialogState* state,
                                       int control_id) {
  if (!state) return nullptr;
  switch (control_id) {
    case kReminderIntervalUnitSurfaceId:
      return &state->unit_hovered;
    case kReminderIntervalCancelId:
      return &state->cancel_hovered;
    case kReminderIntervalGlobalId:
      return &state->global_hovered;
    case kReminderIntervalOkId:
      return &state->ok_hovered;
    default:
      return nullptr;
  }
}

LRESULT CALLBACK ReminderIntervalButtonSubclassProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference_data) noexcept {
  auto* state =
      reinterpret_cast<ReminderIntervalDialogState*>(reference_data);
  bool* hovered =
      ReminderIntervalButtonHoverState(state, GetDlgCtrlID(window));
  switch (message) {
    case WM_MOUSEMOVE: {
      if (hovered && !*hovered) {
        *hovered = true;
        TRACKMOUSEEVENT tracking = {};
        tracking.cbSize = sizeof(tracking);
        tracking.dwFlags = TME_LEAVE;
        tracking.hwndTrack = window;
        TrackMouseEvent(&tracking);
        InvalidateRect(window, nullptr, TRUE);
      }
      break;
    }
    case WM_MOUSELEAVE:
      if (hovered && *hovered) {
        *hovered = false;
        InvalidateRect(window, nullptr, TRUE);
      }
      break;
    case WM_SETFOCUS:
    case WM_KILLFOCUS:
      InvalidateRect(window, nullptr, TRUE);
      break;
    case WM_NCDESTROY:
      RemoveWindowSubclass(window, ReminderIntervalButtonSubclassProc,
                           subclass_id);
      break;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

LRESULT CALLBACK ReminderIntervalValueSubclassProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference_data) noexcept {
  auto* state = reinterpret_cast<ReminderIntervalDialogState*>(reference_data);
  if (!state) {
    return DefSubclassProc(window, message, wparam, lparam);
  }
  if (message == WM_PAINT && !state->dark && state->value_focused) {
    DWORD selection_start = 0;
    DWORD selection_end = 0;
    SendMessageW(window, EM_GETSEL,
                 reinterpret_cast<WPARAM>(&selection_start),
                 reinterpret_cast<LPARAM>(&selection_end));
    const int text_length = GetWindowTextLengthW(window);
    if (text_length > 0 && selection_start == 0 &&
        selection_end == static_cast<DWORD>(text_length)) {
      PAINTSTRUCT paint = {};
      HDC context = BeginPaint(window, &paint);
      RECT bounds = {};
      GetClientRect(window, &bounds);
      FillRect(context, &bounds, state->input_background_brush);
      wchar_t label[16] = {};
      GetWindowTextW(window, label, static_cast<int>(std::size(label)));
      const HGDIOBJ old_font = SelectObject(context, state->numeric_font);
      SIZE text_size = {};
      GetTextExtentPoint32W(context, label, text_length, &text_size);
      RECT selection = {
          (bounds.right - text_size.cx) / 2, bounds.top,
          (bounds.right + text_size.cx) / 2,
          bounds.top + ScaleForDpi(state->dialog, 17)};
      HBRUSH selection_brush = CreateSolidBrush(RGB(149, 193, 220));
      FillRect(context, &selection, selection_brush);
      DeleteObject(selection_brush);
      SetBkMode(context, TRANSPARENT);
      SetTextColor(context, RGB(31, 73, 103));
      DrawTextW(context, label, text_length, &bounds,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
      SelectObject(context, old_font);
      EndPaint(window, &paint);
      return 0;
    }
  }
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, ReminderIntervalValueSubclassProc,
                         subclass_id);
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

LRESULT CALLBACK ReminderIntervalWindowProc(HWND window, UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam) noexcept {
  auto* state = reinterpret_cast<ReminderIntervalDialogState*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    state = create
                ? static_cast<ReminderIntervalDialogState*>(
                      create->lpCreateParams)
                : nullptr;
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(state));
    if (state) state->dialog = window;
  }
  if (!state) return DefWindowProcW(window, message, wparam, lparam);

  switch (message) {
    case WM_CREATE: {
      const auto scaled = [window](int value) {
        return ScaleForDpi(window, value);
      };
      state->background_brush = CreateSolidBrush(state->background);
      state->input_background_brush =
          CreateSolidBrush(state->input_background);
      state->title_font = CreateFontW(
          -scaled(14), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());
      state->body_font = CreateFontW(
          -scaled(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());
      state->control_font = CreateFontW(
          -scaled(13), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());
      state->numeric_font = CreateFontW(
          -scaled(13), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->numeric_font_family.c_str());
      state->button_font = CreateFontW(
          -scaled(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          ANTIALIASED_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
          state->font_family.c_str());

      state->value = CreateWindowExW(
          0, L"EDIT", L"",
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_CENTER |
              ES_NUMBER | ES_AUTOHSCROLL,
          scaled(18), scaled(88), scaled(170), scaled(21), window,
          reinterpret_cast<HMENU>(
              static_cast<INT_PTR>(kReminderIntervalValueId)),
          GetModuleHandleW(nullptr), nullptr);
      state->unit = CreateWindowExW(
          0, WC_COMBOBOXW, L"",
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL |
              CBS_DROPDOWNLIST,
          scaled(197), scaled(87), scaled(112), scaled(174), window,
          reinterpret_cast<HMENU>(
              static_cast<INT_PTR>(kReminderIntervalUnitId)),
          GetModuleHandleW(nullptr), nullptr);
      state->unit_surface = CreateWindowW(
          L"BUTTON", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
          scaled(197), scaled(87), scaled(112), scaled(27), window,
          reinterpret_cast<HMENU>(
              static_cast<INT_PTR>(kReminderIntervalUnitSurfaceId)),
          GetModuleHandleW(nullptr), nullptr);
      state->cancel_button = CreateWindowW(
          L"BUTTON", state->cancel_label.c_str(),
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW, scaled(105),
          scaled(126), scaled(64), scaled(26), window,
          reinterpret_cast<HMENU>(
              static_cast<INT_PTR>(kReminderIntervalCancelId)),
          GetModuleHandleW(nullptr), nullptr);
      state->global_button = CreateWindowW(
          L"BUTTON", state->global_label.c_str(),
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW, scaled(175),
          scaled(126), scaled(64), scaled(26), window,
          reinterpret_cast<HMENU>(
              static_cast<INT_PTR>(kReminderIntervalGlobalId)),
          GetModuleHandleW(nullptr), nullptr);
      state->ok_button = CreateWindowW(
          L"BUTTON", state->ok_label.c_str(),
          WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW |
              BS_DEFPUSHBUTTON,
          scaled(245), scaled(126), scaled(64), scaled(26), window,
          reinterpret_cast<HMENU>(
              static_cast<INT_PTR>(kReminderIntervalOkId)),
          GetModuleHandleW(nullptr), nullptr);

      wchar_t initial_value[16] = {};
      swprintf_s(initial_value, L"%d", state->initial_value);
      SetWindowTextW(state->value, initial_value);
      SendMessageW(state->value, EM_SETLIMITTEXT, 3, 0);
      SendMessageW(state->unit, CB_ADDSTRING, 0,
                   reinterpret_cast<LPARAM>(state->minutes_label.c_str()));
      SendMessageW(state->unit, CB_ADDSTRING, 0,
                   reinterpret_cast<LPARAM>(state->hours_label.c_str()));
      SendMessageW(state->unit, CB_SETCURSEL, state->initial_unit_index, 0);

      SendMessageW(state->value, WM_SETFONT,
                   reinterpret_cast<WPARAM>(state->numeric_font), TRUE);
      SetWindowSubclass(state->value, ReminderIntervalValueSubclassProc, 1,
                        reinterpret_cast<DWORD_PTR>(state));
      SendMessageW(state->unit, WM_SETFONT,
                   reinterpret_cast<WPARAM>(state->control_font), TRUE);
      for (HWND button : {state->cancel_button, state->global_button,
                          state->ok_button, state->unit_surface}) {
        SendMessageW(button, WM_SETFONT,
                     reinterpret_cast<WPARAM>(
                         button == state->unit_surface ? state->control_font
                                                       : state->button_font),
                     TRUE);
        SetWindowSubclass(button, ReminderIntervalButtonSubclassProc, 1,
                          reinterpret_cast<DWORD_PTR>(state));
      }

      SetWindowRgn(window,
                   CreateRoundRectRgn(0, 0, scaled(326) + 1,
                                      scaled(216) + 1, scaled(24), scaled(24)),
                   TRUE);
      const BOOL dark_mode = state->dark ? TRUE : FALSE;
      DwmSetWindowAttribute(window, 20, &dark_mode, sizeof(dark_mode));
      SetFocus(state->value);
      state->value_focused = true;
      SendMessageW(state->value, EM_SETSEL, 0, -1);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC context = BeginPaint(window, &paint);
      RECT bounds = {};
      GetClientRect(window, &bounds);
      const int radius = ScaleForDpi(window, 12);
      const HGDIOBJ old_brush =
          SelectObject(context, state->background_brush);
      const HGDIOBJ old_pen = SelectObject(context, GetStockObject(NULL_PEN));
      RoundRect(context, bounds.left, bounds.top, bounds.right, bounds.bottom,
                radius * 2, radius * 2);
      HPEN border_pen = CreatePen(
          PS_SOLID, std::max(1, ScaleForDpi(window, 1)), state->border);
      SelectObject(context, GetStockObject(NULL_BRUSH));
      SelectObject(context, border_pen);
      RoundRect(context, bounds.left, bounds.top, bounds.right,
                bounds.bottom, radius * 2, radius * 2);

      SetBkMode(context, TRANSPARENT);
      SetTextColor(context, state->text);
      SelectObject(context, state->title_font);
      RECT title_bounds = {ScaleForDpi(window, 17), ScaleForDpi(window, 14),
                           ScaleForDpi(window, 310),
                           ScaleForDpi(window, 39)};
      DrawTextW(context, state->title.c_str(), -1, &title_bounds,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                    DT_NOPREFIX);
      SetTextColor(context, state->weak_text);
      SelectObject(context, state->body_font);
      RECT message_bounds = {ScaleForDpi(window, 17), ScaleForDpi(window, 45),
                             ScaleForDpi(window, 310),
                             ScaleForDpi(window, 84)};
      const int second_line_top =
          message_bounds.top + ScaleForDpi(window, 16);
      const int first_line_dc = SaveDC(context);
      IntersectClipRect(context, message_bounds.left, message_bounds.top,
                        message_bounds.right, second_line_top);
      DrawTextW(context, state->message.c_str(), -1, &message_bounds,
                DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS |
                    DT_NOPREFIX);
      RestoreDC(context, first_line_dc);
      const int remaining_lines_dc = SaveDC(context);
      IntersectClipRect(context, message_bounds.left, second_line_top,
                        message_bounds.right, message_bounds.bottom);
      OffsetRect(&message_bounds, 0, -ScaleForDpi(window, 1));
      DrawTextW(context, state->message.c_str(), -1, &message_bounds,
                DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS |
                    DT_NOPREFIX);
      RestoreDC(context, remaining_lines_dc);
      HPEN input_border_pen = CreatePen(
          PS_SOLID, std::max(1, ScaleForDpi(window, 1)),
          state->value_focused
              ? (state->dark ? GetSysColor(COLOR_HIGHLIGHT)
                             : RGB(86, 157, 229))
                               : BlendColor(state->background, state->accent,
                                            80));
      const HGDIOBJ old_input_brush =
          SelectObject(context, GetStockObject(NULL_BRUSH));
      const HGDIOBJ old_input_pen = SelectObject(context, input_border_pen);
      Rectangle(context, ScaleForDpi(window, 17), ScaleForDpi(window, 87),
                ScaleForDpi(window, 189), ScaleForDpi(window, 110));
      SelectObject(context, old_input_brush);
      SelectObject(context, old_input_pen);
      DeleteObject(input_border_pen);
      SelectObject(context, old_brush);
      SelectObject(context, old_pen);
      DeleteObject(border_pen);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_DRAWITEM: {
      const auto* draw = reinterpret_cast<DRAWITEMSTRUCT*>(lparam);
      if (!draw || draw->CtlType != ODT_BUTTON) break;
      bool hovered = false;
      if (bool* value = ReminderIntervalButtonHoverState(
              state, static_cast<int>(draw->CtlID))) {
        hovered = *value;
      }
      if (draw->CtlID == kReminderIntervalUnitSurfaceId) {
        const bool pressed = (draw->itemState & ODS_SELECTED) != 0;
        const bool emphasized = hovered || pressed;
        FillRect(draw->hDC, &draw->rcItem, state->background_brush);
        RECT control_bounds = draw->rcItem;
        control_bounds.bottom =
            std::min(control_bounds.bottom,
                     control_bounds.top + ScaleForDpi(state->dialog, 23));
        const COLORREF background =
            state->dark
                ? (emphasized
                       ? BlendColor(state->input_background, state->accent, 12)
                       : state->input_background)
                : (emphasized ? RGB(244, 244, 244) : RGB(237, 237, 237));
        const COLORREF border =
            state->dark
                ? BlendColor(state->background, state->accent,
                             emphasized ? 108 : 80)
                : (emphasized ? RGB(122, 122, 122) : RGB(172, 172, 172));
        HBRUSH background_brush = CreateSolidBrush(background);
        HPEN border_pen = CreatePen(PS_SOLID, 1, border);
        const HGDIOBJ old_brush =
            SelectObject(draw->hDC, background_brush);
        const HGDIOBJ old_pen = SelectObject(draw->hDC, border_pen);
        if (!state->dark && !emphasized) {
          for (int y = control_bounds.top + 1;
               y < control_bounds.bottom - 1; ++y) {
            const int span = std::max(
                1, static_cast<int>(control_bounds.bottom -
                                    control_bounds.top - 3));
            const int offset = y - control_bounds.top - 1;
            const int shade = 240 - ((11 * offset + span / 2) / span);
            RECT row = {control_bounds.left + 1, y,
                        control_bounds.right - 1, y + 1};
            HBRUSH row_brush =
                CreateSolidBrush(RGB(shade, shade, shade));
            FillRect(draw->hDC, &row, row_brush);
            DeleteObject(row_brush);
          }
        } else {
          RECT interior = control_bounds;
          InflateRect(&interior, -1, -1);
          FillRect(draw->hDC, &interior, background_brush);
        }
        SelectObject(draw->hDC, GetStockObject(NULL_BRUSH));
        Rectangle(draw->hDC, control_bounds.left, control_bounds.top,
                  control_bounds.right, control_bounds.bottom);
        SetBkMode(draw->hDC, TRANSPARENT);
        SetTextColor(draw->hDC, state->text);
        SelectObject(draw->hDC, state->control_font);
        wchar_t label[64] = {};
        const LRESULT selected = SendMessageW(state->unit, CB_GETCURSEL, 0, 0);
        if (selected != CB_ERR) {
          SendMessageW(state->unit, CB_GETLBTEXT, selected,
                       reinterpret_cast<LPARAM>(label));
        }
        RECT text_bounds = control_bounds;
        text_bounds.right -= ScaleForDpi(state->dialog, 18);
        OffsetRect(&text_bounds, ScaleForDpi(state->dialog, 1), 0);
        DrawTextW(draw->hDC, label, -1, &text_bounds,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                      DT_NOPREFIX);
        const int center_x =
            control_bounds.right - ScaleForDpi(state->dialog, 10);
        const int center_y =
            (control_bounds.top + control_bounds.bottom) / 2;
        const COLORREF chevron_color =
            state->dark ? state->weak_text : RGB(102, 102, 102);
        POINT chevron_points[] = {
            {center_x - ScaleForDpi(state->dialog, 2),
             center_y - ScaleForDpi(state->dialog, 3)},
            {center_x + ScaleForDpi(state->dialog, 3),
             center_y - ScaleForDpi(state->dialog, 3)},
            {center_x, center_y + ScaleForDpi(state->dialog, 2)}};
        HBRUSH chevron_brush = CreateSolidBrush(chevron_color);
        SelectObject(draw->hDC, chevron_brush);
        SelectObject(draw->hDC, GetStockObject(NULL_PEN));
        Polygon(draw->hDC, chevron_points,
                static_cast<int>(std::size(chevron_points)));
        SelectObject(draw->hDC, old_brush);
        SelectObject(draw->hDC, old_pen);
        DeleteObject(chevron_brush);
        DeleteObject(background_brush);
        DeleteObject(border_pen);
        return TRUE;
      }
      const bool primary = draw->CtlID == kReminderIntervalOkId;
      const bool pressed = (draw->itemState & ODS_SELECTED) != 0;
      COLORREF button_background = primary
                                       ? state->accent
                                       : state->secondary_button_background;
      if (hovered) {
        button_background =
            primary ? BlendColor(state->accent, state->primary_text, 28)
                    : BlendColor(state->background, state->accent, 30);
      }
      if (pressed) {
        button_background = BlendColor(button_background, state->text, 28);
      }
      HBRUSH brush = CreateSolidBrush(button_background);
      const HGDIOBJ old_brush = SelectObject(draw->hDC, brush);
      const HGDIOBJ old_pen =
          SelectObject(draw->hDC, GetStockObject(NULL_PEN));
      FillRect(draw->hDC, &draw->rcItem, brush);
      SetBkMode(draw->hDC, TRANSPARENT);
      SetTextColor(draw->hDC,
                   primary ? state->primary_text : state->text);
      SelectObject(draw->hDC, state->button_font);
      wchar_t label[128] = {};
      GetWindowTextW(draw->hwndItem, label, 128);
      RECT text_bounds = draw->rcItem;
      OffsetRect(&text_bounds, 0, ScaleForDpi(state->dialog, 1));
      DrawTextW(draw->hDC, label, -1, &text_bounds,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS |
                    DT_NOPREFIX);
      if ((draw->itemState & ODS_FOCUS) != 0) {
        RECT focus_bounds = draw->rcItem;
        InflateRect(&focus_bounds, -ScaleForDpi(draw->hwndItem, 4),
                    -ScaleForDpi(draw->hwndItem, 4));
        DrawFocusRect(draw->hDC, &focus_bounds);
      }
      SelectObject(draw->hDC, old_brush);
      SelectObject(draw->hDC, old_pen);
      DeleteObject(brush);
      return TRUE;
    }
    case WM_CTLCOLORLISTBOX:
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORSTATIC: {
      HDC context = reinterpret_cast<HDC>(wparam);
      SetTextColor(context, state->text);
      SetBkColor(context, state->input_background);
      return reinterpret_cast<LRESULT>(state->input_background_brush);
    }
    case WM_COMMAND: {
      const int command = LOWORD(wparam);
      const int notification = HIWORD(wparam);
      if (command == kReminderIntervalValueId &&
          (notification == EN_SETFOCUS || notification == EN_KILLFOCUS)) {
        state->value_focused = notification == EN_SETFOCUS;
        RECT value_border = {ScaleForDpi(window, 16),
                             ScaleForDpi(window, 86),
                             ScaleForDpi(window, 190),
                             ScaleForDpi(window, 112)};
        InvalidateRect(window, &value_border, TRUE);
      }
      if (command == kReminderIntervalUnitSurfaceId &&
          notification == BN_CLICKED) {
        SetFocus(state->unit);
        SendMessageW(state->unit, CB_SHOWDROPDOWN, TRUE, 0);
        return 0;
      }
      if (command == kReminderIntervalUnitId &&
          notification == CBN_SELCHANGE) {
        InvalidateRect(state->unit_surface, nullptr, TRUE);
        return 0;
      }
      if (command == kReminderIntervalCancelId) {
        DestroyWindow(window);
        return 0;
      }
      if (command == kReminderIntervalGlobalId) {
        state->clear = true;
        state->accepted = true;
        DestroyWindow(window);
        return 0;
      }
      if (command == kReminderIntervalOkId) {
        wchar_t text[16] = {};
        GetWindowTextW(state->value, text, 16);
        wchar_t* end = nullptr;
        const long parsed = wcstol(text, &end, 10);
        state->selected_value = static_cast<int>(std::clamp<long>(
            end != text ? parsed : state->initial_value, 1, 240));
        const LRESULT selected_unit =
            SendMessageW(state->unit, CB_GETCURSEL, 0, 0);
        state->selected_unit_index =
            selected_unit == 1 ? 1 : 0;
        state->accepted = true;
        DestroyWindow(window);
        return 0;
      }
      break;
    }
    case WM_NCHITTEST: {
      const LRESULT hit = DefWindowProcW(window, message, wparam, lparam);
      if (hit == HTCLIENT) {
        POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ScreenToClient(window, &point);
        if (point.y < ScaleForDpi(window, 43)) return HTCAPTION;
      }
      return hit;
    }
    case WM_CLOSE:
      DestroyWindow(window);
      return 0;
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        DestroyWindow(window);
        return 0;
      }
      if (wparam == VK_RETURN) {
        SendMessageW(window, WM_COMMAND, kReminderIntervalOkId, 0);
        return 0;
      }
      break;
    case WM_DESTROY:
      if (state->background_brush) DeleteObject(state->background_brush);
      if (state->input_background_brush)
        DeleteObject(state->input_background_brush);
      if (state->title_font) DeleteObject(state->title_font);
      if (state->body_font) DeleteObject(state->body_font);
      if (state->control_font) DeleteObject(state->control_font);
      if (state->numeric_font) DeleteObject(state->numeric_font);
      if (state->button_font) DeleteObject(state->button_font);
      state->background_brush = nullptr;
      state->input_background_brush = nullptr;
      state->title_font = nullptr;
      state->body_font = nullptr;
      state->control_font = nullptr;
      state->numeric_font = nullptr;
      state->button_font = nullptr;
      return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

std::optional<flutter::EncodableMap> ShowNativeReminderIntervalPicker(
    HWND owner, const flutter::EncodableMap& arguments) {
  static bool registered = false;
  if (!registered) {
    WNDCLASSW klass = {};
    klass.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
    klass.lpfnWndProc = ReminderIntervalWindowProc;
    klass.hInstance = GetModuleHandleW(nullptr);
    klass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    klass.hbrBackground = nullptr;
    klass.lpszClassName = kReminderIntervalClass;
    registered = RegisterClassW(&klass) != 0 ||
                 GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
  }
  if (!registered) return std::nullopt;

  ReminderIntervalDialogState state;
  state.initial_value = static_cast<int>(std::clamp<int64_t>(
      IntegerValue(arguments, "value", 10), 1, 240));
  state.initial_unit_index =
      StringValue(arguments, "unit", "minutes") == "hours" ? 1 : 0;
  state.selected_value = state.initial_value;
  state.selected_unit_index = state.initial_unit_index;
  const bool chinese = IsChineseUserLocale();
  state.font_family = NativeDialogFontFamily(arguments, chinese);
  state.numeric_font_family = state.font_family == L"Microsoft YaHei UI"
                                  ? L"Segoe UI"
                                  : state.font_family;
  const auto localized = [&](const char* key, const wchar_t* fallback_en,
                             const wchar_t* fallback_zh) {
    const std::string value = StringValue(arguments, key, "");
    return value.empty() ? std::wstring(chinese ? fallback_zh : fallback_en)
                         : Utf8WindowTitle(value);
  };
  state.title = localized("title", L"Reminder interval",
                          L"\u63D0\u9192\u95F4\u9694");
  state.message = localized(
      "message",
      L"Set a custom reminder interval for this todo. It overrides the app "
      L"setting when interval reminder bubbles are enabled.",
      L"\u4E3A\u8FD9\u4E2A\u5F85\u529E\u8BBE\u7F6E\u5355\u72EC\u7684\u63D0\u9192\u95F4\u9694\u3002\u5F00\u542F\u95F4\u9694\u6C14\u6CE1\u63D0\u9192\u65F6\uFF0C\u5B83\u4F1A\u8986\u76D6\u5E94\u7528\u8BBE\u7F6E\u3002");
  state.global_label = localized("globalLabel", L"Global", L"\u5168\u5C40");
  state.cancel_label =
      localized("cancelLabel", L"Cancel", L"\u53D6\u6D88");
  state.ok_label = localized("okLabel", L"OK", L"\u786E\u5B9A");
  state.minutes_label =
      localized("minutesLabel", L"Minutes", L"\u5206\u949F");
  state.hours_label =
      localized("hoursLabel", L"Hours", L"\u5C0F\u65F6");
  state.background = ColorRefFromArgb(
      IntegerValue(arguments, "backgroundColor", 0xFFFFF9EA),
      RGB(255, 249, 234));
  state.border = ColorRefFromArgb(
      IntegerValue(arguments, "borderColor", 0xFFE0CEA7),
      RGB(224, 206, 167));
  state.accent = ColorRefFromArgb(
      IntegerValue(arguments, "accentColor", 0xFF8C7350),
      RGB(140, 115, 80));
  state.primary_text = ColorRefFromArgb(
      IntegerValue(arguments, "primaryTextColor", 0xFFFFFFFF),
      RGB(255, 255, 255));
  state.text = ColorRefFromArgb(
      IntegerValue(arguments, "textColor", 0xFF33291E), RGB(51, 41, 30));
  state.weak_text = ColorRefFromArgb(
      IntegerValue(arguments, "weakTextColor", 0xFF8A7A63),
      RGB(138, 122, 99));
  state.dark = IsDarkColor(state.background);
  state.input_background = ColorRefFromArgb(
      IntegerValue(arguments, "inputBackgroundColor", 0xFFF9F1E1),
      RGB(249, 241, 225));
  state.secondary_button_background = ColorRefFromArgb(
      IntegerValue(arguments, "secondaryButtonColor", 0xFFEEE6D3),
      RGB(238, 230, 211));

  RECT owner_bounds = {};
  if (!owner || !GetWindowRect(owner, &owner_bounds)) {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &owner_bounds, 0);
  }
  const UINT dpi = owner ? GetDpiForWindow(owner) : 96;
  const int dialog_width = MulDiv(326, static_cast<int>(dpi), 96);
  const int dialog_height = MulDiv(216, static_cast<int>(dpi), 96);
  int left = owner_bounds.left +
             ((owner_bounds.right - owner_bounds.left - dialog_width) / 2);
  int top = owner_bounds.top +
            ((owner_bounds.bottom - owner_bounds.top - dialog_height) / 2);
  HMONITOR monitor = MonitorFromRect(&owner_bounds, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  if (monitor && GetMonitorInfoW(monitor, &monitor_info)) {
    const int work_left = static_cast<int>(monitor_info.rcWork.left);
    const int work_top = static_cast<int>(monitor_info.rcWork.top);
    const int work_right = static_cast<int>(monitor_info.rcWork.right);
    const int work_bottom = static_cast<int>(monitor_info.rcWork.bottom);
    left = std::clamp(left, work_left,
                      std::max(work_left, work_right - dialog_width));
    top = std::clamp(top, work_top,
                     std::max(work_top, work_bottom - dialog_height));
  }

  HWND dialog = CreateWindowExW(
      WS_EX_TOOLWINDOW, kReminderIntervalClass, state.title.c_str(),
      WS_POPUP | WS_CLIPCHILDREN, left, top, dialog_width, dialog_height,
      owner, nullptr, GetModuleHandleW(nullptr), &state);
  if (!dialog) return std::nullopt;
  if (owner) EnableWindow(owner, FALSE);
  ShowWindow(dialog, SW_SHOW);
  UpdateWindow(dialog);
  MSG message = {};
  while (IsWindow(dialog) && GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (message.message == WM_KEYDOWN && message.wParam == VK_ESCAPE) {
      SendMessageW(dialog, WM_CLOSE, 0, 0);
      continue;
    }
    if (message.message == WM_KEYDOWN && message.wParam == VK_RETURN) {
      SendMessageW(dialog, WM_COMMAND, kReminderIntervalOkId, 0);
      continue;
    }
    if (!IsDialogMessageW(dialog, &message)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }
  if (owner) {
    EnableWindow(owner, TRUE);
    SetForegroundWindow(owner);
  }
  if (!state.accepted) return std::nullopt;
  if (state.clear) {
    return flutter::EncodableMap{
        {flutter::EncodableValue("clear"), flutter::EncodableValue(true)}};
  }
  return flutter::EncodableMap{
      {flutter::EncodableValue("value"),
       flutter::EncodableValue(static_cast<int32_t>(state.selected_value))},
      {flutter::EncodableValue("unit"),
       flutter::EncodableValue(state.selected_unit_index == 1 ? "hours"
                                                               : "minutes")},
  };
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
        if (call.method_name() == "pickDateTime") {
          if (call.arguments()) {
            if (const auto* arguments =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              const auto picked =
                  ShowNativeDateTimePicker(GetHandle(), *arguments);
              if (picked.has_value()) {
                result->Success(flutter::EncodableValue(*picked));
              } else {
                result->Success();
              }
              return;
            }
          }
          result->Success();
          return;
        }
        if (call.method_name() == "pickReminderInterval") {
          if (call.arguments()) {
            if (const auto* arguments =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              const auto picked =
                  ShowNativeReminderIntervalPicker(GetHandle(), *arguments);
              if (picked.has_value()) {
                result->Success(flutter::EncodableValue(*picked));
              } else {
                result->Success();
              }
              return;
            }
          }
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
            auto* deferred =
                new flutter::EncodableValue(*call.arguments());
            if (!GetHandle() ||
                !PostMessageW(GetHandle(), kDeferredPaperActionMessage, 0,
                              reinterpret_cast<LPARAM>(deferred))) {
              delete deferred;
            }
          }
          result->Success();
          return;
        }
        if (call.method_name() == "startDrag") {
          if (!pinned_to_desktop_) {
            if (HWND window = GetHandle()) {
              POINT cursor = {};
              GetCursorPos(&cursor);
              ReleaseCapture();
              SendMessageW(window, WM_SYSCOMMAND, SC_MOVE | HTCAPTION,
                           MAKELPARAM(cursor.x, cursor.y));
            }
          }
          result->Success();
          return;
        }
        if (call.method_name() == "capsuleHoverChanged") {
          if (call.arguments()) {
            if (const auto* hovered =
                    std::get_if<bool>(call.arguments())) {
              SetCapsuleHovered(*hovered);
            }
          }
          result->Success();
          return;
        }
        if (call.method_name() == "showReminder") {
          if (call.arguments()) {
            if (const auto* reminder =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              if (BoolValue(*reminder, "visible", true)) {
                ShowReminderBubble(*reminder);
              } else {
                HideReminderBubble();
              }
            }
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
              SetPropW(window, L"RePaperTodo.ResizeHitTest",
                       reinterpret_cast<HANDLE>(
                           static_cast<INT_PTR>(hit_test)));
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
  if (HWND window = GetHandle()) {
    KillTimer(window, kCapsuleSlideTimerId);
    KillTimer(window, kCapsuleQueueFollowTimerId);
    KillTimer(window, kCapsuleMasterTransitionTimerId);
  }
  capsule_animation_active_ = false;
  queue_drag_animation_active_ = false;
  master_capsule_transition_active_ = false;
  paper_shadow_refresh_pending_ = false;
  DestroyPaperShadowWindow();
  HideReminderBubble();
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
    case WM_ERASEBKGND:
      // The embedded Flutter view paints the complete client area. Erasing
      // the parent first exposes a black frame while Windows stretches the
      // surface during interactive resize.
      return 1;
    case WM_TIMER:
      if (wparam == kCapsuleSlideTimerId) {
        UpdateCapsuleDockAnimation();
        return 0;
      }
      if (wparam == kCapsuleQueueFollowTimerId) {
        UpdateQueueDragAnimation();
        return 0;
      }
      if (wparam == kCapsuleMasterTransitionTimerId) {
        UpdateMasterCapsuleTransition();
        return 0;
      }
      break;
    case kDeferredPaperActionMessage: {
      std::unique_ptr<flutter::EncodableValue> arguments(
          reinterpret_cast<flutter::EncodableValue*>(lparam));
      if (arguments) {
        SendEvent("paperActionRequested", *arguments);
      }
      return 0;
    }
    case kDeferredPaperShadowRefreshMessage:
      if (paper_shadow_refresh_pending_ && !in_size_move_) {
        paper_shadow_refresh_pending_ = false;
        UpdatePaperShadowWindow(true);
      }
      return 0;
    case WM_CLOSE:
      HidePaper();
      SendEvent("closeRequested", flutter::EncodableMap{
                                      {flutter::EncodableValue("paperId"),
                                       flutter::EncodableValue(paper_id_)},
                                  });
      return 0;
    case WM_MOVE:
      if (reminder_bubble_) {
        PlaceReminderBubble();
      }
      if (!in_size_move_) {
        UpdatePaperShadowWindow(false);
      }
      [[fallthrough]];
    case WM_SIZE:
      if (message == WM_SIZE && wparam != SIZE_MINIMIZED && !in_size_move_) {
        UpdatePaperShadowWindow(false);
      }
      if (surface_initialized_ && !collapsed_ && !applying_bounds_ &&
          !in_size_move_ &&
          wparam != SIZE_MINIMIZED) {
        SendBoundsChanged();
      }
      break;
    case WM_ENTERSIZEMOVE:
      in_size_move_ = true;
      paper_shadow_refresh_pending_ = false;
      // The shadow is a separate layered HWND. Rebuilding its DIB for every
      // interactive resize frame exposes a transient black rectangle on
      // Windows 10/11. Keep the paper itself live and restore one freshly
      // rendered shadow after the size/move transaction completes.
      HidePaperShadowWindow();
      break;
    case WM_EXITSIZEMOVE:
      in_size_move_ = false;
      // Wait for Flutter's final resized frame before showing the separate
      // layered shadow again. Showing the shadow immediately can expose it
      // around one stale/black swap-chain frame at pointer release.
      HidePaperShadowWindow();
      paper_shadow_refresh_pending_ = true;
      if (flutter_controller_ && flutter_controller_->engine()) {
        const HWND target_window = window;
        flutter_controller_->engine()->SetNextFrameCallback(
            [target_window]() {
              if (IsWindow(target_window)) {
                PostMessageW(target_window,
                             kDeferredPaperShadowRefreshMessage, 0, 0);
              }
            });
        flutter_controller_->ForceRedraw();
      } else {
        PostMessageW(window, kDeferredPaperShadowRefreshMessage, 0, 0);
      }
      if (surface_initialized_) {
        if (collapsed_ && deep_capsule_mode_) {
          SendCapsuleDropped();
        } else {
          SendBoundsChanged();
        }
      }
      break;
    case WM_WINDOWPOSCHANGED:
      if (!in_size_move_) {
        UpdatePaperShadowWindow(false);
      }
      break;
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      if (info) {
        info->ptMinTrackSize.x = collapsed_
                                     ? std::max(1, static_cast<int>(
                                                       std::round(capsule_width_)))
                                     : ScaleForDpi(window, 220);
        info->ptMinTrackSize.y =
            collapsed_ ? ScaleForDpi(window, 46) : ScaleForDpi(window, 160);
        return 0;
      }
      break;
    }
    case WM_NCCALCSIZE:
      if (wparam == TRUE) {
        return 0;
      }
      break;
    case WM_NCPAINT:
      return 0;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCHITTEST: {
      if (master_capsule_retracted_ ||
          (master_capsule_transition_active_ &&
           master_capsule_transition_target_hidden_)) {
        return HTTRANSPARENT;
      }
      const int resize_hit = ResizeBorderHitTest(lparam);
      if (resize_hit != HTCLIENT) {
        return resize_hit;
      }
      if (collapsed_) {
        RECT bounds = {};
        if (GetWindowRect(window, &bounds)) {
          const int x = GET_X_LPARAM(lparam) - bounds.left;
          const int y = GET_Y_LPARAM(lparam) - bounds.top;
          const int chrome = ScaleForDpi(window, 8);
          const int drag_width = ScaleForDpi(window, 26);
          const int body_height = ScaleForDpi(window, 30);
          if (x >= chrome && x < chrome + drag_width && y >= chrome &&
              y < chrome + body_height) {
            return HTCAPTION;
          }
        }
      }
      break;
    }
    case WM_MOUSEACTIVATE:
      if (pinned_to_desktop_) {
        return MA_NOACTIVATE;
      }
      break;
  }
  return Win32Window::MessageHandler(window, message, wparam, lparam);
}

void PaperFlutterWindow::ApplyState(const flutter::EncodableValue& state) {
  latest_state_ = state;
  if (const auto* state_map = std::get_if<flutter::EncodableMap>(&state)) {
    const std::string theme = StringValue(*state_map, "theme", "system");
    const bool dark =
        theme == "dark" || (theme != "light" && IsSystemPaperThemeDark());
    if (paper_shadow_dark_ != dark) {
      paper_shadow_dark_ = dark;
      UpdatePaperShadowWindow(true);
    }
  }
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
  const int64_t incoming_generation = IntegerValue(
      surface, "surfaceGeneration", static_cast<int64_t>(-1));
  if (incoming_generation >= 0) {
    if (surface_generation_ >= 0 &&
        incoming_generation < surface_generation_) {
      return;
    }
    surface_generation_ = incoming_generation;
  }
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  const bool previous_intended_visible = intended_visible_;
  intended_visible_ =
      BoolValue(surface, "isVisible", intended_visible_);
  RECT current = {};
  GetWindowRect(window, &current);
  const double x = NumberValue(surface, "x", current.left);
  const double y = NumberValue(surface, "y", current.top);
  const double width = NumberValue(
      surface, "width", std::max<LONG>(1, current.right - current.left));
  const double height = NumberValue(
      surface, "height", std::max<LONG>(1, current.bottom - current.top));
  const UINT target_dpi = DpiForPhysicalPoint(window, x, y);
  const std::string title = StringValue(surface, "title", "RePaperTodo");
  const std::string capsule_title =
      StringValue(surface, "capsuleTitle", title);
  paper_type_ = StringValue(surface, "type", paper_type_);
  script_capsule_ =
      BoolValue(surface, "isScriptCapsule", script_capsule_);
  capsule_font_family_ =
      StringValue(surface, "fontFamily", capsule_font_family_);
  collapsed_ = BoolValue(surface, "isCollapsed", collapsed_);
  const bool was_capsule_hidden_by_master = capsule_hidden_by_master_;
  capsule_hidden_by_master_ =
      BoolValue(surface, "capsuleHiddenByMaster", capsule_hidden_by_master_);
  capsule_master_top_ =
      NumberValue(surface, "capsuleMasterTop", capsule_master_top_);
  capsule_master_top_is_work_area_relative_ = BoolValue(
      surface, "capsuleMasterTopIsWorkAreaRelative",
      capsule_master_top_is_work_area_relative_);
  if (capsule_hidden_by_master_ && !was_capsule_hidden_by_master) {
    // A master toggle can arrive while the pointer is over a child capsule.
    // Clear the transient hover/animation state so revealing the queue starts
    // from the compact resting width instead of flashing its old hover width.
    capsule_hovered_ = false;
    capsule_animation_active_ = false;
    capsule_current_visible_width_ = 0.0;
    KillTimer(window, kCapsuleSlideTimerId);
  }
  deep_capsule_mode_ =
      BoolValue(surface, "useDeepCapsuleMode", deep_capsule_mode_);
  capsule_animations_enabled_ = BoolValue(
      surface, "enableAnimations", capsule_animations_enabled_);
  if (!collapsed_) {
    capsule_hovered_ = false;
    KillTimer(window, kCapsuleSlideTimerId);
    capsule_animation_active_ = false;
    capsule_current_visible_width_ = 0.0;
    capsule_hidden_by_master_ = false;
    master_capsule_retracted_ = false;
    master_capsule_transition_active_ = false;
    master_capsule_transition_initialized_ = false;
    capsule_alpha_ = 255;
    SetLayeredWindowAttributes(window, RGB(1, 2, 3),
                               static_cast<BYTE>(capsule_alpha_),
                               LWA_COLORKEY | LWA_ALPHA);
    KillTimer(window, kCapsuleMasterTransitionTimerId);
  } else if (!intended_visible_ && previous_intended_visible) {
    master_capsule_transition_active_ = false;
    master_capsule_transition_initialized_ = false;
    master_capsule_retracted_ = false;
    capsule_alpha_ = 255;
    SetLayeredWindowAttributes(window, RGB(1, 2, 3),
                               static_cast<BYTE>(capsule_alpha_),
                               LWA_COLORKEY | LWA_ALPHA);
    KillTimer(window, kCapsuleMasterTransitionTimerId);
  }
  hide_when_covered_ =
      BoolValue(surface, "hideWhenCovered", hide_when_covered_);
  hide_when_fullscreen_ =
      BoolValue(surface, "hideWhenFullscreen", hide_when_fullscreen_);
  SetHideFromWindowSwitcher(BoolValue(
      surface, "hideFromWindowSwitcher", hide_from_window_switcher_));
  const double logical_native_width = collapsed_
                                          ? CapsuleWindowWidth(
                                                capsule_title,
                                                deep_capsule_mode_, paper_type_,
                                                script_capsule_,
                                                capsule_font_family_, target_dpi)
                                          : width;
  const double logical_native_height = collapsed_ ? 46.0 : height;
  const double native_width = ScaleLogicalValue(logical_native_width, target_dpi);
  const double native_height =
      ScaleLogicalValue(logical_native_height, target_dpi);
  double native_x = ScaleLogicalValue(x, target_dpi);
  double native_y = ScaleLogicalValue(y, target_dpi);
  if (collapsed_) {
    capsule_monitor_device_name_ =
        StringValue(surface, "capsuleMonitorDeviceName", "");
    const RECT work_area =
        WorkAreaForWindow(window, capsule_monitor_device_name_);
    capsule_side_ = StringValue(surface, "capsuleSide", "right");
    capsule_work_area_ = work_area;
    capsule_width_ = native_width;
    const double logical_resting_visible_width =
        CapsuleRestingVisibleWidth(
            capsule_title, paper_type_, script_capsule_,
            capsule_font_family_, target_dpi, logical_native_width);
    const double logical_hover_visible_width = CapsuleHoverVisibleWidth(
        logical_native_width, logical_resting_visible_width);
    capsule_resting_visible_width_ =
        ScaleLogicalValue(logical_resting_visible_width, target_dpi);
    capsule_hover_visible_width_ =
        ScaleLogicalValue(logical_hover_visible_width, target_dpi);
    const double desired_visible_width =
        deep_capsule_mode_
            ? (capsule_hovered_ ? capsule_hover_visible_width_
                                : capsule_resting_visible_width_)
            : native_width;
    if (!deep_capsule_mode_) {
      KillTimer(window, kCapsuleSlideTimerId);
      capsule_animation_active_ = false;
      capsule_current_visible_width_ = native_width;
    } else if (capsule_current_visible_width_ <= 0.0 ||
               !capsule_animation_active_) {
      capsule_current_visible_width_ = desired_visible_width;
      capsule_animation_target_width_ = desired_visible_width;
    } else {
      capsule_current_visible_width_ = std::clamp(
          capsule_current_visible_width_, 1.0, native_width);
      capsule_animation_target_width_ = desired_visible_width;
    }
    const double visible_width = capsule_current_visible_width_;
    native_x = capsule_side_ == "left"
                   ? static_cast<double>(work_area.left) -
                         (native_width - visible_width)
                   : static_cast<double>(work_area.right) - visible_width;
    const bool top_is_work_area_relative = BoolValue(
        surface, "capsuleTopIsWorkAreaRelative", false);
    const double requested_top = top_is_work_area_relative
                                     ? static_cast<double>(work_area.top) +
                                           ScaleLogicalValue(y, target_dpi)
                                     : ScaleLogicalValue(y, target_dpi);
    native_y = std::clamp(
        requested_top, static_cast<double>(work_area.top),
        std::max(static_cast<double>(work_area.top),
                 static_cast<double>(work_area.bottom) - native_height));
    const int normal_capsule_top = static_cast<int>(std::round(native_y));
    const int master_capsule_top = MasterCapsuleTopPhysical();
    capsule_docked_top_ = normal_capsule_top;
    if (!master_capsule_transition_initialized_) {
      master_capsule_transition_initialized_ = true;
      master_capsule_retracted_ =
          capsule_hidden_by_master_ && intended_visible_;
      master_capsule_transition_active_ = false;
      ApplyMasterCapsuleAlpha(master_capsule_retracted_ ? 0 : 255);
      native_y = master_capsule_retracted_
                     ? static_cast<double>(master_capsule_top)
                     : static_cast<double>(normal_capsule_top);
    } else if ((!master_capsule_transition_active_ &&
                capsule_hidden_by_master_ != master_capsule_retracted_) ||
               (master_capsule_transition_active_ &&
                capsule_hidden_by_master_ !=
                    master_capsule_transition_target_hidden_)) {
      StartMasterCapsuleTransition(
          capsule_hidden_by_master_ ? master_capsule_top : normal_capsule_top,
          capsule_hidden_by_master_,
          capsule_animations_enabled_
              ? std::max(kCapsuleMasterMoveMilliseconds,
                         kCapsuleMasterFadeMilliseconds)
              : 0);
      native_y = capsule_hidden_by_master_
                     ? static_cast<double>(master_capsule_top)
                     : static_cast<double>(normal_capsule_top);
    } else if (master_capsule_transition_active_) {
      master_capsule_transition_target_top_ =
          static_cast<double>(capsule_hidden_by_master_ ? master_capsule_top
                                                         : normal_capsule_top);
      native_y = static_cast<double>(master_capsule_transition_start_top_);
    } else if (master_capsule_retracted_) {
      native_y = static_cast<double>(master_capsule_top);
    }
  }
  // During a master-capsule drag the live HWND position is authoritative.
  // Surface reconciliation can race a mouse-move event, and replaying the
  // saved queue slot here would make the child capsule jump backwards.
  if (!in_size_move_ && !queue_drag_offset_active_ &&
      !master_capsule_transition_active_) {
    const int target_left = static_cast<int>(std::round(native_x));
    const int target_top = static_cast<int>(std::round(native_y));
    const int target_width = std::max(1, static_cast<int>(std::round(native_width)));
    const int target_height = std::max(1, static_cast<int>(std::round(native_height)));
    const bool bounds_changed = current.left != target_left ||
                                current.top != target_top ||
                                current.right - current.left != target_width ||
                                current.bottom - current.top != target_height;
    if (!bounds_changed) {
      surface_initialized_ = true;
    } else if (collapsed_ && queue_drag_animation_active_) {
      // A committed master drag can reconcile the Dart surface while the
      // child capsule is still easing toward the same slot. Retarget the
      // in-flight animation instead of snapping to the final HWND position.
      queue_drag_base_top_ = target_top;
      queue_drag_target_top_ = target_top;
      StartQueueDragAnimation(
          target_top,
          std::max(1, queue_drag_animation_duration_ms_));
    } else {
      applying_bounds_ = true;
      SetWindowPos(window, nullptr, target_left, target_top, target_width,
                   target_height, SWP_NOZORDER | SWP_NOACTIVATE);
      applying_bounds_ = false;
    }
  }
  surface_initialized_ = true;
  const std::wstring window_title = Utf8WindowTitle(title);
  wchar_t existing_title[512] = {};
  const int title_length = GetWindowTextW(
      window, existing_title,
      static_cast<int>(sizeof(existing_title) / sizeof(existing_title[0])));
  if (title_length < 0 ||
      window_title != std::wstring(existing_title, title_length)) {
    SetWindowTextW(window, window_title.c_str());
  }
  // Resolve visibility before the single z-order pass below.  The previous
  // implementation called RefreshZOrder once with the old visibility and
  // once with the new one; a master reveal/pin click could therefore briefly
  // show, hide, and show the same HWND again.
  const auto visibility = surface.find(flutter::EncodableValue("isVisible"));
  if (visibility != surface.end()) {
    if (const auto* visible = std::get_if<bool>(&visibility->second)) {
      intended_visible_ = *visible;
    }
  }
  always_on_top_ = BoolValue(surface, "alwaysOnTop", always_on_top_);
  pinned_to_desktop_ =
      BoolValue(surface, "isPinnedToDesktop", pinned_to_desktop_);
  SetHideFromWindowSwitcher(hide_from_window_switcher_);
  RefreshZOrder();
}

bool PaperFlutterWindow::IsInCapsuleQueue(
    const std::string& monitor_device_name, const std::string& side) const {
  return collapsed_ &&
         capsule_monitor_device_name_ == monitor_device_name &&
         capsule_side_ == (side == "left" ? "left" : "right");
}

void PaperFlutterWindow::ApplyQueueDragOffset(int delta_y) {
  if (!collapsed_) return;
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return;
  if (!queue_drag_offset_active_) {
    queue_drag_offset_active_ = true;
    queue_drag_base_top_ = bounds.top;
  }
  queue_drag_target_top_ = queue_drag_base_top_ + delta_y;
  // The collapsed Flutter HWND follows the same short, retargetable curve as
  // native proxy capsules. Starting from the current frame on every pointer
  // update keeps the queue connected to the master without an abrupt snap.
  StartQueueDragAnimation(queue_drag_target_top_,
                          kCapsuleQueueFollowMilliseconds);
}

void PaperFlutterWindow::FinishQueueDrag(bool commit) {
  if (!queue_drag_offset_active_) return;
  const int target_top = commit ? queue_drag_target_top_
                                : queue_drag_base_top_;
  if (commit) {
    StartQueueDragAnimation(target_top, kCapsuleQueueFollowMilliseconds);
  } else {
    StartQueueDragAnimation(target_top, kCapsuleQueueMoveMilliseconds);
  }
  queue_drag_offset_active_ = false;
}

void PaperFlutterWindow::StartQueueDragAnimation(int target_top,
                                                 int duration_ms) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return;
  queue_drag_target_top_ = target_top;
  if (!capsule_animations_enabled_ || duration_ms <= 0 ||
      std::abs(static_cast<double>(bounds.top - target_top)) < 0.5) {
    KillTimer(window, kCapsuleQueueFollowTimerId);
    queue_drag_animation_active_ = false;
    ApplyQueueDragTop(target_top);
    return;
  }
  queue_drag_animation_start_top_ = static_cast<double>(bounds.top);
  queue_drag_animation_target_top_ = static_cast<double>(target_top);
  queue_drag_animation_started_at_ = GetTickCount64();
  queue_drag_animation_duration_ms_ = duration_ms;
  queue_drag_animation_active_ = true;
  SetTimer(window, kCapsuleQueueFollowTimerId, 16, nullptr);
}

void PaperFlutterWindow::UpdateQueueDragAnimation() {
  if (!queue_drag_animation_active_) return;
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed =
      GetTickCount64() - queue_drag_animation_started_at_;
  const double progress = std::clamp(
      static_cast<double>(elapsed) /
          static_cast<double>(std::max(1, queue_drag_animation_duration_ms_)),
      0.0, 1.0);
  const double inverse = 1.0 - progress;
  const double eased = 1.0 - inverse * inverse * inverse;
  const int top = static_cast<int>(std::lround(
      queue_drag_animation_start_top_ +
      (queue_drag_animation_target_top_ - queue_drag_animation_start_top_) *
          eased));
  ApplyQueueDragTop(top);
  if (progress >= 1.0) {
    queue_drag_animation_active_ = false;
    KillTimer(window, kCapsuleQueueFollowTimerId);
    ApplyQueueDragTop(
        static_cast<int>(std::lround(queue_drag_animation_target_top_)));
  }
}

void PaperFlutterWindow::ApplyQueueDragTop(int top) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds) || bounds.top == top) return;
  applying_bounds_ = true;
  SetWindowPos(window, nullptr, bounds.left, top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER);
  applying_bounds_ = false;
}

void PaperFlutterWindow::SetAlwaysOnTop(bool enabled) {
  always_on_top_ = enabled;
  RefreshZOrder();
}

void PaperFlutterWindow::SetPinnedToDesktop(bool pinned) {
  pinned_to_desktop_ = pinned;
  SetHideFromWindowSwitcher(hide_from_window_switcher_);
  RefreshZOrder();
}

void PaperFlutterWindow::SetPaperTitle(const std::string& title) {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  SetWindowTextW(window, Utf8WindowTitle(title).c_str());
}

void PaperFlutterWindow::SetCapsuleHovered(bool hovered) {
  if (!collapsed_ || !deep_capsule_mode_ || capsule_hovered_ == hovered) {
    return;
  }
  capsule_hovered_ = hovered;
  if (capsule_current_visible_width_ <= 0.0) {
    capsule_current_visible_width_ =
        hovered ? capsule_resting_visible_width_
                : capsule_hover_visible_width_;
  }
  StartCapsuleDockAnimation(
      hovered ? capsule_hover_visible_width_
              : capsule_resting_visible_width_,
      hovered ? kCapsuleSlideOutMilliseconds : kCapsuleSlideInMilliseconds);
}

void PaperFlutterWindow::StartCapsuleDockAnimation(
    double target_visible_width, int duration_ms) {
  HWND window = GetHandle();
  if (!window) return;
  const double target =
      std::clamp(target_visible_width, 1.0, capsule_width_);
  if (!capsule_animations_enabled_ || duration_ms <= 0 ||
      std::abs(capsule_current_visible_width_ - target) < 0.5) {
    KillTimer(window, kCapsuleSlideTimerId);
    capsule_animation_active_ = false;
    capsule_current_visible_width_ = target;
    capsule_animation_target_width_ = target;
    ApplyCapsuleHorizontalPosition();
    return;
  }
  capsule_animation_start_width_ = capsule_current_visible_width_;
  capsule_animation_target_width_ = target;
  capsule_animation_started_at_ = GetTickCount64();
  capsule_animation_duration_ms_ = duration_ms;
  capsule_animation_active_ = true;
  SetTimer(window, kCapsuleSlideTimerId, 16, nullptr);
}

void PaperFlutterWindow::UpdateCapsuleDockAnimation() {
  if (!capsule_animation_active_) return;
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed = GetTickCount64() - capsule_animation_started_at_;
  const double progress = std::clamp(
      static_cast<double>(elapsed) /
          static_cast<double>(std::max(1, capsule_animation_duration_ms_)),
      0.0, 1.0);
  const double inverse = 1.0 - progress;
  const double eased = 1.0 - inverse * inverse * inverse;
  capsule_current_visible_width_ =
      capsule_animation_start_width_ +
      (capsule_animation_target_width_ - capsule_animation_start_width_) *
          eased;
  ApplyCapsuleHorizontalPosition();
  if (progress >= 1.0) {
    capsule_current_visible_width_ = capsule_animation_target_width_;
    capsule_animation_active_ = false;
    KillTimer(window, kCapsuleSlideTimerId);
    ApplyCapsuleHorizontalPosition();
  }
}

void PaperFlutterWindow::ApplyCapsuleHorizontalPosition() {
  HWND window = GetHandle();
  if (!window || !collapsed_ || !deep_capsule_mode_ || in_size_move_ ||
      master_capsule_transition_active_ || master_capsule_retracted_) {
    return;
  }
  RECT current = {};
  if (!GetWindowRect(window, &current)) {
    return;
  }
  const double visible_width = std::clamp(
      capsule_current_visible_width_, 1.0, capsule_width_);
  const double x = capsule_side_ == "left"
                       ? static_cast<double>(capsule_work_area_.left) -
                             (capsule_width_ - visible_width)
                       : static_cast<double>(capsule_work_area_.right) -
                             visible_width;
  applying_bounds_ = true;
  SetWindowPos(window, nullptr, static_cast<int>(std::round(x)), current.top,
               0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER);
  applying_bounds_ = false;
}

int PaperFlutterWindow::DockedCapsuleTopPhysical() const {
  return capsule_docked_top_;
}

int PaperFlutterWindow::MasterCapsuleTopPhysical() const {
  HWND window = const_cast<PaperFlutterWindow*>(this)->GetHandle();
  const UINT dpi = window ? GetDpiForWindow(window) : 96;
  const int height = static_cast<int>(std::round(ScaleLogicalValue(46.0, dpi)));
  const int edge_margin = ScaleForDpi(window, 8);
  const int minimum_top = capsule_work_area_.top + edge_margin;
  const int maximum_top = std::max(
      minimum_top,
      static_cast<int>(capsule_work_area_.bottom) - height - edge_margin);
  const int requested = capsule_master_top_is_work_area_relative_
                            ? capsule_work_area_.top +
                                  static_cast<int>(std::round(
                                      ScaleLogicalValue(capsule_master_top_, dpi)))
                            : static_cast<int>(std::round(
                                  ScaleLogicalValue(capsule_master_top_, dpi)));
  return std::clamp(requested, minimum_top, maximum_top);
}

void PaperFlutterWindow::ApplyMasterCapsuleAlpha(int alpha) {
  capsule_alpha_ = std::clamp(alpha, 0, 255);
  if (HWND window = GetHandle()) {
    SetLayeredWindowAttributes(window, RGB(1, 2, 3),
                               static_cast<BYTE>(capsule_alpha_),
                               LWA_COLORKEY | LWA_ALPHA);
    InvalidateRect(window, nullptr, FALSE);
  }
}

void PaperFlutterWindow::StartMasterCapsuleTransition(int target_top,
                                                      bool target_hidden,
                                                      int duration_ms) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return;

  master_capsule_transition_target_hidden_ = target_hidden;
  master_capsule_transition_start_top_ = static_cast<double>(bounds.top);
  master_capsule_transition_target_top_ = static_cast<double>(target_top);
  master_capsule_transition_start_alpha_ = capsule_alpha_;
  master_capsule_transition_target_alpha_ = target_hidden ? 0 : 255;
  master_capsule_transition_started_at_ = GetTickCount64();
  master_capsule_transition_duration_ms_ = std::max(0, duration_ms);
  master_capsule_transition_active_ = false;

  if (target_hidden) {
    master_capsule_retracted_ = false;
  } else {
    master_capsule_retracted_ = true;
    if (!IsWindowVisible(window) || !z_order_initialized_ ||
        z_order_pinned_ != pinned_to_desktop_ ||
        z_order_topmost_ == pinned_to_desktop_) {
      ShowWindow(window, SW_SHOWNOACTIVATE);
    }
  }

  if (!capsule_animations_enabled_ || duration_ms <= 0 ||
      (std::abs(master_capsule_transition_start_top_ -
                master_capsule_transition_target_top_) < 0.5 &&
       master_capsule_transition_start_alpha_ ==
           master_capsule_transition_target_alpha_)) {
    master_capsule_transition_active_ = false;
    master_capsule_retracted_ = target_hidden;
    ApplyMasterCapsuleAlpha(master_capsule_transition_target_alpha_);
    SetWindowPos(window, nullptr, bounds.left,
                 static_cast<int>(std::lround(master_capsule_transition_target_top_)),
                 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_NOOWNERZORDER);
    KillTimer(window, kCapsuleMasterTransitionTimerId);
    RefreshZOrder();
    return;
  }

  master_capsule_transition_active_ = true;
  SetTimer(window, kCapsuleMasterTransitionTimerId, 16, nullptr);
}

void PaperFlutterWindow::UpdateMasterCapsuleTransition() {
  if (!master_capsule_transition_active_) return;
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed =
      GetTickCount64() - master_capsule_transition_started_at_;
  const double progress = std::clamp(
      static_cast<double>(elapsed) /
          static_cast<double>(std::max(1, master_capsule_transition_duration_ms_)),
      0.0, 1.0);
  const double inverse = 1.0 - progress;
  const double eased = 1.0 - inverse * inverse * inverse;
  RECT bounds = {};
  if (!GetWindowRect(window, &bounds)) return;
  const int top = static_cast<int>(std::lround(
      master_capsule_transition_start_top_ +
      (master_capsule_transition_target_top_ -
       master_capsule_transition_start_top_) * eased));
  const int alpha = static_cast<int>(std::lround(
      master_capsule_transition_start_alpha_ +
      (master_capsule_transition_target_alpha_ -
       master_capsule_transition_start_alpha_) * eased));
  applying_bounds_ = true;
  SetWindowPos(window, nullptr, bounds.left, top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER);
  applying_bounds_ = false;
  ApplyMasterCapsuleAlpha(alpha);
  if (progress >= 1.0) {
    master_capsule_transition_active_ = false;
    master_capsule_retracted_ = master_capsule_transition_target_hidden_;
    KillTimer(window, kCapsuleMasterTransitionTimerId);
    ApplyMasterCapsuleAlpha(master_capsule_transition_target_alpha_);
    RefreshZOrder();
  }
}

void PaperFlutterWindow::ShowReminderBubble(
    const flutter::EncodableMap& reminder) {
  reminder_title_ = Utf8WindowTitle(StringValue(reminder, "title", "Reminder"));
  reminder_message_ = Utf8WindowTitle(StringValue(reminder, "message", ""));
  reminder_duration_seconds_ = std::clamp(
      static_cast<int>(IntegerValue(reminder, "durationSeconds", 5)), 1, 600);
  reminder_background_color_ = ColorRefFromArgb(
      IntegerValue(reminder, "backgroundColor", -1),
      reminder_background_color_);
  reminder_border_color_ = ColorRefFromArgb(
      IntegerValue(reminder, "borderColor", -1), reminder_border_color_);
  reminder_border_alpha_ = std::clamp(
      static_cast<int>(IntegerValue(reminder, "borderAlpha", 150)), 0, 255);
  reminder_icon_background_color_ = ColorRefFromArgb(
      IntegerValue(reminder, "iconBackgroundColor", -1),
      reminder_icon_background_color_);
  reminder_accent_color_ = ColorRefFromArgb(
      IntegerValue(reminder, "accentColor", -1), reminder_accent_color_);
  reminder_text_color_ = ColorRefFromArgb(
      IntegerValue(reminder, "textColor", -1), reminder_text_color_);
  reminder_weak_text_color_ = ColorRefFromArgb(
      IntegerValue(reminder, "weakTextColor", -1),
      reminder_weak_text_color_);

  if (!reminder_bubble_) {
    WNDCLASSEXW window_class = {};
    window_class.cbSize = sizeof(window_class);
    if (!GetClassInfoExW(GetModuleHandleW(nullptr),
                         kReminderBubbleWindowClass, &window_class)) {
      window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
      window_class.lpfnWndProc = ReminderBubbleWindowProc;
      window_class.hInstance = GetModuleHandleW(nullptr);
      window_class.hCursor = LoadCursorW(nullptr, IDC_HAND);
      window_class.lpszClassName = kReminderBubbleWindowClass;
      if (!RegisterClassExW(&window_class) &&
          GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return;
      }
    }
    reminder_bubble_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE | WS_EX_LAYERED,
        kReminderBubbleWindowClass, L"RePaperTodo reminder", WS_POPUP,
        CW_USEDEFAULT, CW_USEDEFAULT, 1, 1, GetHandle(), nullptr,
        GetModuleHandleW(nullptr), this);
    if (!reminder_bubble_) {
      return;
    }
    const DWORD corner_attribute = 33;  // DWMWA_WINDOW_CORNER_PREFERENCE.
    const int rounded_corner = 2;       // DWMWCP_ROUND.
    DwmSetWindowAttribute(reminder_bubble_, corner_attribute,
                          &rounded_corner, sizeof(rounded_corner));
  }

  const int width = ScaleForDpi(reminder_bubble_, 260);
  const int height = ScaleForDpi(reminder_bubble_, 104);
  SetWindowRgn(reminder_bubble_, nullptr, TRUE);
  SetWindowPos(reminder_bubble_, HWND_TOPMOST, 0, 0, width, height,
               SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  PlaceReminderBubble();
  InvalidateRect(reminder_bubble_, nullptr, TRUE);
  UpdateWindow(reminder_bubble_);
  KillTimer(reminder_bubble_, kReminderBubbleTimerId);
  SetTimer(reminder_bubble_, kReminderBubbleTimerId,
           static_cast<UINT>(reminder_duration_seconds_ * 1000), nullptr);
}

void PaperFlutterWindow::HideReminderBubble() {
  if (!reminder_bubble_) {
    return;
  }
  HWND bubble = reminder_bubble_;
  reminder_bubble_ = nullptr;
  KillTimer(bubble, kReminderBubbleTimerId);
  DestroyWindow(bubble);
}

void PaperFlutterWindow::PlaceReminderBubble() {
  HWND anchor_window = GetHandle();
  if (!anchor_window || !reminder_bubble_) {
    return;
  }
  RECT anchor = {};
  RECT bubble = {};
  if (!GetWindowRect(anchor_window, &anchor) ||
      !GetWindowRect(reminder_bubble_, &bubble)) {
    return;
  }
  HMONITOR monitor = MonitorFromWindow(anchor_window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (!monitor || !GetMonitorInfoW(monitor, &info)) {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &info.rcWork, 0);
  }
  const int margin = ScaleForDpi(reminder_bubble_, 8);
  const int width = bubble.right - bubble.left;
  const int height = bubble.bottom - bubble.top;
  const bool prefer_left =
      anchor.left + ((anchor.right - anchor.left) / 2) >
      info.rcWork.left + ((info.rcWork.right - info.rcWork.left) / 2);
  const int work_left = static_cast<int>(info.rcWork.left);
  const int work_top = static_cast<int>(info.rcWork.top);
  const int work_right = static_cast<int>(info.rcWork.right);
  const int work_bottom = static_cast<int>(info.rcWork.bottom);
  int left = prefer_left ? static_cast<int>(anchor.left) - width - margin
                         : static_cast<int>(anchor.right) + margin;
  int top = static_cast<int>(anchor.top) +
            std::min(margin, std::max(
                                 0, (static_cast<int>(anchor.bottom -
                                                      anchor.top) -
                                     height) /
                                        2));
  left = std::clamp(left, work_left + margin,
                    std::max(work_left + margin,
                             work_right - width - margin));
  top = std::clamp(top, work_top + margin,
                   std::max(work_top + margin,
                            work_bottom - height - margin));
  SetWindowPos(reminder_bubble_, HWND_TOPMOST, left, top, 0, 0,
               SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

LRESULT CALLBACK PaperFlutterWindow::ReminderBubbleWindowProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  PaperFlutterWindow* owner = reinterpret_cast<PaperFlutterWindow*>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    owner = create ? static_cast<PaperFlutterWindow*>(create->lpCreateParams)
                   : nullptr;
    SetWindowLongPtrW(window, GWLP_USERDATA,
                      reinterpret_cast<LONG_PTR>(owner));
  }
  if (owner) {
    return owner->ReminderBubbleMessageHandler(window, message, wparam,
                                                lparam);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT PaperFlutterWindow::ReminderBubbleMessageHandler(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_MOUSEMOVE: {
      KillTimer(window, kReminderBubbleTimerId);
      TRACKMOUSEEVENT tracking = {};
      tracking.cbSize = sizeof(tracking);
      tracking.dwFlags = TME_LEAVE;
      tracking.hwndTrack = window;
      TrackMouseEvent(&tracking);
      return 0;
    }
    case WM_MOUSELEAVE:
      SetTimer(window, kReminderBubbleTimerId,
               static_cast<UINT>(reminder_duration_seconds_ * 1000), nullptr);
      return 0;
    case WM_TIMER:
      if (wparam == kReminderBubbleTimerId) {
        HideReminderBubble();
        return 0;
      }
      break;
    case WM_LBUTTONUP: {
      HideReminderBubble();
      SendEvent("paperActionRequested",
                flutter::EncodableMap{
                    {flutter::EncodableValue("paperId"),
                     flutter::EncodableValue(paper_id_)},
                    {flutter::EncodableValue("kind"),
                     flutter::EncodableValue("openReminderPaper")},
                    {flutter::EncodableValue("value"),
                     flutter::EncodableValue(paper_id_)},
                });
      return 0;
    }
    case WM_NCDESTROY:
      if (reminder_bubble_ == window) {
        reminder_bubble_ = nullptr;
      }
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      break;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC target = BeginPaint(window, &paint);
      RECT bounds = {};
      GetClientRect(window, &bounds);
      HDC buffer = CreateCompatibleDC(target);
      const int bitmap_width =
          std::max(1, static_cast<int>(bounds.right - bounds.left));
      const int bitmap_height =
          std::max(1, static_cast<int>(bounds.bottom - bounds.top));
      const UINT window_dpi =
          GetDpiForWindow(window) > 0 ? GetDpiForWindow(window) : 96;
      const double dpi_scale = static_cast<double>(window_dpi) / 96.0;
      BITMAPINFO bitmap_info = {};
      bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      bitmap_info.bmiHeader.biWidth = bitmap_width;
      bitmap_info.bmiHeader.biHeight = -bitmap_height;
      bitmap_info.bmiHeader.biPlanes = 1;
      bitmap_info.bmiHeader.biBitCount = 32;
      bitmap_info.bmiHeader.biCompression = BI_RGB;
      void* bitmap_bits = nullptr;
      HBITMAP bitmap = CreateDIBSection(target, &bitmap_info, DIB_RGB_COLORS,
                                        &bitmap_bits, nullptr, 0);
      if (!buffer || !bitmap || !bitmap_bits) {
        if (bitmap) DeleteObject(bitmap);
        if (buffer) DeleteDC(buffer);
        EndPaint(window, &paint);
        return 0;
      }
      HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);
      auto* pixels = static_cast<uint32_t*>(bitmap_bits);
      const uint32_t background_pixel =
          static_cast<uint32_t>(GetBValue(reminder_background_color_)) |
          (static_cast<uint32_t>(GetGValue(reminder_background_color_)) << 8) |
          (static_cast<uint32_t>(GetRValue(reminder_background_color_)) << 16);
      std::fill(pixels, pixels + bitmap_width * bitmap_height,
                background_pixel);

      const int icon_left = ScaleForDpi(window, 14);
      const int icon_size = ScaleForDpi(window, 28);
      const int icon_top = std::max(
          0, (static_cast<int>(bounds.bottom) - icon_size) / 2);
      for (int y = icon_top;
           y <= icon_top + icon_size && y < bitmap_height; ++y) {
        for (int x = icon_left; x < icon_left + icon_size; ++x) {
          const double coverage = CirclePixelCoverage(
              x, y, static_cast<double>(icon_left),
              static_cast<double>(icon_top) + (0.5 * dpi_scale),
              static_cast<double>(icon_size));
          if (coverage <= 0.0) continue;
          const size_t index =
              static_cast<size_t>(y) * bitmap_width + x;
          const uint32_t pixel = pixels[index];
          const auto blend_channel = [coverage](BYTE background,
                                                BYTE foreground) {
            return static_cast<uint32_t>(std::lround(
                background * (1.0 - coverage) + foreground * coverage));
          };
          const uint32_t blue = blend_channel(
              static_cast<BYTE>(pixel & 0xFF),
              GetBValue(reminder_icon_background_color_));
          const uint32_t green = blend_channel(
              static_cast<BYTE>((pixel >> 8) & 0xFF),
              GetGValue(reminder_icon_background_color_));
          const uint32_t red = blend_channel(
              static_cast<BYTE>((pixel >> 16) & 0xFF),
              GetRValue(reminder_icon_background_color_));
          pixels[index] = blue | (green << 8) | (red << 16);
        }
      }

      SetBkMode(buffer, TRANSPARENT);
      SetTextColor(buffer, reminder_accent_color_);
      HFONT icon_font = CreateFontW(
          -ScaleForDpi(window, 16), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
      HGDIOBJ old_font = SelectObject(buffer, icon_font);
      RECT icon_text = {icon_left, icon_top, icon_left + icon_size,
                        icon_top + icon_size};
      DrawTextW(buffer, L"!", 1, &icon_text,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

      const int text_left = ScaleForDpi(window, 52);
      const int text_right = bounds.right - ScaleForDpi(window, 13);
      SetTextColor(buffer, reminder_text_color_);
      std::wstring ui_font_family = CapsuleFontFamily(capsule_font_family_);
      if (capsule_font_family_ == "Segoe UI" &&
          std::any_of(reminder_title_.begin(), reminder_title_.end(),
                      IsWideCapsuleCharacter)) {
        ui_font_family = L"Microsoft YaHei UI";
      }
      HFONT title_font = CreateFontW(
          -ScaleForDpi(window, 13), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE,
          FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          ANTIALIASED_QUALITY, DEFAULT_PITCH, ui_font_family.c_str());
      SelectObject(buffer, title_font);
      RECT title_rect = {text_left, ScaleForDpi(window, 11), text_right,
                         ScaleForDpi(window, 30)};
      const int previous_character_extra =
          SetTextCharacterExtra(buffer, -ScaleForDpi(window, 1));
      DrawTextW(buffer, reminder_title_.c_str(), -1, &title_rect,
                DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);
      SetTextCharacterExtra(buffer, previous_character_extra);

      SetTextColor(buffer, reminder_weak_text_color_);
      HFONT message_font = CreateFontW(
          -ScaleForDpi(window, 12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH,
          CapsuleFontFamily(capsule_font_family_).c_str());
      SelectObject(buffer, message_font);
      const size_t first_break = reminder_message_.find(L'\n');
      const size_t second_break =
          first_break == std::wstring::npos
              ? std::wstring::npos
              : reminder_message_.find(L'\n', first_break + 1);
      if (first_break != std::wstring::npos &&
          second_break != std::wstring::npos) {
        const size_t third_break =
            reminder_message_.find(L'\n', second_break + 1);
        const std::wstring first_line =
            reminder_message_.substr(0, first_break);
        const std::wstring second_line = reminder_message_.substr(
            first_break + 1, second_break - first_break - 1);
        const std::wstring third_line = reminder_message_.substr(
            second_break + 1,
            third_break == std::wstring::npos
                ? std::wstring::npos
                : third_break - second_break - 1);
        RECT first_line_rect = {text_left, ScaleForDpi(window, 35),
                                text_right, ScaleForDpi(window, 52)};
        RECT second_line_rect = {text_left, ScaleForDpi(window, 52),
                                 text_right, ScaleForDpi(window, 69)};
        RECT third_line_rect = {
            text_left, ScaleForDpi(window, 67),
            text_right - ScaleForDpi(window, 7), ScaleForDpi(window, 84)};
        DrawTextW(buffer, first_line.c_str(), -1, &first_line_rect,
                  DT_SINGLELINE | DT_NOPREFIX);
        DrawTextW(buffer, second_line.c_str(), -1, &second_line_rect,
                  DT_SINGLELINE | DT_NOPREFIX);
        DrawTextW(buffer, third_line.c_str(), -1, &third_line_rect,
                  DT_WORDBREAK | DT_EDITCONTROL | DT_NOPREFIX);
      } else {
        const int message_top = ScaleForDpi(window, 39);
        RECT message_rect = {
            text_left, message_top, text_right,
            std::min(
                static_cast<int>(bounds.bottom) - ScaleForDpi(window, 11),
                message_top + ScaleForDpi(window, 48))};
        DrawTextW(buffer, reminder_message_.c_str(), -1, &message_rect,
                  DT_WORDBREAK | DT_EDITCONTROL | DT_NOPREFIX);
      }

      const double outer_radius = 15.0 * dpi_scale;
      const double border_width = dpi_scale;
      const double inner_radius =
          std::max(0.0, outer_radius - (0.5 * border_width));
      const double border_opacity =
          static_cast<double>(reminder_border_alpha_) / 255.0;
      for (int y = 0; y < bitmap_height; ++y) {
        for (int x = 0; x < bitmap_width; ++x) {
          const double outer_coverage = RoundedRectPixelCoverage(
              x, y, 0.0, 0.0, static_cast<double>(bitmap_width),
              static_cast<double>(bitmap_height), outer_radius);
          const double inner_coverage = RoundedRectPixelCoverage(
              x, y, border_width, border_width,
              bitmap_width - border_width, bitmap_height - border_width,
              inner_radius);
          const double border_coverage =
              std::max(0.0, outer_coverage - inner_coverage) *
              border_opacity;
          const double alpha =
              std::clamp(inner_coverage + border_coverage, 0.0, 1.0);
          const size_t index =
              static_cast<size_t>(y) * bitmap_width + x;
          const uint32_t pixel = pixels[index];
          const auto premultiply_channel =
              [inner_coverage, border_coverage](BYTE content,
                                                BYTE border) {
                return static_cast<uint32_t>(std::clamp(
                    std::lround(content * inner_coverage +
                                border * border_coverage),
                    0L, 255L));
              };
          const uint32_t blue = premultiply_channel(
              static_cast<BYTE>(pixel & 0xFF),
              GetBValue(reminder_border_color_));
          const uint32_t green = premultiply_channel(
              static_cast<BYTE>((pixel >> 8) & 0xFF),
              GetGValue(reminder_border_color_));
          const uint32_t red = premultiply_channel(
              static_cast<BYTE>((pixel >> 16) & 0xFF),
              GetRValue(reminder_border_color_));
          const uint32_t alpha_byte =
              static_cast<uint32_t>(std::lround(alpha * 255.0));
          pixels[index] = blue | (green << 8) | (red << 16) |
                          (alpha_byte << 24);
        }
      }

      RECT window_bounds = {};
      GetWindowRect(window, &window_bounds);
      POINT destination = {window_bounds.left, window_bounds.top};
      POINT source = {0, 0};
      SIZE layer_size = {bitmap_width, bitmap_height};
      BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
      HDC screen = GetDC(nullptr);
      UpdateLayeredWindow(window, screen, &destination, &layer_size, buffer,
                          &source, 0, &blend, ULW_ALPHA);
      if (screen) ReleaseDC(nullptr, screen);
      SelectObject(buffer, old_font);
      SelectObject(buffer, old_bitmap);
      DeleteObject(message_font);
      DeleteObject(title_font);
      DeleteObject(icon_font);
      DeleteObject(bitmap);
      DeleteDC(buffer);
      EndPaint(window, &paint);
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT CALLBACK PaperFlutterWindow::PaperShadowWindowProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_NCHITTEST:
      return HTTRANSPARENT;
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void PaperFlutterWindow::EnsurePaperShadowWindow() {
  if (paper_shadow_window_) {
    return;
  }
  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  if (!GetClassInfoExW(GetModuleHandleW(nullptr), kPaperShadowWindowClass,
                       &window_class)) {
    window_class.lpfnWndProc = PaperShadowWindowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    window_class.lpszClassName = kPaperShadowWindowClass;
    if (!RegisterClassExW(&window_class) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      return;
    }
  }
  paper_shadow_window_ = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kPaperShadowWindowClass, L"", WS_POPUP, 0, 0, 1, 1, nullptr, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  paper_shadow_visible_ = false;
  paper_shadow_z_order_dirty_ = true;
}

void PaperFlutterWindow::UpdatePaperShadowWindow(bool redraw) {
  // WM_MOVE, WM_SIZE, WM_WINDOWPOSCHANGED and z-order refreshes can all arrive
  // after WM_EXITSIZEMOVE but before Flutter presents its final resized frame.
  // Keep the layered shadow suppressed until that frame posts the deferred
  // refresh message; otherwise the stale DIB appears as a one-frame black rim.
  if (paper_shadow_refresh_pending_) {
    HidePaperShadowWindow();
    return;
  }
  HWND window = GetHandle();
  if (in_size_move_) {
    HidePaperShadowWindow();
    return;
  }
  if (!window || collapsed_ || !intended_visible_ ||
      !IsWindowVisible(window)) {
    HidePaperShadowWindow();
    return;
  }
  EnsurePaperShadowWindow();
  if (!paper_shadow_window_) {
    return;
  }
  RECT bounds = {};
  if (!GetWindowRect(window, &bounds)) {
    HidePaperShadowWindow();
    return;
  }
  const int width = std::max(1, static_cast<int>(bounds.right - bounds.left));
  const int height =
      std::max(1, static_cast<int>(bounds.bottom - bounds.top));
  const bool placement_changed = bounds.left != paper_shadow_left_ ||
                                 bounds.top != paper_shadow_top_ ||
                                 width != paper_shadow_width_ ||
                                 height != paper_shadow_height_;
  const bool needs_redraw =
      redraw || width != paper_shadow_width_ || height != paper_shadow_height_ ||
      paper_shadow_dark_ != rendered_paper_shadow_dark_;
  if (needs_redraw) {
    HDC screen = GetDC(nullptr);
    HDC buffer = screen ? CreateCompatibleDC(screen) : nullptr;
    BITMAPINFO bitmap_info = {};
    bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bitmap_info.bmiHeader.biWidth = width;
    bitmap_info.bmiHeader.biHeight = -height;
    bitmap_info.bmiHeader.biPlanes = 1;
    bitmap_info.bmiHeader.biBitCount = 32;
    bitmap_info.bmiHeader.biCompression = BI_RGB;
    void* bitmap_bits = nullptr;
    HBITMAP bitmap = screen
                         ? CreateDIBSection(screen, &bitmap_info, DIB_RGB_COLORS,
                                            &bitmap_bits, nullptr, 0)
                         : nullptr;
    if (!screen || !buffer || !bitmap || !bitmap_bits) {
      if (bitmap) DeleteObject(bitmap);
      if (buffer) DeleteDC(buffer);
      if (screen) ReleaseDC(nullptr, screen);
      HidePaperShadowWindow();
      return;
    }
    HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);
    auto* pixels = static_cast<uint32_t*>(bitmap_bits);
    std::fill(pixels, pixels + static_cast<size_t>(width) * height, 0u);

    const double dpi_scale =
        static_cast<double>(GetDpiForWindow(window) > 0
                                ? GetDpiForWindow(window)
                                : 96) /
        96.0;
    const double inset = 8.0 * dpi_scale;
    const double radius = 18.0 * dpi_scale;
    // Match PaperTodo's broad, low-contrast paper shadow instead of the
    // narrow shadow that made the sheet look like a flat child window.
    const double sigma = 5.5 * dpi_scale;
    const double edge_opacity = paper_shadow_dark_ ? 0.34 : 0.18;
    for (int y = 0; y < height; ++y) {
      for (int x = 0; x < width; ++x) {
        const double distance = RoundedRectSignedDistance(
            static_cast<double>(x) + 0.5, static_cast<double>(y) + 0.5,
            inset, inset, static_cast<double>(width) - inset,
            static_cast<double>(height) - inset, radius);
        if (distance < 0.0 || distance > inset + dpi_scale) {
          continue;
        }
        const double opacity = edge_opacity *
                               std::exp(-(distance * distance) /
                                        (2.0 * sigma * sigma));
        const uint32_t alpha = static_cast<uint32_t>(
            std::clamp(std::lround(opacity * 255.0), 0L, 255L));
        pixels[static_cast<size_t>(y) * width + x] = alpha << 24;
      }
    }

    POINT destination = {bounds.left, bounds.top};
    POINT source = {0, 0};
    SIZE layer_size = {width, height};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    UpdateLayeredWindow(paper_shadow_window_, screen, &destination,
                        &layer_size, buffer, &source, 0, &blend, ULW_ALPHA);
    SelectObject(buffer, old_bitmap);
    DeleteObject(bitmap);
    DeleteDC(buffer);
    ReleaseDC(nullptr, screen);
    paper_shadow_width_ = width;
    paper_shadow_height_ = height;
    rendered_paper_shadow_dark_ = paper_shadow_dark_;
  }
  if (!paper_shadow_visible_ || placement_changed ||
      paper_shadow_z_order_dirty_) {
    SetWindowPos(paper_shadow_window_, window, bounds.left, bounds.top, width,
                 height, SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_NOOWNERZORDER);
    paper_shadow_left_ = bounds.left;
    paper_shadow_top_ = bounds.top;
    paper_shadow_visible_ = true;
    paper_shadow_z_order_dirty_ = false;
  }
}

void PaperFlutterWindow::HidePaperShadowWindow() {
  if (paper_shadow_window_ &&
      (paper_shadow_visible_ || IsWindowVisible(paper_shadow_window_))) {
    ShowWindow(paper_shadow_window_, SW_HIDE);
  }
  paper_shadow_visible_ = false;
  paper_shadow_z_order_dirty_ = true;
}

void PaperFlutterWindow::DestroyPaperShadowWindow() {
  if (!paper_shadow_window_) {
    return;
  }
  HWND shadow = paper_shadow_window_;
  paper_shadow_window_ = nullptr;
  DestroyWindow(shadow);
  paper_shadow_visible_ = false;
  paper_shadow_z_order_dirty_ = true;
}

flutter::EncodableValue PaperFlutterWindow::BoundsValue() const {
  RECT bounds = {};
  HWND window = const_cast<PaperFlutterWindow*>(this)->GetHandle();
  if (!window || !GetWindowRect(window, &bounds)) {
    return flutter::EncodableValue();
  }
  const UINT dpi = GetDpiForWindow(window) > 0 ? GetDpiForWindow(window) : 96;
  return flutter::EncodableMap{
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(
           UnscalePhysicalValue(static_cast<double>(bounds.left), dpi))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(
           UnscalePhysicalValue(static_cast<double>(bounds.top), dpi))},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(UnscalePhysicalValue(
           static_cast<double>(bounds.right - bounds.left), dpi))},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(UnscalePhysicalValue(
           static_cast<double>(bounds.bottom - bounds.top), dpi))},
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
    ShowWindow(window, SW_RESTORE);
    ActivatePaperWindow(window, always_on_top_);
    paper_shadow_z_order_dirty_ = true;
  }
  UpdatePaperShadowWindow(false);
}

void PaperFlutterWindow::HidePaper() {
  intended_visible_ = false;
  HidePaperShadowWindow();
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
  if (pinned_to_desktop_) {
    extended_style = (extended_style | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) &
                     ~WS_EX_APPWINDOW;
  } else if (hidden) {
    extended_style = (extended_style | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW;
    extended_style &= ~WS_EX_NOACTIVATE;
  } else {
    extended_style = (extended_style | WS_EX_APPWINDOW) & ~WS_EX_TOOLWINDOW;
    extended_style &= ~WS_EX_NOACTIVATE;
  }
  const LONG_PTR current_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  if (extended_style != current_style) {
    SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
  }
  RemoveTaskbarButton(window);
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
  const bool fullscreen = IsExternalFullscreenWindow(window);
  fullscreen_blocked_ = avoid_fullscreen_topmost_ && fullscreen;
  const bool capsule_pointer_over =
      capsule_hovered_ || IsPointerInsideWindow(window);
  const bool policy_hidden = collapsed_ && !capsule_pointer_over &&
                             ((hide_when_fullscreen_ && fullscreen) ||
                              (hide_when_covered_ &&
                               IsCoveredByAnotherWindow(window)));
  if (!intended_visible_ || policy_hidden) {
    if (!pinned_to_desktop_) {
      SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                       SWP_NOOWNERZORDER);
    }
    HidePaperShadowWindow();
    if (IsWindowVisible(window)) {
      ShowWindow(window, SW_HIDE);
    }
    z_order_initialized_ = false;
    paper_shadow_z_order_dirty_ = true;
    return;
  }
  const bool retracted_by_master = collapsed_ && capsule_hidden_by_master_ &&
                                   master_capsule_retracted_ &&
                                   !master_capsule_transition_active_;
  if (retracted_by_master) {
    ApplyMasterCapsuleAlpha(0);
    HidePaperShadowWindow();
    if (!IsWindowVisible(window) || !z_order_initialized_ ||
        z_order_pinned_ != pinned_to_desktop_ ||
        z_order_topmost_ == pinned_to_desktop_) {
      SetWindowPos(window, pinned_to_desktop_ ? HWND_BOTTOM : HWND_TOPMOST, 0,
                   0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                       SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
    }
    z_order_initialized_ = true;
    z_order_topmost_ = !pinned_to_desktop_;
    z_order_pinned_ = pinned_to_desktop_;
    paper_shadow_z_order_dirty_ = true;
    return;
  }
  if (!master_capsule_transition_active_ && capsule_alpha_ != 255) {
    ApplyMasterCapsuleAlpha(255);
  }
  const bool visible = IsWindowVisible(window) != FALSE;
  RemoveTaskbarButton(window);
  if (pinned_to_desktop_) {
    // Keep pinned papers as ordinary top-level windows. Parenting them to a
    // WorkerW is unreliable on Windows 11 because the selected WorkerW may sit
    // behind the wallpaper compositor, making the paper appear to disappear.
    // HWND_BOTTOM gives the expected desktop-layer behavior while preserving
    // normal hit testing for the always-available unpin control.
    const LONG_PTR current_style = GetWindowLongPtrW(window, GWL_STYLE);
    const LONG_PTR desired_style =
        WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN |
        (current_style & WS_VISIBLE);
    if (current_style != desired_style) {
      SetWindowLongPtrW(window, GWL_STYLE, desired_style);
      SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                       SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
    if (!visible || !z_order_initialized_ || !z_order_pinned_) {
      SetWindowPos(window, HWND_BOTTOM, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                       SWP_NOOWNERZORDER |
                       (visible ? 0 : SWP_SHOWWINDOW));
      z_order_initialized_ = true;
      z_order_pinned_ = true;
      z_order_topmost_ = false;
      paper_shadow_z_order_dirty_ = true;
    }
    UpdatePaperShadowWindow(false);
    return;
  }
  const HWND z_order =
      always_on_top_ && !fullscreen_blocked_ ? HWND_TOPMOST : HWND_NOTOPMOST;
  const bool topmost = z_order == HWND_TOPMOST;
  if (!visible || !z_order_initialized_ || z_order_pinned_ ||
      z_order_topmost_ != topmost) {
    // Showing and assigning z-order in one SetWindowPos transaction avoids a
    // transient default-z-order frame when a hidden capsule is released by
    // the master capsule.
    SetWindowPos(window, z_order, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                     SWP_NOOWNERZORDER |
                     (visible ? 0 : SWP_SHOWWINDOW));
    z_order_initialized_ = true;
    z_order_pinned_ = false;
    z_order_topmost_ = topmost;
    paper_shadow_z_order_dirty_ = true;
  }
  UpdatePaperShadowWindow(false);
}

void PaperFlutterWindow::SendBoundsChanged() {
  flutter::EncodableMap arguments = {
      {flutter::EncodableValue("paperId"),
       flutter::EncodableValue(paper_id_)},
      {flutter::EncodableValue("isCollapsed"),
       flutter::EncodableValue(collapsed_)},
  };
  const auto bounds = BoundsValue();
  if (const auto* map = std::get_if<flutter::EncodableMap>(&bounds)) {
    arguments.insert(map->begin(), map->end());
  }
  SendEvent("boundsChanged", flutter::EncodableValue(arguments));
}

void PaperFlutterWindow::SendCapsuleDropped() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  POINT cursor = {};
  RECT bounds = {};
  if (!GetCursorPos(&cursor) || !GetWindowRect(window, &bounds)) {
    return;
  }
  HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEXW info = {};
  info.cbSize = sizeof(info);
  if (!monitor ||
      !GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&info))) {
    return;
  }
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor) > 0
                       ? FlutterDesktopGetDpiForMonitor(monitor)
                       : 96;
  const LONG center = info.rcWork.left +
                      ((info.rcWork.right - info.rcWork.left) / 2);
  const std::string side = cursor.x < center ? "left" : "right";
  SendEvent(
      "capsuleDropped",
      flutter::EncodableMap{
          {flutter::EncodableValue("paperId"),
           flutter::EncodableValue(paper_id_)},
          {flutter::EncodableValue("surfaceId"),
           flutter::EncodableValue(paper_id_)},
          {flutter::EncodableValue("monitorDeviceName"),
           flutter::EncodableValue(WideToUtf8(info.szDevice))},
          {flutter::EncodableValue("side"), flutter::EncodableValue(side)},
          {flutter::EncodableValue("dropTop"),
           flutter::EncodableValue(
               UnscalePhysicalValue(static_cast<double>(bounds.top), dpi))},
          {flutter::EncodableValue("workAreaTop"),
           flutter::EncodableValue(UnscalePhysicalValue(
               static_cast<double>(info.rcWork.top), dpi))},
          {flutter::EncodableValue("isMasterCapsule"),
           flutter::EncodableValue(false)},
      });
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
  const LONG_PTR extended_style =
      GetWindowLongPtrW(window, GWL_EXSTYLE) | WS_EX_LAYERED;
  SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style);
  SetLayeredWindowAttributes(window, RGB(1, 2, 3),
                             static_cast<BYTE>(capsule_alpha_),
                             LWA_COLORKEY | LWA_ALPHA);
  const DWMNCRENDERINGPOLICY non_client_rendering = DWMNCRP_DISABLED;
  DwmSetWindowAttribute(window, DWMWA_NCRENDERING_POLICY,
                        &non_client_rendering,
                        sizeof(non_client_rendering));
  MARGINS margins = {0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(window, &margins);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

int PaperFlutterWindow::ResizeBorderHitTest(LPARAM lparam) const {
  if (collapsed_ || pinned_to_desktop_) {
    return HTCLIENT;
  }
  HWND window = const_cast<PaperFlutterWindow*>(this)->GetHandle();
  if (!window) {
    return HTCLIENT;
  }
  RECT rect = {};
  if (!GetWindowRect(window, &rect)) {
    return HTCLIENT;
  }
  const int x = GET_X_LPARAM(lparam);
  const int y = GET_Y_LPARAM(lparam);
  const int edge = std::max(12, ScaleForDpi(window, 12));
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
  return HTCLIENT;
}
