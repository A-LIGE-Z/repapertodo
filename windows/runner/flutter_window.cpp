#include "flutter_window.h"

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

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
          SetWindowPos(window, enabled ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0,
                       0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
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
          SetWindowTextA(window, title.c_str());
          result->Success();
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

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
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

void FlutterWindow::OnDestroy() {
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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
