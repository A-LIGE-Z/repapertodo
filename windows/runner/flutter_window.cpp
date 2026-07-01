#include "flutter_window.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <optional>
#include <string>
#include <thread>
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

std::string TrimAscii(const std::string& value) {
  const auto begin = std::find_if_not(
      value.begin(), value.end(),
      [](unsigned char character) { return std::isspace(character); });
  const auto end = std::find_if_not(
                       value.rbegin(), value.rend(),
                       [](unsigned char character) {
                         return std::isspace(character);
                       })
                       .base();
  if (begin >= end) {
    return std::string();
  }
  return std::string(begin, end);
}

std::string UpperAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char character) {
                   return static_cast<char>(std::toupper(character));
                 });
  return value;
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

std::string Base64Encode(const unsigned char* data, size_t size) {
  constexpr char kAlphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string encoded;
  encoded.reserve(((size + 2) / 3) * 4);
  for (size_t index = 0; index < size; index += 3) {
    const unsigned int octet_a = data[index];
    const unsigned int octet_b = index + 1 < size ? data[index + 1] : 0;
    const unsigned int octet_c = index + 2 < size ? data[index + 2] : 0;
    const unsigned int triple = (octet_a << 16) | (octet_b << 8) | octet_c;
    encoded.push_back(kAlphabet[(triple >> 18) & 0x3F]);
    encoded.push_back(kAlphabet[(triple >> 12) & 0x3F]);
    encoded.push_back(index + 1 < size ? kAlphabet[(triple >> 6) & 0x3F]
                                       : '=');
    encoded.push_back(index + 2 < size ? kAlphabet[triple & 0x3F] : '=');
  }
  return encoded;
}

std::wstring QuoteCommandArgument(const std::wstring& value) {
  std::wstring quoted = L"\"";
  for (const wchar_t character : value) {
    if (character == L'"') {
      quoted += L"\\\"";
    } else {
      quoted.push_back(character);
    }
  }
  quoted += L"\"";
  return quoted;
}

std::wstring EscapePowerShellSingleQuotedString(const std::wstring& value) {
  std::wstring escaped;
  escaped.reserve(value.size());
  for (const wchar_t character : value) {
    if (character == L'\'') {
      escaped += L"''";
    } else {
      escaped.push_back(character);
    }
  }
  return escaped;
}

std::string EncodedPowerShellLaunchCommand(const std::wstring& path) {
  const std::wstring command =
      std::wstring(L"[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
                   L"$OutputEncoding = [System.Text.Encoding]::UTF8; & '") +
      EscapePowerShellSingleQuotedString(path) + L"'";
  return Base64Encode(reinterpret_cast<const unsigned char*>(command.data()),
                      command.size() * sizeof(wchar_t));
}

bool FileExists(const std::wstring& path) {
  const DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring FindExecutableOnPath(const std::wstring& file_name) {
  std::array<wchar_t, 32767> environment = {};
  const DWORD path_length =
      GetEnvironmentVariableW(L"PATH", environment.data(),
                              static_cast<DWORD>(environment.size()));
  if (path_length > 0 && path_length < environment.size()) {
    std::wstring path_value(environment.data(), path_length);
    size_t start = 0;
    while (start <= path_value.size()) {
      const size_t end = path_value.find(L';', start);
      std::wstring directory =
          path_value.substr(start, end == std::wstring::npos
                                       ? std::wstring::npos
                                       : end - start);
      while (!directory.empty() &&
             (directory.back() == L' ' || directory.back() == L'\t')) {
        directory.pop_back();
      }
      if (!directory.empty()) {
        std::wstring candidate = directory;
        if (candidate.back() != L'\\' && candidate.back() != L'/') {
          candidate += L"\\";
        }
        candidate += file_name;
        if (FileExists(candidate)) {
          return candidate;
        }
      }
      if (end == std::wstring::npos) {
        break;
      }
      start = end + 1;
    }
  }

  std::array<wchar_t, MAX_PATH> program_files = {};
  if (GetEnvironmentVariableW(L"ProgramFiles", program_files.data(),
                              static_cast<DWORD>(program_files.size())) > 0) {
    const std::wstring candidate =
        std::wstring(program_files.data()) + L"\\PowerShell\\7\\" + file_name;
    if (FileExists(candidate)) {
      return candidate;
    }
  }
  return std::wstring();
}

std::wstring ResolvePowerShellExecutable(const std::string& engine,
                                         bool prefer_power_shell7) {
  if (engine == "pwsh") {
    return FindExecutableOnPath(L"pwsh.exe");
  }
  if (engine == "powershell") {
    return L"powershell.exe";
  }
  if (prefer_power_shell7) {
    const std::wstring pwsh = FindExecutableOnPath(L"pwsh.exe");
    if (!pwsh.empty()) {
      return pwsh;
    }
  }
  return L"powershell.exe";
}

std::wstring ScriptCapsuleTempDirectory() {
  std::array<wchar_t, MAX_PATH + 1> temp_path = {};
  const DWORD length =
      GetTempPathW(static_cast<DWORD>(temp_path.size()), temp_path.data());
  std::wstring directory =
      length > 0 && length < temp_path.size() ? std::wstring(temp_path.data())
                                              : L".\\";
  if (!directory.empty() && directory.back() != L'\\' &&
      directory.back() != L'/') {
    directory += L"\\";
  }
  directory += L"RePaperTodo\\Scripts";
  CreateDirectoryW((directory.substr(0, directory.find_last_of(L"\\/"))).c_str(),
                   nullptr);
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory;
}

std::wstring WriteScriptCapsuleFile(const std::string& script) {
  const std::wstring directory = ScriptCapsuleTempDirectory();
  std::array<wchar_t, MAX_PATH> path = {};
  if (GetTempFileNameW(directory.c_str(), L"sc", 0, path.data()) == 0) {
    return std::wstring();
  }
  const std::wstring script_path = std::wstring(path.data()) + L".ps1";
  MoveFileExW(path.data(), script_path.c_str(), MOVEFILE_REPLACE_EXISTING);

  HANDLE file = CreateFileW(script_path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return std::wstring();
  }
  constexpr unsigned char kUtf8Bom[] = {0xEF, 0xBB, 0xBF};
  DWORD written = 0;
  WriteFile(file, kUtf8Bom, static_cast<DWORD>(sizeof(kUtf8Bom)), &written,
            nullptr);
  WriteFile(file, script.data(), static_cast<DWORD>(script.size()), &written,
            nullptr);
  CloseHandle(file);
  return script_path;
}

void RunScriptCapsuleProcess(std::wstring executable,
                             std::wstring script_path,
                             bool hide_window) {
  const std::string encoded_command =
      EncodedPowerShellLaunchCommand(script_path);
  std::wstring command_line = QuoteCommandArgument(executable) +
                              L" -NoProfile -NonInteractive "
                              L"-ExecutionPolicy Bypass -EncodedCommand " +
                              Utf8ToWide(encoded_command);
  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  if (hide_window) {
    startup_info.dwFlags = STARTF_USESHOWWINDOW;
    startup_info.wShowWindow = SW_HIDE;
  }
  PROCESS_INFORMATION process_information = {};
  const DWORD creation_flags = hide_window ? CREATE_NO_WINDOW : 0;
  if (CreateProcessW(nullptr, command_line.data(), nullptr, nullptr, FALSE,
                     creation_flags, nullptr, nullptr, &startup_info,
                     &process_information)) {
    WaitForSingleObject(process_information.hProcess, INFINITE);
    CloseHandle(process_information.hThread);
    CloseHandle(process_information.hProcess);
  }
  DeleteFileW(script_path.c_str());
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

std::vector<std::string> SplitHotkey(const std::string& hotkey) {
  std::vector<std::string> parts;
  std::string current;
  for (const char character : hotkey) {
    if (character == '+') {
      const std::string part = TrimAscii(current);
      if (!part.empty()) {
        parts.push_back(part);
      }
      current.clear();
    } else {
      current.push_back(character);
    }
  }
  const std::string part = TrimAscii(current);
  if (!part.empty()) {
    parts.push_back(part);
  }
  return parts;
}

bool TryParseVirtualKey(const std::string& token, UINT* key) {
  if (token.size() == 1) {
    const unsigned char character = static_cast<unsigned char>(token[0]);
    if (std::isalnum(character)) {
      *key = static_cast<UINT>(std::toupper(character));
      return true;
    }
  }
  if (token.size() >= 2 && token[0] == 'F') {
    const int function_key = std::atoi(token.c_str() + 1);
    if (function_key >= 1 && function_key <= 24) {
      *key = VK_F1 + static_cast<UINT>(function_key - 1);
      return true;
    }
  }
  if (token == "SPACE") {
    *key = VK_SPACE;
    return true;
  }
  if (token == "TAB") {
    *key = VK_TAB;
    return true;
  }
  if (token == "ENTER" || token == "RETURN") {
    *key = VK_RETURN;
    return true;
  }
  if (token == "ESC" || token == "ESCAPE") {
    *key = VK_ESCAPE;
    return true;
  }
  if (token == "BACKSPACE") {
    *key = VK_BACK;
    return true;
  }
  if (token == "DELETE" || token == "DEL") {
    *key = VK_DELETE;
    return true;
  }
  if (token == "INSERT" || token == "INS") {
    *key = VK_INSERT;
    return true;
  }
  if (token == "HOME") {
    *key = VK_HOME;
    return true;
  }
  if (token == "END") {
    *key = VK_END;
    return true;
  }
  if (token == "PAGEUP" || token == "PGUP") {
    *key = VK_PRIOR;
    return true;
  }
  if (token == "PAGEDOWN" || token == "PGDN") {
    *key = VK_NEXT;
    return true;
  }
  if (token == "UP") {
    *key = VK_UP;
    return true;
  }
  if (token == "DOWN") {
    *key = VK_DOWN;
    return true;
  }
  if (token == "LEFT") {
    *key = VK_LEFT;
    return true;
  }
  if (token == "RIGHT") {
    *key = VK_RIGHT;
    return true;
  }
  return false;
}

bool TryParseHotkey(const std::string& hotkey, UINT* modifiers, UINT* key) {
  *modifiers = MOD_NOREPEAT;
  *key = 0;
  for (const std::string& raw_part : SplitHotkey(hotkey)) {
    const std::string part = UpperAscii(raw_part);
    if (part == "CTRL" || part == "CONTROL") {
      *modifiers |= MOD_CONTROL;
    } else if (part == "ALT") {
      *modifiers |= MOD_ALT;
    } else if (part == "SHIFT") {
      *modifiers |= MOD_SHIFT;
    } else if (part == "WIN" || part == "WINDOWS" || part == "META") {
      *modifiers |= MOD_WIN;
    } else if (*key == 0) {
      if (!TryParseVirtualKey(part, key)) {
        return false;
      }
    } else {
      return false;
    }
  }
  return *key != 0;
}

bool RegisterConfiguredHotkey(HWND window, int id, const std::string& hotkey) {
  const std::string trimmed_hotkey = TrimAscii(hotkey);
  if (trimmed_hotkey.empty()) {
    return false;
  }
  UINT modifiers = 0;
  UINT key = 0;
  if (!TryParseHotkey(trimmed_hotkey, &modifiers, &key)) {
    return false;
  }
  return RegisterHotKey(window, id, modifiers, key) == TRUE;
}

}  // namespace

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayIconMessage = WM_APP + 1;
constexpr UINT kSingleInstanceCommandMessage = WM_APP + 2;
constexpr UINT kTrayNewTodoCommand = 40001;
constexpr UINT kTrayNewNoteCommand = 40002;
constexpr UINT kTraySettingsCommand = 40003;
constexpr UINT kTrayShowCommand = 40004;
constexpr UINT kTrayHideCommand = 40005;
constexpr UINT kTrayExitCommand = 40006;
constexpr UINT kTrayPaperCommandBase = 41000;
constexpr int kPinnedTodoHotkeyId = 42001;
constexpr int kPinnedNoteHotkeyId = 42002;
constexpr wchar_t kSingleInstancePipeName[] =
    L"\\\\.\\pipe\\RePaperTodo-SingleInstance-Activate";

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
          if (pinned_to_desktop_) {
            ShowWindow(window, SW_SHOWNOACTIVATE);
            SetWindowPos(window, HWND_BOTTOM, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          } else {
            ShowWindow(window, SW_SHOWNORMAL);
            SetForegroundWindow(window);
          }
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
              !pinned_to_desktop_ &&
              !(avoid_fullscreen_topmost_ && IsForegroundFullscreen(window));
          const HWND insert_after =
              should_apply_topmost
                  ? HWND_TOPMOST
                  : (pinned_to_desktop_ ? HWND_BOTTOM : HWND_NOTOPMOST);
          SetWindowPos(window, insert_after, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          result->Success();
          return;
        }
        if (method == "setPinnedToDesktop") {
          pinned_to_desktop_ = false;
          if (call.arguments()) {
            if (const auto* value = std::get_if<bool>(call.arguments())) {
              pinned_to_desktop_ = *value;
            }
          }
          SetWindowPos(window,
                       pinned_to_desktop_ ? HWND_BOTTOM : HWND_NOTOPMOST,
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
        if (method == "acquireSingleInstance") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "forwardToPrimary") {
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
        if (method == "registerGlobalHotkeys") {
          UnregisterHotKey(window, kPinnedTodoHotkeyId);
          UnregisterHotKey(window, kPinnedNoteHotkeyId);
          todo_hotkey_registered_ = false;
          note_hotkey_registered_ = false;
          if (call.arguments()) {
            if (const auto* hotkeys =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              todo_hotkey_registered_ = RegisterConfiguredHotkey(
                  window, kPinnedTodoHotkeyId,
                  GetStringArgument(*hotkeys, "todo", ""));
              note_hotkey_registered_ = RegisterConfiguredHotkey(
                  window, kPinnedNoteHotkeyId,
                  GetStringArgument(*hotkeys, "note", ""));
            }
          }
          result->Success();
          return;
        }
        if (method == "unregisterGlobalHotkeys") {
          UnregisterHotKey(window, kPinnedTodoHotkeyId);
          UnregisterHotKey(window, kPinnedNoteHotkeyId);
          todo_hotkey_registered_ = false;
          note_hotkey_registered_ = false;
          result->Success();
          return;
        }
        if (method == "isForegroundFullscreen") {
          result->Success(flutter::EncodableValue(IsForegroundFullscreen(window)));
          return;
        }
        if (method == "openExternalFile") {
          std::string path;
          if (call.arguments()) {
            if (const auto* value = std::get_if<std::string>(call.arguments())) {
              path = *value;
            }
          }
          if (path.empty()) {
            result->Error("invalid_path", "The external file path is empty.");
            return;
          }
          HINSTANCE open_result =
              ShellExecuteW(window, L"open", Utf8ToWide(path).c_str(), nullptr,
                            nullptr, SW_SHOWNORMAL);
          if (reinterpret_cast<intptr_t>(open_result) <= 32) {
            result->Error("open_external_file_failed",
                          "Unable to open the external file.");
            return;
          }
          result->Success();
          return;
        }
        if (method == "runScriptCapsule") {
          std::string engine = "auto";
          std::string script;
          bool prefer_power_shell7 = true;
          bool hide_script_run_window = true;
          if (call.arguments()) {
            if (const auto* request =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              engine = GetStringArgument(*request, "engine", "auto");
              script = GetStringArgument(*request, "script", "");
              prefer_power_shell7 =
                  GetBoolArgument(*request, "preferPowerShell7", true);
              hide_script_run_window =
                  GetBoolArgument(*request, "hideScriptRunWindow", true);
            }
          }
          if (TrimAscii(script).empty()) {
            result->Error("script_capsule_empty",
                          "The script capsule content is empty.");
            return;
          }
          const std::wstring executable =
              ResolvePowerShellExecutable(engine, prefer_power_shell7);
          if (executable.empty()) {
            result->Error("powershell_not_found",
                          "PowerShell 7 (pwsh.exe) was not found.");
            return;
          }
          const std::wstring script_path = WriteScriptCapsuleFile(script);
          if (script_path.empty()) {
            result->Error("script_capsule_file_failed",
                          "Unable to write the script capsule file.");
            return;
          }
          std::thread(RunScriptCapsuleProcess, executable, script_path,
                      hide_script_run_window)
              .detach();
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
  AddTrayIcon();
  StartSingleInstanceListener();

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

void FlutterWindow::StartSingleInstanceListener() {
  HWND window = GetHandle();
  if (!window || single_instance_listener_running_.exchange(true)) {
    return;
  }

  single_instance_listener_thread_ = std::thread([this, window]() {
    while (single_instance_listener_running_) {
      HANDLE pipe = CreateNamedPipeW(
          kSingleInstancePipeName, PIPE_ACCESS_INBOUND,
          PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0,
          nullptr);
      if (pipe == INVALID_HANDLE_VALUE) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        continue;
      }

      const BOOL connected =
          ConnectNamedPipe(pipe, nullptr)
              ? TRUE
              : (GetLastError() == ERROR_PIPE_CONNECTED);
      std::string command;
      if (connected) {
        char buffer[512];
        DWORD bytes_read = 0;
        while (ReadFile(pipe, buffer, sizeof(buffer), &bytes_read, nullptr) &&
               bytes_read > 0) {
          command.append(buffer, bytes_read);
          if (command.find('\n') != std::string::npos) {
            break;
          }
        }
      }
      DisconnectNamedPipe(pipe);
      CloseHandle(pipe);

      command = TrimAscii(command);
      if (single_instance_listener_running_ && !command.empty()) {
        PostMessageW(window, kSingleInstanceCommandMessage, 0,
                     reinterpret_cast<LPARAM>(new std::string(command)));
      }
    }
  });
}

void FlutterWindow::StopSingleInstanceListener() {
  if (!single_instance_listener_running_.exchange(false)) {
    return;
  }

  for (int attempt = 0; attempt < 10; attempt++) {
    HANDLE pipe = CreateFileW(kSingleInstancePipeName, GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, 0, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      DWORD bytes_written = 0;
      const char newline = '\n';
      WriteFile(pipe, &newline, 1, &bytes_written, nullptr);
      CloseHandle(pipe);
      break;
    }
    WaitNamedPipeW(kSingleInstancePipeName, 100);
    Sleep(20);
  }

  if (single_instance_listener_thread_.joinable()) {
    single_instance_listener_thread_.join();
  }
}

void FlutterWindow::ShowTrayMenu() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  POINT cursor_position;
  GetCursorPos(&cursor_position);
  HMENU menu = CreatePopupMenu();
  AppendMenu(menu, MF_STRING, kTrayNewTodoCommand, L"New todo");
  AppendMenu(menu, MF_STRING, kTrayNewNoteCommand, L"New note");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTraySettingsCommand, L"Settings");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
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
    case kTrayNewTodoCommand:
      SendStartupCommandRequested("new-todo");
      break;
    case kTrayNewNoteCommand:
      SendStartupCommandRequested("new-note");
      break;
    case kTraySettingsCommand:
      SendStartupCommandRequested("settings");
      break;
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

void FlutterWindow::SendStartupCommandRequested(const std::string& command) {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(
      "startupCommandRequested",
      std::make_unique<flutter::EncodableValue>(command));
}

void FlutterWindow::SendWindowEvent(const char* method) {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(method,
                                std::make_unique<flutter::EncodableValue>());
}

void FlutterWindow::OnDestroy() {
  StopSingleInstanceListener();
  HWND window = GetHandle();
  if (window) {
    UnregisterHotKey(window, kPinnedTodoHotkeyId);
    UnregisterHotKey(window, kPinnedNoteHotkeyId);
  }
  todo_hotkey_registered_ = false;
  note_hotkey_registered_ = false;
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
    case WM_HOTKEY:
      if (wparam == kPinnedTodoHotkeyId && todo_hotkey_registered_) {
        SendStartupCommandRequested("new-todo");
        return 0;
      }
      if (wparam == kPinnedNoteHotkeyId && note_hotkey_registered_) {
        SendStartupCommandRequested("new-note");
        return 0;
      }
      break;
    case kSingleInstanceCommandMessage: {
      std::unique_ptr<std::string> command(
          reinterpret_cast<std::string*>(lparam));
      if (command && !command->empty()) {
        SendStartupCommandRequested(*command);
      }
      return 0;
    }
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
