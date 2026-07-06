#include "flutter_window.h"

#include <dwmapi.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

struct PersistentScriptProcess {
  std::wstring key;
  HANDLE process = nullptr;
  HANDLE input = nullptr;
};

std::mutex g_persistent_script_processes_mutex;
std::vector<PersistentScriptProcess> g_persistent_script_processes;
HWND g_last_external_foreground_window = nullptr;
constexpr LONG kFullscreenTolerance = 2;
constexpr LONG kFullscreenMinCandidateSize = 160;

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

std::string LowerAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char character) {
                   return static_cast<char>(std::tolower(character));
                 });
  return value;
}

bool StartsWith(const std::string& value, const std::string& prefix) {
  return value.size() >= prefix.size() &&
         value.compare(0, prefix.size(), prefix) == 0;
}

int HexDigitValue(char character) {
  if (character >= '0' && character <= '9') {
    return character - '0';
  }
  if (character >= 'a' && character <= 'f') {
    return character - 'a' + 10;
  }
  if (character >= 'A' && character <= 'F') {
    return character - 'A' + 10;
  }
  return -1;
}

bool IsControlCodePoint(wchar_t character) {
  const auto code = static_cast<unsigned int>(character);
  return code < 0x20 || (code >= 0x7F && code <= 0x9F);
}

std::optional<std::wstring> Utf8ToWideStrict(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return std::nullopt;
  }
  std::wstring wide_value(size, L'\0');
  const int converted = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), wide_value.data(), size);
  if (converted != size) {
    return std::nullopt;
  }
  return wide_value;
}

bool HasControlCodePoint(const std::string& value) {
  const auto wide_value = Utf8ToWideStrict(value);
  if (!wide_value) {
    return false;
  }
  return std::any_of(wide_value->begin(), wide_value->end(),
                     IsControlCodePoint);
}

bool HasWhitespaceOrControlCodePoint(const std::string& value) {
  const auto wide_value = Utf8ToWideStrict(value);
  if (!wide_value) {
    return false;
  }
  return std::any_of(wide_value->begin(), wide_value->end(),
                     [](wchar_t character) {
                       const auto code = static_cast<unsigned int>(character);
                       return code <= 0x20 ||
                              (code >= 0x7F && code <= 0x9F);
                     });
}

std::optional<std::string> PercentDecodedBytes(const std::string& value) {
  std::string decoded;
  decoded.reserve(value.size());
  bool found_escape = false;
  for (size_t index = 0; index < value.size(); ++index) {
    if (value[index] == '%' && index + 2 < value.size()) {
      const int high = HexDigitValue(value[index + 1]);
      const int low = HexDigitValue(value[index + 2]);
      if (high >= 0 && low >= 0) {
        decoded.push_back(static_cast<char>((high << 4) + low));
        index += 2;
        found_escape = true;
        continue;
      }
    }
    decoded.push_back(value[index]);
  }
  return found_escape ? std::optional<std::string>(decoded) : std::nullopt;
}

bool HasEncodedControlByte(const std::string& uri) {
  for (size_t index = 0; index + 2 < uri.size(); ++index) {
    if (uri[index] != '%') {
      continue;
    }
    const int high = HexDigitValue(uri[index + 1]);
    const int low = HexDigitValue(uri[index + 2]);
    if (high < 0 || low < 0) {
      continue;
    }
    const int code = (high << 4) + low;
    if (code < 0x20 || (code >= 0x7F && code <= 0x9F)) {
      return true;
    }
  }
  return false;
}

bool HasEncodedUnsafeExternalUriCharacter(const std::string& uri) {
  const auto decoded = PercentDecodedBytes(uri);
  if (!decoded) {
    return false;
  }
  const auto decoded_wide = Utf8ToWideStrict(*decoded);
  if (decoded_wide &&
      std::any_of(decoded_wide->begin(), decoded_wide->end(),
                  IsControlCodePoint)) {
    return true;
  }
  return !decoded_wide && HasEncodedControlByte(uri);
}

bool HasMalformedExternalUriPercentEscape(const std::string& uri) {
  for (size_t index = 0; index < uri.size(); ++index) {
    if (uri[index] != '%') {
      continue;
    }
    if (index + 2 >= uri.size() || HexDigitValue(uri[index + 1]) < 0 ||
        HexDigitValue(uri[index + 2]) < 0) {
      return true;
    }
    index += 2;
  }
  return false;
}

bool HasEncodedExternalUriAuthoritySeparator(const std::string& authority) {
  const std::string normalized_authority = LowerAscii(authority);
  for (const std::string& separator :
       {"%23", "%2f", "%3a", "%3f", "%40", "%5b", "%5c", "%5d"}) {
    if (normalized_authority.find(separator) != std::string::npos) {
      return true;
    }
  }
  return false;
}

bool HasUnsafeExternalFilePathCharacter(const std::string& path) {
  for (const char character : path) {
    const unsigned char ascii = static_cast<unsigned char>(character);
    if (ascii < 0x20 || ascii == 0x7F) {
      return true;
    }
  }
  return HasControlCodePoint(path);
}

bool IsAllowedExternalUri(const std::string& value) {
  const std::string uri = TrimAscii(value);
  if (uri.empty()) {
    return false;
  }
  for (const char character : uri) {
    const unsigned char ascii = static_cast<unsigned char>(character);
    if (ascii <= 0x20 || ascii == 0x7F) {
      return false;
    }
  }
  if (HasWhitespaceOrControlCodePoint(uri)) {
    return false;
  }
  if (HasMalformedExternalUriPercentEscape(uri)) {
    return false;
  }
  if (HasEncodedUnsafeExternalUriCharacter(uri)) {
    return false;
  }
  const size_t scheme_separator = uri.find(':');
  if (scheme_separator == std::string::npos || scheme_separator == 0) {
    return false;
  }
  const std::string scheme = LowerAscii(uri.substr(0, scheme_separator));
  if (scheme == "mailto") {
    const std::string recipient = TrimAscii(uri.substr(scheme_separator + 1));
    if (recipient.empty() || StartsWith(recipient, "?") ||
        StartsWith(recipient, "//")) {
      return false;
    }
    return true;
  }
  if (scheme != "http" && scheme != "https") {
    return false;
  }
  const std::string authority_prefix = scheme + "://";
  if (!StartsWith(LowerAscii(uri), authority_prefix)) {
    return false;
  }
  const size_t authority_start = authority_prefix.size();
  const size_t authority_end =
      uri.find_first_of("/?#", authority_start);
  const std::string authority = uri.substr(
      authority_start,
      authority_end == std::string::npos ? std::string::npos
                                         : authority_end - authority_start);
  const std::string normalized_authority = LowerAscii(authority);
  if (TrimAscii(authority).empty() ||
      authority.find('@') != std::string::npos ||
      HasEncodedExternalUriAuthoritySeparator(authority)) {
    return false;
  }
  std::string authority_host;
  if (!authority.empty() && authority.front() == '[') {
    const size_t host_end = authority.find(']');
    if (host_end == std::string::npos || host_end <= 1) {
      return false;
    }
    authority_host = authority.substr(1, host_end - 1);
  } else {
    const size_t host_end = authority.find(':');
    authority_host = authority.substr(0, host_end);
  }
  return !TrimAscii(authority_host).empty();
}

std::string CompactHotkeyToken(const std::string& value) {
  std::string compact;
  compact.reserve(value.size());
  for (const char character : value) {
    const unsigned char ascii = static_cast<unsigned char>(character);
    if (std::isspace(ascii) || character == '-' || character == '_') {
      continue;
    }
    compact.push_back(static_cast<char>(std::toupper(ascii)));
  }
  return compact;
}

std::string GetPaperIdArgument(const flutter::EncodableValue* arguments) {
  if (!arguments) {
    return std::string();
  }
  if (const auto* value = std::get_if<std::string>(arguments)) {
    return TrimAscii(*value);
  }
  if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
    return TrimAscii(GetStringArgument(*map, "paperId", ""));
  }
  return std::string();
}

bool GetBoolArgumentValue(const flutter::EncodableValue* arguments,
                          const std::string& key,
                          bool fallback) {
  if (!arguments) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(arguments)) {
    return *value;
  }
  if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
    return GetBoolArgument(*map, key, fallback);
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

std::wstring ExecutableDirectory() {
  std::array<wchar_t, MAX_PATH> executable_path = {};
  const DWORD length =
      GetModuleFileNameW(nullptr, executable_path.data(),
                         static_cast<DWORD>(executable_path.size()));
  if (length == 0 || length >= executable_path.size()) {
    return std::wstring();
  }
  std::wstring directory(executable_path.data(), length);
  const size_t separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return std::wstring();
  }
  return directory.substr(0, separator);
}

HICON LoadCustomTrayIcon(const std::wstring& file_name) {
  const std::wstring directory = ExecutableDirectory();
  if (directory.empty()) {
    return nullptr;
  }
  const std::wstring path = directory + L"\\" + file_name;
  if (!FileExists(path)) {
    return nullptr;
  }
  return static_cast<HICON>(LoadImageW(
      nullptr, path.c_str(), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
      GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE | LR_DEFAULTCOLOR));
}

HICON LoadTrayIcon(bool* is_custom) {
  if (is_custom) {
    *is_custom = false;
  }
  for (const wchar_t* file_name : {L"PaperTodo.ico", L"RePaperTodo.ico"}) {
    HICON icon = LoadCustomTrayIcon(file_name);
    if (icon) {
      if (is_custom) {
        *is_custom = true;
      }
      return icon;
    }
  }
  return LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
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

bool IsAllowedScriptCapsuleEngine(const std::string& engine) {
  return engine == "auto" || engine == "pwsh" || engine == "powershell";
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

unsigned long long FileTimeValue(const FILETIME& file_time) {
  ULARGE_INTEGER value = {};
  value.LowPart = file_time.dwLowDateTime;
  value.HighPart = file_time.dwHighDateTime;
  return value.QuadPart;
}

void CleanupOldScriptCapsuleTempFiles() {
  const std::wstring directory = ScriptCapsuleTempDirectory();
  FILETIME now_file_time = {};
  GetSystemTimeAsFileTime(&now_file_time);
  constexpr unsigned long long kOneDayInFileTimeTicks =
      24ull * 60ull * 60ull * 1000ull * 1000ull * 10ull;
  const unsigned long long cutoff =
      FileTimeValue(now_file_time) > kOneDayInFileTimeTicks
          ? FileTimeValue(now_file_time) - kOneDayInFileTimeTicks
          : 0;

  WIN32_FIND_DATAW find_data = {};
  HANDLE find_handle =
      FindFirstFileW((directory + L"\\*.ps1").c_str(), &find_data);
  if (find_handle == INVALID_HANDLE_VALUE) {
    return;
  }
  do {
    if ((find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      continue;
    }
    if (FileTimeValue(find_data.ftLastWriteTime) >= cutoff) {
      continue;
    }
    DeleteFileW((directory + L"\\" + find_data.cFileName).c_str());
  } while (FindNextFileW(find_handle, &find_data));
  FindClose(find_handle);
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

void ClosePersistentScriptProcess(PersistentScriptProcess& entry) {
  if (entry.input) {
    CloseHandle(entry.input);
    entry.input = nullptr;
  }
  if (entry.process) {
    if (WaitForSingleObject(entry.process, 0) == WAIT_TIMEOUT) {
      TerminateProcess(entry.process, 0);
      WaitForSingleObject(entry.process, 1000);
    }
    CloseHandle(entry.process);
    entry.process = nullptr;
  }
}

PersistentScriptProcess* EnsurePersistentScriptProcess(
    const std::wstring& executable,
    bool hide_window) {
  const std::wstring key =
      executable + L"|" + (hide_window ? L"hidden" : L"visible");
  std::lock_guard<std::mutex> lock(g_persistent_script_processes_mutex);
  for (auto iterator = g_persistent_script_processes.begin();
       iterator != g_persistent_script_processes.end();) {
    if (iterator->key == key) {
      if (iterator->process &&
          WaitForSingleObject(iterator->process, 0) == WAIT_TIMEOUT) {
        return &(*iterator);
      }
      ClosePersistentScriptProcess(*iterator);
      iterator = g_persistent_script_processes.erase(iterator);
      continue;
    }
    ++iterator;
  }

  SECURITY_ATTRIBUTES security_attributes = {};
  security_attributes.nLength = sizeof(SECURITY_ATTRIBUTES);
  security_attributes.bInheritHandle = TRUE;
  HANDLE input_read = nullptr;
  HANDLE input_write = nullptr;
  if (!CreatePipe(&input_read, &input_write, &security_attributes, 0)) {
    return nullptr;
  }
  SetHandleInformation(input_write, HANDLE_FLAG_INHERIT, 0);
  HANDLE null_output =
      CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE,
                  &security_attributes, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                  nullptr);

  std::wstring command_line =
      QuoteCommandArgument(executable) +
      L" -NoProfile -ExecutionPolicy Bypass -NoExit -Command -";
  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESTDHANDLES;
  startup_info.hStdInput = input_read;
  startup_info.hStdOutput =
      null_output == INVALID_HANDLE_VALUE ? nullptr : null_output;
  startup_info.hStdError =
      null_output == INVALID_HANDLE_VALUE ? nullptr : null_output;
  if (hide_window) {
    startup_info.dwFlags |= STARTF_USESHOWWINDOW;
    startup_info.wShowWindow = SW_HIDE;
  }
  PROCESS_INFORMATION process_information = {};
  const DWORD creation_flags = hide_window ? CREATE_NO_WINDOW : 0;
  const BOOL created = CreateProcessW(
      nullptr, command_line.data(), nullptr, nullptr, TRUE, creation_flags,
      nullptr, nullptr, &startup_info, &process_information);
  CloseHandle(input_read);
  if (null_output != INVALID_HANDLE_VALUE) {
    CloseHandle(null_output);
  }
  if (!created) {
    CloseHandle(input_write);
    return nullptr;
  }
  CloseHandle(process_information.hThread);
  g_persistent_script_processes.push_back(
      PersistentScriptProcess{key, process_information.hProcess, input_write});
  return &g_persistent_script_processes.back();
}

bool WriteUtf8LineToPipe(HANDLE pipe, const std::wstring& line) {
  const std::wstring with_newline = line + L"\r\n";
  const int size = WideCharToMultiByte(CP_UTF8, 0, with_newline.c_str(), -1,
                                       nullptr, 0, nullptr, nullptr);
  if (size <= 1) {
    return false;
  }
  std::string utf8(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, with_newline.c_str(), -1, utf8.data(), size,
                      nullptr, nullptr);
  DWORD written = 0;
  return WriteFile(pipe, utf8.data(), static_cast<DWORD>(utf8.size()),
                   &written, nullptr) &&
         written == static_cast<DWORD>(utf8.size());
}

bool SubmitPersistentScriptCapsule(const std::wstring& executable,
                                   const std::wstring& script_path,
                                   bool hide_window) {
  PersistentScriptProcess* process =
      EnsurePersistentScriptProcess(executable, hide_window);
  if (!process || !process->input) {
    return false;
  }
  const std::wstring escaped_path =
      EscapePowerShellSingleQuotedString(script_path);
  const std::wstring command =
      std::wstring(L"[Console]::OutputEncoding = "
                   L"[System.Text.Encoding]::UTF8; $OutputEncoding = "
                   L"[System.Text.Encoding]::UTF8; try { & '") +
      escaped_path + L"' } finally { Remove-Item -LiteralPath '" +
      escaped_path + L"' -ErrorAction SilentlyContinue }";
  const bool submitted = WriteUtf8LineToPipe(process->input, command);
  if (!submitted) {
    std::lock_guard<std::mutex> lock(g_persistent_script_processes_mutex);
    for (auto iterator = g_persistent_script_processes.begin();
         iterator != g_persistent_script_processes.end(); ++iterator) {
      if (&(*iterator) == process) {
        ClosePersistentScriptProcess(*iterator);
        g_persistent_script_processes.erase(iterator);
        break;
      }
    }
  }
  return submitted;
}

void StopPersistentScriptProcesses() {
  std::lock_guard<std::mutex> lock(g_persistent_script_processes_mutex);
  for (auto& process : g_persistent_script_processes) {
    ClosePersistentScriptProcess(process);
  }
  g_persistent_script_processes.clear();
}

std::wstring TrayPaperLabel(const flutter::EncodableMap& map) {
  const std::string type = GetStringArgument(map, "type", "todo");
  const bool is_visible = GetBoolArgument(map, "isVisible", false);
  const bool is_collapsed = GetBoolArgument(map, "isCollapsed", false);
  const bool always_on_top = GetBoolArgument(map, "alwaysOnTop", false);
  const bool is_pinned_to_desktop =
      GetBoolArgument(map, "isPinnedToDesktop", false);
  const bool is_script_capsule =
      type == "note" && GetBoolArgument(map, "isScriptCapsule", false);
  std::wstring title = Utf8ToWide(GetStringArgument(map, "title", "Untitled"));
  if (title.empty()) {
    title = L"Untitled";
  }
  std::wstring label =
      is_script_capsule ? L"Script - " : (type == "note" ? L"Note - "
                                                          : L"Todo - ");
  label += title;
  std::wstring status;
  auto append_status = [&status](const wchar_t* value) {
    if (!status.empty()) {
      status += L", ";
    }
    status += value;
  };
  if (!is_visible) {
    append_status(L"hidden");
  }
  if (is_collapsed) {
    append_status(L"collapsed");
  }
  if (is_pinned_to_desktop) {
    append_status(L"desktop");
  }
  if (always_on_top) {
    append_status(L"topmost");
  }
  if (!status.empty()) {
    label += L" (";
    label += status;
    label += L")";
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

bool IsEmptyRect(const RECT& rect) {
  return rect.right <= rect.left || rect.bottom <= rect.top;
}

bool TryGetDwmWindowBounds(HWND window, RECT* bounds) {
  if (!bounds) {
    return false;
  }
  RECT rect = {};
  const HRESULT result =
      DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &rect,
                            sizeof(RECT));
  if (FAILED(result) || IsEmptyRect(rect)) {
    return false;
  }
  *bounds = rect;
  return true;
}

bool TryGetRawWindowBounds(HWND window, RECT* bounds) {
  if (!bounds) {
    return false;
  }
  RECT rect = {};
  if (!GetWindowRect(window, &rect) || IsEmptyRect(rect)) {
    return false;
  }
  *bounds = rect;
  return true;
}

bool TryGetWindowBounds(HWND window, RECT* bounds) {
  return TryGetDwmWindowBounds(window, bounds) ||
         TryGetRawWindowBounds(window, bounds);
}

bool TryGetMonitorInfoForRect(const RECT& rect, MONITORINFO* monitor_info) {
  if (!monitor_info || IsEmptyRect(rect) ||
      rect.right - rect.left < kFullscreenMinCandidateSize ||
      rect.bottom - rect.top < kFullscreenMinCandidateSize) {
    return false;
  }
  HMONITOR monitor = MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST);
  if (!monitor) {
    return false;
  }
  monitor_info->cbSize = sizeof(MONITORINFO);
  return GetMonitorInfoW(monitor, monitor_info) == TRUE;
}

bool CoversMonitor(const RECT& window_bounds, const RECT& monitor_bounds) {
  return window_bounds.left <= monitor_bounds.left + kFullscreenTolerance &&
         window_bounds.top <= monitor_bounds.top + kFullscreenTolerance &&
         window_bounds.right >= monitor_bounds.right - kFullscreenTolerance &&
         window_bounds.bottom >= monitor_bounds.bottom - kFullscreenTolerance;
}

bool IsFullscreenRect(const RECT& window_bounds) {
  MONITORINFO monitor_info = {};
  if (!TryGetMonitorInfoForRect(window_bounds, &monitor_info)) {
    return false;
  }
  const RECT& monitor_bounds = monitor_info.rcMonitor;
  return CoversMonitor(window_bounds, monitor_bounds);
}

bool IsFullscreenWindow(HWND window) {
  RECT bounds = {};
  if (TryGetDwmWindowBounds(window, &bounds) && IsFullscreenRect(bounds)) {
    return true;
  }
  return TryGetRawWindowBounds(window, &bounds) && IsFullscreenRect(bounds);
}

DWORD ProcessIdForWindow(HWND window) {
  if (!window) {
    return 0;
  }
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  return process_id;
}

bool IsCurrentProcessWindow(HWND window) {
  return ProcessIdForWindow(window) == GetCurrentProcessId();
}

bool IsCloakedWindow(HWND window) {
  int cloaked = 0;
  return SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked,
                                         sizeof(cloaked))) &&
         cloaked != 0;
}

std::wstring WindowClassName(HWND window) {
  std::array<wchar_t, 256> class_name = {};
  const int length = GetClassNameW(window, class_name.data(),
                                  static_cast<int>(class_name.size()));
  if (length <= 0) {
    return std::wstring();
  }
  return std::wstring(class_name.data(), static_cast<size_t>(length));
}

bool IsShellClassWindow(HWND window) {
  const std::wstring class_name = WindowClassName(window);
  return class_name == L"Progman" || class_name == L"WorkerW" ||
         class_name == L"Shell_TrayWnd" ||
         class_name == L"Shell_SecondaryTrayWnd";
}

bool IsToolWindow(HWND window) {
  const LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  return (extended_style & WS_EX_TOOLWINDOW) != 0;
}

bool IsCandidateExternalWindow(HWND window, HWND own_window) {
  if (!window || window == own_window || !IsWindow(window) ||
      window == GetShellWindow() || IsCurrentProcessWindow(window) ||
      !IsWindowVisible(window) || IsIconic(window) || IsToolWindow(window) ||
      IsCloakedWindow(window) || IsShellClassWindow(window)) {
    return false;
  }
  return true;
}

bool TryGetTrackedExternalForegroundFullscreen(HWND own_window,
                                               HWND* fullscreen_window) {
  if (fullscreen_window) {
    *fullscreen_window = nullptr;
  }
  if (!g_last_external_foreground_window) {
    return false;
  }
  if (!IsWindow(g_last_external_foreground_window) ||
      IsCurrentProcessWindow(g_last_external_foreground_window)) {
    g_last_external_foreground_window = nullptr;
    return false;
  }
  if (IsCandidateExternalWindow(g_last_external_foreground_window,
                                own_window) &&
      IsFullscreenWindow(g_last_external_foreground_window)) {
    if (fullscreen_window) {
      *fullscreen_window = g_last_external_foreground_window;
    }
    return true;
  }
  return false;
}

struct ForegroundScanState {
  HWND own_window = nullptr;
  HWND foreground_window = nullptr;
  DWORD foreground_process_id = 0;
  HWND found_window = nullptr;
};

BOOL CALLBACK FindForegroundRelatedFullscreenWindow(HWND window,
                                                    LPARAM parameter) {
  auto* state = reinterpret_cast<ForegroundScanState*>(parameter);
  if (!state || !IsCandidateExternalWindow(window, state->own_window)) {
    return TRUE;
  }
  if (window != state->foreground_window &&
      ProcessIdForWindow(window) != state->foreground_process_id) {
    return TRUE;
  }
  if (!IsFullscreenWindow(window)) {
    return TRUE;
  }
  g_last_external_foreground_window = window;
  state->found_window = window;
  return FALSE;
}

bool TryGetAnyForegroundRelatedFullscreenWindow(HWND own_window,
                                                HWND foreground_window,
                                                HWND* fullscreen_window) {
  if (fullscreen_window) {
    *fullscreen_window = nullptr;
  }
  const DWORD foreground_process_id = ProcessIdForWindow(foreground_window);
  if (foreground_process_id == 0) {
    return false;
  }
  ForegroundScanState state = {
      own_window,
      foreground_window,
      foreground_process_id,
      nullptr,
  };
  EnumWindows(FindForegroundRelatedFullscreenWindow,
              reinterpret_cast<LPARAM>(&state));
  if (!state.found_window) {
    return false;
  }
  if (fullscreen_window) {
    *fullscreen_window = state.found_window;
  }
  return true;
}

bool IsForegroundFullscreen(HWND own_window) {
  HWND foreground_window = GetForegroundWindow();
  const bool has_external_foreground =
      IsCandidateExternalWindow(foreground_window, own_window);
  if (has_external_foreground) {
    g_last_external_foreground_window = foreground_window;
  }

  HWND fullscreen_window = nullptr;
  if (TryGetTrackedExternalForegroundFullscreen(own_window,
                                                &fullscreen_window)) {
    return true;
  }

  return has_external_foreground &&
         TryGetAnyForegroundRelatedFullscreenWindow(
             own_window, foreground_window, &fullscreen_window);
}

flutter::EncodableValue BoundsValueFromRect(
    const RECT& bounds, const std::string& paper_id = "") {
  flutter::EncodableMap result_map;
  if (!paper_id.empty()) {
    result_map[flutter::EncodableValue("paperId")] =
        flutter::EncodableValue(paper_id);
  }
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

struct MonitorWorkAreaLookup {
  explicit MonitorWorkAreaLookup(std::wstring device_name)
      : target_device_name(std::move(device_name)) {}

  std::wstring target_device_name;
  RECT work_area = {};
  bool found = false;
};

BOOL CALLBACK FindMonitorWorkAreaByDeviceName(HMONITOR monitor,
                                              HDC,
                                              LPRECT,
                                              LPARAM data) {
  auto* context = reinterpret_cast<MonitorWorkAreaLookup*>(data);
  if (!context) {
    return TRUE;
  }
  MONITORINFOEXW monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFOEXW);
  if (GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&monitor_info)) !=
          TRUE ||
      IsEmptyRect(monitor_info.rcWork)) {
    return TRUE;
  }

  const bool wants_primary = context->target_device_name.empty();
  const bool matches = wants_primary
                           ? (monitor_info.dwFlags & MONITORINFOF_PRIMARY) != 0
                           : context->target_device_name == monitor_info.szDevice;
  if (!matches) {
    return TRUE;
  }

  context->work_area = monitor_info.rcWork;
  context->found = true;
  return FALSE;
}

std::optional<RECT> WorkAreaForMonitorDeviceName(
    const std::string& monitor_device_name) {
  MonitorWorkAreaLookup context(Utf8ToWide(TrimAscii(monitor_device_name)));
  EnumDisplayMonitors(nullptr, nullptr, FindMonitorWorkAreaByDeviceName,
                      reinterpret_cast<LPARAM>(&context));
  if (!context.found) {
    return std::nullopt;
  }
  return context.work_area;
}

RECT BoundsRectFromArguments(const flutter::EncodableValue* arguments,
                             const RECT& fallback) {
  if (!arguments) {
    return fallback;
  }
  if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
    const double x =
        GetNumberArgument(*map, "x", static_cast<double>(fallback.left));
    const double y =
        GetNumberArgument(*map, "y", static_cast<double>(fallback.top));
    const double width = GetNumberArgument(
        *map, "width", static_cast<double>(fallback.right - fallback.left));
    const double height = GetNumberArgument(
        *map, "height", static_cast<double>(fallback.bottom - fallback.top));
    if (std::isfinite(x) && std::isfinite(y) && std::isfinite(width) &&
        std::isfinite(height) && width > 0 && height > 0) {
      return RECT{static_cast<LONG>(x), static_cast<LONG>(y),
                  static_cast<LONG>(x + width),
                  static_cast<LONG>(y + height)};
    }
  }
  return fallback;
}

flutter::EncodableValue WorkAreaValueForArguments(
    HWND window, const flutter::EncodableValue* arguments) {
  std::string monitor_device_name;
  if (arguments) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
      monitor_device_name = GetStringArgument(*map, "monitorDeviceName", "");
    }
  }

  if (auto named_work_area = WorkAreaForMonitorDeviceName(monitor_device_name)) {
    return BoundsValueFromRect(*named_work_area);
  }

  RECT window_bounds = {};
  GetWindowRect(window, &window_bounds);
  const RECT requested_bounds = BoundsRectFromArguments(arguments, window_bounds);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFO);
  HMONITOR monitor =
      MonitorFromRect(&requested_bounds, MONITOR_DEFAULTTONEAREST);
  if (monitor && GetMonitorInfoW(monitor, &monitor_info) == TRUE &&
      !IsEmptyRect(monitor_info.rcWork)) {
    return BoundsValueFromRect(monitor_info.rcWork);
  }

  return BoundsValueFromRect(requested_bounds);
}

flutter::EncodableValue WindowBoundsValue(HWND window,
                                          const std::string& paper_id = "") {
  RECT bounds;
  GetWindowRect(window, &bounds);
  return BoundsValueFromRect(bounds, paper_id);
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
  const std::string compact = CompactHotkeyToken(token);
  if (compact.size() == 1) {
    const unsigned char character = static_cast<unsigned char>(compact[0]);
    if (std::isalnum(character)) {
      *key = static_cast<UINT>(std::toupper(character));
      return true;
    }
  }
  if (compact.size() >= 2 && compact[0] == 'F') {
    const int function_key = std::atoi(compact.c_str() + 1);
    if (function_key >= 1 && function_key <= 24) {
      *key = VK_F1 + static_cast<UINT>(function_key - 1);
      return true;
    }
  }

  std::string numpad_suffix;
  if (compact.rfind("NUMPAD", 0) == 0) {
    numpad_suffix = compact.substr(6);
  } else if (compact.rfind("NUM", 0) == 0 && compact != "NUMLOCK") {
    numpad_suffix = compact.substr(3);
  }
  if (!numpad_suffix.empty()) {
    if (numpad_suffix.size() == 1 &&
        std::isdigit(static_cast<unsigned char>(numpad_suffix[0]))) {
      *key = VK_NUMPAD0 + static_cast<UINT>(numpad_suffix[0] - '0');
      return true;
    }
    if (numpad_suffix == "ADD" || numpad_suffix == "PLUS") {
      *key = VK_ADD;
      return true;
    }
    if (numpad_suffix == "SUBTRACT" || numpad_suffix == "MINUS") {
      *key = VK_SUBTRACT;
      return true;
    }
    if (numpad_suffix == "MULTIPLY" || numpad_suffix == "ASTERISK") {
      *key = VK_MULTIPLY;
      return true;
    }
    if (numpad_suffix == "DIVIDE" || numpad_suffix == "SLASH") {
      *key = VK_DIVIDE;
      return true;
    }
    if (numpad_suffix == "DECIMAL" || numpad_suffix == "DOT" ||
        numpad_suffix == "PERIOD") {
      *key = VK_DECIMAL;
      return true;
    }
  }

  if (compact == "SPACE") {
    *key = VK_SPACE;
    return true;
  }
  if (compact == "TAB") {
    *key = VK_TAB;
    return true;
  }
  if (compact == "ENTER" || compact == "RETURN") {
    *key = VK_RETURN;
    return true;
  }
  if (compact == "ESC" || compact == "ESCAPE") {
    *key = VK_ESCAPE;
    return true;
  }
  if (compact == "BACKSPACE") {
    *key = VK_BACK;
    return true;
  }
  if (compact == "DELETE" || compact == "DEL") {
    *key = VK_DELETE;
    return true;
  }
  if (compact == "INSERT" || compact == "INS") {
    *key = VK_INSERT;
    return true;
  }
  if (compact == "HOME") {
    *key = VK_HOME;
    return true;
  }
  if (compact == "END") {
    *key = VK_END;
    return true;
  }
  if (compact == "PAGEUP" || compact == "PGUP") {
    *key = VK_PRIOR;
    return true;
  }
  if (compact == "PAGEDOWN" || compact == "PGDN") {
    *key = VK_NEXT;
    return true;
  }
  if (compact == "UP" || compact == "ARROWUP" || compact == "UPARROW") {
    *key = VK_UP;
    return true;
  }
  if (compact == "DOWN" || compact == "ARROWDOWN" ||
      compact == "DOWNARROW") {
    *key = VK_DOWN;
    return true;
  }
  if (compact == "LEFT" || compact == "ARROWLEFT" ||
      compact == "LEFTARROW") {
    *key = VK_LEFT;
    return true;
  }
  if (compact == "RIGHT" || compact == "ARROWRIGHT" ||
      compact == "RIGHTARROW") {
    *key = VK_RIGHT;
    return true;
  }
  if (compact == "PRINTSCREEN" || compact == "PRTSC" ||
      compact == "PRTSCR") {
    *key = VK_SNAPSHOT;
    return true;
  }
  if (compact == "CAPSLOCK") {
    *key = VK_CAPITAL;
    return true;
  }
  if (compact == "NUMLOCK") {
    *key = VK_NUMLOCK;
    return true;
  }
  if (compact == "SCROLLLOCK") {
    *key = VK_SCROLL;
    return true;
  }
  if (compact == "PLUS" || compact == "EQUAL" || compact == "EQUALS") {
    *key = VK_OEM_PLUS;
    return true;
  }
  if (compact == "MINUS" || compact == "DASH") {
    *key = VK_OEM_MINUS;
    return true;
  }
  if (compact == "COMMA") {
    *key = VK_OEM_COMMA;
    return true;
  }
  if (compact == "PERIOD" || compact == "DOT") {
    *key = VK_OEM_PERIOD;
    return true;
  }
  if (compact == "SLASH" || compact == "FORWARDSLASH") {
    *key = VK_OEM_2;
    return true;
  }
  if (compact == "BACKSLASH") {
    *key = VK_OEM_5;
    return true;
  }
  if (compact == "SEMICOLON") {
    *key = VK_OEM_1;
    return true;
  }
  if (compact == "QUOTE" || compact == "APOSTROPHE") {
    *key = VK_OEM_7;
    return true;
  }
  if (compact == "LEFTBRACKET" || compact == "OPENBRACKET") {
    *key = VK_OEM_4;
    return true;
  }
  if (compact == "RIGHTBRACKET" || compact == "CLOSEBRACKET") {
    *key = VK_OEM_6;
    return true;
  }
  if (compact == "BACKQUOTE" || compact == "GRAVE" || compact == "TILDE") {
    *key = VK_OEM_3;
    return true;
  }
  return false;
}

bool TryParseHotkey(const std::string& hotkey, UINT* modifiers, UINT* key) {
  *modifiers = MOD_NOREPEAT;
  *key = 0;
  bool has_modifier = false;
  for (const std::string& raw_part : SplitHotkey(hotkey)) {
    const std::string part = UpperAscii(raw_part);
    if (part == "CTRL" || part == "CONTROL") {
      *modifiers |= MOD_CONTROL;
      has_modifier = true;
    } else if (part == "ALT") {
      *modifiers |= MOD_ALT;
      has_modifier = true;
    } else if (part == "SHIFT") {
      *modifiers |= MOD_SHIFT;
      has_modifier = true;
    } else if (part == "WIN" || part == "WINDOWS" || part == "META") {
      *modifiers |= MOD_WIN;
      has_modifier = true;
    } else if (*key == 0) {
      if (!TryParseVirtualKey(part, key)) {
        return false;
      }
    } else {
      return false;
    }
  }
  return has_modifier && *key != 0;
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
constexpr UINT kTrayToggleCommand = 40007;
constexpr UINT kTrayPaperCommandBase = 41000;
constexpr UINT kTrayPaperDeleteCommandBase = 45000;
constexpr int kPinnedTodoHotkeyId = 42001;
constexpr int kPinnedNoteHotkeyId = 42002;
constexpr UINT_PTR kFullscreenTopmostRefreshTimerId = 43001;
constexpr UINT kFullscreenTopmostRefreshIntervalMs = 1000;
constexpr wchar_t kSingleInstancePipeName[] =
    L"\\\\.\\pipe\\RePaperTodo-SingleInstance-Activate";

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  CleanupOldScriptCapsuleTempFiles();
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");

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
          RememberActivePaperId(call.arguments());
          RememberPaperVisibility(active_paper_id_, true);
          if (!active_paper_id_.empty()) {
            pinned_to_desktop_ = GetBoolArgumentValue(
                call.arguments(), "isPinnedToDesktop", pinned_to_desktop_);
            RememberPaperPinnedToDesktop(active_paper_id_, pinned_to_desktop_);
            RememberPaperAlwaysOnTop(
                active_paper_id_,
                GetBoolArgumentValue(call.arguments(), "alwaysOnTop",
                                     paper_surfaces_[active_paper_id_]
                                         .always_on_top));
          }
          ApplyActivePaperBounds(window);
          if (pinned_to_desktop_) {
            ShowWindow(window, SW_SHOWNOACTIVATE);
            SetWindowPos(window, HWND_BOTTOM, 0, 0, 0, 0,
                         SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
          } else {
            ShowWindow(window, SW_SHOWNORMAL);
            SetForegroundWindow(window);
          }
          z_order_state_initialized_ = false;
          RefreshActivePaperZOrder(window);
          result->Success();
          return;
        }
        if (method == "hide") {
          const std::string requested_paper_id =
              GetPaperIdArgument(call.arguments());
          if (requested_paper_id.empty()) {
            RememberPaperVisibility(active_paper_id_, false);
          } else {
            RememberPaperVisibility(requested_paper_id, false);
          }
          if (requested_paper_id.empty() ||
              requested_paper_id == active_paper_id_) {
            ShowWindow(window, SW_HIDE);
            z_order_state_initialized_ = false;
          }
          result->Success();
          return;
        }
        if (method == "setAlwaysOnTop") {
          const std::string requested_paper_id =
              GetPaperIdArgument(call.arguments());
          const std::string target_paper_id =
              requested_paper_id.empty() ? active_paper_id_
                                         : requested_paper_id;
          const bool previous = target_paper_id.empty()
                                    ? false
                                    : paper_surfaces_[target_paper_id]
                                          .always_on_top;
          const bool enabled =
              GetBoolArgumentValue(call.arguments(), "enabled", previous);
          RememberPaperAlwaysOnTop(target_paper_id, enabled);
          if (target_paper_id.empty() || target_paper_id == active_paper_id_) {
            RefreshActivePaperZOrder(window);
          }
          result->Success();
          return;
        }
        if (method == "setPinnedToDesktop") {
          const std::string requested_paper_id =
              GetPaperIdArgument(call.arguments());
          const std::string target_paper_id =
              requested_paper_id.empty() ? active_paper_id_
                                         : requested_paper_id;
          const bool previous = target_paper_id.empty()
                                    ? pinned_to_desktop_
                                    : paper_surfaces_[target_paper_id]
                                          .pinned_to_desktop;
          const bool enabled =
              GetBoolArgumentValue(call.arguments(), "enabled", previous);
          RememberPaperPinnedToDesktop(target_paper_id, enabled);
          if (target_paper_id.empty() || target_paper_id == active_paper_id_) {
            pinned_to_desktop_ = enabled;
            RefreshActivePaperZOrder(window);
          }
          result->Success();
          return;
        }
        if (method == "setTitle") {
          std::string title = "RePaperTodo";
          std::string requested_paper_id;
          bool structured_title = false;
          if (call.arguments()) {
            if (const auto* value =
                    std::get_if<std::string>(call.arguments())) {
              title = *value;
            } else if (const auto* map =
                           std::get_if<flutter::EncodableMap>(
                               call.arguments())) {
              structured_title = true;
              requested_paper_id = GetPaperIdArgument(call.arguments());
              title = GetStringArgument(*map, "title", title);
            }
          }
          if (!structured_title || requested_paper_id.empty() ||
              requested_paper_id == active_paper_id_) {
            SetWindowTextW(window, Utf8ToWide(title).c_str());
          }
          result->Success();
          return;
        }
        if (method == "setTrayMenu") {
          tray_papers_.clear();
          std::vector<std::string> current_paper_ids;
          if (call.arguments()) {
            if (const auto* papers =
                    std::get_if<flutter::EncodableList>(call.arguments())) {
              for (const auto& paper : *papers) {
                if (const auto* paper_map =
                        std::get_if<flutter::EncodableMap>(&paper)) {
                  const std::string id =
                      GetStringArgument(*paper_map, "id", "");
                  if (!id.empty()) {
                    current_paper_ids.push_back(id);
                    RememberPaperVisibility(
                        id, GetBoolArgument(*paper_map, "isVisible", false));
                    RememberPaperPinnedToDesktop(
                        id, GetBoolArgument(*paper_map, "isPinnedToDesktop",
                                            false));
                    RememberPaperAlwaysOnTop(
                        id,
                        GetBoolArgument(*paper_map, "alwaysOnTop", false));
                    const double x = GetNumberArgument(*paper_map, "x", 0);
                    const double y = GetNumberArgument(*paper_map, "y", 0);
                    const double width =
                        GetNumberArgument(*paper_map, "width", 0);
                    const double height =
                        GetNumberArgument(*paper_map, "height", 0);
                    if (width > 0 && height > 0) {
                      const RECT paper_bounds = {
                          static_cast<LONG>(x),
                          static_cast<LONG>(y),
                          static_cast<LONG>(x + width),
                          static_cast<LONG>(y + height)};
                      RememberPaperBounds(id, paper_bounds);
                    }
                    tray_papers_.push_back(
                        {id, TrayPaperLabel(*paper_map),
                         GetBoolArgument(*paper_map, "isVisible", false)});
                  }
                }
              }
            }
          }
          for (auto iterator = paper_surfaces_.begin();
               iterator != paper_surfaces_.end();) {
            if (std::find(current_paper_ids.begin(), current_paper_ids.end(),
                          iterator->first) == current_paper_ids.end()) {
              iterator = paper_surfaces_.erase(iterator);
            } else {
              ++iterator;
            }
          }
          if (!active_paper_id_.empty() &&
              std::find(current_paper_ids.begin(), current_paper_ids.end(),
                        active_paper_id_) == current_paper_ids.end()) {
            active_paper_id_.clear();
            pinned_to_desktop_ = false;
            z_order_state_initialized_ = false;
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
          RefreshActivePaperZOrder(window);
          result->Success();
          return;
        }
        if (method == "registerGlobalHotkeys") {
          UnregisterHotKey(window, kPinnedTodoHotkeyId);
          UnregisterHotKey(window, kPinnedNoteHotkeyId);
          todo_hotkey_registered_ = false;
          note_hotkey_registered_ = false;
          std::string todo_hotkey;
          std::string note_hotkey;
          if (call.arguments()) {
            if (const auto* hotkeys =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              todo_hotkey = GetStringArgument(*hotkeys, "todo", "");
              note_hotkey = GetStringArgument(*hotkeys, "note", "");
              todo_hotkey_registered_ = RegisterConfiguredHotkey(
                  window, kPinnedTodoHotkeyId, todo_hotkey);
              note_hotkey_registered_ = RegisterConfiguredHotkey(
                  window, kPinnedNoteHotkeyId, note_hotkey);
            }
          }
          const bool todo_hotkey_requested = !TrimAscii(todo_hotkey).empty();
          const bool note_hotkey_requested = !TrimAscii(note_hotkey).empty();
          if ((todo_hotkey_requested && !todo_hotkey_registered_) ||
              (note_hotkey_requested && !note_hotkey_registered_)) {
            UnregisterHotKey(window, kPinnedTodoHotkeyId);
            UnregisterHotKey(window, kPinnedNoteHotkeyId);
            todo_hotkey_registered_ = false;
            note_hotkey_registered_ = false;
            result->Error(
                "hotkey_registration_failed",
                "Unable to register one or more global hotkeys. Use Ctrl, Alt, "
                "Shift, or Win plus a key and make sure the shortcut is not "
                "already used.");
            return;
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
        if (method == "exitApplication") {
          result->Success();
          DestroyWindow(window);
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
          if (HasUnsafeExternalFilePathCharacter(path)) {
            result->Error("invalid_path",
                          "The external file path contains unsupported characters.");
            return;
          }
          path = TrimAscii(path);
          if (path.empty()) {
            result->Error("invalid_path", "The external file path is empty.");
            return;
          }
          const std::wstring wide_path = Utf8ToWide(path);
          if (!FileExists(wide_path)) {
            result->Error("file_not_found", "The file does not exist.");
            return;
          }
          HINSTANCE open_result =
              ShellExecuteW(window, L"open", wide_path.c_str(), nullptr,
                            nullptr, SW_SHOWNORMAL);
          if (reinterpret_cast<intptr_t>(open_result) <= 32) {
            result->Error("open_external_file_failed",
                          "Unable to open the external file.");
            return;
          }
          result->Success();
          return;
        }
        if (method == "openUri") {
          std::string uri;
          if (call.arguments()) {
            if (const auto* value = std::get_if<std::string>(call.arguments())) {
              uri = *value;
            }
          }
          uri = TrimAscii(uri);
          if (uri.empty()) {
            result->Error("invalid_uri", "The URI is empty.");
            return;
          }
          if (!IsAllowedExternalUri(uri)) {
            result->Error("invalid_uri", "The URI scheme is not supported.");
            return;
          }
          HINSTANCE open_result =
              ShellExecuteW(window, L"open", Utf8ToWide(uri).c_str(), nullptr,
                            nullptr, SW_SHOWNORMAL);
          if (reinterpret_cast<intptr_t>(open_result) <= 32) {
            result->Error("open_uri_failed", "Unable to open the URI.");
            return;
          }
          result->Success();
          return;
        }
        if (method == "runScriptCapsule") {
          std::string engine = "auto";
          std::string script;
          bool use_persistent_process = false;
          bool use_persistent_power_shell_process = false;
          bool prefer_power_shell7 = true;
          bool hide_script_run_window = true;
          if (call.arguments()) {
            if (const auto* request =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              engine = GetStringArgument(*request, "engine", "auto");
              script = GetStringArgument(*request, "script", "");
              use_persistent_process =
                  GetBoolArgument(*request, "usePersistentProcess", false);
              use_persistent_power_shell_process = GetBoolArgument(
                  *request, "usePersistentPowerShellProcess", false);
              prefer_power_shell7 =
                  GetBoolArgument(*request, "preferPowerShell7", true);
              hide_script_run_window =
                  GetBoolArgument(*request, "hideScriptRunWindow", true);
            }
          }
          engine = LowerAscii(TrimAscii(engine));
          if (!IsAllowedScriptCapsuleEngine(engine)) {
            result->Error("invalid_script_capsule_engine",
                          "The script capsule engine is not supported.");
            return;
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
          if (use_persistent_process && use_persistent_power_shell_process) {
            if (!SubmitPersistentScriptCapsule(executable, script_path,
                                               hide_script_run_window)) {
              DeleteFileW(script_path.c_str());
              result->Error("persistent_script_capsule_failed",
                            "Unable to submit the script capsule.");
              return;
            }
            result->Success();
            return;
          }
          std::thread(RunScriptCapsuleProcess, executable, script_path,
                      hide_script_run_window)
              .detach();
          result->Success();
          return;
        }
        if (method == "preparePersistentScriptCapsule") {
          bool prefer_power_shell7 = true;
          bool hide_script_run_window = true;
          if (call.arguments()) {
            if (const auto* request =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              prefer_power_shell7 =
                  GetBoolArgument(*request, "preferPowerShell7", true);
              hide_script_run_window =
                  GetBoolArgument(*request, "hideScriptRunWindow", true);
            }
          }
          const std::wstring executable =
              ResolvePowerShellExecutable("auto", prefer_power_shell7);
          if (executable.empty()) {
            result->Error("powershell_not_found",
                          "PowerShell 7 (pwsh.exe) was not found.");
            return;
          }
          if (!EnsurePersistentScriptProcess(executable,
                                             hide_script_run_window)) {
            result->Error("persistent_script_capsule_failed",
                          "Unable to prepare the script capsule process.");
            return;
          }
          result->Success();
          return;
        }
        if (method == "stopPersistentScriptCapsules") {
          StopPersistentScriptProcesses();
          result->Success();
          return;
        }
        if (method == "setBounds") {
          const std::string requested_paper_id =
              GetPaperIdArgument(call.arguments());
          const std::string target_paper_id =
              requested_paper_id.empty() ? active_paper_id_
                                         : requested_paper_id;
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
          const RECT bounds = {static_cast<LONG>(x), static_cast<LONG>(y),
                               static_cast<LONG>(x + width),
                               static_cast<LONG>(y + height)};
          RememberPaperBounds(target_paper_id, bounds);
          if (target_paper_id.empty() || target_paper_id == active_paper_id_) {
            SetWindowPos(window, nullptr, static_cast<int>(x),
                         static_cast<int>(y), static_cast<int>(width),
                         static_cast<int>(height),
                         SWP_NOZORDER | SWP_NOACTIVATE);
          }
          result->Success();
          return;
        }
        if (method == "getBounds") {
          const std::string requested_paper_id =
              GetPaperIdArgument(call.arguments());
          result->Success(BoundsValueForPaper(
              window, requested_paper_id.empty() ? active_paper_id_
                                                 : requested_paper_id));
          return;
        }
        if (method == "getWorkArea") {
          result->Success(WorkAreaValueForArguments(window, call.arguments()));
          return;
        }

        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  AddTrayIcon();
  StartSingleInstanceListener();
  SetTimer(GetHandle(), kFullscreenTopmostRefreshTimerId,
           kFullscreenTopmostRefreshIntervalMs, nullptr);

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
  if (tray_icon_handle_is_custom_ && tray_icon_handle_) {
    DestroyIcon(tray_icon_handle_);
  }
  tray_icon_handle_ = LoadTrayIcon(&tray_icon_handle_is_custom_);
  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATA);
  tray_icon_data_.hWnd = window;
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayIconMessage;
  tray_icon_data_.hIcon = tray_icon_handle_;
  wcscpy_s(tray_icon_data_.szTip, L"RePaperTodo");
  tray_icon_added_ = Shell_NotifyIcon(NIM_ADD, &tray_icon_data_) == TRUE;
  if (tray_icon_added_) {
    tray_icon_data_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIcon(NIM_SETVERSION, &tray_icon_data_);
  } else if (tray_icon_handle_is_custom_ && tray_icon_handle_) {
    DestroyIcon(tray_icon_handle_);
    tray_icon_handle_ = nullptr;
    tray_icon_handle_is_custom_ = false;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_added_) {
    Shell_NotifyIcon(NIM_DELETE, &tray_icon_data_);
    tray_icon_added_ = false;
  }
  if (tray_icon_handle_is_custom_ && tray_icon_handle_) {
    DestroyIcon(tray_icon_handle_);
  }
  tray_icon_handle_ = nullptr;
  tray_icon_handle_is_custom_ = false;
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
  AppendMenu(menu, MF_STRING, kTrayNewTodoCommand, L"+ New todo paper");
  AppendMenu(menu, MF_STRING, kTrayNewNoteCommand, L"+ New note paper");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTraySettingsCommand, L"Settings");
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kTrayShowCommand, L"Show all papers");
  AppendMenu(menu, MF_STRING, kTrayHideCommand, L"Hide all papers");
  AppendMenu(menu, MF_STRING, kTrayToggleCommand, L"Toggle all papers");
  if (!tray_papers_.empty()) {
    AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenu(menu, MF_STRING | MF_DISABLED, 0, L"Papers");
    for (size_t index = 0; index < tray_papers_.size(); index++) {
      const UINT flags =
          MF_STRING | (tray_papers_[index].is_visible ? MF_CHECKED
                                                      : MF_UNCHECKED);
      AppendMenu(menu, flags,
                 kTrayPaperCommandBase + static_cast<UINT>(index),
                 tray_papers_[index].label.c_str());
    }
    HMENU delete_menu = CreatePopupMenu();
    if (delete_menu) {
      for (size_t index = 0; index < tray_papers_.size(); index++) {
        AppendMenu(delete_menu, MF_STRING,
                   kTrayPaperDeleteCommandBase + static_cast<UINT>(index),
                   tray_papers_[index].label.c_str());
      }
      AppendMenu(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(delete_menu),
                 L"Delete paper...");
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
      ShowWindow(window, SW_SHOWNORMAL);
      SetForegroundWindow(window);
      break;
    case kTrayShowCommand:
      SendStartupCommandRequested("show");
      ShowWindow(window, SW_SHOWNORMAL);
      SetForegroundWindow(window);
      break;
    case kTrayHideCommand:
      SendStartupCommandRequested("hide");
      ShowWindow(window, SW_HIDE);
      break;
    case kTrayToggleCommand:
      SendStartupCommandRequested("toggle");
      break;
    case kTrayExitCommand:
      SendStartupCommandRequested("exit");
      break;
    default:
      if (command >= kTrayPaperCommandBase &&
          command < kTrayPaperCommandBase + tray_papers_.size()) {
        SendPaperRequested(tray_papers_[command - kTrayPaperCommandBase].id);
        ShowWindow(window, SW_SHOWNORMAL);
        SetForegroundWindow(window);
      } else if (command >= kTrayPaperDeleteCommandBase &&
                 command <
                     kTrayPaperDeleteCommandBase + tray_papers_.size()) {
        const auto& paper =
            tray_papers_[command - kTrayPaperDeleteCommandBase];
        std::wstring message = L"Delete \"";
        message += paper.label;
        message += L"\"?";
        const int response =
            MessageBoxW(window, message.c_str(), L"Delete paper?",
                        MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2);
        if (response == IDYES) {
          SendPaperDeleteRequested(paper.id);
        }
      }
      break;
  }
}

void FlutterWindow::SendBoundsChanged() {
  HWND window = GetHandle();
  if (!window_channel_ || !window) {
    return;
  }
  if (IsIconic(window)) {
    return;
  }
  RememberActivePaperBounds(window);
  window_channel_->InvokeMethod(
      "boundsChanged", std::make_unique<flutter::EncodableValue>(
                           BoundsValueForPaper(window, active_paper_id_)));
}

void FlutterWindow::SendCloseRequested() {
  SendWindowEvent("closeRequested");
}

void FlutterWindow::SendPaperRequested(const std::string& paper_id) {
  if (!window_channel_) {
    return;
  }
  active_paper_id_ = paper_id;
  flutter::EncodableMap event;
  event[flutter::EncodableValue("paperId")] = flutter::EncodableValue(paper_id);
  window_channel_->InvokeMethod(
      "paperRequested", std::make_unique<flutter::EncodableValue>(event));
}

void FlutterWindow::SendPaperDeleteRequested(const std::string& paper_id) {
  if (!window_channel_) {
    return;
  }
  flutter::EncodableMap event;
  event[flutter::EncodableValue("paperId")] = flutter::EncodableValue(paper_id);
  window_channel_->InvokeMethod(
      "paperDeleteRequested",
      std::make_unique<flutter::EncodableValue>(event));
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
  window_channel_->InvokeMethod(
      method, std::make_unique<flutter::EncodableValue>(
                  WindowEventArguments()));
}

void FlutterWindow::RememberActivePaperId(
    const flutter::EncodableValue* arguments) {
  const std::string paper_id = GetPaperIdArgument(arguments);
  if (!paper_id.empty()) {
    active_paper_id_ = paper_id;
    paper_surfaces_.try_emplace(paper_id);
  }
}

void FlutterWindow::RememberActivePaperBounds(HWND window) {
  if (active_paper_id_.empty()) {
    return;
  }
  if (IsIconic(window)) {
    return;
  }
  RECT bounds;
  if (GetWindowRect(window, &bounds)) {
    RememberPaperBounds(active_paper_id_, bounds);
  }
}

void FlutterWindow::ApplyActivePaperBounds(HWND window) {
  if (!window || !IsWindow(window) || active_paper_id_.empty()) {
    return;
  }
  const auto iterator = paper_surfaces_.find(active_paper_id_);
  if (iterator == paper_surfaces_.end() || !iterator->second.has_bounds) {
    return;
  }
  const RECT bounds = iterator->second.bounds;
  SetWindowPos(window, nullptr, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void FlutterWindow::RememberPaperBounds(const std::string& paper_id,
                                        const RECT& bounds) {
  if (paper_id.empty()) {
    return;
  }
  PaperSurfaceState& state = paper_surfaces_[paper_id];
  state.bounds = bounds;
  state.has_bounds = true;
}

void FlutterWindow::RememberPaperVisibility(const std::string& paper_id,
                                            bool is_visible) {
  if (paper_id.empty()) {
    return;
  }
  paper_surfaces_[paper_id].is_visible = is_visible;
}

void FlutterWindow::RememberPaperPinnedToDesktop(const std::string& paper_id,
                                                 bool enabled) {
  if (paper_id.empty()) {
    return;
  }
  paper_surfaces_[paper_id].pinned_to_desktop = enabled;
}

void FlutterWindow::RememberPaperAlwaysOnTop(const std::string& paper_id,
                                             bool enabled) {
  if (paper_id.empty()) {
    return;
  }
  paper_surfaces_[paper_id].always_on_top = enabled;
}

bool FlutterWindow::ActivePaperPinnedToDesktop() const {
  if (active_paper_id_.empty()) {
    return pinned_to_desktop_;
  }
  const auto iterator = paper_surfaces_.find(active_paper_id_);
  if (iterator == paper_surfaces_.end()) {
    return pinned_to_desktop_;
  }
  return iterator->second.pinned_to_desktop;
}

bool FlutterWindow::ActivePaperAlwaysOnTop() const {
  if (active_paper_id_.empty()) {
    return false;
  }
  const auto iterator = paper_surfaces_.find(active_paper_id_);
  return iterator != paper_surfaces_.end() && iterator->second.always_on_top;
}

void FlutterWindow::RefreshActivePaperZOrder(HWND window) {
  if (!window || !IsWindow(window)) {
    return;
  }
  const bool pinned_to_desktop = ActivePaperPinnedToDesktop();
  pinned_to_desktop_ = pinned_to_desktop;
  const bool fullscreen_blocked =
      avoid_fullscreen_topmost_ && IsForegroundFullscreen(window);
  const bool should_apply_topmost =
      ActivePaperAlwaysOnTop() && !pinned_to_desktop &&
      !fullscreen_blocked;
  if (z_order_state_initialized_ &&
      z_order_pinned_to_desktop_ == pinned_to_desktop &&
      z_order_topmost_applied_ == should_apply_topmost &&
      z_order_fullscreen_blocked_ == fullscreen_blocked) {
    return;
  }
  const HWND insert_after =
      pinned_to_desktop
          ? HWND_BOTTOM
          : (should_apply_topmost ? HWND_TOPMOST : HWND_NOTOPMOST);
  SetWindowPos(window, insert_after, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  z_order_state_initialized_ = true;
  z_order_pinned_to_desktop_ = pinned_to_desktop;
  z_order_topmost_applied_ = should_apply_topmost;
  z_order_fullscreen_blocked_ = fullscreen_blocked;
}

flutter::EncodableValue FlutterWindow::BoundsValueForPaper(
    HWND window, const std::string& paper_id) const {
  if (!paper_id.empty()) {
    const auto iterator = paper_surfaces_.find(paper_id);
    if (iterator != paper_surfaces_.end() && iterator->second.has_bounds) {
      return BoundsValueFromRect(iterator->second.bounds, paper_id);
    }
  }
  return WindowBoundsValue(window, paper_id);
}

flutter::EncodableValue FlutterWindow::WindowEventArguments() const {
  if (active_paper_id_.empty()) {
    return flutter::EncodableValue();
  }
  flutter::EncodableMap event;
  event[flutter::EncodableValue("paperId")] =
      flutter::EncodableValue(active_paper_id_);
  return flutter::EncodableValue(event);
}

void FlutterWindow::OnDestroy() {
  StopSingleInstanceListener();
  StopPersistentScriptProcesses();
  HWND window = GetHandle();
  if (window) {
    KillTimer(window, kFullscreenTopmostRefreshTimerId);
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

  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    tray_icon_added_ = false;
    AddTrayIcon();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_MOVE:
      if (!IsIconic(hwnd)) {
        SendBoundsChanged();
      }
      break;
    case WM_SIZE:
      if (wparam != SIZE_MINIMIZED && !IsIconic(hwnd)) {
        SendBoundsChanged();
      }
      break;
    case WM_CLOSE:
      SendCloseRequested();
      ShowWindow(hwnd, SW_HIDE);
      return 0;
    case WM_HOTKEY:
      if (wparam == kPinnedTodoHotkeyId && todo_hotkey_registered_) {
        SendStartupCommandRequested("reveal-pinned-todo");
        return 0;
      }
      if (wparam == kPinnedNoteHotkeyId && note_hotkey_registered_) {
        SendStartupCommandRequested("reveal-pinned-note");
        return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kFullscreenTopmostRefreshTimerId) {
        RefreshActivePaperZOrder(hwnd);
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
          SendStartupCommandRequested("show");
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
