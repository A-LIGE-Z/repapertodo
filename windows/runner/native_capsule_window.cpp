#include "native_capsule_window.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cwctype>
#include <string>
#include <utility>

#include <dwmapi.h>
#include <flutter_windows.h>

namespace {

constexpr UINT_PTR kCapsuleSlideTimerId = 0xCA51;
constexpr UINT_PTR kCapsuleQueueFollowTimerId = 0xCA54;
constexpr UINT_PTR kCapsuleMasterTransitionTimerId = 0xCA55;
constexpr int kCapsuleChromeMargin = 8;
constexpr int kCapsuleBodyHeight = 30;
constexpr int kCapsuleCornerRadius = 12;
constexpr int kCapsuleCloseWidth = 30;
constexpr int kCapsuleCloseGlyphOffset = 8;
constexpr int kCapsuleSlideOutMilliseconds = 220;
constexpr int kCapsuleSlideInMilliseconds = 180;
constexpr int kCapsuleQueueFollowMilliseconds = 64;
constexpr int kCapsuleQueueMoveMilliseconds = 200;
constexpr int kCapsuleMasterMoveMilliseconds = 200;
constexpr int kCapsuleMasterFadeMilliseconds = 160;

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

double RelativeLuminance(COLORREF color) {
  const auto channel = [](BYTE value) {
    const double normalized = static_cast<double>(value) / 255.0;
    return normalized <= 0.03928
               ? normalized / 12.92
               : std::pow((normalized + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * channel(GetRValue(color)) +
         0.7152 * channel(GetGValue(color)) +
         0.0722 * channel(GetBValue(color));
}

COLORREF BlendAlpha(COLORREF background, COLORREF overlay, int alpha) {
  const int normalized_alpha = std::clamp(alpha, 0, 255);
  const int background_alpha = 255 - normalized_alpha;
  return RGB((GetRValue(background) * background_alpha +
              GetRValue(overlay) * normalized_alpha) /
                 255,
             (GetGValue(background) * background_alpha +
              GetGValue(overlay) * normalized_alpha) /
                 255,
             (GetBValue(background) * background_alpha +
              GetBValue(overlay) * normalized_alpha) /
                 255);
}

struct CapsulePalette {
  COLORREF paper;
  COLORREF border;
  COLORREF text;
  COLORREF weak;
  COLORREF tint;
};

CapsulePalette ResolveCapsulePalette(
    bool dark, const std::string& color_scheme,
    const std::string& custom_theme_color_hex) {
  CapsulePalette palette = {
      dark ? RGB(33, 31, 28) : RGB(255, 249, 234),
      dark ? RGB(76, 69, 61) : RGB(224, 206, 167),
      dark ? RGB(231, 224, 212) : RGB(51, 41, 30),
      dark ? RGB(146, 137, 123) : RGB(138, 122, 99),
      dark ? RGB(230, 223, 211) : RGB(120, 92, 48),
  };
  if (color_scheme == "forest") {
    palette = {
        dark ? RGB(26, 30, 27) : RGB(243, 248, 241),
        dark ? RGB(58, 70, 60) : RGB(200, 218, 198),
        dark ? RGB(220, 228, 220) : RGB(38, 50, 42),
        dark ? RGB(134, 148, 136) : RGB(110, 128, 112),
        dark ? RGB(180, 208, 186) : RGB(70, 110, 80),
    };
  } else if (color_scheme == "rose") {
    palette = {
        dark ? RGB(33, 28, 30) : RGB(253, 245, 246),
        dark ? RGB(78, 64, 68) : RGB(228, 205, 210),
        dark ? RGB(232, 220, 223) : RGB(54, 38, 42),
        dark ? RGB(152, 132, 137) : RGB(140, 114, 120),
        dark ? RGB(224, 180, 190) : RGB(150, 80, 96),
    };
  } else if (color_scheme == "ink") {
    palette = {
        dark ? RGB(26, 28, 32) : RGB(246, 247, 249),
        dark ? RGB(60, 66, 76) : RGB(208, 214, 222),
        dark ? RGB(222, 227, 234) : RGB(38, 44, 54),
        dark ? RGB(138, 146, 158) : RGB(118, 126, 138),
        dark ? RGB(180, 200, 228) : RGB(70, 90, 120),
    };
  }

  COLORREF custom = 0;
  if (!ParseHexColor(custom_theme_color_hex, &custom)) {
    return palette;
  }
  const double luminance = RelativeLuminance(custom);
  const COLORREF active = dark
                              ? Mix(custom, RGB(255, 255, 255),
                                    luminance < 0.26 ? 36 : 12)
                              : (luminance > 0.78
                                     ? Mix(custom, RGB(0, 0, 0), 30)
                                     : custom);
  palette.paper = dark ? Mix(custom, RGB(0, 0, 0), 82)
                       : Mix(custom, RGB(255, 255, 255), 90);
  palette.text = dark ? Mix(custom, RGB(255, 255, 255), 82)
                      : Mix(custom, RGB(0, 0, 0), 72);
  palette.border = Mix(palette.paper, palette.text, dark ? 17 : 16);
  palette.weak = Mix(palette.text, palette.paper, 46);
  palette.tint = dark ? Mix(active, RGB(255, 255, 255), 50)
                      : Mix(active, RGB(0, 0, 0), 10);
  return palette;
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
                    WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED);
  SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void NativeCapsuleWindow::ApplySurface(
    const flutter::EncodableMap& surface) {
  const double generation_value =
      NumberValue(surface, "surfaceGeneration", -1.0);
  if (std::isfinite(generation_value) && generation_value >= 0.0) {
    const int64_t incoming_generation =
        static_cast<int64_t>(std::llround(generation_value));
    if (surface_generation_ >= 0 &&
        incoming_generation < surface_generation_) {
      return;
    }
    surface_generation_ = incoming_generation;
  }
  const bool previous_intended_visible = intended_visible_;
  const bool previous_master_hidden = capsule_hidden_by_master_;
  const std::string previous_capsule_side = capsule_side_;
  const std::string previous_monitor_device_name = monitor_device_name_;
  surface_id_ = StringValue(surface, "surfaceId", surface_id_);
  kind_ = StringValue(surface, "kind", kind_);
  master_ = kind_ == "master";
  paper_id_ = StringValue(surface, "paperId", paper_id_);
  paper_type_ = StringValue(surface, "paperType", paper_type_);
  script_capsule_ = BoolValue(surface, "isScriptCapsule", script_capsule_);
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
  capsule_hidden_by_master_ =
      BoolValue(surface, "capsuleHiddenByMaster", capsule_hidden_by_master_);
  capsule_master_top_ =
      NumberValue(surface, "capsuleMasterTop", capsule_master_top_);
  capsule_master_top_is_work_area_relative_ = BoolValue(
      surface, "capsuleMasterTopIsWorkAreaRelative",
      capsule_master_top_is_work_area_relative_);
  hide_when_covered_ =
      BoolValue(surface, "hideWhenCovered", hide_when_covered_);
  hide_when_fullscreen_ =
      BoolValue(surface, "hideWhenFullscreen", hide_when_fullscreen_);
  animations_enabled_ =
      BoolValue(surface, "enableAnimations", animations_enabled_);
  theme_ = StringValue(surface, "theme", theme_);
  color_scheme_ = StringValue(surface, "colorScheme", color_scheme_);
  custom_theme_color_hex_ = StringValue(
      surface, "customThemeColorHex", custom_theme_color_hex_);
  font_family_ = StringValue(surface, "fontFamily", font_family_);

  if (previous_capsule_side != capsule_side_ ||
      previous_monitor_device_name != monitor_device_name_) {
    queue_drag_offset_active_ = false;
    queue_drag_animation_active_ = false;
    if (HWND window = GetHandle()) {
      KillTimer(window, kCapsuleQueueFollowTimerId);
    }
  }

  // A master collapse hides an existing proxy HWND instead of destroying it.
  // Reset transient hover/slide state while hidden so expansion starts from a
  // stable resting width and never paints one stale hover frame.
  if (!intended_visible_ && previous_intended_visible) {
    hovered_ = false;
    close_hovered_ = false;
    close_pressed_ = false;
    pointer_down_ = false;
    dock_animation_active_ = false;
    current_visible_width_ = 0.0;
    master_transition_active_ = false;
    master_transition_initialized_ = false;
    master_retracted_ = false;
    ApplyMasterTransitionAlpha(255);
    if (HWND window = GetHandle()) {
      KillTimer(window, kCapsuleSlideTimerId);
      KillTimer(window, kCapsuleMasterTransitionTimerId);
    }
  }

  const UINT previous_dpi = dpi_;
  ResolveWorkArea();
  const std::wstring label = EffectiveLabel();
  const int label_width = MeasureLabelWidth(label);
  const std::wstring glyph = master_
                                 ? (active_ ? L"\u25B8" : L"\u25BE")
                                 : (script_capsule_
                                        ? L"\u26A1"
                                        : (paper_type_ == "note" ? L"\u270E"
                                                                    : L"\u2713"));
  const int glyph_font_size = master_ ? 12 : (script_capsule_ ? 15 : 13);
  const int glyph_width = MeasureTextWidth(
      glyph, glyph_font_size, FW_SEMIBOLD, L"Segoe UI Symbol");
  // WPF's FormattedText advance is a few pixels tighter than GDI for the
  // compact capsule label. Keep the full viewport and the hidden edge reveal
  // on the same source metrics as the Flutter paper window.
  const int wpf_metric_correction =
      (!master_ && (paper_type_ == "note" || script_capsule_)) ? -2 : -3;
  const int logical_full_width = master_
                                     ? std::max(
                                           1, 35 + glyph_width + label_width)
                                     : std::max(
                                           92, 62 + glyph_width + label_width +
                                                   wpf_metric_correction);
  const int first_label_width =
      label.empty()
          ? 0
          : MeasureTextWidth(label.substr(0, 1), 11, FW_NORMAL,
                             EffectiveFontFamily());
  const int master_peek_glyph_width =
      master_
          ? std::max(MeasureTextWidth(L"\u25BE", 12, FW_SEMIBOLD,
                                      L"Segoe UI Symbol"),
                     MeasureTextWidth(L"\u25B8", 12, FW_SEMIBOLD,
                                      L"Segoe UI Symbol"))
          : 0;
  const int logical_resting_visible_width = master_
                                                ? std::clamp(
                                                      29 +
                                                          master_peek_glyph_width +
                                                          first_label_width,
                                                      1, logical_full_width)
                                                : std::clamp(
                                                      22 + glyph_width +
                                                          label_width - 3,
                                                      34,
                                                      std::max(
                                                          34,
                                                          logical_full_width -
                                                              32));
  const int logical_hover_visible_width =
      master_ ? logical_resting_visible_width
              : std::clamp(logical_resting_visible_width +
                               (logical_full_width -
                                logical_resting_visible_width) /
                                   2,
                           std::min(54, logical_full_width),
                           logical_full_width);
  full_width_ = ScaleMetric(logical_full_width);
  resting_visible_width_ = ScaleMetric(logical_resting_visible_width);
  hover_visible_width_ = ScaleMetric(logical_hover_visible_width);
  height_ = ScaleMetric(46);
  const int desired_visible_width =
      hovered_ ? hover_visible_width_ : resting_visible_width_;
  if (previous_dpi != dpi_ || current_visible_width_ <= 0.0 ||
      !dock_animation_active_) {
    current_visible_width_ = desired_visible_width;
    animation_target_visible_width_ = desired_visible_width;
  } else {
    current_visible_width_ = std::clamp(
        current_visible_width_, 1.0, static_cast<double>(full_width_));
  }
  ApplyWindowRegion();
  // The master capsule owns only the visibility of this queue item. Keep the
  // child HWND alive and move/fade it through the master slot instead of
  // destroying or hiding it synchronously; this avoids a stale cached frame
  // when the queue is released again.
  const bool master_transition_supported = !master_ && intended_visible_;
  if (master_transition_supported) {
    if (!master_transition_initialized_) {
      master_transition_initialized_ = true;
      master_retracted_ = capsule_hidden_by_master_;
      master_transition_active_ = false;
      ApplyMasterTransitionAlpha(master_retracted_ ? 0 : 255);
      if (master_retracted_) {
        if (HWND window = GetHandle()) {
          RECT bounds = {};
          if (GetWindowRect(window, &bounds)) {
            SetWindowPos(window, nullptr, bounds.left, MasterTopPhysical(), 0,
                         0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                             SWP_NOOWNERZORDER);
          }
        }
      }
    } else if (previous_master_hidden != capsule_hidden_by_master_) {
      StartMasterTransition(
          capsule_hidden_by_master_ ? MasterTopPhysical()
                                     : DockedTopPhysical(),
          capsule_hidden_by_master_,
          animations_enabled_ ? kCapsuleMasterMoveMilliseconds : 0);
    } else if (master_transition_active_) {
      // Retarget a transition when the master is dragged or the queue is
      // reordered while the fade is still running. Keep the current frame and
      // only change its destination; restarting from the old slot causes a
      // visible backwards hop.
      master_transition_target_top_ = capsule_hidden_by_master_
                                          ? static_cast<double>(
                                                MasterTopPhysical())
                                          : static_cast<double>(
                                                DockedTopPhysical());
    } else if (master_retracted_) {
      if (HWND window = GetHandle()) {
        RECT bounds = {};
        if (GetWindowRect(window, &bounds) &&
            bounds.top != MasterTopPhysical()) {
          SetWindowPos(window, nullptr, bounds.left, MasterTopPhysical(), 0,
                       0,
                       SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                           SWP_NOOWNERZORDER);
        }
      }
    }
  } else if (!master_) {
    master_transition_initialized_ = true;
    master_retracted_ = false;
    master_transition_active_ = false;
    ApplyMasterTransitionAlpha(255);
    if (HWND window = GetHandle()) {
      KillTimer(window, kCapsuleMasterTransitionTimerId);
    }
  }
  // A master drag owns the live position of every child capsule. A model
  // refresh can arrive between mouse-move messages, so never replay the saved
  // queue slot while that live offset is active.
  if (!queue_drag_offset_active_ && !queue_drag_animation_active_ &&
      !master_transition_active_ && !master_retracted_) {
    ApplyDockedPosition();
  }
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
  const UINT monitor_dpi =
      lookup.monitor ? FlutterDesktopGetDpiForMonitor(lookup.monitor) : 0;
  dpi_ = monitor_dpi > 0 ? monitor_dpi : 96;
}

int NativeCapsuleWindow::ScaleMetric(int logical_pixels) const {
  return MulDiv(logical_pixels, static_cast<int>(dpi_ > 0 ? dpi_ : 96), 96);
}

double NativeCapsuleWindow::UnscaleMetric(double physical_pixels) const {
  return physical_pixels * 96.0 /
         static_cast<double>(dpi_ > 0 ? dpi_ : 96);
}

void NativeCapsuleWindow::ApplyWindowRegion() {
  HWND window = GetHandle();
  if (!window) return;
  if (region_width_ == full_width_ && region_height_ == height_ &&
      region_side_ == capsule_side_) {
    return;
  }
  const bool left = capsule_side_ == "left";
  const int chrome_margin = ScaleMetric(kCapsuleChromeMargin);
  const int body_height = ScaleMetric(kCapsuleBodyHeight);
  const int body_left = left ? 0 : chrome_margin;
  const int body_right = left ? full_width_ - chrome_margin
                              : full_width_;
  const int body_top = (height_ - body_height) / 2;
  const int body_bottom = body_top + body_height;
  HRGN region = CreateRoundRectRgn(
      body_left, body_top, body_right + 1, body_bottom + 1,
      ScaleMetric(kCapsuleCornerRadius * 2),
      ScaleMetric(kCapsuleCornerRadius * 2));
  SetWindowRgn(window, region, TRUE);
  region_width_ = full_width_;
  region_height_ = height_;
  region_side_ = capsule_side_;
}

void NativeCapsuleWindow::ApplyDockedPosition() {
  HWND window = GetHandle();
  if (!window || dragging_ || master_transition_active_ || master_retracted_) {
    return;
  }
  const int visible_width = std::clamp(
      static_cast<int>(std::lround(current_visible_width_)), 1, full_width_);
  const int x = capsule_side_ == "left"
                    ? work_area_.left - (full_width_ - visible_width)
                    : work_area_.right - visible_width;
  const int y = DockedTopPhysical();
  RECT current = {};
  if (GetWindowRect(window, &current) && current.left == x &&
      current.top == y && current.right - current.left == full_width_ &&
      current.bottom - current.top == height_) {
    return;
  }
  SetWindowPos(window, nullptr, x, y, full_width_, height_,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

int NativeCapsuleWindow::DockedTopPhysical() const {
  const int work_area_top = static_cast<int>(work_area_.top);
  const int work_area_bottom = static_cast<int>(work_area_.bottom);
  const int edge_margin = ScaleMetric(8);
  const int minimum_top = work_area_top + edge_margin;
  const int maximum_top =
      std::max(minimum_top, work_area_bottom - height_ - edge_margin);
  return std::clamp(
      work_area_top + ScaleMetric(static_cast<int>(std::lround(top_margin_))),
      minimum_top, maximum_top);
}

int NativeCapsuleWindow::MasterTopPhysical() const {
  const int work_area_top = static_cast<int>(work_area_.top);
  const int work_area_bottom = static_cast<int>(work_area_.bottom);
  const int edge_margin = ScaleMetric(8);
  const int minimum_top = work_area_top + edge_margin;
  const int maximum_top =
      std::max(minimum_top, work_area_bottom - height_ - edge_margin);
  const int requested = capsule_master_top_is_work_area_relative_
                            ? work_area_top + ScaleMetric(static_cast<int>(
                                                               std::lround(
                                                                   capsule_master_top_)))
                            : ScaleMetric(static_cast<int>(std::lround(
                                  capsule_master_top_)));
  return std::clamp(requested, minimum_top, maximum_top);
}

void NativeCapsuleWindow::ApplyMasterTransitionAlpha(int alpha) {
  const int next_alpha = std::clamp(alpha, 0, 255);
  if (current_alpha_ == next_alpha) {
    return;
  }
  current_alpha_ = next_alpha;
  if (HWND window = GetHandle()) {
    SetLayeredWindowAttributes(window, 0,
                               static_cast<BYTE>(current_alpha_), LWA_ALPHA);
  }
}

void NativeCapsuleWindow::StartMasterTransition(int target_top,
                                                bool target_hidden,
                                                int duration_ms) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return;

  master_transition_target_hidden_ = target_hidden;
  master_transition_start_top_ = static_cast<double>(bounds.top);
  master_transition_target_top_ = static_cast<double>(target_top);
  master_transition_start_alpha_ = current_alpha_;
  master_transition_target_alpha_ = target_hidden ? 0 : 255;
  master_transition_started_at_ = GetTickCount64();
  master_transition_duration_ms_ = std::max(0, duration_ms);
  master_transition_active_ = false;

  if (target_hidden) {
    // Keep the HWND visible while it travels to the master slot. It becomes
    // hit-test transparent as soon as the target is a retracted state.
    master_retracted_ = false;
  } else {
    master_retracted_ = true;
    if (!IsWindowVisible(window)) {
      ShowWindow(window, SW_SHOWNOACTIVATE);
    }
  }

  if (!animations_enabled_ || duration_ms <= 0 ||
      (std::abs(master_transition_start_top_ -
                master_transition_target_top_) < 0.5 &&
       master_transition_start_alpha_ == master_transition_target_alpha_)) {
    master_transition_active_ = false;
    master_retracted_ = target_hidden;
    ApplyMasterTransitionAlpha(master_transition_target_alpha_);
    SetWindowPos(window, nullptr, bounds.left,
                 static_cast<int>(std::lround(master_transition_target_top_)),
                 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_NOOWNERZORDER);
    KillTimer(window, kCapsuleMasterTransitionTimerId);
    RefreshVisibility();
    return;
  }

  master_transition_active_ = true;
  SetTimer(window, kCapsuleMasterTransitionTimerId, 16, nullptr);
}

void NativeCapsuleWindow::UpdateMasterTransition() {
  if (!master_transition_active_) return;
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed = GetTickCount64() - master_transition_started_at_;
  const double progress = std::clamp(
      static_cast<double>(elapsed) /
          static_cast<double>(std::max(1, master_transition_duration_ms_)),
      0.0, 1.0);
  const double inverse = 1.0 - progress;
  const double eased = 1.0 - inverse * inverse * inverse;
  RECT bounds = {};
  if (!GetWindowRect(window, &bounds)) return;
  const int top = static_cast<int>(std::lround(
      master_transition_start_top_ +
      (master_transition_target_top_ - master_transition_start_top_) *
          eased));
  const int alpha = static_cast<int>(std::lround(
      master_transition_start_alpha_ +
      (master_transition_target_alpha_ - master_transition_start_alpha_) *
          eased));
  SetWindowPos(window, nullptr, bounds.left, top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER);
  ApplyMasterTransitionAlpha(alpha);
  if (progress >= 1.0) {
    master_transition_active_ = false;
    master_retracted_ = master_transition_target_hidden_;
    KillTimer(window, kCapsuleMasterTransitionTimerId);
    ApplyMasterTransitionAlpha(master_transition_target_alpha_);
    RefreshVisibility();
  }
}

void NativeCapsuleWindow::SetHovered(bool hovered) {
  if (hovered_ == hovered || dragging_) return;
  hovered_ = hovered;
  const int target = hovered_ ? hover_visible_width_ : resting_visible_width_;
  if (animations_enabled_ && !master_) {
    StartDockAnimation(
        target, hovered_ ? kCapsuleSlideOutMilliseconds
                         : kCapsuleSlideInMilliseconds);
  } else {
    if (HWND window = GetHandle()) {
      KillTimer(window, kCapsuleSlideTimerId);
    }
    dock_animation_active_ = false;
    current_visible_width_ = target;
    ApplyDockedPosition();
  }
  if (HWND window = GetHandle()) InvalidateRect(window, nullptr, FALSE);
}

void NativeCapsuleWindow::StartDockAnimation(int target_visible_width,
                                             int duration_ms) {
  HWND window = GetHandle();
  if (!window) return;
  const double target = std::clamp(
      static_cast<double>(target_visible_width), 1.0,
      static_cast<double>(full_width_));
  if (std::abs(current_visible_width_ - target) < 0.5 || duration_ms <= 0) {
    KillTimer(window, kCapsuleSlideTimerId);
    dock_animation_active_ = false;
    current_visible_width_ = target;
    ApplyDockedPosition();
    return;
  }
  animation_start_visible_width_ = current_visible_width_;
  animation_target_visible_width_ = target;
  animation_started_at_ = GetTickCount64();
  animation_duration_ms_ = duration_ms;
  dock_animation_active_ = true;
  SetTimer(window, kCapsuleSlideTimerId, 16, nullptr);
}

void NativeCapsuleWindow::UpdateDockAnimation() {
  if (!dock_animation_active_) return;
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed = GetTickCount64() - animation_started_at_;
  const double progress = std::clamp(
      static_cast<double>(elapsed) /
          static_cast<double>(std::max(1, animation_duration_ms_)),
      0.0, 1.0);
  const double inverse = 1.0 - progress;
  const double eased = 1.0 - inverse * inverse * inverse;
  current_visible_width_ =
      animation_start_visible_width_ +
      (animation_target_visible_width_ - animation_start_visible_width_) *
          eased;
  ApplyDockedPosition();
  if (progress >= 1.0) {
    current_visible_width_ = animation_target_visible_width_;
    dock_animation_active_ = false;
    KillTimer(window, kCapsuleSlideTimerId);
    ApplyDockedPosition();
  }
}

void NativeCapsuleWindow::SetAvoidFullscreenTopmost(bool avoid) {
  avoid_fullscreen_topmost_ = avoid;
  RefreshVisibility();
}

bool NativeCapsuleWindow::IsVisible() const {
  HWND window = const_cast<NativeCapsuleWindow*>(this)->GetHandle();
  return window && IsWindowVisible(window);
}

bool NativeCapsuleWindow::IsInQueue(
    const std::string& monitor_device_name, const std::string& side) const {
  return monitor_device_name_ == monitor_device_name &&
         capsule_side_ == (side == "left" ? "left" : "right");
}

void NativeCapsuleWindow::ApplyQueueDragOffset(int delta_y) {
  if (master_) return;
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return;
  if (!queue_drag_offset_active_) {
    queue_drag_offset_active_ = true;
    queue_drag_base_top_ = bounds.top;
  }
  queue_drag_target_top_ = queue_drag_base_top_ + delta_y;
  // Follow the master with a deliberately short, retargetable ease-out. Each
  // pointer update starts from the child HWND's current frame, so the queue
  // reads as one connected strip without either snapping or accumulating the
  // lag produced by the normal 200 ms move transition.
  StartQueueDragAnimation(queue_drag_target_top_,
                          kCapsuleQueueFollowMilliseconds);
}

void NativeCapsuleWindow::FinishQueueDrag(bool commit) {
  if (!queue_drag_offset_active_) return;
  const int target_top = commit ? queue_drag_target_top_ : queue_drag_base_top_;
  if (commit) {
    StartQueueDragAnimation(target_top, kCapsuleQueueFollowMilliseconds);
  } else {
    StartQueueDragAnimation(target_top, kCapsuleQueueMoveMilliseconds);
  }
  queue_drag_offset_active_ = false;
}

void NativeCapsuleWindow::StartQueueDragAnimation(int target_top,
                                                  int duration_ms) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return;
  queue_drag_target_top_ = target_top;
  if (!animations_enabled_ || duration_ms <= 0 ||
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

void NativeCapsuleWindow::UpdateQueueDragAnimation() {
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

void NativeCapsuleWindow::ApplyQueueDragTop(int top) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds) || bounds.top == top) return;
  SetWindowPos(window, nullptr, bounds.left, top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER);
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

std::wstring NativeCapsuleWindow::EffectiveFontFamily() const {
  std::wstring family = Utf8ToWide(font_family_);
  if (family.empty()) family = L"Segoe UI";
  if (family.size() >= LF_FACESIZE) family.resize(LF_FACESIZE - 1);
  return family;
}

int NativeCapsuleWindow::MeasureTextWidth(
    const std::wstring& value,
    int logical_font_size,
    int font_weight,
    const std::wstring& font_family) const {
  if (value.empty()) return 0;
  HDC dc = GetDC(nullptr);
  if (!dc) return TextWidthEstimate(value);
  HFONT font = CreateFontW(
      -ScaleMetric(logical_font_size), 0, 0, 0, font_weight, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH, font_family.c_str());
  if (!font) {
    ReleaseDC(nullptr, dc);
    return TextWidthEstimate(value);
  }
  HGDIOBJ old_font = SelectObject(dc, font);
  SIZE measured = {};
  const bool measured_ok =
      GetTextExtentPoint32W(dc, value.c_str(),
                            static_cast<int>(value.size()), &measured) == TRUE;
  SelectObject(dc, old_font);
  DeleteObject(font);
  ReleaseDC(nullptr, dc);
  return measured_ok
             ? std::max(0, static_cast<int>(
                               std::ceil(UnscaleMetric(measured.cx))))
             : TextWidthEstimate(value);
}

int NativeCapsuleWindow::MeasureLabelWidth(
    const std::wstring& value) const {
  return MeasureTextWidth(value, 11, FW_NORMAL, EffectiveFontFamily());
}

void NativeCapsuleWindow::SendClick() {
  if (!event_callback_ || paper_id_.empty()) return;
  const std::string kind = master_
                               ? "toggleCollapseAll"
                               : (collapse_on_click_ ? "collapsePaper"
                                                     : "openPaper");
  flutter::EncodableMap arguments{
      {flutter::EncodableValue("paperId"), flutter::EncodableValue(paper_id_)},
      {flutter::EncodableValue("kind"), flutter::EncodableValue(kind)},
      {flutter::EncodableValue("value"),
       flutter::EncodableValue(
           master_ && surface_id_.rfind("master:", 0) == 0
               ? surface_id_.substr(7)
               : paper_id_)},
  };
  if (surface_generation_ >= 0) {
    arguments.emplace(flutter::EncodableValue("surfaceGeneration"),
                      flutter::EncodableValue(surface_generation_));
  }
  event_callback_("paperActionRequested", flutter::EncodableValue(arguments));
}

void NativeCapsuleWindow::SendHide() {
  if (!event_callback_ || paper_id_.empty() || master_) return;
  event_callback_(
      "hideRequested",
      flutter::EncodableMap{
          {flutter::EncodableValue("paperId"),
           flutter::EncodableValue(paper_id_)},
      });
}

bool NativeCapsuleWindow::IsClosePoint(POINT client_point) const {
  if (master_) return false;
  const int chrome_margin = ScaleMetric(kCapsuleChromeMargin);
  const int body_height = ScaleMetric(kCapsuleBodyHeight);
  const int body_top = (height_ - body_height) / 2;
  const int body_bottom = body_top + body_height;
  if (client_point.y < body_top || client_point.y >= body_bottom) {
    return false;
  }
  const int body_left = capsule_side_ == "left" ? 0 : chrome_margin;
  const int body_right = capsule_side_ == "left"
                             ? full_width_ - chrome_margin
                             : full_width_;
  const int close_width = ScaleMetric(kCapsuleCloseWidth);
  return capsule_side_ == "left"
             ? client_point.x >= body_left &&
                   client_point.x < body_left + close_width
             : client_point.x >= body_right - close_width &&
                   client_point.x < body_right;
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
  const UINT monitor_dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double dpi = static_cast<double>(monitor_dpi > 0 ? monitor_dpi : 96);
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
           flutter::EncodableValue(static_cast<double>(bounds.top) * 96.0 /
                                   dpi)},
          {flutter::EncodableValue("workAreaTop"),
           flutter::EncodableValue(
               static_cast<double>(info.rcWork.top) * 96.0 / dpi)},
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

bool NativeCapsuleWindow::IsPointerOverWindow() const {
  HWND window = const_cast<NativeCapsuleWindow*>(this)->GetHandle();
  if (!window || !IsWindowVisible(window)) return false;
  POINT cursor = {};
  RECT bounds = {};
  return GetCursorPos(&cursor) && GetWindowRect(window, &bounds) &&
         PtInRect(&bounds, cursor) == TRUE;
}

void NativeCapsuleWindow::RefreshVisibility() {
  HWND window = GetHandle();
  if (!window) return;
  const bool fullscreen = IsExternalFullscreenWindow();
  // Never hide a capsule while the pointer is interacting with it. Because
  // capsule HWNDs are no-activate windows, the previously focused fullscreen
  // or overlapping app can otherwise remain foreground and make the capsule
  // disappear directly under the cursor.
  const bool pointer_over = hovered_ || pointer_down_ || dragging_ ||
                            IsPointerOverWindow();
  const bool policy_hidden = !pointer_over &&
                             ((hide_when_fullscreen_ && fullscreen) ||
                              (hide_when_covered_ &&
                               IsCoveredByHigherWindow()));
  if (!intended_visible_ || policy_hidden) {
    if (IsWindowVisible(window)) {
      SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_NOOWNERZORDER | SWP_HIDEWINDOW);
    }
    z_order_initialized_ = false;
    return;
  }
  const bool retracted_by_master = !master_ && capsule_hidden_by_master_ &&
                                   master_retracted_ &&
                                   !master_transition_active_;
  if (retracted_by_master) {
    ApplyMasterTransitionAlpha(0);
    if (!IsWindowVisible(window)) {
      SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                       SWP_NOOWNERZORDER | SWP_SHOWWINDOW);
    }
    z_order_initialized_ = true;
    z_order_topmost_ = true;
    return;
  }
  if (!master_transition_active_ && current_alpha_ != 255) {
    ApplyMasterTransitionAlpha(255);
  }
  const HWND z_order =
      avoid_fullscreen_topmost_ && fullscreen ? HWND_NOTOPMOST : HWND_TOPMOST;
  const bool topmost = z_order == HWND_TOPMOST;
  const bool visible = IsWindowVisible(window) != FALSE;
  if (!visible || !z_order_initialized_ || z_order_topmost_ != topmost ||
      master_) {
    if (!visible) {
      // Paint the final label, hover state and theme into the hidden HWND
      // before revealing it. Otherwise Windows can briefly present the last
      // cached frame when a master capsule expands its queue.
      RedrawWindow(window, nullptr, nullptr,
                   RDW_INVALIDATE | RDW_UPDATENOW | RDW_NOERASE);
    }
    SetWindowPos(window, z_order, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                     SWP_NOOWNERZORDER | (visible ? 0 : SWP_SHOWWINDOW));
    z_order_initialized_ = true;
    z_order_topmost_ = topmost;
  }
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
  const CapsulePalette palette = ResolveCapsulePalette(
      dark, color_scheme_, custom_theme_color_hex_);
  COLORREF background = palette.paper;
  const COLORREF border = palette.border;
  const COLORREF text = palette.text;
  const COLORREF weak = palette.weak;
  if (hovered_ && !close_hovered_) {
    background = BlendAlpha(background, palette.tint, dark ? 48 : 32);
  }
  if (pointer_down_ && !close_pressed_) {
    background = Mix(background, text, dark ? 9 : 6);
  }

  HBRUSH background_brush = CreateSolidBrush(background);
  HPEN border_pen =
      CreatePen(PS_SOLID, std::max(1, ScaleMetric(1)), border);
  HGDIOBJ old_brush = SelectObject(buffer, background_brush);
  HGDIOBJ old_pen = SelectObject(buffer, border_pen);
  const bool left = capsule_side_ == "left";
  const int chrome_margin = ScaleMetric(kCapsuleChromeMargin);
  const int body_height = ScaleMetric(kCapsuleBodyHeight);
  const int body_left = left ? 0 : chrome_margin;
  const int body_right = left ? bounds.right - chrome_margin
                              : bounds.right;
  const int body_top =
      (static_cast<int>(bounds.bottom - bounds.top) - body_height) / 2;
  const int body_bottom = body_top + body_height;
  const int corner_ellipse = ScaleMetric(kCapsuleCornerRadius * 2);
  RoundRect(buffer, body_left, body_top, body_right, body_bottom,
            corner_ellipse, corner_ellipse);

  const int close_width = ScaleMetric(kCapsuleCloseWidth);
  RECT close_rect = capsule_side_ == "left"
                        ? RECT{body_left, body_top,
                               body_left + close_width, body_bottom}
                        : RECT{body_right - close_width, body_top,
                               body_right, body_bottom};
  if (!master_ && close_hovered_) {
    const COLORREF close_background = close_pressed_
                                          ? Mix(background, text, dark ? 22 : 16)
                                          : BlendAlpha(
                                                palette.paper, palette.tint,
                                                dark ? 48 : 32);
    HBRUSH close_brush = CreateSolidBrush(close_background);
    SelectObject(buffer, close_brush);
    SelectObject(buffer, GetStockObject(NULL_PEN));
    RoundRect(buffer, close_rect.left, close_rect.top, close_rect.right,
              close_rect.bottom, corner_ellipse, corner_ellipse);
    RECT close_fill = close_rect;
    if (capsule_side_ == "left") {
      close_fill.left += ScaleMetric(kCapsuleCornerRadius);
    } else {
      close_fill.right -= ScaleMetric(kCapsuleCornerRadius);
    }
    FillRect(buffer, &close_fill, close_brush);
    SelectObject(buffer, background_brush);
    SelectObject(buffer, border_pen);
    DeleteObject(close_brush);
  }

  SetBkMode(buffer, TRANSPARENT);
  const std::wstring glyph = master_
                                 ? (active_ ? L"\u25B8" : L"\u25BE")
                                 : (script_capsule_
                                        ? L"\u26A1"
                                        : (paper_type_ == "note" ? L"\u270E"
                                                                    : L"\u2713"));
  const std::wstring label = EffectiveLabel();
  const int glyph_font_size = master_
                                  ? ScaleMetric(12)
                                  : (script_capsule_ ? ScaleMetric(15)
                                                     : ScaleMetric(13));
  HFONT glyph_font = CreateFontW(
      -glyph_font_size, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Segoe UI Symbol");
  const std::wstring text_font_family = EffectiveFontFamily();
  HFONT text_font = CreateFontW(
      -ScaleMetric(11), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      ANTIALIASED_QUALITY, DEFAULT_PITCH, text_font_family.c_str());
  const int inset_6 = ScaleMetric(6);
  const int glyph_inset = master_ ? ScaleMetric(5) : inset_6;
  const int glyph_gap = ScaleMetric(4);
  const int measured_glyph_width = ScaleMetric(std::max(
      1, MeasureTextWidth(glyph, master_ ? 12 : (script_capsule_ ? 15 : 13),
                          FW_SEMIBOLD, L"Segoe UI Symbol")));
  RECT glyph_rect = left
                        ? RECT{body_right - glyph_inset - measured_glyph_width,
                               body_top, body_right - glyph_inset, body_bottom}
                        : RECT{body_left + glyph_inset, body_top,
                               body_left + glyph_inset + measured_glyph_width,
                               body_bottom};
  const int master_tail_padding = ScaleMetric(10);
  RECT text_rect = left
                       ? RECT{body_left +
                                  (master_ ? master_tail_padding : close_width),
                              body_top, glyph_rect.left - glyph_gap,
                              body_bottom}
                       : RECT{glyph_rect.right + glyph_gap, body_top,
                              body_right -
                                  (master_ ? master_tail_padding : close_width),
                              body_bottom};
  if (!master_ && paper_type_ == "todo" && !script_capsule_) {
    OffsetRect(&text_rect, left ? ScaleMetric(1) : -ScaleMetric(1), 0);
  }
  if (!master_) {
    const int title_offset = paper_type_ == "note" ? 1 : 0;
    if (left) {
      text_rect.right -= ScaleMetric(title_offset);
    } else {
      text_rect.left -= ScaleMetric(title_offset);
    }
  }
  SetTextColor(buffer, master_ ? text : weak);
  HGDIOBJ old_font = SelectObject(buffer, glyph_font);
  DrawTextW(buffer, glyph.c_str(), static_cast<int>(glyph.size()), &glyph_rect,
            DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_NOPREFIX);
  SelectObject(buffer, text_font);
  SetTextColor(buffer, weak);
  if (master_) {
    DrawTextW(buffer, label.c_str(), static_cast<int>(label.size()), &text_rect,
              DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX |
                  (left ? DT_RIGHT : DT_LEFT));
  } else {
    RECT title_clip = text_rect;
    const int title_clip_width =
        ScaleMetric(std::max(1, MeasureLabelWidth(label) - 2));
    if (left) {
      title_clip.left = std::max(title_clip.left,
                                 title_clip.right - title_clip_width);
    } else {
      title_clip.right = std::min(title_clip.right,
                                  title_clip.left + title_clip_width);
    }
    const int saved_dc = SaveDC(buffer);
    IntersectClipRect(buffer, title_clip.left, title_clip.top,
                      title_clip.right, title_clip.bottom);
    DrawTextW(buffer, label.c_str(), static_cast<int>(label.size()), &text_rect,
              DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX |
                  (left ? DT_RIGHT : DT_LEFT));
    RestoreDC(buffer, saved_dc);
  }
  if (!master_) {
    RECT close_glyph_rect = close_rect;
    OffsetRect(&close_glyph_rect,
               ScaleMetric(capsule_side_ == "left"
                               ? kCapsuleCloseGlyphOffset
                               : -kCapsuleCloseGlyphOffset),
               0);
    HFONT close_font = CreateFontW(
        -ScaleMetric(18), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
        ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Segoe UI Symbol");
    SelectObject(buffer, close_font);
    SetTextColor(buffer, close_hovered_ ? text : weak);
    DrawTextW(buffer, L"\u00D7", 1, &close_glyph_rect,
              DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_NOPREFIX);
    SelectObject(buffer, text_font);
    DeleteObject(close_font);
  }

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
    case WM_TIMER:
      if (wparam == kCapsuleSlideTimerId) {
        UpdateDockAnimation();
        return 0;
      }
      if (wparam == kCapsuleQueueFollowTimerId) {
        UpdateQueueDragAnimation();
        return 0;
      }
      if (wparam == kCapsuleMasterTransitionTimerId) {
        UpdateMasterTransition();
        return 0;
      }
      break;
    case WM_NCHITTEST:
      if (master_retracted_ ||
          (master_transition_active_ && master_transition_target_hidden_)) {
        return HTTRANSPARENT;
      }
      return HTCLIENT;
    case WM_SETCURSOR:
      SetCursor(LoadCursor(
          nullptr, pointer_down_ && !close_pressed_ ? IDC_SIZEALL : IDC_HAND));
      return TRUE;
    case WM_MOUSEMOVE: {
      if (!tracking_mouse_leave_) {
        TRACKMOUSEEVENT tracking = {};
        tracking.cbSize = sizeof(tracking);
        tracking.dwFlags = TME_LEAVE;
        tracking.hwndTrack = window;
        tracking_mouse_leave_ = TrackMouseEvent(&tracking) == TRUE;
      }
      POINT client_point = {
          static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
          static_cast<LONG>(static_cast<short>(HIWORD(lparam))),
      };
      const bool close_hovered = IsClosePoint(client_point);
      if (close_hovered_ != close_hovered) {
        close_hovered_ = close_hovered;
        InvalidateRect(window, nullptr, FALSE);
      }
      if (!pointer_down_) {
        SetHovered(true);
        return 0;
      }
      if (close_pressed_) return 0;
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
        const int edge_margin = ScaleMetric(8);
        const int minimum_top = work_area_top + edge_margin;
        const int maximum_top =
            std::max(minimum_top, work_area_bottom - height - edge_margin);
        const int target_top =
            std::clamp(static_cast<int>(drag_start_bounds_.top) + delta_y,
                       minimum_top,
                       maximum_top);
        SetWindowPos(window, nullptr, drag_start_bounds_.left, target_top,
                     width, height, SWP_NOZORDER | SWP_NOACTIVATE);
        if (event_callback_) {
          event_callback_(
              "capsuleMasterDragUpdated",
              flutter::EncodableMap{
                  {flutter::EncodableValue("monitorDeviceName"),
                   flutter::EncodableValue(monitor_device_name_)},
                  {flutter::EncodableValue("side"),
                   flutter::EncodableValue(capsule_side_)},
                  {flutter::EncodableValue("deltaY"),
                   flutter::EncodableValue(target_top -
                                           drag_start_bounds_.top)},
              });
        }
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
      close_hovered_ = false;
      if (!pointer_down_) SetHovered(false);
      RefreshVisibility();
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    case WM_LBUTTONDOWN: {
      POINT client_point = {
          static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
          static_cast<LONG>(static_cast<short>(HIWORD(lparam))),
      };
      pointer_down_ = true;
      close_pressed_ = IsClosePoint(client_point);
      close_hovered_ = close_pressed_;
      dragging_ = false;
      GetCursorPos(&drag_start_cursor_);
      GetWindowRect(window, &drag_start_bounds_);
      SetCapture(window);
      SetHovered(true);
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    case WM_LBUTTONUP: {
      if (!pointer_down_) return 0;
      POINT client_point = {
          static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
          static_cast<LONG>(static_cast<short>(HIWORD(lparam))),
      };
      const bool was_dragging = dragging_;
      const bool close_clicked =
          close_pressed_ && IsClosePoint(client_point);
      pointer_down_ = false;
      close_pressed_ = false;
      dragging_ = false;
      if (GetCapture() == window) ReleaseCapture();
      if (close_clicked) {
        SendHide();
      } else if (was_dragging) {
        SendDrop();
        if (master_ && event_callback_) {
          event_callback_(
              "capsuleMasterDragFinished",
              flutter::EncodableMap{
                  {flutter::EncodableValue("monitorDeviceName"),
                   flutter::EncodableValue(monitor_device_name_)},
                  {flutter::EncodableValue("side"),
                   flutter::EncodableValue(capsule_side_)},
                  {flutter::EncodableValue("commit"),
                   flutter::EncodableValue(true)},
              });
        }
      } else {
        SendClick();
      }
      // Releasing capture does not guarantee a WM_MOUSEMOVE before the next
      // paint.  Derive the hover state from the actual cursor location so a
      // click that ends inside the pill does not start a needless slide-out
      // (or allow the covered/fullscreen policy to hide it for one frame).
      bool cursor_inside = false;
      POINT cursor = {};
      RECT bounds = {};
      if (GetCursorPos(&cursor) && GetWindowRect(window, &bounds)) {
        cursor_inside = PtInRect(&bounds, cursor) == TRUE;
      }
      SetHovered(cursor_inside);
      RefreshVisibility();
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    case WM_CAPTURECHANGED:
      if (master_ && dragging_ && event_callback_) {
        event_callback_(
            "capsuleMasterDragFinished",
            flutter::EncodableMap{
                {flutter::EncodableValue("monitorDeviceName"),
                 flutter::EncodableValue(monitor_device_name_)},
                {flutter::EncodableValue("side"),
                 flutter::EncodableValue(capsule_side_)},
                {flutter::EncodableValue("commit"),
                 flutter::EncodableValue(false)},
            });
      }
      pointer_down_ = false;
      close_pressed_ = false;
      dragging_ = false;
      InvalidateRect(window, nullptr, FALSE);
      return 0;
    case WM_DESTROY:
      KillTimer(window, kCapsuleSlideTimerId);
      KillTimer(window, kCapsuleQueueFollowTimerId);
      KillTimer(window, kCapsuleMasterTransitionTimerId);
      dock_animation_active_ = false;
      queue_drag_animation_active_ = false;
      master_transition_active_ = false;
      break;
    case WM_CLOSE:
      z_order_initialized_ = false;
      SetWindowPos(window, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                       SWP_NOOWNERZORDER | SWP_HIDEWINDOW);
      return 0;
  }
  return Win32Window::MessageHandler(window, message, wparam, lparam);
}
