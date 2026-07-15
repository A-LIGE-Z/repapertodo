#include "paper_flutter_window.h"

#include <dwmapi.h>
#include <commctrl.h>
#include <shobjidl.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>
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

constexpr wchar_t kReminderBubbleWindowClass[] =
    L"RePaperTodo.ReminderBubble";
constexpr UINT_PTR kReminderBubbleTimerId = 1;
constexpr UINT kDeferredPaperActionMessage = WM_APP + 0x351;

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

double CapsuleTitleWidth(const std::string& title) {
  const std::wstring text = Utf8WindowTitle(title);
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

double CapsuleWindowWidth(const std::string& title, bool deep) {
  // PaperTodo measures the rendered 11 px label and adds the capsule's fixed
  // icon, gaps, close target, padding, and 8 px transparent chrome per side.
  const double fixed_width = deep ? 73.0 : 64.0;
  const double minimum_width = deep ? 92.0 : 76.0;
  return std::ceil(std::max(minimum_width,
                            fixed_width + CapsuleTitleWidth(title)));
}

double CapsuleRestingVisibleWidth(const std::string& title,
                                  double capsule_width) {
  const double title_width = CapsuleTitleWidth(title);
  const double desired = 33.0 + title_width;
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
  HWND time = nullptr;
  SYSTEMTIME initial = {};
  SYSTEMTIME selected = {};
  bool accepted = false;
  bool clear = false;
};

constexpr int kDatePickerDateId = 1001;
constexpr int kDatePickerTimeId = 1002;
constexpr int kDatePickerClearId = 1003;
constexpr int kDatePickerCancelId = 1004;
constexpr int kDatePickerOkId = 1005;
constexpr wchar_t kDatePickerClass[] = L"RePaperTodo.DateTimePicker";

bool IsChineseUserLocale() {
  wchar_t locale[LOCALE_NAME_MAX_LENGTH] = {};
  return GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH) > 1 &&
         (locale[0] == L'z' || locale[0] == L'Z') &&
         (locale[1] == L'h' || locale[1] == L'H');
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
      const HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
      const bool chinese = IsChineseUserLocale();
      state->date = CreateWindowExW(
          0, DATETIMEPICK_CLASSW, L"", WS_CHILD | WS_VISIBLE |
          DTS_SHORTDATEFORMAT, 20, 24, 250, 28, window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerDateId)), GetModuleHandleW(nullptr),
          nullptr);
      state->time = CreateWindowExW(
          0, DATETIMEPICK_CLASSW, L"", WS_CHILD | WS_VISIBLE | DTS_TIMEFORMAT |
          DTS_UPDOWN, 280, 24, 110, 28, window,
          reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerTimeId)), GetModuleHandleW(nullptr),
          nullptr);
      const HWND clear = CreateWindowW(
          L"BUTTON", chinese ? L"\u6E05\u9664" : L"Clear",
          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 20, 88,
          82, 28, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerClearId)),
          GetModuleHandleW(nullptr), nullptr);
      const HWND cancel = CreateWindowW(
          L"BUTTON", chinese ? L"\u53D6\u6D88" : L"Cancel",
          WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 220,
          88, 82, 28, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerCancelId)),
          GetModuleHandleW(nullptr), nullptr);
      const HWND ok = CreateWindowW(
          L"BUTTON", chinese ? L"\u4FDD\u5B58" : L"Save",
          WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON, 310,
          88, 82, 28, window, reinterpret_cast<HMENU>(static_cast<INT_PTR>(kDatePickerOkId)),
          GetModuleHandleW(nullptr), nullptr);
      for (HWND child : {state->date, state->time, clear, cancel, ok}) {
        SendMessageW(child, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
      }
      DateTime_SetSystemtime(state->date, GDT_VALID, &state->initial);
      DateTime_SetSystemtime(state->time, GDT_VALID, &state->initial);
      SetFocus(state->date);
      return 0;
    }
    case WM_COMMAND: {
      const int command = LOWORD(wparam);
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
        SYSTEMTIME time = {};
        if (DateTime_GetSystemtime(state->date, &date) == GDT_VALID &&
            DateTime_GetSystemtime(state->time, &time) == GDT_VALID) {
          state->selected = date;
          state->selected.wHour = time.wHour;
          state->selected.wMinute = time.wMinute;
          state->selected.wSecond = 0;
          state->accepted = true;
        }
        DestroyWindow(window);
        return 0;
      }
      break;
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
    klass.lpfnWndProc = DateTimePickerWindowProc;
    klass.hInstance = GetModuleHandleW(nullptr);
    klass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    klass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
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
  RECT owner_bounds = {};
  if (!owner || !GetWindowRect(owner, &owner_bounds)) {
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &owner_bounds, 0);
  }
  const int left = owner_bounds.left +
                   ((owner_bounds.right - owner_bounds.left - 430) / 2);
  const int top = owner_bounds.top +
                  ((owner_bounds.bottom - owner_bounds.top - 160) / 2);
  HWND dialog = CreateWindowExW(
      WS_EX_DLGMODALFRAME, kDatePickerClass,
      IsChineseUserLocale() ? L"RePaperTodo - \u65E5\u671F\u548C\u65F6\u95F4"
                            : L"RePaperTodo - Due date and time",
      WS_POPUP | WS_CAPTION | WS_SYSMENU, left, top, 430, 160, owner, nullptr,
      GetModuleHandleW(nullptr), &state);
  if (!dialog) return std::nullopt;
  if (owner) EnableWindow(owner, FALSE);
  ShowWindow(dialog, SW_SHOW);
  UpdateWindow(dialog);
  MSG message = {};
  while (IsWindow(dialog) && GetMessageW(&message, nullptr, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
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
    case kDeferredPaperActionMessage: {
      std::unique_ptr<flutter::EncodableValue> arguments(
          reinterpret_cast<flutter::EncodableValue*>(lparam));
      if (arguments) {
        SendEvent("paperActionRequested", *arguments);
      }
      return 0;
    }
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
      [[fallthrough]];
    case WM_SIZE:
      if (surface_initialized_ && !collapsed_ && !applying_bounds_ &&
          !in_size_move_ &&
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
        if (collapsed_ && deep_capsule_mode_) {
          SendCapsuleDropped();
        } else {
          SendBoundsChanged();
        }
      }
      break;
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      if (info) {
        info->ptMinTrackSize.x = collapsed_
                                     ? std::max(1, static_cast<int>(
                                                       std::round(capsule_width_)))
                                     : 220;
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
      const int resize_hit = ResizeBorderHitTest(lparam);
      if (resize_hit != HTCLIENT) {
        return resize_hit;
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
  queue_drag_offset_active_ = false;
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
  const std::string title = StringValue(surface, "title", "RePaperTodo");
  const std::string capsule_title =
      StringValue(surface, "capsuleTitle", title);
  collapsed_ = BoolValue(surface, "isCollapsed", collapsed_);
  deep_capsule_mode_ =
      BoolValue(surface, "useDeepCapsuleMode", deep_capsule_mode_);
  if (!collapsed_) {
    capsule_hovered_ = false;
  }
  hide_when_covered_ =
      BoolValue(surface, "hideWhenCovered", hide_when_covered_);
  hide_when_fullscreen_ =
      BoolValue(surface, "hideWhenFullscreen", hide_when_fullscreen_);
  SetHideFromWindowSwitcher(BoolValue(
      surface, "hideFromWindowSwitcher", hide_from_window_switcher_));
  const double native_width =
      collapsed_ ? CapsuleWindowWidth(capsule_title, deep_capsule_mode_) : width;
  const double native_height = collapsed_ ? 46.0 : height;
  double native_x = x;
  double native_y = y;
  if (collapsed_) {
    capsule_monitor_device_name_ =
        StringValue(surface, "capsuleMonitorDeviceName", "");
    const RECT work_area =
        WorkAreaForWindow(window, capsule_monitor_device_name_);
    capsule_side_ = StringValue(surface, "capsuleSide", "right");
    capsule_work_area_ = work_area;
    capsule_width_ = native_width;
    capsule_resting_visible_width_ =
        CapsuleRestingVisibleWidth(capsule_title, native_width);
    capsule_hover_visible_width_ = CapsuleHoverVisibleWidth(
        native_width, capsule_resting_visible_width_);
    const double visible_width = deep_capsule_mode_
                                     ? (capsule_hovered_
                                            ? capsule_hover_visible_width_
                                            : capsule_resting_visible_width_)
                                     : native_width;
    native_x = capsule_side_ == "left"
                   ? static_cast<double>(work_area.left) -
                         (native_width - visible_width)
                   : static_cast<double>(work_area.right) - visible_width;
    const bool top_is_work_area_relative = BoolValue(
        surface, "capsuleTopIsWorkAreaRelative", false);
    const double requested_top =
        top_is_work_area_relative
            ? static_cast<double>(work_area.top) + y
            : y;
    native_y = std::clamp(
        requested_top, static_cast<double>(work_area.top),
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
  SetWindowTextW(window, Utf8WindowTitle(title).c_str());
  always_on_top_ = BoolValue(surface, "alwaysOnTop", always_on_top_);
  pinned_to_desktop_ =
      BoolValue(surface, "isPinnedToDesktop", pinned_to_desktop_);
  SetHideFromWindowSwitcher(hide_from_window_switcher_);
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
  SetWindowPos(window, nullptr, bounds.left, queue_drag_base_top_ + delta_y,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void PaperFlutterWindow::FinishQueueDrag(bool commit) {
  if (!queue_drag_offset_active_) return;
  HWND window = GetHandle();
  RECT bounds = {};
  if (!commit && window && GetWindowRect(window, &bounds)) {
    SetWindowPos(window, nullptr, bounds.left, queue_drag_base_top_,
                 bounds.right - bounds.left, bounds.bottom - bounds.top,
                 SWP_NOZORDER | SWP_NOACTIVATE);
  }
  queue_drag_offset_active_ = false;
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
  ApplyCapsuleHorizontalPosition();
}

void PaperFlutterWindow::ApplyCapsuleHorizontalPosition() {
  HWND window = GetHandle();
  if (!window || !collapsed_ || !deep_capsule_mode_ || in_size_move_) {
    return;
  }
  RECT current = {};
  if (!GetWindowRect(window, &current)) {
    return;
  }
  const double visible_width = capsule_hovered_
                                   ? capsule_hover_visible_width_
                                   : capsule_resting_visible_width_;
  const double x = capsule_side_ == "left"
                       ? static_cast<double>(capsule_work_area_.left) -
                             (capsule_width_ - visible_width)
                       : static_cast<double>(capsule_work_area_.right) -
                             visible_width;
  applying_bounds_ = true;
  SetWindowPos(window, nullptr, static_cast<int>(std::round(x)), current.top,
               0, 0,
               SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  applying_bounds_ = false;
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
      window_class.style = CS_HREDRAW | CS_VREDRAW;
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
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
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
  const int radius = ScaleForDpi(reminder_bubble_, 14);
  SetWindowRgn(reminder_bubble_,
               CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                  radius * 2, radius * 2),
               TRUE);
  SetWindowPos(reminder_bubble_, HWND_TOPMOST, 0, 0, width, height,
               SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  PlaceReminderBubble();
  InvalidateRect(reminder_bubble_, nullptr, TRUE);
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
      HBITMAP bitmap = CreateCompatibleBitmap(
          target, std::max(1L, bounds.right), std::max(1L, bounds.bottom));
      HGDIOBJ old_bitmap = SelectObject(buffer, bitmap);
      const int radius = ScaleForDpi(window, 14);
      HBRUSH background = CreateSolidBrush(reminder_background_color_);
      HPEN border = CreatePen(PS_SOLID, std::max(1, ScaleForDpi(window, 1)),
                              reminder_border_color_);
      HGDIOBJ old_brush = SelectObject(buffer, background);
      HGDIOBJ old_pen = SelectObject(buffer, border);
      RoundRect(buffer, 0, 0, bounds.right, bounds.bottom, radius * 2,
                radius * 2);

      const int icon_left = ScaleForDpi(window, 13);
      const int icon_top = ScaleForDpi(window, 12);
      const int icon_size = ScaleForDpi(window, 28);
      HBRUSH accent = CreateSolidBrush(reminder_accent_color_);
      SelectObject(buffer, accent);
      SelectObject(buffer, GetStockObject(NULL_PEN));
      Ellipse(buffer, icon_left, icon_top, icon_left + icon_size,
              icon_top + icon_size);

      SetBkMode(buffer, TRANSPARENT);
      SetTextColor(buffer, reminder_background_color_);
      HFONT icon_font = CreateFontW(
          -ScaleForDpi(window, 16), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
      HGDIOBJ old_font = SelectObject(buffer, icon_font);
      RECT icon_text = {icon_left, icon_top, icon_left + icon_size,
                        icon_top + icon_size};
      DrawTextW(buffer, L"!", 1, &icon_text,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

      const int text_left = ScaleForDpi(window, 51);
      const int text_right = bounds.right - ScaleForDpi(window, 13);
      SetTextColor(buffer, reminder_text_color_);
      HFONT title_font = CreateFontW(
          -ScaleForDpi(window, 13), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE,
          FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
      SelectObject(buffer, title_font);
      RECT title_rect = {text_left, ScaleForDpi(window, 11), text_right,
                         ScaleForDpi(window, 34)};
      DrawTextW(buffer, reminder_title_.c_str(), -1, &title_rect,
                DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS);

      SetTextColor(buffer, reminder_weak_text_color_);
      HFONT message_font = CreateFontW(
          -ScaleForDpi(window, 12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
          DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
          CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
      SelectObject(buffer, message_font);
      RECT message_rect = {text_left, ScaleForDpi(window, 39), text_right,
                           bounds.bottom - ScaleForDpi(window, 9)};
      DrawTextW(buffer, reminder_message_.c_str(), -1, &message_rect,
                DT_WORDBREAK | DT_EDITCONTROL | DT_NOPREFIX);

      BitBlt(target, 0, 0, bounds.right, bounds.bottom, buffer, 0, 0,
             SRCCOPY);
      SelectObject(buffer, old_font);
      SelectObject(buffer, old_pen);
      SelectObject(buffer, old_brush);
      SelectObject(buffer, old_bitmap);
      DeleteObject(message_font);
      DeleteObject(title_font);
      DeleteObject(icon_font);
      DeleteObject(accent);
      DeleteObject(border);
      DeleteObject(background);
      DeleteObject(bitmap);
      DeleteDC(buffer);
      EndPaint(window, &paint);
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
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
  SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
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
  fullscreen_blocked_ =
      avoid_fullscreen_topmost_ && IsExternalFullscreenWindow(window);
  const bool policy_hidden = collapsed_ &&
                             (IsExternalFullscreenWindow(window) ||
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
  RemoveTaskbarButton(window);
  if (pinned_to_desktop_) {
    // Keep pinned papers as ordinary top-level windows. Parenting them to a
    // WorkerW is unreliable on Windows 11 because the selected WorkerW may sit
    // behind the wallpaper compositor, making the paper appear to disappear.
    // HWND_BOTTOM gives the expected desktop-layer behavior while preserving
    // normal hit testing for the always-available unpin control.
    SetWindowLongPtrW(window, GWL_STYLE,
                      WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN |
                          WS_VISIBLE);
    SetHideFromWindowSwitcher(hide_from_window_switcher_);
    SetWindowPos(window, HWND_BOTTOM, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
    return;
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
           flutter::EncodableValue(static_cast<double>(bounds.top))},
          {flutter::EncodableValue("workAreaTop"),
           flutter::EncodableValue(static_cast<double>(info.rcWork.top))},
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
  SetLayeredWindowAttributes(window, RGB(1, 2, 3), 0, LWA_COLORKEY);
  MARGINS margins = {-1};
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
