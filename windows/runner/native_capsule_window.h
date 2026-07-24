#ifndef RUNNER_NATIVE_CAPSULE_WINDOW_H_
#define RUNNER_NATIVE_CAPSULE_WINDOW_H_

#include <flutter/encodable_value.h>

#include <functional>
#include <cstdint>
#include <string>

#include "win32_window.h"

// A lightweight Win32-only deep-capsule surface. Master capsules and the
// edge proxies for expanded papers deliberately do not create Flutter engines.
class NativeCapsuleWindow : public Win32Window {
 public:
  using EventCallback = std::function<void(
      const std::string&, const flutter::EncodableValue&)>;

  explicit NativeCapsuleWindow(EventCallback event_callback);
  ~NativeCapsuleWindow() override;

  void ApplySurface(const flutter::EncodableMap& surface);
  void SetAvoidFullscreenTopmost(bool avoid);
  void RefreshVisibility();

  const std::string& surface_id() const { return surface_id_; }
  const std::string& paper_id() const { return paper_id_; }
  bool is_master() const { return master_; }
  bool IsInQueue(const std::string& monitor_device_name,
                 const std::string& side) const;
  void ApplyQueueDragOffset(int delta_y);
  void FinishQueueDrag(bool commit);
  bool IsVisible() const;

 protected:
  bool OnCreate() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void ApplyNativeStyle();
  void ResolveWorkArea();
  void ApplyDockedPosition();
  void ApplyWindowRegion();
  void SetHovered(bool hovered);
  void StartDockAnimation(int target_visible_width, int duration_ms);
  void UpdateDockAnimation();
  void SendClick();
  void SendHide();
  void SendDrop();
  void Paint(HWND window);
  bool IsClosePoint(POINT client_point) const;
  std::wstring EffectiveLabel() const;
  std::wstring EffectiveFontFamily() const;
  int MeasureTextWidth(const std::wstring& value,
                       int logical_font_size,
                       int font_weight,
                       const std::wstring& font_family) const;
  int MeasureLabelWidth(const std::wstring& value) const;
  bool IsChineseLocale() const;
  bool IsExternalFullscreenWindow() const;
  bool IsCoveredByHigherWindow() const;
  int ScaleMetric(int logical_pixels) const;
  double UnscaleMetric(double physical_pixels) const;

  EventCallback event_callback_;
  std::string surface_id_;
  std::string kind_ = "proxy";
  std::string paper_id_;
  std::string paper_type_ = "todo";
  bool script_capsule_ = false;
  std::string title_;
  std::string label_en_ = "Collapse all";
  std::string label_zh_ = "\xE6\x94\xB6\xE8\xB5\xB7\xE5\x85\xA8\xE9\x83\xA8";
  std::string count_label_en_;
  std::string count_label_zh_;
  std::string capsule_side_ = "right";
  std::string monitor_device_name_;
  std::string theme_ = "system";
  std::string color_scheme_ = "warm";
  std::string custom_theme_color_hex_;
  std::string font_family_;
  RECT work_area_ = {};
  UINT dpi_ = 96;
  double top_margin_ = 48.0;
  int full_width_ = 112;
  int resting_visible_width_ = 52;
  int hover_visible_width_ = 82;
  int height_ = 46;
  int region_width_ = 0;
  int region_height_ = 0;
  std::string region_side_;
  double current_visible_width_ = 0.0;
  double animation_start_visible_width_ = 0.0;
  double animation_target_visible_width_ = 0.0;
  ULONGLONG animation_started_at_ = 0;
  int animation_duration_ms_ = 0;
  bool dock_animation_active_ = false;
  bool master_ = false;
  bool active_ = false;
  bool collapse_on_click_ = false;
  bool intended_visible_ = false;
  bool hide_when_covered_ = false;
  bool hide_when_fullscreen_ = false;
  bool animations_enabled_ = true;
  bool avoid_fullscreen_topmost_ = true;
  bool hovered_ = false;
  bool close_hovered_ = false;
  bool close_pressed_ = false;
  bool tracking_mouse_leave_ = false;
  bool pointer_down_ = false;
  bool dragging_ = false;
  POINT drag_start_cursor_ = {};
  RECT drag_start_bounds_ = {};
  bool queue_drag_offset_active_ = false;
  int queue_drag_base_top_ = 0;
  int64_t surface_generation_ = -1;
};

#endif  // RUNNER_NATIVE_CAPSULE_WINDOW_H_
