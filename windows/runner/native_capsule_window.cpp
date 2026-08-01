#include "native_capsule_window.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cwctype>
#include <string>
#include <utility>

#include <d2d1.h>
#include <dwrite.h>
#include <dwmapi.h>
#include <flutter_windows.h>
#include <wrl/client.h>

#include "paper_motion.h"

namespace {

constexpr UINT_PTR kCapsuleSlideTimerId = 0xCA51;
constexpr UINT_PTR kCapsuleQueueFollowTimerId = 0xCA54;
constexpr UINT_PTR kCapsuleMasterTransitionTimerId = 0xCA55;
constexpr wchar_t kCapsuleAlphaProperty[] =
    L"RePaperTodo.NativeCapsuleAlpha";
constexpr int kCapsuleChromeMargin = 8;
constexpr int kCapsuleBodyHeight = 30;
constexpr int kCapsuleCornerRadius = 12;
constexpr int kCapsuleFocusOutlineThickness = 2;
constexpr int kCapsuleFocusOutlineOverlap = 1;
constexpr int kCapsuleCloseWidth = 30;
constexpr int kCapsuleCloseGlyphOffset = 8;
using repapertodo::motion::kAnimationFrameMilliseconds;
using repapertodo::motion::kCapsuleMasterFadeMilliseconds;
using repapertodo::motion::kCapsuleMasterMoveMilliseconds;
using repapertodo::motion::kCapsuleQueueMoveMilliseconds;
using repapertodo::motion::kCapsuleSlideInMilliseconds;
using repapertodo::motion::kCapsuleSlideOutMilliseconds;
using repapertodo::motion::AnimationProgress;
using repapertodo::motion::EaseOutCubic;

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
  const double delta_x = x - nearest_x;
  const double delta_y = y - nearest_y;
  return delta_x * delta_x + delta_y * delta_y <=
         normalized_radius * normalized_radius;
}

bool DrawMasterLabelDirectWrite(HDC context, const RECT& target_bounds,
                                const RECT& text_bounds,
                                const RECT& clip_bounds,
                                const std::wstring& text,
                                const std::wstring& font_family,
                                COLORREF color, int physical_font_size,
                                bool align_right) {
  if (!context || text.empty() || physical_font_size <= 0) return false;

  using Microsoft::WRL::ComPtr;
  ComPtr<ID2D1Factory> d2d_factory;
  if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                               IID_PPV_ARGS(&d2d_factory)))) {
    return false;
  }
  ComPtr<IDWriteFactory> write_factory;
  if (FAILED(DWriteCreateFactory(
          DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
          reinterpret_cast<IUnknown**>(write_factory.GetAddressOf())))) {
    return false;
  }

  D2D1_RENDER_TARGET_PROPERTIES properties = {};
  properties.type = D2D1_RENDER_TARGET_TYPE_DEFAULT;
  properties.pixelFormat.format = DXGI_FORMAT_B8G8R8A8_UNORM;
  properties.pixelFormat.alphaMode = D2D1_ALPHA_MODE_IGNORE;
  properties.dpiX = 96.0f;
  properties.dpiY = 96.0f;
  ComPtr<ID2D1DCRenderTarget> render_target;
  if (FAILED(d2d_factory->CreateDCRenderTarget(
          &properties, render_target.GetAddressOf())) ||
      FAILED(render_target->BindDC(context, &target_bounds))) {
    return false;
  }
  render_target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
  ComPtr<IDWriteRenderingParams> rendering_params;
  if (SUCCEEDED(write_factory->CreateCustomRenderingParams(
          2.2f, 1.0f, 0.0f, DWRITE_PIXEL_GEOMETRY_FLAT,
          DWRITE_RENDERING_MODE_NATURAL,
          rendering_params.GetAddressOf()))) {
    render_target->SetTextRenderingParams(rendering_params.Get());
  }

  wchar_t locale_name[LOCALE_NAME_MAX_LENGTH] = {};
  if (GetUserDefaultLocaleName(locale_name,
                               static_cast<int>(std::size(locale_name))) <= 0) {
    wcscpy_s(locale_name, L"en-US");
  }
  ComPtr<IDWriteTextFormat> format;
  if (FAILED(write_factory->CreateTextFormat(
          font_family.c_str(), nullptr, DWRITE_FONT_WEIGHT_NORMAL,
          DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
          static_cast<float>(physical_font_size), locale_name,
          format.GetAddressOf()))) {
    return false;
  }
  format->SetTextAlignment(align_right ? DWRITE_TEXT_ALIGNMENT_TRAILING
                                      : DWRITE_TEXT_ALIGNMENT_LEADING);
  format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
  format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);

  const float width = static_cast<float>(text_bounds.right - text_bounds.left);
  const float height =
      static_cast<float>(text_bounds.bottom - text_bounds.top);
  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(write_factory->CreateTextLayout(
          text.c_str(), static_cast<UINT32>(text.size()), format.Get(), width,
          height, layout.GetAddressOf()))) {
    return false;
  }
  const D2D1_COLOR_F brush_color = {
      GetRValue(color) / 255.0f, GetGValue(color) / 255.0f,
      GetBValue(color) / 255.0f, 1.0f};
  ComPtr<ID2D1SolidColorBrush> brush;
  if (FAILED(render_target->CreateSolidColorBrush(
          &brush_color, nullptr, brush.GetAddressOf()))) {
    return false;
  }

  render_target->BeginDraw();
  render_target->PushAxisAlignedClip(
      D2D1_RECT_F{static_cast<float>(clip_bounds.left),
                  static_cast<float>(clip_bounds.top),
                  static_cast<float>(clip_bounds.right),
                  static_cast<float>(clip_bounds.bottom)},
      D2D1_ANTIALIAS_MODE_ALIASED);
  render_target->DrawTextLayout(
      D2D1_POINT_2F{static_cast<float>(text_bounds.left),
                    static_cast<float>(text_bounds.top)},
      layout.Get(), brush.Get(), D2D1_DRAW_TEXT_OPTIONS_CLIP);
  render_target->PopAxisAlignedClip();
  return SUCCEEDED(render_target->EndDraw());
}

struct CapsulePalette {
  COLORREF paper;
  COLORREF border;
  COLORREF text;
  COLORREF weak;
  COLORREF active;
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
      dark ? RGB(168, 142, 106) : RGB(140, 115, 80),
      dark ? RGB(230, 223, 211) : RGB(120, 92, 48),
  };
  if (color_scheme == "forest") {
    palette = {
        dark ? RGB(26, 30, 27) : RGB(243, 248, 241),
        dark ? RGB(58, 70, 60) : RGB(200, 218, 198),
        dark ? RGB(220, 228, 220) : RGB(38, 50, 42),
        dark ? RGB(134, 148, 136) : RGB(110, 128, 112),
        dark ? RGB(124, 168, 134) : RGB(88, 130, 96),
        dark ? RGB(180, 208, 186) : RGB(70, 110, 80),
    };
  } else if (color_scheme == "rose") {
    palette = {
        dark ? RGB(33, 28, 30) : RGB(253, 245, 246),
        dark ? RGB(78, 64, 68) : RGB(228, 205, 210),
        dark ? RGB(232, 220, 223) : RGB(54, 38, 42),
        dark ? RGB(152, 132, 137) : RGB(140, 114, 120),
        dark ? RGB(190, 134, 148) : RGB(158, 104, 118),
        dark ? RGB(224, 180, 190) : RGB(150, 80, 96),
    };
  } else if (color_scheme == "ink") {
    palette = {
        dark ? RGB(26, 28, 32) : RGB(246, 247, 249),
        dark ? RGB(60, 66, 76) : RGB(208, 214, 222),
        dark ? RGB(222, 227, 234) : RGB(38, 44, 54),
        dark ? RGB(138, 146, 158) : RGB(118, 126, 138),
        dark ? RGB(132, 156, 188) : RGB(90, 108, 134),
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
  palette.active = active;
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
  SetPropW(window, kCapsuleAlphaProperty,
           reinterpret_cast<HANDLE>(static_cast<INT_PTR>(current_alpha_ + 1)));
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void NativeCapsuleWindow::ApplySurface(
    const flutter::EncodableMap& surface,
    ULONGLONG animation_epoch) {
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
  if (!hide_when_covered_) {
    covering_window_ = nullptr;
  }
  hide_when_fullscreen_ =
      BoolValue(surface, "hideWhenFullscreen", hide_when_fullscreen_);
  animations_enabled_ =
      BoolValue(surface, "enableAnimations", animations_enabled_);
  if (!animations_enabled_ && queue_drag_animation_active_) {
    // The setting change must also settle an animation that was already
    // armed.  Leaving its timer alive after the setting is disabled lets an
    // old easing curve overwrite the newly committed capsule position; merely
    // killing that timer would instead leave the HWND at an intermediate slot.
    CompleteQueueDragAnimationAtTarget();
  }
  theme_ = StringValue(surface, "theme", theme_);
  color_scheme_ = StringValue(surface, "colorScheme", color_scheme_);
  custom_theme_color_hex_ = StringValue(
      surface, "customThemeColorHex", custom_theme_color_hex_);
  font_family_ = StringValue(surface, "fontFamily", font_family_);
  ui_font_preset_ =
      StringValue(surface, "uiFontPreset", ui_font_preset_);
  system_font_family_name_ = StringValue(
      surface, "systemFontFamilyName", system_font_family_name_);

  if (previous_capsule_side != capsule_side_ ||
      previous_monitor_device_name != monitor_device_name_) {
    queue_drag_offset_active_ = false;
    queue_drag_last_delta_y_ = 0;
    ResumeMasterTransitionAfterQueueDrag();
    queue_drag_master_transition_coupled_ = false;
    ClearCommittedQueueDrag();
    queue_drag_animation_active_ = false;
    if (HWND window = GetHandle()) {
      KillTimer(window, kCapsuleQueueFollowTimerId);
    }
  }

  if (!master_ && capsule_hidden_by_master_ && !previous_master_hidden) {
    // The pointer may still be logically hovering when the master starts to
    // retract this no-activate HWND. Clear the transient width/close state now
    // so the next expansion begins from one stable resting frame.
    ResetHoverAnimationForHiddenState();
  }

  // A master collapse hides an existing proxy HWND instead of destroying it.
  // Reset transient hover/slide state while hidden so expansion starts from a
  // stable resting width and never paints one stale hover frame.
  if (!intended_visible_ && previous_intended_visible) {
    ResetHoverAnimationForHiddenState();
    master_transition_active_ = false;
    master_transition_initialized_ = false;
    master_retracted_ = false;
    queue_drag_offset_active_ = false;
    queue_drag_last_delta_y_ = 0;
    queue_drag_master_transition_coupled_ = false;
    queue_drag_master_transition_paused_at_ = 0;
    ClearCommittedQueueDrag();
    ApplyMasterTransitionAlpha(255);
    if (HWND window = GetHandle()) {
      KillTimer(window, kCapsuleSlideTimerId);
      KillTimer(window, kCapsuleMasterTransitionTimerId);
    }
  }

  const UINT previous_dpi = dpi_;
  ResolveWorkArea();
  const int raw_docked_top = DockedTopPhysical();
  const int raw_master_top = master_ ? raw_docked_top : MasterTopPhysical();
  ReconcileCommittedQueueModel(raw_docked_top, raw_master_top);
  const std::wstring label = EffectiveLabel();
  const bool chinese_locale = IsChineseLocale();
  const std::wstring master_idle_label =
      master_ ? Utf8ToWide(chinese_locale ? label_zh_ : label_en_)
              : std::wstring();
  const std::wstring master_active_label =
      master_ ? Utf8ToWide(chinese_locale ? count_label_zh_ : count_label_en_)
              : std::wstring();
  const std::wstring master_measurement_font =
      master_ ? MasterMeasurementFontFamily(chinese_locale) : std::wstring();
  const double master_label_width =
      master_ ? std::max(MeasureWpfTextWidth(master_idle_label, 11, FW_NORMAL,
                                             master_measurement_font),
                         MeasureWpfTextWidth(master_active_label, 11, FW_NORMAL,
                                             master_measurement_font))
              : 0.0;
  const int label_width = master_ ? 0 : MeasureLabelWidth(label);
  const std::wstring glyph = master_
                                 ? (active_ ? L"\u25B8" : L"\u25BE")
                                 : (script_capsule_
                                        ? L"\u26A1"
                                        : (paper_type_ == "note" ? L"\u270E"
                                                                    : L"\u2713"));
  const int glyph_font_size = master_ ? 12 : (script_capsule_ ? 15 : 13);
  const int glyph_width = MeasureTextWidth(
      glyph, glyph_font_size, FW_SEMIBOLD, L"Segoe UI Symbol");
  const double master_peek_glyph_width =
      master_
          ? std::max(MeasureWpfTextWidth(L"\u25BE", 12, FW_SEMIBOLD,
                                        L"Segoe UI Symbol"),
                     MeasureWpfTextWidth(L"\u25B8", 12, FW_SEMIBOLD,
                                        L"Segoe UI Symbol"))
          : 0.0;
  // Ordinary proxy labels still use their capture-calibrated GDI-to-WPF
  // correction. The master uses DirectWrite advances and rounds only after
  // adding every source padding, matching WPF FormattedText for each locale
  // and selected Windows font instead of relying on one fixed correction.
  const int wpf_metric_correction =
      script_capsule_ ? -2 : (paper_type_ == "note" ? -1 : -3);
  const int logical_full_width = master_
                                     ? std::max(1, static_cast<int>(std::ceil(
                                                       35.0 +
                                                       master_peek_glyph_width +
                                                       master_label_width)))
                                     : std::max(
                                           92, 62 + glyph_width + label_width +
                                                   wpf_metric_correction);
  const double master_leading_label_width =
      master_
          ? std::max(
                master_idle_label.empty()
                    ? 0.0
                    : MeasureWpfTextWidth(master_idle_label.substr(0, 1), 11,
                                          FW_NORMAL, master_measurement_font),
                master_active_label.empty()
                    ? 0.0
                    : MeasureWpfTextWidth(master_active_label.substr(0, 1), 11,
                                          FW_NORMAL, master_measurement_font))
          : 0.0;
  const int logical_resting_visible_width = master_
                                                 ? std::clamp(
                                                       static_cast<int>(
                                                           std::lround(
                                                               29.0 +
                                                               master_peek_glyph_width +
                                                               master_leading_label_width)),
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
  // Update the clip before a retarget can snap/reposition the HWND. This keeps
  // a disabled-animation surface refresh from composing one frame with the
  // new bounds but the previous title-width region.
  ApplyWindowRegion();
  const int desired_visible_width = TargetVisibleWidth();
  if (previous_dpi != dpi_ || current_visible_width_ <= 0.0 ||
      !dock_animation_active_) {
    current_visible_width_ = desired_visible_width;
    animation_target_visible_width_ = desired_visible_width;
  } else {
    current_visible_width_ = std::clamp(
        current_visible_width_, 1.0, static_cast<double>(full_width_));
    // Surface refreshes can change the measured title/font widths during a
    // hover reveal. Retarget from the currently composed width; keeping the
    // old start time while only swapping the endpoint makes the next timer
    // frame jump. The same path cancels an in-flight reveal immediately when
    // the user confirms that animations should be disabled.
    if (!animations_enabled_ ||
        std::abs(animation_target_visible_width_ -
                 desired_visible_width) >= 0.5) {
      StartDockAnimation(
          desired_visible_width,
          hovered_ ? kCapsuleSlideOutMilliseconds
                   : kCapsuleSlideInMilliseconds);
    } else {
      animation_target_visible_width_ = desired_visible_width;
    }
  }
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
            SetWindowPos(window, nullptr, bounds.left,
                         EffectiveMasterTopPhysical(), 0, 0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                             SWP_NOOWNERZORDER);
          }
        }
      }
    } else if (previous_master_hidden != capsule_hidden_by_master_) {
      StartMasterTransition(
          capsule_hidden_by_master_ ? EffectiveMasterTopPhysical()
                                     : EffectiveDockedTopPhysical(),
          capsule_hidden_by_master_,
          animations_enabled_ ? kCapsuleMasterMoveMilliseconds : 0,
          animations_enabled_ ? kCapsuleMasterFadeMilliseconds : 0,
          animation_epoch);
    } else if (master_transition_active_) {
      // Retarget a transition when the master is dragged or the queue is
      // reordered while the fade is still running. Keep the current frame and
      // only change its destination; restarting from the old slot causes a
      // visible backwards hop.
      if (!queue_drag_offset_active_) {
        master_transition_target_top_ = capsule_hidden_by_master_
                                            ? static_cast<double>(
                                                  EffectiveMasterTopPhysical())
                                            : static_cast<double>(
                                                  EffectiveDockedTopPhysical());
      }
      if (!animations_enabled_) {
        // Settings can disable animations while this transition is between
        // timer ticks.  Snap the retained HWND and alpha together instead of
        // allowing the stale timer to present a half-retracted frame.
        CompleteMasterTransitionAtTarget();
      }
    } else if (master_retracted_ && !queue_drag_offset_active_) {
      if (HWND window = GetHandle()) {
        RECT bounds = {};
        if (GetWindowRect(window, &bounds) &&
            bounds.top != EffectiveMasterTopPhysical()) {
          SetWindowPos(window, nullptr, bounds.left,
                       EffectiveMasterTopPhysical(), 0, 0,
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
  // UpdateLayeredWindow supplies the antialiased per-pixel shape. A Win32
  // region clips that fractional alpha back to a staircase, which is exactly
  // the rough edge visible in the old GDI capsule captures.
  SetWindowRgn(window, nullptr, FALSE);
}

int NativeCapsuleWindow::TargetVisibleWidth() const {
  // Native proxies represent an expanded paper's reserved edge slot. PaperTodo
  // renders that slot in its active/focus-width presentation even after the
  // pointer leaves; only an inactive proxy would use the half-hidden resting
  // width. Master capsules keep their own fixed peek width.
  return (!master_ && active_) || hovered_ ? hover_visible_width_
                                           : resting_visible_width_;
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
  RECT current = {};
  if (!GetWindowRect(window, &current)) {
    return;
  }
  // Hover/reveal animation owns only the horizontal edge exposure. During a
  // master queue drag, replaying EffectiveDockedTopPhysical here resets the
  // child to its pre-drag slot between two atomic DeferWindowPos frames. Keep
  // the coordinator-owned live Y while continuing to animate X normally.
  const int y = queue_drag_offset_active_ ? current.top
                                          : EffectiveDockedTopPhysical();
  if (current.left == x && current.top == y &&
      current.right - current.left == full_width_ &&
      current.bottom - current.top == height_) {
    return;
  }
  SetWindowPos(window, nullptr, x, y, full_width_, height_,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOREDRAW);
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

int NativeCapsuleWindow::QueueDragModelOffsetY() const {
  return queue_drag_commit_pending_ ? queue_drag_committed_delta_y_ : 0;
}

int NativeCapsuleWindow::EffectiveDockedTopPhysical() const {
  return DockedTopPhysical() + QueueDragModelOffsetY();
}

int NativeCapsuleWindow::EffectiveMasterTopPhysical() const {
  return MasterTopPhysical() + QueueDragModelOffsetY();
}

void NativeCapsuleWindow::CaptureQueueDragModelAnchors() {
  if (queue_drag_commit_pending_) {
    return;
  }
  queue_drag_model_base_docked_top_ = DockedTopPhysical();
  queue_drag_model_base_master_top_ =
      master_ ? queue_drag_model_base_docked_top_ : MasterTopPhysical();
}

void NativeCapsuleWindow::ReconcileCommittedQueueModel(int docked_top,
                                                       int master_top) {
  if (!queue_drag_commit_pending_) {
    return;
  }
  constexpr int kPositionTolerance = 2;
  const int docked_change =
      docked_top - queue_drag_model_base_docked_top_;
  const int master_change =
      master_top - queue_drag_model_base_master_top_;
  const bool unchanged = std::abs(docked_change) <= kPositionTolerance &&
                         std::abs(master_change) <= kPositionTolerance;
  const bool acknowledged =
      std::abs(docked_change - queue_drag_committed_delta_y_) <=
          kPositionTolerance ||
      std::abs(master_change - queue_drag_committed_delta_y_) <=
          kPositionTolerance;
  if (!unchanged || acknowledged) {
    ClearCommittedQueueDrag();
    queue_drag_model_base_docked_top_ = docked_top;
    queue_drag_model_base_master_top_ = master_top;
  }
}

void NativeCapsuleWindow::ClearCommittedQueueDrag() {
  queue_drag_commit_pending_ = false;
  queue_drag_committed_delta_y_ = 0;
}

void NativeCapsuleWindow::ApplyMasterTransitionAlpha(int alpha) {
  const int next_alpha = std::clamp(alpha, 0, 255);
  if (current_alpha_ == next_alpha) {
    return;
  }
  current_alpha_ = next_alpha;
  if (HWND window = GetHandle()) {
    SetPropW(window, kCapsuleAlphaProperty,
             reinterpret_cast<HANDLE>(
                 static_cast<INT_PTR>(current_alpha_ + 1)));
    if (IsWindowVisible(window)) {
      RenderLayeredWindow(window);
    }
  }
}

void NativeCapsuleWindow::CompleteMasterTransitionAtTarget() {
  HWND window = GetHandle();
  master_transition_active_ = false;
  queue_drag_master_transition_paused_at_ = 0;
  master_retracted_ = master_transition_target_hidden_;
  if (window) {
    KillTimer(window, kCapsuleMasterTransitionTimerId);
    RECT bounds = {};
    if (GetWindowRect(window, &bounds)) {
      SetWindowPos(
          window, nullptr, bounds.left,
          static_cast<int>(std::lround(master_transition_target_top_)), 0, 0,
          SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER |
              SWP_NOREDRAW);
    }
  }
  ApplyMasterTransitionAlpha(master_transition_target_alpha_);
  // A horizontal reveal may have been running while the child travelled
  // between the docked and master slots.  Apply its current width after the
  // vertical transition is settled so the final frame cannot retain the old
  // edge position.
  if (!master_retracted_) {
    ApplyDockedPosition();
  }
}

void NativeCapsuleWindow::StartMasterTransition(int target_top,
                                                bool target_hidden,
                                                int move_duration_ms,
                                                int fade_duration_ms,
                                                ULONGLONG animation_epoch) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return;

  master_transition_target_hidden_ = target_hidden;
  master_transition_start_top_ = static_cast<double>(bounds.top);
  master_transition_target_top_ = static_cast<double>(
      target_top +
      (queue_drag_offset_active_ ? queue_drag_last_delta_y_ : 0));
  if (queue_drag_offset_active_) {
    queue_drag_master_transition_coupled_ = true;
  }
  master_transition_start_alpha_ = current_alpha_;
  master_transition_target_alpha_ = target_hidden ? 0 : 255;
  // A transition armed while a queue drag is already active must start its
  // clock at the frozen drag frame. Reusing an older animation epoch would
  // make ResumeMasterTransitionAfterQueueDrag see the whole pre-drag delay as
  // elapsed and snap the child to its endpoint on release.
  master_transition_started_at_ = queue_drag_offset_active_
                                      ? GetTickCount64()
                                      : (animation_epoch > 0
                                             ? animation_epoch
                                             : GetTickCount64());
  master_transition_move_duration_ms_ = std::max(0, move_duration_ms);
  master_transition_fade_duration_ms_ = std::max(0, fade_duration_ms);
  master_transition_active_ = false;

  if (target_hidden) {
    // Keep the HWND visible while it travels to the master slot. It becomes
    // hit-test transparent as soon as the target is a retracted state.
    master_retracted_ = false;
  } else {
    master_retracted_ = true;
    // Paint the destination state while the retained HWND is still fully
    // transparent. RefreshVisibility will reveal it with the correct z-order
    // in one transaction after this method returns.
    RedrawWindow(window, nullptr, nullptr,
                 RDW_INVALIDATE | RDW_UPDATENOW | RDW_NOERASE);
  }

  if (!animations_enabled_ ||
      std::max(master_transition_move_duration_ms_,
               master_transition_fade_duration_ms_) <= 0 ||
      (std::abs(master_transition_start_top_ -
                master_transition_target_top_) < 0.5 &&
       master_transition_start_alpha_ == master_transition_target_alpha_)) {
    CompleteMasterTransitionAtTarget();
    // ApplySurface owns the single visibility/z-order pass for an immediate
    // transition. Refreshing here and again at the end of that transaction
    // briefly exposes two show/restack compositions.
    return;
  }

  master_transition_active_ = true;
  if (queue_drag_offset_active_) {
    // A master drag owns the vertical position of every queue member. Arm the
    // transition but freeze its clock until the gesture ends, otherwise its
    // 16 ms timer adds an independent vertical delta between atomic drag
    // frames and the child visibly lags behind the master.
    queue_drag_master_transition_coupled_ = true;
    queue_drag_master_transition_paused_at_ = GetTickCount64();
    KillTimer(window, kCapsuleMasterTransitionTimerId);
  } else {
    SetTimer(window, kCapsuleMasterTransitionTimerId,
             kAnimationFrameMilliseconds, nullptr);
  }
}

void NativeCapsuleWindow::UpdateMasterTransition() {
  if (!master_transition_active_ ||
      queue_drag_master_transition_paused_at_ != 0) {
    return;
  }
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed = GetTickCount64() - master_transition_started_at_;
  const double move_progress = AnimationProgress(
      elapsed, master_transition_move_duration_ms_);
  const double fade_progress = AnimationProgress(
      elapsed, master_transition_fade_duration_ms_);
  const double move_eased = EaseOutCubic(move_progress);
  const double fade_eased = EaseOutCubic(fade_progress);
  RECT bounds = {};
  if (!GetWindowRect(window, &bounds)) return;
  const int top = static_cast<int>(std::lround(
      master_transition_start_top_ +
      (master_transition_target_top_ - master_transition_start_top_) *
          move_eased));
  const int alpha = static_cast<int>(std::lround(
      master_transition_start_alpha_ +
      (master_transition_target_alpha_ - master_transition_start_alpha_) *
          fade_eased));
  SetWindowPos(window, nullptr, bounds.left, top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER | SWP_NOREDRAW);
  ApplyMasterTransitionAlpha(alpha);
  if (move_progress >= 1.0 && fade_progress >= 1.0) {
    CompleteMasterTransitionAtTarget();
    RefreshVisibility();
  }
}

void NativeCapsuleWindow::PauseMasterTransitionForQueueDrag() {
  if (!master_transition_active_ ||
      queue_drag_master_transition_paused_at_ != 0) {
    return;
  }
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) {
    return;
  }

  // Freeze the frame that DWM has actually presented. Calling
  // UpdateMasterTransition here advances the child by one timer interval
  // before the first atomic queue move, so a drag that begins during a master
  // reveal/retract starts with an observable 8-12 px child-only jump.
  const ULONGLONG paused_at = GetTickCount64();
  const ULONGLONG elapsed =
      paused_at >= master_transition_started_at_
          ? paused_at - master_transition_started_at_
          : 0;
  const auto remaining_duration = [elapsed](int duration,
                                             bool value_not_at_target) {
    if (!value_not_at_target) {
      return 0;
    }
    if (duration <= 0 || elapsed >= static_cast<ULONGLONG>(duration)) {
      return kAnimationFrameMilliseconds;
    }
    return std::max(1, duration - static_cast<int>(elapsed));
  };
  master_transition_move_duration_ms_ = remaining_duration(
      master_transition_move_duration_ms_,
      std::abs(static_cast<double>(bounds.top) -
               master_transition_target_top_) >= 0.5);
  master_transition_fade_duration_ms_ = remaining_duration(
      master_transition_fade_duration_ms_,
      current_alpha_ != master_transition_target_alpha_);
  master_transition_start_top_ = static_cast<double>(bounds.top);
  master_transition_start_alpha_ = current_alpha_;
  master_transition_started_at_ = paused_at;
  if (master_transition_move_duration_ms_ <= 0 &&
      master_transition_fade_duration_ms_ <= 0) {
    CompleteMasterTransitionAtTarget();
    return;
  }
  queue_drag_master_transition_paused_at_ = paused_at;
  queue_drag_master_transition_coupled_ = true;
  KillTimer(window, kCapsuleMasterTransitionTimerId);
}

void NativeCapsuleWindow::ResumeMasterTransitionAfterQueueDrag() {
  const ULONGLONG paused_at = queue_drag_master_transition_paused_at_;
  if (paused_at == 0) {
    return;
  }
  const ULONGLONG now = GetTickCount64();
  if (now >= paused_at) {
    master_transition_started_at_ += now - paused_at;
  }
  queue_drag_master_transition_paused_at_ = 0;
  if (master_transition_active_) {
    if (HWND window = GetHandle()) {
      SetTimer(window, kCapsuleMasterTransitionTimerId,
               kAnimationFrameMilliseconds, nullptr);
    }
  }
}

void NativeCapsuleWindow::SetHovered(bool hovered) {
  if (dragging_) return;
  HWND window = GetHandle();
  const bool hidden_by_transition =
      !master_ &&
      (capsule_hidden_by_master_ || master_retracted_ ||
       (master_transition_active_ && master_transition_target_hidden_));
  if (!master_ &&
      (!intended_visible_ || hidden_by_transition ||
       (window && !IsWindowVisible(window)))) {
    // A Flutter/native hover message can remain queued after the master
    // capsule has started retracting, or after this HWND was hidden by the
    // fullscreen/covered policy. Never let that stale message restart the
    // edge reveal timer while the capsule is not interactive.
    ResetHoverAnimationForHiddenState();
    return;
  }
  if (hovered_ == hovered) return;
  hovered_ = hovered;
  const int target = TargetVisibleWidth();
  if (animations_enabled_ && !master_) {
    StartDockAnimation(
        target, hovered_ ? kCapsuleSlideOutMilliseconds
                         : kCapsuleSlideInMilliseconds);
  } else {
    if (window) {
      KillTimer(window, kCapsuleSlideTimerId);
    }
    dock_animation_active_ = false;
    current_visible_width_ = target;
    ApplyDockedPosition();
  }
  if (window) InvalidateRect(window, nullptr, FALSE);
}

void NativeCapsuleWindow::ResetHoverAnimationForHiddenState() {
  hovered_ = false;
  close_hovered_ = false;
  close_pressed_ = false;
  pointer_down_ = false;
  tracking_mouse_leave_ = false;
  dock_animation_active_ = false;
  animation_duration_ms_ = 0;
  animation_start_visible_width_ = 0.0;
  animation_target_visible_width_ = 0.0;
  current_visible_width_ = 0.0;
  if (HWND window = GetHandle()) {
    if (GetCapture() == window) {
      // Keep dragging_ set until WM_CAPTURECHANGED has had a chance to emit a
      // cancelled master-drag transaction. Clearing it before ReleaseCapture
      // would strand the rest of the capsule queue at its live drag offset.
      ReleaseCapture();
    }
    KillTimer(window, kCapsuleSlideTimerId);
  }
  dragging_ = false;
}

void NativeCapsuleWindow::StartDockAnimation(int target_visible_width,
                                             int duration_ms) {
  HWND window = GetHandle();
  if (!window) return;
  const double target = std::clamp(
      static_cast<double>(target_visible_width), 1.0,
      static_cast<double>(full_width_));
  if (!animations_enabled_ ||
      std::abs(current_visible_width_ - target) < 0.5 || duration_ms <= 0) {
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
  SetTimer(window, kCapsuleSlideTimerId, kAnimationFrameMilliseconds,
           nullptr);
}

void NativeCapsuleWindow::UpdateDockAnimation() {
  if (!dock_animation_active_) return;
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed = GetTickCount64() - animation_started_at_;
  const double progress = AnimationProgress(elapsed, animation_duration_ms_);
  const double eased = EaseOutCubic(progress);
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

void NativeCapsuleWindow::BeginQueueDrag() {
  if (queue_drag_offset_active_) return;
  HWND window = GetHandle();
  if (!window) return;

  // Freeze an in-flight collapse-all transition at mouse-down, before the
  // pointer has crossed USER32's drag threshold. Waiting for the first
  // WM_MOUSEMOVE lets a child consume one more 16 ms transition frame while
  // the master remains still, which permanently bends the queue by 8-12 px.
  PauseMasterTransitionForQueueDrag();

  RECT bounds = {};
  if (!GetWindowRect(window, &bounds)) {
    ResumeMasterTransitionAfterQueueDrag();
    return;
  }
  queue_drag_offset_active_ = true;
  queue_drag_base_top_ = bounds.top;
  queue_drag_target_top_ = bounds.top;
  queue_drag_last_delta_y_ = 0;
  queue_drag_master_transition_coupled_ =
      master_transition_active_ ||
      queue_drag_master_transition_paused_at_ != 0;
  CaptureQueueDragModelAnchors();
  KillTimer(window, kCapsuleQueueFollowTimerId);
  queue_drag_animation_active_ = false;
}

bool NativeCapsuleWindow::PrepareMasterDragTop(int target_top,
                                               RECT* target_bounds) {
  if (!master_ || !target_bounds) return false;
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) return false;
  if (!queue_drag_offset_active_) {
    BeginQueueDrag();
    if (!queue_drag_offset_active_) return false;
    if (!GetWindowRect(window, &bounds)) return false;
  }
  queue_drag_target_top_ = target_top;
  queue_drag_last_delta_y_ = target_top - queue_drag_base_top_;
  KillTimer(window, kCapsuleQueueFollowTimerId);
  queue_drag_animation_active_ = false;
  *target_bounds = bounds;
  const int height = bounds.bottom - bounds.top;
  target_bounds->top = target_top;
  target_bounds->bottom = target_top + height;
  return bounds.top != target_top;
}

bool NativeCapsuleWindow::PrepareQueueDragOffset(int delta_y,
                                                 RECT* target_bounds) {
  if (master_ || !target_bounds) return false;
  HWND window = GetHandle();
  if (!window) return false;
  if (!queue_drag_offset_active_) {
    BeginQueueDrag();
    if (!queue_drag_offset_active_) return false;
  }
  RECT bounds = {};
  if (!GetWindowRect(window, &bounds)) return false;
  const int incremental_delta = delta_y - queue_drag_last_delta_y_;
  queue_drag_last_delta_y_ = delta_y;
  queue_drag_target_top_ = bounds.top + incremental_delta;
  if (master_transition_active_) {
    queue_drag_master_transition_coupled_ = true;
  }
  if (queue_drag_master_transition_coupled_) {
    // A child can still be travelling into or out of the master slot when a
    // master drag begins. Translate the whole animation coordinate system by
    // the pointer delta so its timer and the atomic queue move produce the
    // same visual frame instead of fighting over the HWND top coordinate.
    master_transition_start_top_ += incremental_delta;
    master_transition_target_top_ += incremental_delta;
  }
  // A master drag is one physical gesture, so every child must share the
  // master's exact frame instead of starting a separate easing curve on each
  // WM_MOUSEMOVE.  Independent 64 ms curves accumulated visible lag and made
  // the queue appear elastic or backwards when the pointer changed direction.
  KillTimer(window, kCapsuleQueueFollowTimerId);
  queue_drag_animation_active_ = false;
  *target_bounds = bounds;
  const int height = bounds.bottom - bounds.top;
  target_bounds->top = queue_drag_target_top_;
  target_bounds->bottom = queue_drag_target_top_ + height;
  return bounds.top != queue_drag_target_top_;
}

void NativeCapsuleWindow::ApplyQueueDragOffset(int delta_y) {
  RECT target_bounds = {};
  if (!PrepareQueueDragOffset(delta_y, &target_bounds)) return;
  HWND window = GetHandle();
  if (!window) return;
  SetWindowPos(window, nullptr, target_bounds.left, target_bounds.top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER | SWP_NOREDRAW);
}

void NativeCapsuleWindow::FinishQueueDrag(bool commit) {
  if (!queue_drag_offset_active_) return;
  int target_top = commit ? queue_drag_target_top_ : queue_drag_base_top_;
  if (!commit && queue_drag_master_transition_coupled_) {
    master_transition_start_top_ -= queue_drag_last_delta_y_;
    master_transition_target_top_ -= queue_drag_last_delta_y_;
    RECT bounds = {};
    if (HWND window = GetHandle(); window && GetWindowRect(window, &bounds)) {
      // Remove the cancelled gesture from both the current HWND frame and the
      // transition endpoints. Let the still-running master transition resume
      // from that coherent frame; a second queue animation would otherwise
      // compete with the master timer and reintroduce the backwards hop.
      target_top = master_transition_active_
                       ? bounds.top - queue_drag_last_delta_y_
                       : static_cast<int>(
                             std::lround(master_transition_target_top_));
      if (master_transition_active_) {
        ApplyQueueDragTop(target_top);
      }
    }
  }
  if (commit) {
    if (HWND window = GetHandle()) {
      KillTimer(window, kCapsuleQueueFollowTimerId);
    }
    queue_drag_animation_active_ = false;
    ApplyQueueDragTop(target_top);
    queue_drag_committed_delta_y_ += queue_drag_last_delta_y_;
    queue_drag_commit_pending_ = queue_drag_committed_delta_y_ != 0;
  } else if (!master_transition_active_) {
    StartQueueDragAnimation(target_top, kCapsuleQueueMoveMilliseconds);
  }
  queue_drag_offset_active_ = false;
  queue_drag_last_delta_y_ = 0;
  ResumeMasterTransitionAfterQueueDrag();
  queue_drag_master_transition_coupled_ = false;
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
  SetTimer(window, kCapsuleQueueFollowTimerId,
           kAnimationFrameMilliseconds, nullptr);
}

void NativeCapsuleWindow::UpdateQueueDragAnimation() {
  if (!queue_drag_animation_active_) return;
  HWND window = GetHandle();
  if (!window) return;
  const ULONGLONG elapsed =
      GetTickCount64() - queue_drag_animation_started_at_;
  const double progress = AnimationProgress(
      elapsed, queue_drag_animation_duration_ms_);
  const double eased = EaseOutCubic(progress);
  const int top = static_cast<int>(std::lround(
      queue_drag_animation_start_top_ +
      (queue_drag_animation_target_top_ - queue_drag_animation_start_top_) *
          eased));
  ApplyQueueDragTop(top);
  if (progress >= 1.0) {
    CompleteQueueDragAnimationAtTarget();
  }
}

void NativeCapsuleWindow::CompleteQueueDragAnimationAtTarget() {
  if (!queue_drag_animation_active_) {
    return;
  }
  const int target_top = static_cast<int>(
      std::lround(queue_drag_animation_target_top_));
  queue_drag_animation_active_ = false;
  queue_drag_animation_duration_ms_ = 0;
  if (HWND window = GetHandle()) {
    KillTimer(window, kCapsuleQueueFollowTimerId);
  }
  ApplyQueueDragTop(target_top);
}

void NativeCapsuleWindow::ApplyQueueDragTop(int top) {
  HWND window = GetHandle();
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds) || bounds.top == top) return;
  SetWindowPos(window, nullptr, bounds.left, top, 0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_NOOWNERZORDER | SWP_NOREDRAW);
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
  if (family.empty()) family = L"Microsoft YaHei UI";
  if (family.size() >= LF_FACESIZE) family.resize(LF_FACESIZE - 1);
  return family;
}

std::wstring NativeCapsuleWindow::MasterMeasurementFontFamily(
    bool chinese_locale) const {
  std::wstring system_family = Utf8ToWide(system_font_family_name_);
  if (!system_family.empty()) {
    return system_family;
  }

  if (chinese_locale) {
    if (ui_font_preset_ == "yahei") return L"Microsoft YaHei UI";
    if (ui_font_preset_ == "dengxian") return L"DengXian";
  } else if (ui_font_preset_ == "default" || ui_font_preset_ == "yahei" ||
             ui_font_preset_ == "dengxian") {
    // PaperTodo's three source presets all put Segoe UI first, so Latin master
    // labels retain its advance even when the CJK fallback changes.
    return L"Segoe UI";
  }
  return EffectiveFontFamily();
}

double NativeCapsuleWindow::MeasureWpfTextWidth(
    const std::wstring& value, int logical_font_size, int font_weight,
    const std::wstring& font_family) const {
  if (value.empty()) return 0.0;

  using Microsoft::WRL::ComPtr;
  ComPtr<IDWriteFactory> factory;
  if (FAILED(DWriteCreateFactory(
          DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
          reinterpret_cast<IUnknown**>(factory.GetAddressOf())))) {
    return static_cast<double>(MeasureTextWidth(
        value, logical_font_size, font_weight, font_family));
  }

  wchar_t locale_name[LOCALE_NAME_MAX_LENGTH] = {};
  if (GetUserDefaultLocaleName(locale_name,
                               static_cast<int>(std::size(locale_name))) <= 0) {
    wcscpy_s(locale_name, L"en-US");
  }
  ComPtr<IDWriteTextFormat> format;
  if (FAILED(factory->CreateTextFormat(
          font_family.c_str(), nullptr,
          static_cast<DWRITE_FONT_WEIGHT>(font_weight),
          DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
          static_cast<float>(logical_font_size), locale_name,
          format.GetAddressOf()))) {
    return static_cast<double>(MeasureTextWidth(
        value, logical_font_size, font_weight, font_family));
  }
  format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);

  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(factory->CreateTextLayout(
          value.c_str(), static_cast<UINT32>(value.size()), format.Get(),
          4096.0f, 256.0f, layout.GetAddressOf()))) {
    return static_cast<double>(MeasureTextWidth(
        value, logical_font_size, font_weight, font_family));
  }
  DWRITE_TEXT_METRICS metrics = {};
  if (FAILED(layout->GetMetrics(&metrics))) {
    return static_cast<double>(MeasureTextWidth(
        value, logical_font_size, font_weight, font_family));
  }
  return std::max(0.0, static_cast<double>(
                           metrics.widthIncludingTrailingWhitespace));
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

bool NativeCapsuleWindow::IsPointInsideVisual(POINT client_point) const {
  const bool focus_outline_active = !master_ && active_;
  const bool left = capsule_side_ == "left";
  const double margin = static_cast<double>(ScaleMetric(
      focus_outline_active
          ? kCapsuleChromeMargin - kCapsuleFocusOutlineThickness +
                kCapsuleFocusOutlineOverlap
          : kCapsuleChromeMargin));
  const double visual_left = left ? 0.0 : margin;
  const double visual_right =
      left ? static_cast<double>(full_width_) - margin
           : static_cast<double>(full_width_);
  const double radius = static_cast<double>(ScaleMetric(
      kCapsuleCornerRadius +
      (focus_outline_active ? kCapsuleFocusOutlineThickness -
                                  kCapsuleFocusOutlineOverlap
                            : 0)));
  return PointInsideRoundedRect(
      static_cast<double>(client_point.x) + 0.5,
      static_cast<double>(client_point.y) + 0.5, visual_left, margin,
      visual_right, static_cast<double>(height_) - margin, radius);
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

bool NativeCapsuleWindow::IsCoveredByHigherWindow() {
  HWND window = GetHandle();
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

  const auto still_covers = [&](HWND candidate) {
    if (!candidate || !IsWindow(candidate) || !IsWindowVisible(candidate) ||
        IsIconic(candidate)) {
      return false;
    }
    DWORD process = 0;
    GetWindowThreadProcessId(candidate, &process);
    if (process == own_process) return false;
    RECT candidate_bounds = {};
    RECT intersection = {};
    return GetWindowRect(candidate, &candidate_bounds) &&
           IntersectRect(&intersection, &visible, &candidate_bounds);
  };

  // A hidden capsule no longer has a meaningful place in the visible Z-order.
  // Validate the latched blocker geometrically so a continuously overlapping
  // window keeps the capsule hidden instead of letting it flash back each tick.
  if (covering_window_) {
    if (still_covers(covering_window_)) return true;
    covering_window_ = nullptr;
  }

  // Prefer the active application as a recovery source. When this capsule was
  // hidden on the preceding timer tick, its own HWND no longer has a stable
  // position in the visible Z order, but the window the user is working in
  // remains a reliable blocker.
  HWND foreground = GetForegroundWindow();
  if (foreground != window && still_covers(foreground)) {
    covering_window_ = foreground;
    return true;
  }
  for (HWND candidate = GetWindow(window, GW_HWNDPREV); candidate;
       candidate = GetWindow(candidate, GW_HWNDPREV)) {
    if (still_covers(candidate)) {
      covering_window_ = candidate;
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
  if (!GetCursorPos(&cursor) || !GetWindowRect(window, &bounds) ||
      PtInRect(&bounds, cursor) != TRUE) {
    return false;
  }
  // Geometry alone is insufficient: while another app covers the capsule,
  // the cursor can be inside these stale bounds but actually belong to that
  // app. Only exempt the capsule from hiding when it is the real hit target.
  HWND hit = WindowFromPoint(cursor);
  return hit == window || (hit && IsChild(window, hit));
}

void NativeCapsuleWindow::RefreshVisibility(bool force_master_z_order) {
  HWND window = GetHandle();
  if (!window) return;
  const bool fullscreen = IsExternalFullscreenWindow();
  // Never hide a capsule while the pointer is interacting with it. Because
  // capsule HWNDs are no-activate windows, the previously focused fullscreen
  // or overlapping app can otherwise remain foreground and make the capsule
  // disappear directly under the cursor.
  const bool pointer_over = pointer_down_ || dragging_ || IsPointerOverWindow();
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
      RenderLayeredWindow(window);
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
      (master_ && force_master_z_order)) {
    if (!visible) {
      // Paint the final label, hover state and theme into the hidden HWND
      // before revealing it. Otherwise Windows can briefly present the last
      // cached frame when a master capsule expands its queue.
      RenderLayeredWindow(window);
    }
    SetWindowPos(window, z_order, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                     SWP_NOOWNERZORDER |
                     (visible ? SWP_NOREDRAW : SWP_SHOWWINDOW));
    z_order_initialized_ = true;
    z_order_topmost_ = topmost;
  }
}

void NativeCapsuleWindow::RenderLayeredWindow(HWND window) {
  RECT bounds = {};
  GetClientRect(window, &bounds);
  const int bitmap_width = std::max(1L, bounds.right - bounds.left);
  const int bitmap_height = std::max(1L, bounds.bottom - bounds.top);
  HDC screen = GetDC(nullptr);
  HDC buffer = screen ? CreateCompatibleDC(screen) : nullptr;
  BITMAPINFO bitmap_info = {};
  bitmap_info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bitmap_info.bmiHeader.biWidth = bitmap_width;
  bitmap_info.bmiHeader.biHeight = -bitmap_height;
  bitmap_info.bmiHeader.biPlanes = 1;
  bitmap_info.bmiHeader.biBitCount = 32;
  bitmap_info.bmiHeader.biCompression = BI_RGB;
  void* bitmap_bits = nullptr;
  HBITMAP bitmap =
      screen && buffer
          ? CreateDIBSection(screen, &bitmap_info, DIB_RGB_COLORS,
                             &bitmap_bits, nullptr, 0)
          : nullptr;
  if (!screen || !buffer || !bitmap || !bitmap_bits) {
    if (bitmap) DeleteObject(bitmap);
    if (buffer) DeleteDC(buffer);
    if (screen) ReleaseDC(nullptr, screen);
    return;
  }
  HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);
  auto* pixels = static_cast<uint32_t*>(bitmap_bits);
  std::fill(pixels,
            pixels + static_cast<size_t>(bitmap_width) * bitmap_height, 0u);

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
  // A capsule is a no-activate proxy for another surface.  Painting a
  // separate pressed background here makes the old frame and the following
  // paper/capsule reconciliation compose as a visible flash on Windows 10.
  // Keep click feedback to the stable hover/close affordance instead.

  HBRUSH background_brush = CreateSolidBrush(background);
  HGDIOBJ old_brush = SelectObject(buffer, background_brush);
  HGDIOBJ old_pen = SelectObject(buffer, GetStockObject(NULL_PEN));
  // GDI supplies the existing grayscale text metrics while the post-process
  // below supplies the WPF-like rounded alpha and borders. Filling the whole
  // DIB gives antialiased text a stable paper background; pixels outside the
  // capsule are made fully transparent before UpdateLayeredWindow.
  FillRect(buffer, &bounds, background_brush);
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
    SelectObject(buffer, GetStockObject(NULL_PEN));
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
  constexpr DWORD glyph_quality = ANTIALIASED_QUALITY;
  constexpr DWORD label_quality = ANTIALIASED_QUALITY;
  constexpr int master_label_font_size = 11;
  constexpr int master_label_weight = FW_NORMAL;
  const int glyph_font_size = master_
                                  ? ScaleMetric(12)
                                  : (script_capsule_ ? ScaleMetric(15)
                                                     : ScaleMetric(13));
  HFONT glyph_font = CreateFontW(
      -glyph_font_size, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      glyph_quality, DEFAULT_PITCH, L"Segoe UI Symbol");
  const std::wstring text_font_family = EffectiveFontFamily();
  HFONT text_font = CreateFontW(
      -ScaleMetric(master_ ? master_label_font_size : 11), 0, 0, 0,
      master_ ? master_label_weight : FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      master_ ? label_quality : ANTIALIASED_QUALITY, DEFAULT_PITCH,
      text_font_family.c_str());
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
  if (master_) {
    // Keep the master glyph and label corrections paint-only. The mirrored
    // left glyph needs the same two-pixel reversal as the label; vertical
    // centering remains glyph-specific through the selected Symbol raster.
    OffsetRect(&glyph_rect, ScaleMetric(1), ScaleMetric(1));
    if (left) {
      OffsetRect(&glyph_rect, -ScaleMetric(2), 0);
    }
    OffsetRect(&text_rect, ScaleMetric(1), 0);
  }
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
    RECT master_label_clip = text_rect;
    master_label_clip.top = body_top + ScaleMetric(9);
    master_label_clip.bottom = body_top + ScaleMetric(20);
    const int master_visible_width = static_cast<int>(
        std::lround(std::clamp(current_visible_width_, 1.0,
                               static_cast<double>(full_width_))));
    const int master_text_reserve = ScaleMetric(2);
    if (left) {
      master_label_clip.left = std::max(
          master_label_clip.left,
          static_cast<LONG>(full_width_ - master_visible_width +
                            master_text_reserve));
    } else {
      master_label_clip.right = std::min(
          master_label_clip.right,
          static_cast<LONG>(master_visible_width - master_text_reserve));
    }
    const int master_label_dc = SaveDC(buffer);
    IntersectClipRect(buffer, master_label_clip.left, master_label_clip.top,
                      master_label_clip.right, master_label_clip.bottom);
    RECT directwrite_text_rect = text_rect;
    if (left) {
      OffsetRect(&directwrite_text_rect, -ScaleMetric(2), 0);
    }
    if (active_) {
      OffsetRect(&directwrite_text_rect, 0, -ScaleMetric(1));
    }
    const bool directwrite_drawn =
        DrawMasterLabelDirectWrite(
            buffer, bounds, directwrite_text_rect, master_label_clip, label,
            MasterMeasurementFontFamily(IsChineseLocale()), weak,
            ScaleMetric(master_label_font_size), left);
    if (!directwrite_drawn) {
      DrawTextW(buffer, label.c_str(), static_cast<int>(label.size()),
                &text_rect,
                DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX |
                    (left ? DT_RIGHT : DT_LEFT));
    }
    RestoreDC(buffer, master_label_dc);
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
    const bool directwrite_drawn = DrawMasterLabelDirectWrite(
        buffer, bounds, text_rect, title_clip, label, text_font_family, weak,
        ScaleMetric(11), left);
    if (!directwrite_drawn) {
      DrawTextW(buffer, label.c_str(), static_cast<int>(label.size()),
                &text_rect,
                DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX |
                    (left ? DT_RIGHT : DT_LEFT));
    }
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

  // Build the capsule shape from 4x4 coverage samples. This preserves the
  // source GDI text metrics but replaces both the jagged Win32 region and the
  // jagged GDI RoundRect border with per-pixel alpha. The focus ring remains a
  // separate two-pixel overlay, matching PaperTodo's DeepCapsuleSlotOutline.
  constexpr int kSamplesPerAxis = 4;
  constexpr int kSampleCount = kSamplesPerAxis * kSamplesPerAxis;
  const double body_border_width =
      static_cast<double>(std::max(1, ScaleMetric(1)));
  // WPF Border does not use CornerRadius directly for both edges of a
  // stroke. Its outer and inner stream geometries add/subtract half of the
  // relevant BorderThickness. Reproducing that distinction keeps the
  // antialiased cap from looking one pixel fuller than PaperTodo's pill.
  const double body_corner_radius =
      static_cast<double>(ScaleMetric(kCapsuleCornerRadius));
  const double body_outer_radius =
      body_corner_radius + body_border_width / 2.0;
  const double body_inner_radius =
      std::max(0.0, body_corner_radius - body_border_width / 2.0);
  const bool focus_outline_active = !master_ && active_;
  const double focus_outline_thickness = static_cast<double>(
      std::max(1, ScaleMetric(kCapsuleFocusOutlineThickness)));
  const double focus_outline_margin = static_cast<double>(ScaleMetric(
      kCapsuleChromeMargin - kCapsuleFocusOutlineThickness +
      kCapsuleFocusOutlineOverlap));
  const double focus_corner_radius = static_cast<double>(ScaleMetric(
      kCapsuleCornerRadius + kCapsuleFocusOutlineThickness -
      kCapsuleFocusOutlineOverlap));
  const double focus_outer_radius =
      focus_corner_radius + focus_outline_thickness / 2.0;
  const double focus_inner_radius =
      std::max(0.0,
               focus_corner_radius - focus_outline_thickness / 2.0);
  const double focus_left = left ? 0.0 : focus_outline_margin;
  const double focus_right =
      left ? static_cast<double>(bitmap_width) - focus_outline_margin
           : static_cast<double>(bitmap_width);
  const COLORREF focus_border =
      Mix(palette.active, palette.text, dark ? 38 : 8);
  for (int y = 0; y < bitmap_height; ++y) {
    for (int x = 0; x < bitmap_width; ++x) {
      const size_t index = static_cast<size_t>(y) * bitmap_width + x;
      const uint32_t content_pixel = pixels[index];
      const BYTE content_blue = static_cast<BYTE>(content_pixel & 0xFF);
      const BYTE content_green =
          static_cast<BYTE>((content_pixel >> 8) & 0xFF);
      const BYTE content_red =
          static_cast<BYTE>((content_pixel >> 16) & 0xFF);
      int alpha_samples = 0;
      int red_sum = 0;
      int green_sum = 0;
      int blue_sum = 0;
      for (int sample_y = 0; sample_y < kSamplesPerAxis; ++sample_y) {
        for (int sample_x = 0; sample_x < kSamplesPerAxis; ++sample_x) {
          const double point_x =
              x + (static_cast<double>(sample_x) + 0.5) / kSamplesPerAxis;
          const double point_y =
              y + (static_cast<double>(sample_y) + 0.5) / kSamplesPerAxis;
          bool opaque = false;
          COLORREF sample_color = 0;
          const bool inside_body = PointInsideRoundedRect(
              point_x, point_y, static_cast<double>(body_left),
              static_cast<double>(body_top), static_cast<double>(body_right),
              static_cast<double>(body_bottom), body_outer_radius);
          if (inside_body) {
            const bool inside_body_content = PointInsideRoundedRect(
                point_x, point_y,
                static_cast<double>(body_left) + body_border_width,
                static_cast<double>(body_top) + body_border_width,
                static_cast<double>(body_right) - body_border_width,
                static_cast<double>(body_bottom) - body_border_width,
                body_inner_radius);
            sample_color = inside_body_content
                               ? RGB(content_red, content_green, content_blue)
                               : border;
            opaque = true;
          }
          if (focus_outline_active) {
            const bool inside_focus = PointInsideRoundedRect(
                point_x, point_y, focus_left, focus_outline_margin,
                focus_right,
                static_cast<double>(bitmap_height) - focus_outline_margin,
                focus_outer_radius);
            const bool inside_focus_content = PointInsideRoundedRect(
                point_x, point_y, focus_left + focus_outline_thickness,
                focus_outline_margin + focus_outline_thickness,
                focus_right - focus_outline_thickness,
                static_cast<double>(bitmap_height) - focus_outline_margin -
                    focus_outline_thickness,
                focus_inner_radius);
            if (inside_focus && !inside_focus_content) {
              sample_color = focus_border;
              opaque = true;
            }
          }
          if (!opaque) continue;
          ++alpha_samples;
          red_sum += GetRValue(sample_color);
          green_sum += GetGValue(sample_color);
          blue_sum += GetBValue(sample_color);
        }
      }
      const uint32_t alpha = static_cast<uint32_t>(
          (alpha_samples * 255 + kSampleCount / 2) / kSampleCount);
      const uint32_t red = static_cast<uint32_t>(
          (red_sum + kSampleCount / 2) / kSampleCount);
      const uint32_t green = static_cast<uint32_t>(
          (green_sum + kSampleCount / 2) / kSampleCount);
      const uint32_t blue = static_cast<uint32_t>(
          (blue_sum + kSampleCount / 2) / kSampleCount);
      pixels[index] = blue | (green << 8) | (red << 16) | (alpha << 24);
    }
  }

  RECT window_bounds = {};
  GetWindowRect(window, &window_bounds);
  POINT destination = {window_bounds.left, window_bounds.top};
  POINT source = {0, 0};
  SIZE layer_size = {bitmap_width, bitmap_height};
  BLENDFUNCTION blend = {AC_SRC_OVER, 0,
                         static_cast<BYTE>(current_alpha_), AC_SRC_ALPHA};
  UpdateLayeredWindow(window, screen, &destination, &layer_size, buffer,
                      &source, 0, &blend, ULW_ALPHA);
  SelectObject(buffer, old_font);
  SelectObject(buffer, old_pen);
  SelectObject(buffer, old_brush);
  SelectObject(buffer, old_bitmap);
  DeleteObject(text_font);
  DeleteObject(glyph_font);
  DeleteObject(background_brush);
  DeleteObject(bitmap);
  DeleteDC(buffer);
  ReleaseDC(nullptr, screen);
}

void NativeCapsuleWindow::Paint(HWND window) {
  PAINTSTRUCT paint = {};
  BeginPaint(window, &paint);
  RenderLayeredWindow(window);
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
    case WM_NCHITTEST: {
      if (master_retracted_ ||
          (master_transition_active_ && master_transition_target_hidden_)) {
        return HTTRANSPARENT;
      }
      POINT client_point = {
          static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
          static_cast<LONG>(static_cast<short>(HIWORD(lparam))),
      };
      ScreenToClient(window, &client_point);
      if (!IsPointInsideVisual(client_point)) {
        return HTTRANSPARENT;
      }
      return HTCLIENT;
    }
    case WM_MOUSEACTIVATE:
      // WS_EX_NOACTIVATE is the persistent policy, but explicitly answering
      // the click message prevents USER32 from briefly activating a stale
      // capsule frame on systems that recalculate styles during a show/z-order
      // transaction.
      return MA_NOACTIVATE;
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
                  {flutter::EncodableValue("targetTop"),
                   flutter::EncodableValue(target_top)},
              });
        } else {
          SetWindowPos(window, nullptr, drag_start_bounds_.left, target_top,
                       width, height,
                       SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOREDRAW);
        }
      } else {
        SetWindowPos(window, HWND_TOPMOST,
                     drag_start_bounds_.left + delta_x,
                     drag_start_bounds_.top + delta_y, width, height,
                     SWP_NOACTIVATE | SWP_NOREDRAW);
      }
      return 0;
    }
    case WM_MOUSELEAVE: {
      tracking_mouse_leave_ = false;
      const bool close_visual_changed = close_hovered_;
      close_hovered_ = false;
      const bool hover_changed = !pointer_down_ && hovered_;
      if (!pointer_down_) {
        SetHovered(false);
      }
      RefreshVisibility();
      if (!hover_changed && close_visual_changed) {
        InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    }
    case WM_LBUTTONDOWN: {
      POINT client_point = {
          static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
          static_cast<LONG>(static_cast<short>(HIWORD(lparam))),
      };
      const bool hover_changed = !hovered_;
      const bool previous_close_hovered = close_hovered_;
      const bool previous_close_pressed = close_pressed_;
      pointer_down_ = true;
      close_pressed_ = IsClosePoint(client_point);
      close_hovered_ = close_pressed_;
      dragging_ = false;
      GetCursorPos(&drag_start_cursor_);
      GetWindowRect(window, &drag_start_bounds_);
      SetCapture(window);
      if (master_ && event_callback_) {
        event_callback_(
            "capsuleMasterDragStarted",
            flutter::EncodableMap{
                {flutter::EncodableValue("monitorDeviceName"),
                 flutter::EncodableValue(monitor_device_name_)},
                {flutter::EncodableValue("side"),
                 flutter::EncodableValue(capsule_side_)},
            });
      }
      SetHovered(true);
      if (!hover_changed &&
          (previous_close_hovered != close_hovered_ ||
           previous_close_pressed != close_pressed_)) {
        InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    }
    case WM_LBUTTONUP: {
      if (!pointer_down_) return 0;
      POINT client_point = {
          static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
          static_cast<LONG>(static_cast<short>(HIWORD(lparam))),
      };
      const bool was_dragging = dragging_;
      const bool had_close_press = close_pressed_;
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
        if (master_ && event_callback_) {
          // Mouse-down prepared and froze the whole queue. A normal click is
          // not a drag, so release that preparation before toggleCollapseAll
          // starts the next independent capsule transition.
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
      const bool next_close_hovered =
          cursor_inside && IsClosePoint(client_point);
      const bool close_visual_changed =
          had_close_press || close_hovered_ != next_close_hovered;
      close_hovered_ = next_close_hovered;
      const bool hover_changed = hovered_ != cursor_inside;
      SetHovered(cursor_inside);
      RefreshVisibility();
      if (!hover_changed && close_visual_changed && IsWindowVisible(window)) {
        InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    }
    case WM_CAPTURECHANGED: {
      if (master_ && pointer_down_ && event_callback_) {
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
      const bool close_visual_changed = close_pressed_;
      pointer_down_ = false;
      close_pressed_ = false;
      dragging_ = false;
      if (close_visual_changed) {
        InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    }
    case WM_DESTROY:
      KillTimer(window, kCapsuleSlideTimerId);
      KillTimer(window, kCapsuleQueueFollowTimerId);
      KillTimer(window, kCapsuleMasterTransitionTimerId);
      dock_animation_active_ = false;
      queue_drag_animation_active_ = false;
      master_transition_active_ = false;
      RemovePropW(window, kCapsuleAlphaProperty);
      ClearCommittedQueueDrag();
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
