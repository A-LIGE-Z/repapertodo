#include "flutter_window.h"

#include <dwrite.h>
#include <dwmapi.h>
#include <commdlg.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windowsx.h>

#include <flutter_windows.h>

#include <algorithm>
#include <atomic>
#include <array>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdio>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <limits>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

#include <wrl/client.h>

#include "flutter/generated_plugin_registrant.h"
#include "native_capsule_window.h"
#include "paper_flutter_window.h"
#include "resource.h"
#include "utils.h"

namespace {

struct PersistentScriptProcess {
  std::wstring key;
  HANDLE process = nullptr;
  HANDLE input = nullptr;
  HANDLE job = nullptr;
};

class ScopedWinHandle {
 public:
  explicit ScopedWinHandle(HANDLE handle) : handle_(handle) {}

  ~ScopedWinHandle() { Reset(); }

  ScopedWinHandle(const ScopedWinHandle&) = delete;
  ScopedWinHandle& operator=(const ScopedWinHandle&) = delete;

  bool is_valid() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }

  HANDLE get() const { return handle_; }

 private:
  void Reset() {
    if (is_valid()) {
      CloseHandle(handle_);
      handle_ = nullptr;
    }
  }

  HANDLE handle_ = nullptr;
};

std::mutex g_persistent_script_processes_mutex;
std::vector<PersistentScriptProcess> g_persistent_script_processes;
HWND g_last_external_foreground_window = nullptr;
constexpr LONG kFullscreenTolerance = 2;
constexpr LONG kFullscreenMinCandidateSize = 160;
constexpr int kSettingsWindowMinWidth = 560;
constexpr int kSettingsWindowMinHeight = 360;
constexpr int kSettingsWindowMinDefaultWidth = 672;
constexpr int kSettingsWindowMaxDefaultWidth = 792;
constexpr int kSettingsWindowMinDefaultHeight = 520;
constexpr int kSettingsWindowMaxDefaultHeight = 720;
constexpr int kSettingsWindowWorkAreaInset = 16;
constexpr int kSettingsWindowResizeBorder = 12;
constexpr int kSettingsWindowTitleTop = 20;
constexpr int kSettingsWindowTitleBottom = 64;
constexpr int kSettingsWindowCloseAreaWidth = 64;
constexpr wchar_t kSettingsPositionedProperty[] =
    L"RePaperTodo.SettingsPositioned";
COLORREF g_settings_coordinator_background = RGB(255, 249, 234);

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

std::string FirstStartupCommandLine(std::string command) {
  const size_t newline = command.find('\n');
  if (newline != std::string::npos) {
    command = command.substr(0, newline);
  }
  return TrimAscii(command);
}

bool HasAsciiControlCharacter(const std::string& value) {
  return std::any_of(value.begin(), value.end(), [](unsigned char character) {
    return std::iscntrl(character) != 0;
  });
}

std::string CanonicalStartupCommandLine(std::string command) {
  command = FirstStartupCommandLine(command);
  if (command.empty() || HasAsciiControlCharacter(command)) {
    return std::string();
  }
  return StartupCommandFromArgs(std::vector<std::string>{command});
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

bool HasRawExternalUriControlCharacter(const std::string& uri) {
  for (const char character : uri) {
    const unsigned char ascii = static_cast<unsigned char>(character);
    if (ascii < 0x20 || ascii == 0x7F) {
      return true;
    }
  }
  return HasControlCodePoint(uri);
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

std::optional<int> ParsePositiveAsciiInteger(const std::string& value,
                                             int max_value) {
  if (value.empty() || max_value <= 0) {
    return std::nullopt;
  }
  int result = 0;
  for (const char character : value) {
    const unsigned char ascii = static_cast<unsigned char>(character);
    if (!std::isdigit(ascii)) {
      return std::nullopt;
    }
    const int digit = ascii - '0';
    if (result > (max_value - digit) / 10) {
      return std::nullopt;
    }
    result = result * 10 + digit;
  }
  return result;
}

struct PaperIdArgument {
  bool provided = false;
  bool valid = false;
  std::string value;
};

PaperIdArgument ValidatePaperIdArgumentValue(const std::string& value) {
  if (value.empty() || TrimAscii(value) != value ||
      HasAsciiControlCharacter(value) || HasControlCodePoint(value)) {
    return PaperIdArgument{true, false, std::string()};
  }
  return PaperIdArgument{true, true, value};
}

PaperIdArgument GetPaperIdArgument(
    const flutter::EncodableValue* arguments) {
  if (!arguments) {
    return PaperIdArgument{};
  }
  if (const auto* value = std::get_if<std::string>(arguments)) {
    return ValidatePaperIdArgumentValue(*value);
  }
  if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
    const auto iterator = map->find(flutter::EncodableValue("paperId"));
    if (iterator == map->end()) {
      return PaperIdArgument{};
    }
    if (const auto* value = std::get_if<std::string>(&iterator->second)) {
      return ValidatePaperIdArgumentValue(*value);
    }
    return PaperIdArgument{true, false, std::string()};
  }
  return PaperIdArgument{};
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

std::string GetStringArgumentValue(const flutter::EncodableValue* arguments,
                                   const std::string& key,
                                   const std::string& fallback) {
  if (!arguments) {
    return fallback;
  }
  if (const auto* value = std::get_if<std::string>(arguments)) {
    return *value;
  }
  if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
    return GetStringArgument(*map, key, fallback);
  }
  return fallback;
}

std::vector<std::string> GetStringListArgumentValue(
    const flutter::EncodableValue* arguments) {
  if (!arguments) {
    return {};
  }
  if (const auto* value = std::get_if<std::string>(arguments)) {
    return {*value};
  }
  std::vector<std::string> values;
  if (const auto* list = std::get_if<flutter::EncodableList>(arguments)) {
    for (const auto& item : *list) {
      if (const auto* value = std::get_if<std::string>(&item)) {
        values.push_back(*value);
      }
    }
  }
  return values;
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

std::wstring AppDisplayName() {
#ifdef FLUTTER_VERSION
  std::string version = TrimAscii(FLUTTER_VERSION);
  const size_t metadata_separator = version.find('+');
  if (metadata_separator != std::string::npos) {
    version = TrimAscii(version.substr(0, metadata_separator));
  }
  if (!version.empty()) {
    return std::wstring(L"RePaperTodo v") + Utf8ToWide(version);
  }
#endif
  return L"RePaperTodo";
}

std::wstring AppWindowTitleForPaper(const std::string& paper_title) {
  const std::string title = TrimAscii(paper_title);
  if (title.empty()) {
    return AppDisplayName();
  }
  return std::wstring(L"RePaperTodo - ") + Utf8ToWide(title);
}

std::optional<std::string> WideToUtf8Strict(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  const int size = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) {
    return std::nullopt;
  }
  std::string utf8_value(size, '\0');
  const int converted = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), utf8_value.data(), size, nullptr,
      nullptr);
  if (converted != size) {
    return std::nullopt;
  }
  return utf8_value;
}

std::optional<std::filesystem::path> KnownFolderPath(
    REFKNOWNFOLDERID folder_id) {
  PWSTR raw_path = nullptr;
  if (FAILED(SHGetKnownFolderPath(folder_id, KF_FLAG_CREATE, nullptr,
                                  &raw_path)) ||
      !raw_path) {
    return std::nullopt;
  }
  std::filesystem::path result(raw_path);
  CoTaskMemFree(raw_path);
  return result;
}

std::filesystem::path DataDirectoryConfigPath() {
  const auto local_app_data = KnownFolderPath(FOLDERID_LocalAppData);
  if (!local_app_data) {
    return {};
  }
  return *local_app_data / L"RePaperTodo" / L"storage-path.txt";
}

std::optional<std::filesystem::path> ReadProcessDataDirectoryOverride() {
  std::array<wchar_t, 32768> raw_directory = {};
  const DWORD directory_length = GetEnvironmentVariableW(
      L"REPAPERTODO_DATA_DIRECTORY", raw_directory.data(),
      static_cast<DWORD>(raw_directory.size()));
  if (directory_length == 0 || directory_length >= raw_directory.size()) {
    return std::nullopt;
  }
  const std::wstring directory_value(raw_directory.data(), directory_length);
  if (directory_value.empty() ||
      std::any_of(directory_value.begin(), directory_value.end(),
                  [](wchar_t character) { return character < L' '; })) {
    return std::nullopt;
  }
  std::filesystem::path directory(directory_value);
  if (!directory.is_absolute()) {
    return std::nullopt;
  }
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  return error ? std::nullopt
               : std::optional<std::filesystem::path>(directory);
}

std::optional<std::filesystem::path> ReadConfiguredDataDirectory() {
  const std::filesystem::path config_path = DataDirectoryConfigPath();
  if (config_path.empty()) {
    return std::nullopt;
  }
  std::ifstream input(config_path, std::ios::binary);
  if (!input) {
    return std::nullopt;
  }
  const std::string encoded((std::istreambuf_iterator<char>(input)),
                            std::istreambuf_iterator<char>());
  const auto decoded = Utf8ToWideStrict(encoded);
  if (!decoded || decoded->empty()) {
    return std::nullopt;
  }
  std::filesystem::path directory(*decoded);
  if (!directory.is_absolute()) {
    return std::nullopt;
  }
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  return error ? std::nullopt
               : std::optional<std::filesystem::path>(directory);
}

bool WriteConfiguredDataDirectory(const std::filesystem::path& directory) {
  if (directory.empty() || !directory.is_absolute()) {
    return false;
  }
  std::error_code error;
  std::filesystem::create_directories(directory, error);
  if (error) {
    return false;
  }
  const std::filesystem::path config_path = DataDirectoryConfigPath();
  if (config_path.empty()) {
    return false;
  }
  std::filesystem::create_directories(config_path.parent_path(), error);
  if (error) {
    return false;
  }
  const auto encoded = WideToUtf8Strict(directory.wstring());
  if (!encoded) {
    return false;
  }
  std::ofstream output(config_path,
                       std::ios::binary | std::ios::trunc);
  if (!output) {
    return false;
  }
  output.write(encoded->data(), static_cast<std::streamsize>(encoded->size()));
  return output.good();
}

std::optional<std::filesystem::path> PickDataDirectory(
    HWND owner, const std::filesystem::path& initial_directory) {
  IFileOpenDialog* dialog = nullptr;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog))) ||
      !dialog) {
    return std::nullopt;
  }
  DWORD options = 0;
  dialog->GetOptions(&options);
  dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM |
                     FOS_PATHMUSTEXIST);
  dialog->SetTitle(L"选择 RePaperTodo 数据目录 / Choose data folder");
  IShellItem* initial_item = nullptr;
  if (!initial_directory.empty() &&
      SUCCEEDED(SHCreateItemFromParsingName(initial_directory.c_str(), nullptr,
                                            IID_PPV_ARGS(&initial_item))) &&
      initial_item) {
    dialog->SetFolder(initial_item);
    initial_item->Release();
  }
  const HRESULT shown = dialog->Show(owner);
  if (FAILED(shown)) {
    dialog->Release();
    return std::nullopt;
  }
  IShellItem* selected_item = nullptr;
  if (FAILED(dialog->GetResult(&selected_item)) || !selected_item) {
    dialog->Release();
    return std::nullopt;
  }
  PWSTR selected_path = nullptr;
  const HRESULT path_result =
      selected_item->GetDisplayName(SIGDN_FILESYSPATH, &selected_path);
  selected_item->Release();
  dialog->Release();
  if (FAILED(path_result) || !selected_path) {
    return std::nullopt;
  }
  std::filesystem::path result(selected_path);
  CoTaskMemFree(selected_path);
  return result;
}

std::filesystem::path EnsureLogDirectory(std::filesystem::path directory) {
  std::error_code error;
  std::filesystem::create_directories(directory / L"LOG", error);
  return directory;
}

std::filesystem::path ResolveDataDirectory(HWND owner) {
  // Automated validation and managed deployments may isolate one process from
  // the user's persisted storage-path selection.  The override is inherited
  // only by that process and is never written back to storage-path.txt.
  if (const auto process_override = ReadProcessDataDirectoryOverride()) {
    return EnsureLogDirectory(*process_override);
  }
  if (const auto configured = ReadConfiguredDataDirectory()) {
    return EnsureLogDirectory(*configured);
  }
  std::array<wchar_t, 32768> executable_path = {};
  const DWORD executable_length = GetModuleFileNameW(
      nullptr, executable_path.data(), static_cast<DWORD>(executable_path.size()));
  if (executable_length > 0 && executable_length < executable_path.size()) {
    const std::filesystem::path legacy_directory =
        std::filesystem::path(executable_path.data()).parent_path();
    std::error_code legacy_error;
    if (std::filesystem::is_regular_file(legacy_directory / L"data.json",
                                         legacy_error) &&
        !legacy_error) {
      return EnsureLogDirectory(legacy_directory);
    }
  }
  std::filesystem::path fallback;
  if (const auto documents = KnownFolderPath(FOLDERID_Documents)) {
    fallback = *documents / L"RePaperTodo";
  } else if (const auto local_app_data = KnownFolderPath(FOLDERID_LocalAppData)) {
    fallback = *local_app_data / L"RePaperTodo" / L"Data";
  }
  MessageBoxW(owner,
              L"请选择 data.json 和备份文件的保存目录。\nChoose where "
              L"RePaperTodo should save data.json and backups.",
              L"RePaperTodo 首次运行 / First run",
              MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
  const auto selected = PickDataDirectory(owner, fallback);
  const std::filesystem::path resolved = selected.value_or(fallback);
  WriteConfiguredDataDirectory(resolved);
  return EnsureLogDirectory(resolved);
}

std::wstring TrimWide(const std::wstring& value) {
  const auto is_trim_character = [](wchar_t character) {
    return character <= L' ' || character == 0x00A0;
  };
  const auto begin =
      std::find_if_not(value.begin(), value.end(), is_trim_character);
  const auto end =
      std::find_if_not(value.rbegin(), value.rend(), is_trim_character).base();
  if (begin >= end) {
    return std::wstring();
  }
  return std::wstring(begin, end);
}

std::wstring SanitizeFontFamilyName(const std::wstring& value,
                                    bool strip_registry_type_suffix) {
  std::wstring cleaned;
  cleaned.reserve(value.size());
  for (const wchar_t character : value) {
    if (!IsControlCodePoint(character)) {
      cleaned.push_back(character);
    }
  }
  cleaned = TrimWide(cleaned);
  if (!cleaned.empty() && cleaned.front() == L'@') {
    cleaned.erase(cleaned.begin());
    cleaned = TrimWide(cleaned);
  }
  if (strip_registry_type_suffix && !cleaned.empty() &&
      cleaned.back() == L')') {
    const size_t suffix_start = cleaned.rfind(L" (");
    if (suffix_start != std::wstring::npos) {
      cleaned = TrimWide(cleaned.substr(0, suffix_start));
    }
  }
  if (cleaned.size() > 128) {
    cleaned.resize(128);
    cleaned = TrimWide(cleaned);
  }
  return cleaned;
}

int CompareFontFamilyName(const std::wstring& left,
                          const std::wstring& right,
                          bool ignore_case) {
  return CompareStringOrdinal(left.c_str(), static_cast<int>(left.size()),
                              right.c_str(), static_cast<int>(right.size()),
                              ignore_case ? TRUE : FALSE);
}

bool FontLocaleStartsWith(const std::wstring& locale,
                          const wchar_t first,
                          const wchar_t second) {
  return locale.size() >= 2 && std::towlower(locale[0]) == first &&
         std::towlower(locale[1]) == second;
}

bool FontLocaleEquals(const std::wstring& left, const std::wstring& right) {
  return !left.empty() && !right.empty() &&
         CompareStringOrdinal(left.c_str(), static_cast<int>(left.size()),
                              right.c_str(), static_cast<int>(right.size()),
                              TRUE) == CSTR_EQUAL;
}

std::wstring UserFontLocaleName() {
  wchar_t locale_name[LOCALE_NAME_MAX_LENGTH] = {};
  const int length = GetUserDefaultLocaleName(
      locale_name, static_cast<int>(std::size(locale_name)));
  return length > 0 ? std::wstring(locale_name, length - 1) : std::wstring();
}

int FontLocalePriority(const std::wstring& locale,
                       const std::wstring& preferred_locale) {
  // PaperTodo presents Chinese family names before Latin names when a
  // localized alias is available.  Prefer the user's exact locale within
  // each group, then English, and finally any remaining localized alias.
  if (FontLocaleStartsWith(locale, L'z', L'h')) {
    return FontLocaleEquals(locale, preferred_locale) ? 0 : 1;
  }
  if (FontLocaleEquals(locale, preferred_locale)) {
    return 2;
  }
  if (FontLocaleStartsWith(locale, L'e', L'n')) {
    return 3;
  }
  return 4;
}

bool EqualFontFamilyName(const std::wstring& left,
                         const std::wstring& right) {
  return CompareFontFamilyName(left, right, true) == CSTR_EQUAL;
}

void AddFontFamily(std::vector<std::wstring>* families,
                   const std::wstring& family) {
  if (family.empty()) {
    return;
  }
  families->push_back(family);
}

void AddRegistryFontFamilies(HKEY root,
                             const wchar_t* subkey,
                             std::vector<std::wstring>* families) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(root, subkey, 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return;
  }
  DWORD value_count = 0;
  DWORD max_value_name_length = 0;
  if (RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, nullptr, nullptr,
                       nullptr, &value_count, &max_value_name_length, nullptr,
                       nullptr, nullptr) != ERROR_SUCCESS) {
    RegCloseKey(key);
    return;
  }
  std::vector<wchar_t> name(max_value_name_length + 2);
  for (DWORD index = 0; index < value_count; ++index) {
    DWORD name_length = static_cast<DWORD>(name.size());
    DWORD type = 0;
    const LONG status = RegEnumValueW(key, index, name.data(), &name_length,
                                      nullptr, &type, nullptr, nullptr);
    if (status != ERROR_SUCCESS) {
      continue;
    }
    if (type != REG_SZ && type != REG_EXPAND_SZ) {
      continue;
    }
    AddFontFamily(families, SanitizeFontFamilyName(
                                std::wstring(name.data(), name_length), true));
  }
  RegCloseKey(key);
}

struct FontEnumerationContext {
  std::vector<std::wstring>* families;
};

int CALLBACK AddEnumeratedFontFamily(const LOGFONTW* log_font,
                                     const TEXTMETRICW*,
                                     DWORD,
                                     LPARAM data) {
  auto* context = reinterpret_cast<FontEnumerationContext*>(data);
  if (!context || !context->families || !log_font) {
    return 1;
  }
  AddFontFamily(context->families,
                SanitizeFontFamilyName(log_font->lfFaceName, false));
  return 1;
}

void AddGdiFontFamilies(std::vector<std::wstring>* families) {
  HDC screen = GetDC(nullptr);
  if (!screen) {
    return;
  }
  LOGFONTW log_font = {};
  log_font.lfCharSet = DEFAULT_CHARSET;
  FontEnumerationContext context = {families};
  EnumFontFamiliesExW(screen, &log_font,
                      reinterpret_cast<FONTENUMPROCW>(AddEnumeratedFontFamily),
                      reinterpret_cast<LPARAM>(&context), 0);
  ReleaseDC(nullptr, screen);
}

bool AddDirectWriteFontFamilies(std::vector<std::wstring>* families) {
  if (!families) {
    return false;
  }
  Microsoft::WRL::ComPtr<IDWriteFactory> factory;
  const HRESULT factory_status = DWriteCreateFactory(
      DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
      reinterpret_cast<IUnknown**>(factory.GetAddressOf()));
  if (FAILED(factory_status) || !factory) {
    return false;
  }

  Microsoft::WRL::ComPtr<IDWriteFontCollection> collection;
  if (FAILED(factory->GetSystemFontCollection(&collection, FALSE)) ||
      !collection) {
    return false;
  }
  const std::wstring preferred_locale = UserFontLocaleName();
  const UINT32 family_count = collection->GetFontFamilyCount();
  for (UINT32 index = 0; index < family_count; ++index) {
    Microsoft::WRL::ComPtr<IDWriteFontFamily> family;
    if (FAILED(collection->GetFontFamily(index, &family)) || !family) {
      continue;
    }
    Microsoft::WRL::ComPtr<IDWriteLocalizedStrings> names;
    if (FAILED(family->GetFamilyNames(&names)) || !names) {
      continue;
    }
    const UINT32 name_count = names->GetCount();
    std::wstring selected_name;
    int selected_priority = std::numeric_limits<int>::max();
    for (UINT32 name_index = 0; name_index < name_count; ++name_index) {
      UINT32 locale_length = 0;
      if (FAILED(names->GetLocaleNameLength(name_index, &locale_length))) {
        continue;
      }
      std::vector<wchar_t> locale_buffer(
          static_cast<size_t>(locale_length) + 1, L'\0');
      if (FAILED(names->GetLocaleName(name_index, locale_buffer.data(),
                                      locale_length + 1))) {
        continue;
      }
      UINT32 length = 0;
      if (FAILED(names->GetStringLength(name_index, &length))) {
        continue;
      }
      std::vector<wchar_t> buffer(static_cast<size_t>(length) + 1, L'\0');
      if (FAILED(names->GetString(name_index, buffer.data(), length + 1))) {
        continue;
      }
      const std::wstring candidate =
          SanitizeFontFamilyName(std::wstring(buffer.data()), false);
      if (candidate.empty()) {
        continue;
      }
      const std::wstring locale(locale_buffer.data());
      const int priority = FontLocalePriority(locale, preferred_locale);
      if (priority < selected_priority ||
          (priority == selected_priority &&
           (selected_name.empty() ||
            CompareFontFamilyName(candidate, selected_name, true) ==
                CSTR_LESS_THAN))) {
        selected_name = candidate;
        selected_priority = priority;
      }
    }
    if (!selected_name.empty()) {
      AddFontFamily(families, selected_name);
    }
  }
  return true;
}

flutter::EncodableList InstalledFontFamilies() {
  constexpr wchar_t kFontsRegistryPath[] =
      L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts";
  std::vector<std::wstring> families;
  // DirectWrite is the preferred source because it gives us a localized
  // family name, but it is not guaranteed to expose every legacy, per-user,
  // or newly-installed face immediately.  Merge all three Windows sources and
  // de-duplicate below instead of treating GDI/registry as an all-or-nothing
  // fallback; otherwise a successful DirectWrite call silently hides fonts
  // that the Settings picker can still use.
  AddDirectWriteFontFamilies(&families);
  AddGdiFontFamilies(&families);
  AddRegistryFontFamilies(HKEY_LOCAL_MACHINE, kFontsRegistryPath, &families);
  AddRegistryFontFamilies(HKEY_CURRENT_USER, kFontsRegistryPath, &families);
  std::sort(families.begin(), families.end(),
            [](const std::wstring& left, const std::wstring& right) {
              const int comparison = CompareFontFamilyName(left, right, true);
              if (comparison == CSTR_LESS_THAN) {
                return true;
              }
              if (comparison == CSTR_GREATER_THAN) {
                return false;
              }
              return CompareFontFamilyName(left, right, false) ==
                     CSTR_LESS_THAN;
            });
  families.erase(std::unique(families.begin(), families.end(),
                             EqualFontFamilyName),
                 families.end());
  flutter::EncodableList result;
  result.reserve(families.size());
  for (const auto& family : families) {
    const auto utf8_family = WideToUtf8Strict(family);
    if (utf8_family && !utf8_family->empty()) {
      result.emplace_back(*utf8_family);
    }
  }
  return result;
}

struct PrimaryMonitorDeviceNameLookup {
  std::wstring device_name;
};

BOOL CALLBACK FindPrimaryMonitorDeviceName(HMONITOR monitor,
                                            HDC,
                                            LPRECT,
                                            LPARAM data) {
  auto* context = reinterpret_cast<PrimaryMonitorDeviceNameLookup*>(data);
  if (!context) {
    return TRUE;
  }
  MONITORINFOEXW monitor_info = {};
  monitor_info.cbSize = sizeof(MONITORINFOEXW);
  if (GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&monitor_info)) !=
      TRUE) {
    return TRUE;
  }
  if ((monitor_info.dwFlags & MONITORINFOF_PRIMARY) == 0) {
    return TRUE;
  }
  context->device_name = monitor_info.szDevice;
  return FALSE;
}

std::wstring PrimaryMonitorDeviceName() {
  PrimaryMonitorDeviceNameLookup context;
  EnumDisplayMonitors(nullptr, nullptr, FindPrimaryMonitorDeviceName,
                      reinterpret_cast<LPARAM>(&context));
  return context.device_name;
}

std::string NormalizeQueueMonitorDeviceName(
    const std::string& monitor_device_name) {
  const std::string trimmed = TrimAscii(monitor_device_name);
  if (trimmed.empty()) {
    return "";
  }
  const std::wstring primary = PrimaryMonitorDeviceName();
  return !primary.empty() && Utf8ToWide(trimmed) == primary ? "" : trimmed;
}

std::wstring GetWideStringArgument(const flutter::EncodableMap& map,
                                   const std::string& key,
                                   const std::wstring& fallback) {
  const std::string value = GetStringArgument(map, key, "");
  if (value.empty()) {
    return fallback;
  }
  return Utf8ToWide(value);
}

TrayMenuLabels TrayMenuLabelsFromMap(const flutter::EncodableMap& map,
                                     const TrayMenuLabels& fallback) {
  TrayMenuLabels labels = fallback;
  labels.new_todo = GetWideStringArgument(map, "newTodo", labels.new_todo);
  labels.new_note = GetWideStringArgument(map, "newNote", labels.new_note);
  labels.settings = GetWideStringArgument(map, "settings", labels.settings);
  labels.show_all = GetWideStringArgument(map, "showAll", labels.show_all);
  labels.hide_all = GetWideStringArgument(map, "hideAll", labels.hide_all);
  labels.toggle_all =
      GetWideStringArgument(map, "toggleAll", labels.toggle_all);
  labels.papers = GetWideStringArgument(map, "papers", labels.papers);
  labels.delete_paper =
      GetWideStringArgument(map, "deletePaper", labels.delete_paper);
  labels.delete_confirm_title = GetWideStringArgument(
      map, "deleteConfirmTitle", labels.delete_confirm_title);
  labels.delete_confirm_message = GetWideStringArgument(
      map, "deleteConfirmMessage", labels.delete_confirm_message);
  labels.inline_confirm_delete = GetWideStringArgument(
      map, "inlineConfirmDelete", labels.inline_confirm_delete);
  labels.inline_confirm_action = GetWideStringArgument(
      map, "inlineConfirmAction", labels.inline_confirm_action);
  labels.cancel = GetWideStringArgument(map, "cancel", labels.cancel);
  labels.exit = GetWideStringArgument(map, "exit", labels.exit);
  labels.todo_paper =
      GetWideStringArgument(map, "todoPaper", labels.todo_paper);
  labels.note_paper =
      GetWideStringArgument(map, "notePaper", labels.note_paper);
  labels.script_paper =
      GetWideStringArgument(map, "scriptPaper", labels.script_paper);
  labels.hidden = GetWideStringArgument(map, "hidden", labels.hidden);
  labels.collapsed =
      GetWideStringArgument(map, "collapsed", labels.collapsed);
  labels.desktop = GetWideStringArgument(map, "desktop", labels.desktop);
  labels.topmost = GetWideStringArgument(map, "topmost", labels.topmost);
  return labels;
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

std::wstring CurrentExecutablePath();

std::wstring ExecutableDirectory() {
  const std::wstring executable_path = CurrentExecutablePath();
  if (executable_path.empty()) {
    return std::wstring();
  }
  std::wstring directory(executable_path);
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

bool WriteAllToFile(HANDLE file, const void* data, size_t size) {
  const char* bytes = static_cast<const char*>(data);
  size_t offset = 0;
  while (offset < size) {
    const DWORD chunk = static_cast<DWORD>(
        std::min<size_t>(size - offset, 1024u * 1024u));
    DWORD written = 0;
    if (!WriteFile(file, bytes + offset, chunk, &written, nullptr) ||
        written == 0) {
      return false;
    }
    offset += written;
  }
  return true;
}

std::wstring WriteScriptCapsuleFile(const std::string& script) {
  const std::wstring directory = ScriptCapsuleTempDirectory();
  std::array<wchar_t, MAX_PATH> path = {};
  if (GetTempFileNameW(directory.c_str(), L"sc", 0, path.data()) == 0) {
    return std::wstring();
  }
  const std::wstring script_path = std::wstring(path.data()) + L".ps1";
  if (!MoveFileExW(path.data(), script_path.c_str(),
                   MOVEFILE_REPLACE_EXISTING)) {
    DeleteFileW(path.data());
    return std::wstring();
  }

  HANDLE file = CreateFileW(script_path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    DeleteFileW(script_path.c_str());
    return std::wstring();
  }
  constexpr unsigned char kUtf8Bom[] = {0xEF, 0xBB, 0xBF};
  const bool write_succeeded =
      WriteAllToFile(file, kUtf8Bom, sizeof(kUtf8Bom)) &&
      WriteAllToFile(file, script.data(), script.size());
  CloseHandle(file);
  if (!write_succeeded) {
    DeleteFileW(script_path.c_str());
    return std::wstring();
  }
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
  // Closing a kill-on-close job terminates the persistent host and every
  // PowerShell process it spawned, including a script that is still running.
  // This also protects abnormal application exits because Windows closes the
  // coordinator process's job handle automatically.
  if (entry.job) {
    CloseHandle(entry.job);
    entry.job = nullptr;
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

HANDLE CreateKillOnCloseJob() {
  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (!job) {
    return nullptr;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION job_information = {};
  job_information.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                               &job_information,
                               sizeof(job_information))) {
    CloseHandle(job);
    return nullptr;
  }
  return job;
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
      L" -NoProfile -NonInteractive -ExecutionPolicy Bypass -NoExit "
      L"-Command -";
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
  HANDLE process_job = CreateKillOnCloseJob();
  const DWORD creation_flags =
      (hide_window ? CREATE_NO_WINDOW : 0) | CREATE_SUSPENDED;
  const BOOL created = CreateProcessW(
      nullptr, command_line.data(), nullptr, nullptr, TRUE, creation_flags,
      nullptr, nullptr, &startup_info, &process_information);
  CloseHandle(input_read);
  if (null_output != INVALID_HANDLE_VALUE) {
    CloseHandle(null_output);
  }
  if (!created) {
    if (process_job) {
      CloseHandle(process_job);
    }
    CloseHandle(input_write);
    return nullptr;
  }
  if (process_job &&
      !AssignProcessToJobObject(process_job, process_information.hProcess)) {
    CloseHandle(process_job);
    process_job = nullptr;
  }
  if (ResumeThread(process_information.hThread) == static_cast<DWORD>(-1)) {
    CloseHandle(input_write);
    if (process_job) {
      CloseHandle(process_job);
    }
    TerminateProcess(process_information.hProcess, 0);
    WaitForSingleObject(process_information.hProcess, 1000);
    CloseHandle(process_information.hThread);
    CloseHandle(process_information.hProcess);
    return nullptr;
  }
  CloseHandle(process_information.hThread);
  g_persistent_script_processes.push_back(PersistentScriptProcess{
      key, process_information.hProcess, input_write, process_job});
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

std::wstring TrayPaperLabel(const flutter::EncodableMap& map,
                            const TrayMenuLabels& labels) {
  const std::wstring tray_label =
      GetWideStringArgument(map, "trayLabel", std::wstring());
  if (!tray_label.empty()) {
    return tray_label;
  }
  const bool is_visible = GetBoolArgument(map, "isVisible", false);
  const bool is_collapsed = GetBoolArgument(map, "isCollapsed", false);
  const bool always_on_top = GetBoolArgument(map, "alwaysOnTop", false);
  const bool is_pinned_to_desktop =
      GetBoolArgument(map, "isPinnedToDesktop", false);
  std::wstring title = Utf8ToWide(GetStringArgument(map, "title", "Untitled"));
  if (title.empty()) {
    title = L"Untitled";
  }
  std::wstring label = title;
  std::wstring status;
  auto append_status = [&status](const std::wstring& value) {
    if (!status.empty()) {
      status += L", ";
    }
    status += value;
  };
  if (!is_visible) {
    append_status(labels.hidden);
  }
  if (is_collapsed) {
    append_status(labels.collapsed);
  }
  if (is_pinned_to_desktop) {
    append_status(labels.desktop);
  }
  if (always_on_top) {
    append_status(labels.topmost);
  }
  if (!status.empty()) {
    label += L" (";
    label += status;
    label += L")";
  }
  return label;
}

class ScopedMenu {
 public:
  explicit ScopedMenu(HMENU menu) : menu_(menu) {}

  ~ScopedMenu() { Reset(); }

  ScopedMenu(const ScopedMenu&) = delete;
  ScopedMenu& operator=(const ScopedMenu&) = delete;

  HMENU get() const { return menu_; }

  HMENU release() {
    HMENU menu = menu_;
    menu_ = nullptr;
    return menu;
  }

 private:
  void Reset() {
    if (menu_) {
      DestroyMenu(menu_);
      menu_ = nullptr;
    }
  }

  HMENU menu_;
};

std::wstring CurrentExecutablePath() {
  std::vector<wchar_t> buffer(MAX_PATH);
  while (buffer.size() <= 32768) {
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (length < buffer.size()) {
      return std::wstring(buffer.data(), length);
    }
    buffer.resize(buffer.size() * 2);
  }
  return std::wstring();
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
    const std::wstring module_path = CurrentExecutablePath();
    if (module_path.empty()) {
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

bool SetHideFromWindowSwitcher(HWND window, bool enabled) {
  SetLastError(ERROR_SUCCESS);
  LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  if (extended_style == 0 && GetLastError() != ERROR_SUCCESS) {
    return false;
  }
  if (enabled) {
    extended_style |= WS_EX_TOOLWINDOW;
    extended_style &= ~WS_EX_APPWINDOW;
  } else {
    extended_style &= ~WS_EX_TOOLWINDOW;
    extended_style |= WS_EX_APPWINDOW;
  }
  SetLastError(ERROR_SUCCESS);
  if (SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style) == 0 &&
      GetLastError() != ERROR_SUCCESS) {
    return false;
  }
  return SetWindowPos(window, nullptr, 0, 0, 0, 0,
                      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                          SWP_NOACTIVATE | SWP_FRAMECHANGED) != 0;
}

int ScaleSettingsMetric(UINT dpi, int logical_pixels) {
  return MulDiv(logical_pixels, dpi > 0 ? static_cast<int>(dpi) : 96, 96);
}

double UnscaleSettingsMetric(UINT dpi, LONG physical_pixels) {
  return static_cast<double>(physical_pixels) * 96.0 /
         static_cast<double>(dpi > 0 ? dpi : 96);
}

void PaintSettingsCoordinatorBackground(HWND window, HDC dc) {
  if (!window || !dc) {
    return;
  }
  RECT client = {};
  if (!GetClientRect(window, &client)) {
    return;
  }
  HBRUSH transparent_brush = CreateSolidBrush(RGB(1, 2, 3));
  FillRect(dc, &client, transparent_brush);
  DeleteObject(transparent_brush);

  const UINT dpi = GetDpiForWindow(window) > 0 ? GetDpiForWindow(window) : 96;
  const int diameter = ScaleSettingsMetric(dpi, 36);
  HBRUSH paper_brush = CreateSolidBrush(g_settings_coordinator_background);
  HGDIOBJ old_brush = SelectObject(dc, paper_brush);
  HGDIOBJ old_pen = SelectObject(dc, GetStockObject(NULL_PEN));
  RoundRect(dc, 0, 0, client.right, client.bottom, diameter, diameter);
  SelectObject(dc, old_pen);
  SelectObject(dc, old_brush);
  DeleteObject(paper_brush);
}

void ApplySettingsCoordinatorWindowStyle(HWND window) {
  if (!window) {
    return;
  }
  SetWindowLongPtrW(window, GWL_STYLE,
                    WS_POPUP | WS_THICKFRAME | WS_CLIPCHILDREN);
  LONG_PTR extended_style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  extended_style |= WS_EX_LAYERED | WS_EX_TOOLWINDOW;
  extended_style &= ~WS_EX_APPWINDOW;
  SetWindowLongPtrW(window, GWL_EXSTYLE, extended_style);
  SetLayeredWindowAttributes(window, RGB(1, 2, 3), 0, LWA_COLORKEY);
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

int SettingsCoordinatorHitTest(HWND window, LPARAM lparam) {
  RECT bounds = {};
  if (!window || !GetWindowRect(window, &bounds)) {
    return HTCLIENT;
  }
  const UINT dpi = GetDpiForWindow(window) > 0 ? GetDpiForWindow(window) : 96;
  const int x = GET_X_LPARAM(lparam);
  const int y = GET_Y_LPARAM(lparam);
  const int edge = ScaleSettingsMetric(dpi, kSettingsWindowResizeBorder);
  const bool left = x < bounds.left + edge;
  const bool right = x >= bounds.right - edge;
  const bool top = y < bounds.top + edge;
  const bool bottom = y >= bounds.bottom - edge;
  if (top && left) return HTTOPLEFT;
  if (top && right) return HTTOPRIGHT;
  if (bottom && left) return HTBOTTOMLEFT;
  if (bottom && right) return HTBOTTOMRIGHT;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  if (top) return HTTOP;
  if (bottom) return HTBOTTOM;

  POINT client_point = {x, y};
  ScreenToClient(window, &client_point);
  RECT client = {};
  GetClientRect(window, &client);
  const int title_top = ScaleSettingsMetric(dpi, kSettingsWindowTitleTop);
  const int title_bottom =
      ScaleSettingsMetric(dpi, kSettingsWindowTitleBottom);
  const int close_width =
      ScaleSettingsMetric(dpi, kSettingsWindowCloseAreaWidth);
  if (client_point.y >= title_top && client_point.y < title_bottom &&
      client_point.x < client.right - close_width) {
    return HTCAPTION;
  }
  return HTCLIENT;
}

void ShowSettingsCoordinatorWindow(HWND window) {
  if (!window) {
    return;
  }
  // The coordinator spends most of its lifetime hidden after having carried
  // the active paper title. Reapply the borderless chrome before every reveal
  // and clear that stale caption so transparent shadow pixels can never expose
  // an old title-band frame behind the settings paper.
  ApplySettingsCoordinatorWindowStyle(window);
  SetWindowTextW(window, L"");
  SetHideFromWindowSwitcher(window, true);
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (monitor && GetMonitorInfoW(monitor, &info)) {
    const LONG work_width = info.rcWork.right - info.rcWork.left;
    const LONG work_height = info.rcWork.bottom - info.rcWork.top;
    const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor) > 0
                         ? FlutterDesktopGetDpiForMonitor(monitor)
                         : 96;
    const double logical_work_width = UnscaleSettingsMetric(dpi, work_width);
    const double logical_work_height = UnscaleSettingsMetric(dpi, work_height);
    const double logical_width = std::clamp(
        logical_work_width - 64.0,
        static_cast<double>(kSettingsWindowMinDefaultWidth),
        static_cast<double>(kSettingsWindowMaxDefaultWidth));
    const double logical_height = std::clamp(
        logical_work_height * 0.72,
        static_cast<double>(kSettingsWindowMinDefaultHeight),
        static_cast<double>(kSettingsWindowMaxDefaultHeight));
    const LONG available_width = std::max<LONG>(
        1, work_width -
               2 * ScaleSettingsMetric(dpi, kSettingsWindowWorkAreaInset));
    const LONG available_height = std::max<LONG>(
        1, work_height -
               2 * ScaleSettingsMetric(dpi, kSettingsWindowWorkAreaInset));
    const LONG width = std::min<LONG>(
        available_width,
        static_cast<LONG>(std::lround(
            logical_width * static_cast<double>(dpi) / 96.0)));
    const LONG height = std::min<LONG>(
        available_height,
        static_cast<LONG>(std::lround(
            logical_height * static_cast<double>(dpi) / 96.0)));
    RECT current = {};
    const bool has_saved_bounds =
        GetPropW(window, kSettingsPositionedProperty) != nullptr &&
        GetWindowRect(window, &current) && current.right > current.left &&
        current.bottom > current.top;
    if (!has_saved_bounds) {
      const LONG x = info.rcWork.left + (work_width - width) / 2;
      const LONG y = info.rcWork.top + (work_height - height) / 2;
      SetWindowPos(window, HWND_TOP, x, y, width, height,
                   SWP_NOACTIVATE | SWP_FRAMECHANGED);
      SetPropW(window, kSettingsPositionedProperty,
               reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
    } else {
      // The settings paper is deliberately movable/resizable. Keep the last
      // user bounds across hide/show cycles, only nudging them back into the
      // current monitor work area after a display/DPI change.
      const LONG saved_width = current.right - current.left;
      const LONG saved_height = current.bottom - current.top;
      const LONG usable_width = std::max<LONG>(1, work_width -
                                                    2 * ScaleSettingsMetric(
                                                        dpi,
                                                        kSettingsWindowWorkAreaInset));
      const LONG usable_height = std::max<LONG>(1, work_height -
                                                     2 * ScaleSettingsMetric(
                                                         dpi,
                                                         kSettingsWindowWorkAreaInset));
      const LONG clamped_width = std::clamp(saved_width,
                                            static_cast<LONG>(ScaleSettingsMetric(
                                                dpi, kSettingsWindowMinWidth)),
                                            usable_width);
      const LONG clamped_height = std::clamp(saved_height,
                                             static_cast<LONG>(ScaleSettingsMetric(
                                                 dpi, kSettingsWindowMinHeight)),
                                             usable_height);
      const LONG min_x = info.rcWork.left +
                         ScaleSettingsMetric(dpi, kSettingsWindowWorkAreaInset);
      const LONG min_y = info.rcWork.top +
                         ScaleSettingsMetric(dpi, kSettingsWindowWorkAreaInset);
      const LONG max_x = std::max(min_x, info.rcWork.right -
                                           ScaleSettingsMetric(
                                               dpi, kSettingsWindowWorkAreaInset) -
                                           clamped_width);
      const LONG max_y = std::max(min_y, info.rcWork.bottom -
                                           ScaleSettingsMetric(
                                               dpi, kSettingsWindowWorkAreaInset) -
                                           clamped_height);
      const LONG x = std::clamp(current.left, min_x, max_x);
      const LONG y = std::clamp(current.top, min_y, max_y);
      SetWindowPos(window, HWND_TOP, x, y, clamped_width, clamped_height,
                   SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
  }
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
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

flutter::EncodableValue LogicalBoundsValueFromRect(const RECT& bounds) {
  const HMONITOR monitor =
      MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);
  const UINT monitor_dpi =
      monitor ? FlutterDesktopGetDpiForMonitor(monitor) : 96;
  const double scale = 96.0 /
                       static_cast<double>(monitor_dpi > 0 ? monitor_dpi : 96);
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(bounds.left) * scale)},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(bounds.top) * scale)},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(
           static_cast<double>(bounds.right - bounds.left) * scale)},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(
           static_cast<double>(bounds.bottom - bounds.top) * scale)},
  });
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
  MonitorWorkAreaLookup context(
      Utf8ToWide(NormalizeQueueMonitorDeviceName(monitor_device_name)));
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
    HWND window,
    const flutter::EncodableValue* arguments,
    const std::string& cached_monitor_device_name = "") {
  std::string monitor_device_name;
  if (arguments) {
    if (const auto* map = std::get_if<flutter::EncodableMap>(arguments)) {
      monitor_device_name = GetStringArgument(*map, "monitorDeviceName", "");
    }
  }
  if (monitor_device_name.empty()) {
    monitor_device_name = cached_monitor_device_name;
  }

  if (auto named_work_area = WorkAreaForMonitorDeviceName(monitor_device_name)) {
    return LogicalBoundsValueFromRect(*named_work_area);
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
    return LogicalBoundsValueFromRect(monitor_info.rcWork);
  }

  return LogicalBoundsValueFromRect(requested_bounds);
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
    const auto function_key = ParsePositiveAsciiInteger(compact.substr(1), 24);
    if (function_key && *function_key >= 1) {
      *key = VK_F1 + static_cast<UINT>(*function_key - 1);
      return true;
    }
  }

  std::string numpad_suffix;
  if (compact.rfind("NUMPAD", 0) == 0) {
    numpad_suffix = compact.substr(6);
  } else if (compact.rfind("NUMBERPAD", 0) == 0) {
    numpad_suffix = compact.substr(9);
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
constexpr UINT kStyleTrayMenuMessage = WM_APP + 3;
constexpr UINT kTrayNewTodoCommand = 40001;
constexpr UINT kTrayNewNoteCommand = 40002;
constexpr UINT kTraySettingsCommand = 40003;
constexpr UINT kTrayShowCommand = 40004;
constexpr UINT kTrayHideCommand = 40005;
constexpr UINT kTrayExitCommand = 40006;
constexpr UINT kTrayToggleCommand = 40007;
constexpr UINT kTrayPaperCommandBase = 41000;
constexpr UINT kTrayPaperDeleteCommandBase = 45000;
constexpr int kTrayMenuMinimumWidth = 190;
// WPF's 190px menu minimum is carried by a 168px content grid plus padding.
// Win32 adds shell metrics around owner-drawn rows, so compensate the row
// measurement to preserve the source menu footprint.
constexpr int kTrayMenuNativeWidthCompensation = 21;
constexpr int kTrayMenuItemHeight = 24;
constexpr int kTrayMenuHeaderHeight = 22;
constexpr int kTrayMenuItemRadius = 8;
constexpr int kTrayMenuShellRadius = 10;
constexpr int kTrayMenuCheckboxSize = 13;
constexpr int kTrayMenuPadding = 4;
constexpr int kPinnedTodoHotkeyId = 42001;
constexpr int kPinnedNoteHotkeyId = 42002;
constexpr UINT_PTR kFullscreenTopmostRefreshTimerId = 43001;
constexpr UINT kFullscreenTopmostRefreshIntervalMs = 250;
constexpr UINT kTrayMenuChromeRefreshIntervalMs = 16;
constexpr wchar_t kSingleInstancePipeName[] =
    L"\\\\.\\pipe\\RePaperTodo-SingleInstance-Activate";
constexpr size_t kMaxSingleInstanceCommandBytes = 4096;

namespace {

bool SignalPrimaryInstanceFromChannel(const std::vector<std::string>& args) {
  return SignalStartupCommandPipe(kSingleInstancePipeName, args, 6, 180, 70);
}

int ScaleTrayMetric(HWND window, int logical_pixels) {
  const UINT dpi = window ? GetDpiForWindow(window) : 96;
  return MulDiv(logical_pixels, static_cast<int>(dpi), 96);
}

bool IsSystemAppThemeDark() {
  DWORD light_mode = 1;
  DWORD size = sizeof(light_mode);
  const LSTATUS status = RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
      L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light_mode, &size);
  return status == ERROR_SUCCESS && light_mode == 0;
}

COLORREF MixTrayColor(COLORREF first, COLORREF second, double amount) {
  const double t = std::clamp(amount, 0.0, 1.0);
  const auto channel = [t](BYTE first_channel, BYTE second_channel) {
    return static_cast<BYTE>(std::clamp(
        static_cast<int>(std::lround(first_channel +
                                     (second_channel - first_channel) * t)),
        0, 255));
  };
  return RGB(channel(GetRValue(first), GetRValue(second)),
             channel(GetGValue(first), GetGValue(second)),
             channel(GetBValue(first), GetBValue(second)));
}

bool ParseTrayHexColor(const std::string& value, COLORREF* color) {
  if (!color) {
    return false;
  }
  std::string hex = TrimAscii(value);
  if (!hex.empty() && hex.front() == '#') {
    hex.erase(hex.begin());
  }
  if (hex.size() != 6 ||
      !std::all_of(hex.begin(), hex.end(), [](unsigned char character) {
        return std::isxdigit(character) != 0;
      })) {
    return false;
  }
  try {
    const unsigned long rgb = std::stoul(hex, nullptr, 16);
    *color = RGB((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
    return true;
  } catch (...) {
    return false;
  }
}

std::optional<std::string> PickCustomColor(HWND owner,
                                           const std::string& initial_hex) {
  COLORREF initial = RGB(140, 115, 80);
  ParseTrayHexColor(initial_hex, &initial);
  static COLORREF custom_colors[16] = {};
  custom_colors[0] = initial;

  CHOOSECOLORW chooser = {};
  chooser.lStructSize = sizeof(chooser);
  chooser.hwndOwner = owner;
  chooser.rgbResult = initial;
  chooser.lpCustColors = custom_colors;
  chooser.Flags = CC_ANYCOLOR | CC_FULLOPEN | CC_RGBINIT;
  if (!ChooseColorW(&chooser)) {
    return std::nullopt;
  }

  char selected[8] = {};
  std::snprintf(selected, sizeof(selected), "#%02X%02X%02X",
                GetRValue(chooser.rgbResult), GetGValue(chooser.rgbResult),
                GetBValue(chooser.rgbResult));
  return std::string(selected);
}

double TrayRelativeLuminance(COLORREF color) {
  const auto channel = [](BYTE value) {
    const double normalized = value / 255.0;
    return normalized <= 0.03928
               ? normalized / 12.92
               : std::pow((normalized + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * channel(GetRValue(color)) +
         0.7152 * channel(GetGValue(color)) +
         0.0722 * channel(GetBValue(color));
}

struct TrayMenuChromeContext {
  int radius = 10;
  COLORREF border = RGB(224, 206, 167);
  bool dark = false;
  DWORD process_id = 0;
};

BOOL CALLBACK ApplyTrayMenuChrome(HWND window, LPARAM parameter) {
  const auto* context =
      reinterpret_cast<const TrayMenuChromeContext*>(parameter);
  DWORD process_id = 0;
  GetWindowThreadProcessId(window, &process_id);
  if (!context || process_id != context->process_id) {
    return TRUE;
  }
  wchar_t class_name[32] = {};
  if (GetClassNameW(window, class_name, static_cast<int>(std::size(class_name))) <=
          0 ||
      wcscmp(class_name, L"#32768") != 0 || !IsWindowVisible(window)) {
    return TRUE;
  }
  RECT bounds = {};
  if (!GetWindowRect(window, &bounds)) {
    return TRUE;
  }
  const int width = std::max(1L, bounds.right - bounds.left);
  const int height = std::max(1L, bounds.bottom - bounds.top);
  HRGN current_region = CreateRectRgn(0, 0, 0, 0);
  const bool has_region =
      current_region && GetWindowRgn(window, current_region) != ERROR;
  if (current_region) {
    DeleteObject(current_region);
  }
  if (!has_region) {
    HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                     context->radius * 2,
                                     context->radius * 2);
    if (region && SetWindowRgn(window, region, TRUE) == 0) {
      DeleteObject(region);
    }

    // These attributes are ignored on older Windows builds. The region above
    // keeps the same 10 px shell radius available on Windows 10.
    constexpr DWORD kDwmWindowCornerPreference = 33;
    constexpr DWORD kDwmBorderColor = 34;
    constexpr int kDwmCornerRound = 2;
    const BOOL dark = context->dark ? TRUE : FALSE;
    DwmSetWindowAttribute(window, static_cast<DWMWINDOWATTRIBUTE>(20), &dark,
                          sizeof(dark));
    DwmSetWindowAttribute(
        window, static_cast<DWMWINDOWATTRIBUTE>(kDwmWindowCornerPreference),
        &kDwmCornerRound, sizeof(kDwmCornerRound));
    DwmSetWindowAttribute(window,
                          static_cast<DWMWINDOWATTRIBUTE>(kDwmBorderColor),
                          &context->border, sizeof(context->border));
  }
  return TRUE;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  CleanupOldScriptCapsuleTempFiles();
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  ApplySettingsCoordinatorWindowStyle(GetHandle());
  SetHideFromWindowSwitcher(GetHandle(), true);

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
        if (method == "getDataDirectory") {
          const std::filesystem::path directory = ResolveDataDirectory(window);
          const auto encoded = WideToUtf8Strict(directory.wstring());
          if (!encoded || encoded->empty()) {
            result->Error("data_directory_unavailable",
                          "Unable to resolve the Windows data directory.");
            return;
          }
          result->Success(flutter::EncodableValue(*encoded));
          return;
        }
        if (method == "chooseDataDirectory") {
          std::filesystem::path initial_directory;
          if (call.arguments()) {
            if (const auto* value =
                    std::get_if<std::string>(call.arguments())) {
              const auto decoded = Utf8ToWideStrict(*value);
              if (decoded) {
                initial_directory = *decoded;
              }
            }
          }
          const auto selected = PickDataDirectory(window, initial_directory);
          if (!selected) {
            result->Success(flutter::EncodableValue());
            return;
          }
          const auto encoded = WideToUtf8Strict(selected->wstring());
          if (!encoded) {
            result->Error("data_directory_invalid",
                          "The selected data directory is invalid.");
            return;
          }
          result->Success(flutter::EncodableValue(*encoded));
          return;
        }
        if (method == "chooseCustomColor") {
          std::string initial_color;
          if (call.arguments()) {
            if (const auto* value =
                    std::get_if<std::string>(call.arguments())) {
              initial_color = *value;
            }
          }
          const auto selected = PickCustomColor(window, initial_color);
          if (!selected) {
            result->Success(flutter::EncodableValue());
            return;
          }
          result->Success(flutter::EncodableValue(*selected));
          return;
        }
        if (method == "commitDataDirectory") {
          if (!call.arguments()) {
            result->Error("data_directory_invalid",
                          "The data directory is required.");
            return;
          }
          const auto* value =
              std::get_if<std::string>(call.arguments());
          const auto decoded = value ? Utf8ToWideStrict(*value) : std::nullopt;
          if (!decoded ||
              !WriteConfiguredDataDirectory(std::filesystem::path(*decoded))) {
            result->Error("data_directory_save_failed",
                          "Unable to save the Windows data directory.");
            return;
          }
          result->Success();
          return;
        }
        if (method == "show") {
          if (!RememberActivePaperId(call.arguments())) {
            result->Success();
            return;
          }
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
            RememberPaperCapsuleState(
                active_paper_id_,
                GetStringArgumentValue(call.arguments(), "capsuleSide",
                                       paper_surfaces_[active_paper_id_]
                                           .capsule_side),
                GetStringArgumentValue(call.arguments(),
                                       "capsuleMonitorDeviceName",
                                       paper_surfaces_[active_paper_id_]
                                           .monitor_device_name));
          }
          if (PaperFlutterWindow* paper_window =
                  EnsurePaperWindow(active_paper_id_)) {
            paper_window->ShowPaper(!pinned_to_desktop_);
            ShowWindow(window, SW_HIDE);
            result->Success();
            return;
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
        if (method == "revealPinnedPaper") {
          if (!RememberActivePaperId(call.arguments())) {
            result->Success();
            return;
          }
          RememberPaperVisibility(active_paper_id_, true);
          if (!active_paper_id_.empty()) {
            pinned_to_desktop_ = GetBoolArgumentValue(
                call.arguments(), "isPinnedToDesktop", true);
            RememberPaperPinnedToDesktop(active_paper_id_, pinned_to_desktop_);
            RememberPaperAlwaysOnTop(
                active_paper_id_,
                GetBoolArgumentValue(call.arguments(), "alwaysOnTop",
                                     paper_surfaces_[active_paper_id_]
                                         .always_on_top));
            RememberPaperCapsuleState(
                active_paper_id_,
                GetStringArgumentValue(call.arguments(), "capsuleSide",
                                       paper_surfaces_[active_paper_id_]
                                           .capsule_side),
                GetStringArgumentValue(call.arguments(),
                                       "capsuleMonitorDeviceName",
                                       paper_surfaces_[active_paper_id_]
                                           .monitor_device_name));
          }
          if (PaperFlutterWindow* paper_window =
                  EnsurePaperWindow(active_paper_id_)) {
            paper_window->ShowPaper(false);
            ShowWindow(window, SW_HIDE);
            result->Success();
            return;
          }
          ApplyActivePaperBounds(window);
          ShowWindow(window, SW_SHOWNOACTIVATE);
          SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE |
                           SWP_NOOWNERZORDER);
          z_order_state_initialized_ = false;
          z_order_pinned_to_desktop_ = pinned_to_desktop_;
          z_order_topmost_applied_ = false;
          z_order_fullscreen_blocked_ =
              avoid_fullscreen_topmost_ && IsForegroundFullscreen(window);
          result->Success();
          return;
        }
        if (method == "hide") {
          const PaperIdArgument paper_id_argument =
              GetPaperIdArgument(call.arguments());
          if (paper_id_argument.provided && !paper_id_argument.valid) {
            result->Success();
            return;
          }
          const std::string requested_paper_id = paper_id_argument.value;
          if (requested_paper_id.empty()) {
            RememberPaperVisibility(active_paper_id_, false);
          } else {
            RememberPaperVisibility(requested_paper_id, false);
          }
          const std::string child_paper_id =
              requested_paper_id.empty() ? active_paper_id_
                                         : requested_paper_id;
          if (PaperFlutterWindow* paper_window =
                  PaperWindowForId(child_paper_id)) {
            paper_window->HidePaper();
            result->Success();
            return;
          }
          if (!requested_paper_id.empty() &&
              requested_paper_id == active_paper_id_ &&
              RetargetActivePaperToVisibleSurface(window, requested_paper_id)) {
            result->Success();
            return;
          }
          if (requested_paper_id.empty() ||
              requested_paper_id == active_paper_id_) {
            ShowWindow(window, SW_HIDE);
            z_order_state_initialized_ = false;
          }
          result->Success();
          return;
        }
        if (method == "hideCoordinator") {
          ShowWindow(window, SW_HIDE);
          result->Success();
          return;
        }
        if (method == "setCoordinatorBackgroundColor") {
          int64_t argb = 0xFFFFF9EA;
          if (call.arguments()) {
            if (const auto* int32_value =
                    std::get_if<int32_t>(call.arguments())) {
              argb = static_cast<uint32_t>(*int32_value);
            } else if (const auto* int64_value =
                           std::get_if<int64_t>(call.arguments())) {
              argb = *int64_value;
            }
          }
          const uint32_t color = static_cast<uint32_t>(argb);
          g_settings_coordinator_background =
              RGB((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF);
          RedrawWindow(window, nullptr, nullptr,
                       RDW_INVALIDATE | RDW_ERASE | RDW_FRAME |
                           RDW_ALLCHILDREN);
          result->Success();
          return;
        }
        if (method == "hasVisibleSurfaces") {
          for (const auto& entry : native_capsule_windows_) {
            if (entry.second->IsVisible()) {
              result->Success(flutter::EncodableValue(true));
              return;
            }
          }
          for (const auto& entry : paper_windows_) {
            if (entry.second->IsVisible()) {
              result->Success(flutter::EncodableValue(true));
              return;
            }
          }
          result->Success(flutter::EncodableValue(HasAnyVisibleSurface(window)));
          return;
        }
        if (method == "hasVisibleSurface") {
          const PaperIdArgument paper_id_argument =
              GetPaperIdArgument(call.arguments());
          if (paper_id_argument.provided && !paper_id_argument.valid) {
            result->Success(flutter::EncodableValue(false));
            return;
          }
          const std::string requested_paper_id = paper_id_argument.value;
          for (const auto& entry : native_capsule_windows_) {
            if (entry.second->paper_id() == requested_paper_id &&
                entry.second->IsVisible()) {
              result->Success(flutter::EncodableValue(true));
              return;
            }
          }
          if (PaperFlutterWindow* paper_window =
                  PaperWindowForId(requested_paper_id)) {
            result->Success(
                flutter::EncodableValue(paper_window->IsVisible()));
            return;
          }
          result->Success(flutter::EncodableValue(
              HasVisibleSurfaceForPaper(window, requested_paper_id)));
          return;
        }
        if (method == "setAlwaysOnTop") {
          const PaperIdArgument paper_id_argument =
              GetPaperIdArgument(call.arguments());
          if (paper_id_argument.provided && !paper_id_argument.valid) {
            result->Success();
            return;
          }
          const std::string requested_paper_id = paper_id_argument.value;
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
          if (!target_paper_id.empty()) {
            auto& surface = paper_window_surfaces_[target_paper_id];
            surface[flutter::EncodableValue("id")] =
                flutter::EncodableValue(target_paper_id);
            surface[flutter::EncodableValue("alwaysOnTop")] =
                flutter::EncodableValue(enabled);
            if (PaperFlutterWindow* paper_window =
                    PaperWindowForId(target_paper_id)) {
              paper_window->SetAlwaysOnTop(enabled);
            }
          }
          if (target_paper_id.empty() || target_paper_id == active_paper_id_) {
            RefreshActivePaperZOrder(window);
          }
          result->Success();
          return;
        }
        if (method == "setPinnedToDesktop") {
          const PaperIdArgument paper_id_argument =
              GetPaperIdArgument(call.arguments());
          if (paper_id_argument.provided && !paper_id_argument.valid) {
            result->Success();
            return;
          }
          const std::string requested_paper_id = paper_id_argument.value;
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
          if (!target_paper_id.empty()) {
            auto& surface = paper_window_surfaces_[target_paper_id];
            surface[flutter::EncodableValue("id")] =
                flutter::EncodableValue(target_paper_id);
            surface[flutter::EncodableValue("isPinnedToDesktop")] =
                flutter::EncodableValue(enabled);
            if (PaperFlutterWindow* paper_window =
                    PaperWindowForId(target_paper_id)) {
              paper_window->SetPinnedToDesktop(enabled);
            }
          }
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
              const PaperIdArgument paper_id_argument =
                  GetPaperIdArgument(call.arguments());
              if (paper_id_argument.provided && !paper_id_argument.valid) {
                result->Success();
                return;
              }
              requested_paper_id = paper_id_argument.value;
              title = GetStringArgument(*map, "title", title);
            }
          }
          if (!structured_title || requested_paper_id.empty() ||
              requested_paper_id == active_paper_id_) {
            SetWindowTextW(window, Utf8ToWide(title).c_str());
          }
          if (!requested_paper_id.empty()) {
            RememberPaperTitle(requested_paper_id, Utf8ToWide(title));
            auto& surface = paper_window_surfaces_[requested_paper_id];
            surface[flutter::EncodableValue("id")] =
                flutter::EncodableValue(requested_paper_id);
            surface[flutter::EncodableValue("title")] =
                flutter::EncodableValue(title);
            if (PaperFlutterWindow* paper_window =
                    PaperWindowForId(requested_paper_id)) {
              paper_window->SetPaperTitle(title);
            }
          }
          result->Success();
          return;
        }
        if (method == "normalizeQueueMonitorDeviceName") {
          const std::string monitor_device_name =
              call.arguments()
                  ? GetStringArgumentValue(call.arguments(),
                                           "monitorDeviceName", "")
                  : "";
          result->Success(NormalizeQueueMonitorDeviceName(monitor_device_name));
          return;
        }
        if (method == "setPaperWindowState") {
          if (call.arguments()) {
            ApplyPaperWindowState(*call.arguments());
          }
          result->Success();
          return;
        }
        if (method == "updatePaperWindow") {
          if (call.arguments()) {
            ApplyPaperWindowUpdate(*call.arguments());
          }
          result->Success();
          return;
        }
        if (method == "setPaperSurfaces") {
          if (call.arguments()) {
            if (const auto* papers =
                    std::get_if<flutter::EncodableList>(call.arguments())) {
              ApplyPaperSurfaceRegistry(*papers, false);
              ReconcilePaperWindows(*papers);
            }
          }
          result->Success();
          return;
        }
        if (method == "setNativeCapsuleSurfaces") {
          if (call.arguments()) {
            if (const auto* surfaces =
                    std::get_if<flutter::EncodableList>(call.arguments())) {
              ReconcileNativeCapsuleWindows(*surfaces);
            }
          }
          result->Success();
          return;
        }
        if (method == "setTrayMenu") {
          const flutter::EncodableList* papers = nullptr;
          if (call.arguments()) {
            papers = std::get_if<flutter::EncodableList>(call.arguments());
            if (const auto* payload =
                    std::get_if<flutter::EncodableMap>(call.arguments())) {
              const auto labels_iterator =
                  payload->find(flutter::EncodableValue("labels"));
              if (labels_iterator != payload->end()) {
                if (const auto* labels_map =
                        std::get_if<flutter::EncodableMap>(
                            &labels_iterator->second)) {
                  tray_labels_ =
                      TrayMenuLabelsFromMap(*labels_map, tray_labels_);
                }
              }
              const auto papers_iterator =
                  payload->find(flutter::EncodableValue("papers"));
              if (papers_iterator != payload->end()) {
                papers =
                    std::get_if<flutter::EncodableList>(
                        &papers_iterator->second);
              }
            }
          }
          if (papers) {
            ApplyPaperSurfaceRegistry(*papers, true);
            ReconcilePaperWindows(*papers);
          } else {
            tray_papers_.clear();
          }
          result->Success();
          return;
        }
        if (method == "acquireSingleInstance") {
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (method == "forwardToPrimary") {
          if (!SignalPrimaryInstanceFromChannel(
                  GetStringListArgumentValue(call.arguments()))) {
            result->Error("forward_to_primary_failed",
                          "Unable to forward startup command to the primary "
                          "RePaperTodo instance.");
            return;
          }
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
          hide_papers_from_window_switcher_ = enabled;
          for (auto& entry : paper_windows_) {
            entry.second->SetHideFromWindowSwitcher(enabled);
          }
          if (!SetHideFromWindowSwitcher(window, enabled)) {
            result->Error(
                "window_switcher_visibility_failed",
                "Unable to update the Windows task-switcher visibility.");
            return;
          }
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
          for (auto& entry : paper_windows_) {
            entry.second->SetAvoidFullscreenTopmost(
                avoid_fullscreen_topmost_);
          }
          for (auto& entry : native_capsule_windows_) {
            entry.second->SetAvoidFullscreenTopmost(
                avoid_fullscreen_topmost_);
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
        if (method == "listInstalledFontFamilies") {
          result->Success(flutter::EncodableValue(InstalledFontFamilies()));
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
          const auto wide_path = Utf8ToWideStrict(path);
          if (!wide_path) {
            result->Error("invalid_path",
                          "The external file path is not valid UTF-8.");
            return;
          }
          if (!FileExists(*wide_path)) {
            result->Error("file_not_found", "The file does not exist.");
            return;
          }
          HINSTANCE open_result =
              ShellExecuteW(window, L"open", wide_path->c_str(), nullptr,
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
          if (HasRawExternalUriControlCharacter(uri)) {
            result->Error("invalid_uri",
                          "The URI contains unsupported characters.");
            return;
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
          const auto wide_uri = Utf8ToWideStrict(uri);
          if (!wide_uri) {
            result->Error("invalid_uri", "The URI is not valid UTF-8.");
            return;
          }
          HINSTANCE open_result =
              ShellExecuteW(window, L"open", wide_uri->c_str(), nullptr,
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
          const PaperIdArgument paper_id_argument =
              GetPaperIdArgument(call.arguments());
          if (paper_id_argument.provided && !paper_id_argument.valid) {
            result->Success();
            return;
          }
          const std::string requested_paper_id = paper_id_argument.value;
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
          if (!target_paper_id.empty()) {
            auto& surface = paper_window_surfaces_[target_paper_id];
            surface[flutter::EncodableValue("id")] =
                flutter::EncodableValue(target_paper_id);
            surface[flutter::EncodableValue("x")] =
                flutter::EncodableValue(x);
            surface[flutter::EncodableValue("y")] =
                flutter::EncodableValue(y);
            surface[flutter::EncodableValue("width")] =
                flutter::EncodableValue(width);
            surface[flutter::EncodableValue("height")] =
                flutter::EncodableValue(height);
            PaperFlutterWindow* paper_window =
                EnsurePaperWindow(target_paper_id, &surface);
            if (paper_window) {
              result->Success();
              return;
            }
          }
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
          const PaperIdArgument paper_id_argument =
              GetPaperIdArgument(call.arguments());
          if (paper_id_argument.provided && !paper_id_argument.valid) {
            result->Success(flutter::EncodableValue());
            return;
          }
          const std::string requested_paper_id = paper_id_argument.value;
          if (PaperFlutterWindow* paper_window =
                  PaperWindowForId(requested_paper_id)) {
            result->Success(paper_window->BoundsValue());
            return;
          }
          result->Success(BoundsValueForPaper(
              window, requested_paper_id.empty() ? active_paper_id_
                                                 : requested_paper_id));
          return;
        }
        if (method == "getWorkArea") {
          const PaperIdArgument paper_id_argument =
              GetPaperIdArgument(call.arguments());
          if (paper_id_argument.provided && !paper_id_argument.valid) {
            result->Success(flutter::EncodableValue());
            return;
          }
          const std::string requested_paper_id = paper_id_argument.value;
          result->Success(WorkAreaValueForArguments(
              window, call.arguments(),
              CachedMonitorDeviceNameForPaper(requested_paper_id)));
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
    if (GetHandle()) {
      ShowWindow(GetHandle(), SW_HIDE);
    }
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
      ScopedWinHandle pipe(CreateNamedPipeW(
          kSingleInstancePipeName, PIPE_ACCESS_INBOUND,
          PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0,
          nullptr));
      if (!pipe.is_valid()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        continue;
      }

      const BOOL connected =
          ConnectNamedPipe(pipe.get(), nullptr)
              ? TRUE
              : (GetLastError() == ERROR_PIPE_CONNECTED);
      std::string command;
      if (connected) {
        char buffer[512];
        DWORD bytes_read = 0;
        while (ReadFile(pipe.get(), buffer, sizeof(buffer), &bytes_read,
                        nullptr) &&
               bytes_read > 0) {
          const size_t remaining =
              kMaxSingleInstanceCommandBytes - command.size();
          const size_t bytes_to_append =
              std::min(static_cast<size_t>(bytes_read), remaining);
          command.append(buffer, bytes_to_append);
          if (command.find('\n') != std::string::npos ||
              bytes_to_append < bytes_read ||
              command.size() >= kMaxSingleInstanceCommandBytes) {
            break;
          }
        }
      }
      DisconnectNamedPipe(pipe.get());

      command = CanonicalStartupCommandLine(command);
      if (single_instance_listener_running_ && !command.empty()) {
        auto command_message = std::make_unique<std::string>(command);
        if (PostMessageW(window, kSingleInstanceCommandMessage, 0,
                         reinterpret_cast<LPARAM>(command_message.get()))) {
          command_message.release();
        }
      }
    }
  });
}

void FlutterWindow::StopSingleInstanceListener() {
  if (!single_instance_listener_running_.exchange(false)) {
    return;
  }

  SignalPipeWake(kSingleInstancePipeName, 10, 100, 20);

  if (single_instance_listener_thread_.joinable()) {
    single_instance_listener_thread_.join();
  }
}

FlutterWindow::TrayPalette FlutterWindow::ResolveTrayPalette() const {
  TrayPalette palette;
  std::string theme = "system";
  std::string scheme = "warm";
  std::string custom_color;
  if (const auto* state =
          std::get_if<flutter::EncodableMap>(&paper_window_state_)) {
    theme = LowerAscii(GetStringArgument(*state, "theme", theme));
    scheme = LowerAscii(GetStringArgument(*state, "colorScheme", scheme));
    custom_color = GetStringArgument(*state, "customThemeColorHex", "");
  }
  palette.dark = theme == "dark" ||
                 (theme != "light" && IsSystemAppThemeDark());

  if (scheme == "ink") {
    palette.paper = palette.dark ? RGB(26, 28, 32) : RGB(246, 247, 249);
    palette.border = palette.dark ? RGB(60, 66, 76) : RGB(208, 214, 222);
    palette.text = palette.dark ? RGB(222, 227, 234) : RGB(38, 44, 54);
    palette.weak = palette.dark ? RGB(138, 146, 158) : RGB(118, 126, 138);
    palette.active = palette.dark ? RGB(132, 156, 188) : RGB(90, 108, 134);
    palette.tint = palette.dark ? RGB(180, 200, 228) : RGB(70, 90, 120);
    palette.danger = palette.dark ? RGB(224, 116, 108) : RGB(188, 84, 80);
  } else if (scheme == "forest") {
    palette.paper = palette.dark ? RGB(26, 30, 27) : RGB(243, 248, 241);
    palette.border = palette.dark ? RGB(58, 70, 60) : RGB(200, 218, 198);
    palette.text = palette.dark ? RGB(220, 228, 220) : RGB(38, 50, 42);
    palette.weak = palette.dark ? RGB(134, 148, 136) : RGB(110, 128, 112);
    palette.active = palette.dark ? RGB(124, 168, 134) : RGB(88, 130, 96);
    palette.tint = palette.dark ? RGB(180, 208, 186) : RGB(70, 110, 80);
    palette.danger = palette.dark ? RGB(222, 124, 104) : RGB(188, 96, 76);
  } else if (scheme == "rose") {
    palette.paper = palette.dark ? RGB(33, 28, 30) : RGB(253, 245, 246);
    palette.border = palette.dark ? RGB(78, 64, 68) : RGB(228, 205, 210);
    palette.text = palette.dark ? RGB(232, 220, 223) : RGB(54, 38, 42);
    palette.weak = palette.dark ? RGB(152, 132, 137) : RGB(140, 114, 120);
    palette.active = palette.dark ? RGB(190, 134, 148) : RGB(158, 104, 118);
    palette.tint = palette.dark ? RGB(224, 180, 190) : RGB(150, 80, 96);
    palette.danger = palette.dark ? RGB(230, 114, 100) : RGB(188, 82, 78);
  } else {
    palette.paper = palette.dark ? RGB(33, 31, 28) : RGB(255, 249, 234);
    palette.border = palette.dark ? RGB(76, 69, 61) : RGB(224, 206, 167);
    palette.text = palette.dark ? RGB(231, 224, 212) : RGB(51, 41, 30);
    palette.weak = palette.dark ? RGB(146, 137, 123) : RGB(138, 122, 99);
    palette.active = palette.dark ? RGB(168, 142, 106) : RGB(140, 115, 80);
    palette.tint = palette.dark ? RGB(230, 223, 211) : RGB(120, 92, 48);
    palette.danger = palette.dark ? RGB(230, 110, 90) : RGB(176, 90, 70);
  }

  COLORREF custom = 0;
  if (ParseTrayHexColor(custom_color, &custom)) {
    const double luminance = TrayRelativeLuminance(custom);
    palette.active = palette.dark
                         ? MixTrayColor(custom, RGB(255, 255, 255),
                                        luminance < 0.26 ? 0.36 : 0.12)
                         : (luminance > 0.78
                                ? MixTrayColor(custom, RGB(0, 0, 0), 0.30)
                                : custom);
    if (palette.dark) {
      palette.paper = MixTrayColor(custom, RGB(0, 0, 0), 0.82);
      palette.text = MixTrayColor(custom, RGB(255, 255, 255), 0.82);
      palette.border = MixTrayColor(palette.paper, palette.text, 0.17);
      palette.weak = MixTrayColor(palette.text, palette.paper, 0.46);
      palette.tint = MixTrayColor(palette.active, RGB(255, 255, 255), 0.50);
    } else {
      palette.paper = MixTrayColor(custom, RGB(255, 255, 255), 0.90);
      palette.text = MixTrayColor(custom, RGB(0, 0, 0), 0.72);
      palette.border = MixTrayColor(palette.paper, palette.text, 0.16);
      palette.weak = MixTrayColor(palette.text, palette.paper, 0.46);
      palette.tint = MixTrayColor(palette.active, RGB(0, 0, 0), 0.10);
    }
  }
  palette.hover = MixTrayColor(
      palette.paper, palette.tint, (palette.dark ? 48.0 : 32.0) / 255.0);
  return palette;
}

bool FlutterWindow::MeasureTrayMenuItem(MEASUREITEMSTRUCT* measure) {
  if (!measure || measure->CtlType != ODT_MENU || measure->itemData == 0) {
    return false;
  }
  const auto* item =
      reinterpret_cast<const TrayOwnerDrawItem*>(measure->itemData);
  HWND window = GetHandle();
  measure->itemWidth = ScaleTrayMetric(
      window, kTrayMenuMinimumWidth - kTrayMenuNativeWidthCompensation);
  switch (item->kind) {
    case TrayOwnerDrawKind::header:
      measure->itemHeight = ScaleTrayMetric(window, kTrayMenuHeaderHeight);
      break;
    case TrayOwnerDrawKind::separator:
      measure->itemHeight = ScaleTrayMetric(window, 7);
      break;
    case TrayOwnerDrawKind::padding:
      measure->itemHeight = ScaleTrayMetric(window, kTrayMenuPadding);
      break;
    case TrayOwnerDrawKind::command:
    case TrayOwnerDrawKind::paper:
      measure->itemHeight = ScaleTrayMetric(window, kTrayMenuItemHeight);
      break;
  }
  return true;
}

bool FlutterWindow::DrawTrayMenuItem(const DRAWITEMSTRUCT* draw) {
  if (!draw || draw->CtlType != ODT_MENU || draw->itemData == 0 ||
      !draw->hDC) {
    return false;
  }
  const auto* item =
      reinterpret_cast<const TrayOwnerDrawItem*>(draw->itemData);
  const TrayPalette palette = ResolveTrayPalette();
  HWND window = GetHandle();
  HDC dc = draw->hDC;
  const int saved = SaveDC(dc);
  SetBkMode(dc, TRANSPARENT);

  HBRUSH paper_brush = CreateSolidBrush(palette.paper);
  FillRect(dc, &draw->rcItem, paper_brush);
  DeleteObject(paper_brush);

  const bool interactive = item->kind == TrayOwnerDrawKind::command ||
                           item->kind == TrayOwnerDrawKind::paper;
  if (interactive && (draw->itemState & ODS_SELECTED) != 0 &&
      (draw->itemState & ODS_DISABLED) == 0) {
    RECT hover_bounds = draw->rcItem;
    InflateRect(&hover_bounds, -ScaleTrayMetric(window, kTrayMenuPadding),
                -ScaleTrayMetric(window, 1));
    HBRUSH hover_brush = CreateSolidBrush(palette.hover);
    HPEN no_pen = static_cast<HPEN>(GetStockObject(NULL_PEN));
    HGDIOBJ previous_brush = SelectObject(dc, hover_brush);
    HGDIOBJ previous_pen = SelectObject(dc, no_pen);
    const int radius = ScaleTrayMetric(window, kTrayMenuItemRadius) * 2;
    RoundRect(dc, hover_bounds.left, hover_bounds.top, hover_bounds.right,
              hover_bounds.bottom, radius, radius);
    SelectObject(dc, previous_pen);
    SelectObject(dc, previous_brush);
    DeleteObject(hover_brush);
  }

  if (item->kind == TrayOwnerDrawKind::separator) {
    const int y = (draw->rcItem.top + draw->rcItem.bottom) / 2;
    HPEN separator_pen = CreatePen(PS_SOLID, 1,
                                   MixTrayColor(palette.paper, palette.border,
                                                0.45));
    HGDIOBJ previous_pen = SelectObject(dc, separator_pen);
    MoveToEx(dc, draw->rcItem.left + ScaleTrayMetric(window, 12), y, nullptr);
    LineTo(dc, draw->rcItem.right - ScaleTrayMetric(window, 12), y);
    SelectObject(dc, previous_pen);
    DeleteObject(separator_pen);
    RestoreDC(dc, saved);
    return true;
  }
  if (item->kind == TrayOwnerDrawKind::padding) {
    RestoreDC(dc, saved);
    return true;
  }

  const bool header = item->kind == TrayOwnerDrawKind::header;
  HFONT text_font = CreateFontW(
      -ScaleTrayMetric(window, header ? 11 : 12), 0, 0, 0,
      header ? FW_SEMIBOLD : FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
      DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  HGDIOBJ previous_font = SelectObject(dc, text_font);
  SetTextColor(
      dc, item->danger
              ? palette.danger
              : (header ? MixTrayColor(palette.paper, palette.weak, 0.72)
                        : palette.text));

  RECT text_bounds = draw->rcItem;
  text_bounds.left += ScaleTrayMetric(window, 14);
  text_bounds.right -= ScaleTrayMetric(window, item->has_submenu ? 30 : 16);

  if (item->kind == TrayOwnerDrawKind::paper) {
    const int checkbox_size =
        ScaleTrayMetric(window, kTrayMenuCheckboxSize);
    const int checkbox_left = draw->rcItem.left + ScaleTrayMetric(window, 12);
    const int checkbox_top = draw->rcItem.top +
                             (draw->rcItem.bottom - draw->rcItem.top -
                              checkbox_size) /
                                 2;
    const RECT checkbox_bounds = {
        checkbox_left, checkbox_top, checkbox_left + checkbox_size,
        checkbox_top + checkbox_size};
    const int checkbox_radius = ScaleTrayMetric(window, 3) * 2;
    HBRUSH checkbox_brush = CreateSolidBrush(
        item->checked ? MixTrayColor(palette.paper, palette.active, 0.92)
                      : palette.paper);
    HPEN checkbox_pen = CreatePen(
        PS_SOLID, std::max(1, ScaleTrayMetric(window, 1)),
        item->checked ? MixTrayColor(palette.paper, palette.active, 0.92)
                      : MixTrayColor(palette.paper, palette.weak, 0.72));
    HGDIOBJ previous_brush = SelectObject(dc, checkbox_brush);
    HGDIOBJ previous_pen = SelectObject(dc, checkbox_pen);
    RoundRect(dc, checkbox_bounds.left, checkbox_bounds.top,
              checkbox_bounds.right, checkbox_bounds.bottom, checkbox_radius,
              checkbox_radius);
    SelectObject(dc, previous_pen);
    SelectObject(dc, previous_brush);
    DeleteObject(checkbox_pen);
    DeleteObject(checkbox_brush);
    if (item->checked) {
      HPEN check_pen = CreatePen(PS_SOLID,
                                 std::max(1, ScaleTrayMetric(window, 2)),
                                 palette.paper);
      previous_pen = SelectObject(dc, check_pen);
      POINT points[3] = {
          {checkbox_bounds.left + ScaleTrayMetric(window, 3),
           checkbox_bounds.top + ScaleTrayMetric(window, 7)},
          {checkbox_bounds.left + ScaleTrayMetric(window, 6),
           checkbox_bounds.top + ScaleTrayMetric(window, 10)},
          {checkbox_bounds.left + ScaleTrayMetric(window, 11),
           checkbox_bounds.top + ScaleTrayMetric(window, 4)},
      };
      Polyline(dc, points, 3);
      SelectObject(dc, previous_pen);
      DeleteObject(check_pen);
    }

    const int icon_left = draw->rcItem.left + ScaleTrayMetric(window, 34);
    RECT icon_bounds = {icon_left, draw->rcItem.top,
                        icon_left + ScaleTrayMetric(window, 20),
                        draw->rcItem.bottom};
    const std::wstring icon = item->paper_type == "script"
                                  ? L"\u26A1"
                                  : (item->paper_type == "note" ? L"\u270E"
                                                                  : L"\u2713");
    HFONT icon_font = CreateFontW(
        -ScaleTrayMetric(window, item->paper_type == "script" ? 15 : 14), 0,
        0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Symbol");
    SelectObject(dc, icon_font);
    SetTextColor(dc, MixTrayColor(palette.paper, palette.text, 0.82));
    DrawTextW(dc, icon.c_str(), static_cast<int>(icon.size()), &icon_bounds,
              DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_NOPREFIX);
    SelectObject(dc, text_font);
    DeleteObject(icon_font);
    SetTextColor(dc, palette.text);
    text_bounds.left = draw->rcItem.left + ScaleTrayMetric(window, 56);
  }

  DrawTextW(dc, item->text.c_str(), static_cast<int>(item->text.size()),
            &text_bounds,
            DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS |
                DT_NOPREFIX);

  if (item->has_submenu) {
    const int center_x = draw->rcItem.right - ScaleTrayMetric(window, 15);
    const int center_y = (draw->rcItem.top + draw->rcItem.bottom) / 2;
    HPEN arrow_pen = CreatePen(PS_SOLID,
                               std::max(1, ScaleTrayMetric(window, 1)),
                               palette.weak);
    HGDIOBJ previous_pen = SelectObject(dc, arrow_pen);
    MoveToEx(dc, center_x - ScaleTrayMetric(window, 2),
             center_y - ScaleTrayMetric(window, 4), nullptr);
    LineTo(dc, center_x + ScaleTrayMetric(window, 2), center_y);
    LineTo(dc, center_x - ScaleTrayMetric(window, 2),
           center_y + ScaleTrayMetric(window, 4));
    SelectObject(dc, previous_pen);
    DeleteObject(arrow_pen);
  }

  SelectObject(dc, previous_font);
  DeleteObject(text_font);
  RestoreDC(dc, saved);
  return true;
}

void FlutterWindow::ApplyTrayMenuWindowChrome() {
  const TrayPalette palette = ResolveTrayPalette();
  TrayMenuChromeContext context;
  context.radius = ScaleTrayMetric(GetHandle(), kTrayMenuShellRadius);
  context.border = palette.border;
  context.dark = palette.dark;
  context.process_id = GetCurrentProcessId();
  EnumWindows(ApplyTrayMenuChrome, reinterpret_cast<LPARAM>(&context));
}

void FlutterWindow::ShowTrayMenu() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  POINT cursor_position;
  GetCursorPos(&cursor_position);
  active_tray_items_.clear();
  const TrayPalette palette = ResolveTrayPalette();
  HBRUSH menu_background = CreateSolidBrush(palette.paper);
  UINT command = 0;
  {
    ScopedMenu menu(CreatePopupMenu());
    if (!menu.get()) {
      DeleteObject(menu_background);
      return;
    }
    const auto configure_menu = [&](HMENU target) {
      MENUINFO info = {};
      info.cbSize = sizeof(info);
      info.fMask = MIM_BACKGROUND | MIM_STYLE;
      info.hbrBack = menu_background;
      info.dwStyle = MNS_NOCHECK;
      return SetMenuInfo(target, &info) != 0;
    };
    const auto append_owner_draw =
        [&](HMENU target, UINT id, const std::wstring& text,
            TrayOwnerDrawKind kind, bool enabled = true, bool checked = false,
            HMENU submenu = nullptr, bool danger = false,
            const std::string& paper_type = std::string()) {
          auto item = std::make_unique<TrayOwnerDrawItem>();
          item->text = text;
          item->kind = kind;
          item->checked = checked;
          item->has_submenu = submenu != nullptr;
          item->danger = danger;
          item->paper_type = paper_type;
          TrayOwnerDrawItem* data = item.get();

          MENUITEMINFOW info = {};
          info.cbSize = sizeof(info);
          info.fMask = MIIM_FTYPE | MIIM_STATE | MIIM_DATA | MIIM_ID;
          info.fType = MFT_OWNERDRAW;
          info.fState = enabled ? MFS_ENABLED : MFS_DISABLED;
          info.wID = id;
          info.dwItemData = reinterpret_cast<ULONG_PTR>(data);
          if (submenu) {
            info.fMask |= MIIM_SUBMENU;
            info.hSubMenu = submenu;
          }
          const bool inserted =
              InsertMenuItemW(target, GetMenuItemCount(target), TRUE, &info) !=
              0;
          if (inserted) {
            active_tray_items_.push_back(std::move(item));
          }
          return inserted;
        };
    const auto append_padding = [&](HMENU target) {
      return append_owner_draw(target, 0, L"", TrayOwnerDrawKind::padding,
                               false);
    };
    const auto append_separator = [&](HMENU target) {
      return append_owner_draw(target, 0, L"", TrayOwnerDrawKind::separator,
                               false);
    };

    configure_menu(menu.get());
    append_padding(menu.get());
    append_owner_draw(menu.get(), 0, AppDisplayName(),
                      TrayOwnerDrawKind::header, false);
    append_owner_draw(menu.get(), kTrayNewTodoCommand, tray_labels_.new_todo,
                      TrayOwnerDrawKind::command);
    append_owner_draw(menu.get(), kTrayNewNoteCommand, tray_labels_.new_note,
                      TrayOwnerDrawKind::command);
    append_separator(menu.get());
    append_owner_draw(menu.get(), kTraySettingsCommand, tray_labels_.settings,
                      TrayOwnerDrawKind::command);
    append_separator(menu.get());
    append_owner_draw(menu.get(), kTrayShowCommand, tray_labels_.show_all,
                      TrayOwnerDrawKind::command);
    append_owner_draw(menu.get(), kTrayHideCommand, tray_labels_.hide_all,
                      TrayOwnerDrawKind::command);
    append_owner_draw(menu.get(), kTrayToggleCommand, tray_labels_.toggle_all,
                      TrayOwnerDrawKind::command);
    if (!tray_papers_.empty()) {
      append_separator(menu.get());
      append_owner_draw(menu.get(), 0, tray_labels_.papers,
                        TrayOwnerDrawKind::header, false);
      for (size_t index = 0; index < tray_papers_.size(); index++) {
        append_owner_draw(
            menu.get(), kTrayPaperCommandBase + static_cast<UINT>(index),
            tray_papers_[index].label, TrayOwnerDrawKind::paper, true,
            tray_papers_[index].is_visible, nullptr, false,
            tray_papers_[index].paper_type);
      }
      ScopedMenu delete_menu(CreatePopupMenu());
      if (delete_menu.get()) {
        configure_menu(delete_menu.get());
        append_padding(delete_menu.get());
        bool has_delete_confirmation = false;
        for (size_t index = 0; index < tray_papers_.size(); index++) {
          ScopedMenu confirm_menu(CreatePopupMenu());
          if (!confirm_menu.get()) {
            continue;
          }
          configure_menu(confirm_menu.get());
          append_padding(confirm_menu.get());
          const std::wstring confirm_title =
              tray_labels_.inline_confirm_delete.empty()
                  ? tray_papers_[index].label
                  : tray_labels_.inline_confirm_delete + L" - " +
                        tray_papers_[index].label;
          const bool confirm_items_added =
              append_owner_draw(
                  confirm_menu.get(),
                  kTrayPaperDeleteCommandBase + static_cast<UINT>(index),
                  tray_labels_.inline_confirm_action,
                  TrayOwnerDrawKind::command, true, false, nullptr, true) &&
              append_owner_draw(confirm_menu.get(), 0, tray_labels_.cancel,
                                TrayOwnerDrawKind::command) &&
              append_padding(confirm_menu.get());
          if (!confirm_items_added) {
            continue;
          }
          if (append_owner_draw(delete_menu.get(), 0, confirm_title,
                                TrayOwnerDrawKind::command, true, false,
                                confirm_menu.get())) {
            confirm_menu.release();
            has_delete_confirmation = true;
          }
        }
        append_padding(delete_menu.get());
        if (has_delete_confirmation &&
            append_owner_draw(menu.get(), 0, tray_labels_.delete_paper,
                              TrayOwnerDrawKind::command, true, false,
                              delete_menu.get())) {
          delete_menu.release();
        }
      }
    }
    append_separator(menu.get());
    append_owner_draw(menu.get(), kTrayExitCommand, tray_labels_.exit,
                      TrayOwnerDrawKind::command);
    append_padding(menu.get());

    SetForegroundWindow(window);
    TrayMenuChromeContext chrome_context;
    chrome_context.radius = ScaleTrayMetric(window, kTrayMenuShellRadius);
    chrome_context.border = palette.border;
    chrome_context.dark = palette.dark;
    chrome_context.process_id = GetCurrentProcessId();
    std::atomic_bool keep_styling_menu{true};
    std::thread chrome_thread([chrome_context, &keep_styling_menu]() {
      do {
        TrayMenuChromeContext context = chrome_context;
        EnumWindows(ApplyTrayMenuChrome,
                    reinterpret_cast<LPARAM>(&context));
        std::this_thread::sleep_for(
            std::chrono::milliseconds(kTrayMenuChromeRefreshIntervalMs));
      } while (keep_styling_menu.load(std::memory_order_relaxed));
    });
    command = TrackPopupMenu(
        menu.get(), TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_WORKAREA,
        cursor_position.x, cursor_position.y, 0, window, nullptr);
    keep_styling_menu.store(false, std::memory_order_relaxed);
    chrome_thread.join();
  }
  DeleteObject(menu_background);
  active_tray_items_.clear();

  switch (command) {
    case kTrayNewTodoCommand:
      SendStartupCommandRequested("new-todo");
      break;
    case kTrayNewNoteCommand:
      SendStartupCommandRequested("new-note");
      break;
    case kTraySettingsCommand:
      SendStartupCommandRequested("settings");
      ShowSettingsCoordinatorWindow(window);
      break;
    case kTrayShowCommand:
      SendStartupCommandRequested("show");
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
      } else if (command >= kTrayPaperDeleteCommandBase &&
                 command <
                     kTrayPaperDeleteCommandBase + tray_papers_.size()) {
        const auto& paper =
            tray_papers_[command - kTrayPaperDeleteCommandBase];
        SendPaperDeleteRequested(paper.id);
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
  const std::string canonical_command =
      StartupCommandFromArgs(std::vector<std::string>{command});
  if (canonical_command.empty() ||
      HasAsciiControlCharacter(canonical_command)) {
    return;
  }
  window_channel_->InvokeMethod(
      "startupCommandRequested",
      std::make_unique<flutter::EncodableValue>(canonical_command));
}

void FlutterWindow::SendSessionEndingExitRequested() {
  if (session_ending_exit_requested_ || !window_channel_) {
    return;
  }
  session_ending_exit_requested_ = true;
  SendStartupCommandRequested("exit");
}

void FlutterWindow::SendWindowEvent(const char* method) {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(
      method, std::make_unique<flutter::EncodableValue>(
                  WindowEventArguments()));
}

bool FlutterWindow::RememberActivePaperId(
    const flutter::EncodableValue* arguments) {
  const PaperIdArgument paper_id_argument = GetPaperIdArgument(arguments);
  if (paper_id_argument.provided && !paper_id_argument.valid) {
    return false;
  }
  const std::string paper_id = paper_id_argument.value;
  if (!paper_id.empty()) {
    active_paper_id_ = paper_id;
    paper_surfaces_.try_emplace(paper_id);
    RememberPaperSurfaceOrder(paper_id);
  }
  return true;
}

void FlutterWindow::RememberPaperSurfaceOrder(const std::string& paper_id) {
  if (paper_id.empty()) {
    return;
  }
  if (std::find(paper_surface_order_.begin(), paper_surface_order_.end(),
                paper_id) == paper_surface_order_.end()) {
    paper_surface_order_.push_back(paper_id);
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

void FlutterWindow::RememberPaperTitle(const std::string& paper_id,
                                       const std::wstring& title) {
  if (paper_id.empty()) {
    return;
  }
  paper_surfaces_[paper_id].title = title;
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

void FlutterWindow::RememberPaperCapsuleState(
    const std::string& paper_id,
    const std::string& capsule_side,
    const std::string& monitor_device_name) {
  if (paper_id.empty()) {
    return;
  }
  PaperSurfaceState& state = paper_surfaces_[paper_id];
  state.capsule_side = capsule_side;
  state.monitor_device_name =
      NormalizeQueueMonitorDeviceName(monitor_device_name);
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

bool FlutterWindow::HasAnyVisibleSurface(HWND window) const {
  if (IsWindowVisible(window) != 0) {
    return true;
  }
  return std::any_of(
      paper_surfaces_.begin(), paper_surfaces_.end(),
      [this](const auto& entry) {
        return entry.first != active_paper_id_ && entry.second.is_visible;
      });
}

bool FlutterWindow::HasVisibleSurfaceForPaper(
    HWND window, const std::string& paper_id) const {
  if (paper_id.empty()) {
    return IsWindowVisible(window) != 0;
  }
  if (paper_id == active_paper_id_) {
    return IsWindowVisible(window) != 0;
  }
  const auto iterator = paper_surfaces_.find(paper_id);
  return iterator != paper_surfaces_.end() && iterator->second.is_visible;
}

bool FlutterWindow::RetargetActivePaperToVisibleSurface(
    HWND window, const std::string& hidden_paper_id) {
  if (!window || !IsWindow(window)) {
    return false;
  }
  const auto retarget_to_surface =
      [this, window](const std::string& paper_id,
                     const PaperSurfaceState& state) {
        active_paper_id_ = paper_id;
        pinned_to_desktop_ = state.pinned_to_desktop;
        ApplyActivePaperBounds(window);
        if (!state.title.empty()) {
          SetWindowTextW(window, state.title.c_str());
        }
        ShowWindow(window,
                   pinned_to_desktop_ ? SW_SHOWNOACTIVATE : SW_SHOWNORMAL);
        z_order_state_initialized_ = false;
        RefreshActivePaperZOrder(window);
        return true;
      };

  size_t start_index = 0;
  const auto hidden_iterator = std::find(
      paper_surface_order_.begin(), paper_surface_order_.end(),
      hidden_paper_id);
  if (hidden_iterator != paper_surface_order_.end() &&
      !paper_surface_order_.empty()) {
    start_index = (static_cast<size_t>(
                       std::distance(paper_surface_order_.begin(),
                                     hidden_iterator)) +
                   1) %
                  paper_surface_order_.size();
  }

  for (size_t offset = 0; offset < paper_surface_order_.size(); ++offset) {
    const std::string& paper_id =
        paper_surface_order_[(start_index + offset) %
                             paper_surface_order_.size()];
    if (paper_id == hidden_paper_id) {
      continue;
    }
    const auto iterator = paper_surfaces_.find(paper_id);
    if (iterator == paper_surfaces_.end() || !iterator->second.is_visible) {
      continue;
    }
    return retarget_to_surface(iterator->first, iterator->second);
  }
  for (const auto& entry : paper_surfaces_) {
    if (entry.first == hidden_paper_id || !entry.second.is_visible ||
        std::find(paper_surface_order_.begin(), paper_surface_order_.end(),
                  entry.first) != paper_surface_order_.end()) {
      continue;
    }
    return retarget_to_surface(entry.first, entry.second);
  }
  return false;
}

void FlutterWindow::ApplyPaperSurfaceRegistry(
    const flutter::EncodableList& papers, bool rebuild_tray_items) {
  std::vector<std::string> current_paper_ids;
  if (rebuild_tray_items) {
    tray_papers_.clear();
  }
  for (const auto& paper : papers) {
    if (const auto* paper_map = std::get_if<flutter::EncodableMap>(&paper)) {
      const PaperIdArgument paper_id_argument =
          ValidatePaperIdArgumentValue(GetStringArgument(*paper_map, "id", ""));
      if (paper_id_argument.valid) {
        const std::string id = paper_id_argument.value;
        current_paper_ids.push_back(id);
        RememberPaperTitle(
            id, AppWindowTitleForPaper(
                    GetStringArgument(*paper_map, "title", "")));
        RememberPaperVisibility(
            id, GetBoolArgument(*paper_map, "isVisible", false));
        RememberPaperPinnedToDesktop(
            id, GetBoolArgument(*paper_map, "isPinnedToDesktop", false));
        RememberPaperAlwaysOnTop(
            id, GetBoolArgument(*paper_map, "alwaysOnTop", false));
        RememberPaperCapsuleState(
            id, GetStringArgument(*paper_map, "capsuleSide", ""),
            GetStringArgument(*paper_map, "capsuleMonitorDeviceName", ""));
        const double x = GetNumberArgument(*paper_map, "x", 0);
        const double y = GetNumberArgument(*paper_map, "y", 0);
        const double width = GetNumberArgument(*paper_map, "width", 0);
        const double height = GetNumberArgument(*paper_map, "height", 0);
        if (width > 0 && height > 0) {
          const RECT paper_bounds = {static_cast<LONG>(x),
                                     static_cast<LONG>(y),
                                     static_cast<LONG>(x + width),
                                     static_cast<LONG>(y + height)};
          RememberPaperBounds(id, paper_bounds);
        }
        if (rebuild_tray_items) {
          const std::string paper_type =
              GetBoolArgument(*paper_map, "isScriptCapsule", false)
                  ? "script"
                  : (GetStringArgument(*paper_map, "type", "todo") == "note"
                         ? "note"
                         : "todo");
          tray_papers_.push_back(
              {id, TrayPaperLabel(*paper_map, tray_labels_),
               GetBoolArgument(*paper_map, "isVisible", false), paper_type});
        }
      }
    }
  }
  paper_surface_order_ = current_paper_ids;
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
}

std::string FlutterWindow::CachedMonitorDeviceNameForPaper(
    const std::string& paper_id) const {
  if (paper_id.empty()) {
    return "";
  }
  const auto iterator = paper_surfaces_.find(paper_id);
  if (iterator == paper_surfaces_.end()) {
    return "";
  }
  return iterator->second.monitor_device_name;
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

void FlutterWindow::ApplyPaperWindowState(
    const flutter::EncodableValue& state) {
  paper_window_state_ = state;
  for (auto& entry : paper_windows_) {
    entry.second->ApplyState(paper_window_state_);
  }
}

void FlutterWindow::ApplyPaperWindowUpdate(
    const flutter::EncodableValue& paper) {
  const auto* map = std::get_if<flutter::EncodableMap>(&paper);
  if (!map) {
    return;
  }
  const auto iterator = map->find(flutter::EncodableValue("id"));
  if (iterator == map->end()) {
    return;
  }
  const auto* paper_id = std::get_if<std::string>(&iterator->second);
  if (!paper_id || !ValidatePaperIdArgumentValue(*paper_id).valid) {
    return;
  }
  PaperFlutterWindow* paper_window = EnsurePaperWindow(*paper_id);
  if (paper_window) {
    // Content updates are intentionally geometry-neutral, but expansion and
    // pin actions still need to reach the native surface before a following
    // setBounds call. Otherwise a capsule HWND can interpret the new full
    // paper bounds through its stale isCollapsed=true cache for one frame.
    auto& surface = paper_window_surfaces_[*paper_id];
    surface[flutter::EncodableValue("id")] =
        flutter::EncodableValue(*paper_id);
    for (const char* key : {"isVisible", "isCollapsed", "isPinnedToDesktop",
                            "alwaysOnTop", "capsuleSide",
                            "capsuleMonitorDeviceName"}) {
      const auto value_iterator = map->find(flutter::EncodableValue(key));
      if (value_iterator != map->end()) {
        surface[flutter::EncodableValue(key)] = value_iterator->second;
      }
    }
    paper_window->ApplyPaper(paper);
  }
}

void FlutterWindow::ReconcilePaperWindows(
    const flutter::EncodableList& papers) {
  std::map<std::string, flutter::EncodableMap> next_surfaces;
  bool has_visible_paper = false;
  for (const auto& value : papers) {
    const auto* surface = std::get_if<flutter::EncodableMap>(&value);
    if (!surface) {
      continue;
    }
    const auto id_iterator = surface->find(flutter::EncodableValue("id"));
    if (id_iterator == surface->end()) {
      continue;
    }
    const auto* paper_id = std::get_if<std::string>(&id_iterator->second);
    if (!paper_id || !ValidatePaperIdArgumentValue(*paper_id).valid) {
      continue;
    }
    flutter::EncodableMap resolved_surface = *surface;
    PaperFlutterWindow* existing_window = PaperWindowForId(*paper_id);
    const bool collapsed =
        GetBoolArgument(resolved_surface, "isCollapsed", false);
    // Live HWND bounds are authoritative only while both the incoming model
    // and the native surface are already expanded. During capsule -> paper
    // transitions the HWND still has capsule geometry; replaying that geometry
    // would replace the saved paper bounds with the Win32 minimum size.
    if (existing_window && !collapsed && !existing_window->IsCollapsed()) {
      const auto live_bounds = existing_window->BoundsValue();
      if (const auto* bounds =
              std::get_if<flutter::EncodableMap>(&live_bounds)) {
        for (const char* key : {"x", "y", "width", "height"}) {
          const auto bounds_entry =
              bounds->find(flutter::EncodableValue(key));
          if (bounds_entry != bounds->end()) {
            resolved_surface[flutter::EncodableValue(key)] =
                bounds_entry->second;
          }
        }
        const double x = GetNumberArgument(resolved_surface, "x", 0);
        const double y = GetNumberArgument(resolved_surface, "y", 0);
        const double width =
            GetNumberArgument(resolved_surface, "width", 0);
        const double height =
            GetNumberArgument(resolved_surface, "height", 0);
        if (width > 0 && height > 0) {
          RememberPaperBounds(
              *paper_id,
              {static_cast<LONG>(std::round(x)),
               static_cast<LONG>(std::round(y)),
               static_cast<LONG>(std::round(x + width)),
               static_cast<LONG>(std::round(y + height))});
        }
      }
    }
    next_surfaces[*paper_id] = resolved_surface;
    const bool visible =
        GetBoolArgument(resolved_surface, "isVisible", false);
    if (visible) {
      has_visible_paper = true;
      PaperFlutterWindow* paper_window =
          // Apply the resolved surface exactly once below.  Passing it to
          // EnsurePaperWindow as well used to initialize a new HWND and then
          // immediately apply the same map a second time, causing duplicate
          // bounds/shadow/z-order work on the first visible frame.
          EnsurePaperWindow(*paper_id);
      if (paper_window) {
        paper_window->ApplyState(paper_window_state_);
        paper_window->ApplySurface(resolved_surface);
      }
    } else if (existing_window) {
      existing_window->ApplySurface(resolved_surface);
    }
  }
  paper_window_surfaces_ = std::move(next_surfaces);
  for (auto iterator = paper_windows_.begin();
       iterator != paper_windows_.end();) {
    if (paper_window_surfaces_.find(iterator->first) !=
        paper_window_surfaces_.end()) {
      ++iterator;
      continue;
    }
    iterator->second->Destroy();
    iterator = paper_windows_.erase(iterator);
  }
  if (has_visible_paper && GetHandle()) {
    ShowWindow(GetHandle(), SW_HIDE);
  }
}

void FlutterWindow::ReconcileNativeCapsuleWindows(
    const flutter::EncodableList& surfaces) {
  std::map<std::string, flutter::EncodableMap> next_surfaces;
  for (const auto& value : surfaces) {
    const auto* surface = std::get_if<flutter::EncodableMap>(&value);
    if (!surface) {
      continue;
    }
    const auto id_iterator =
        surface->find(flutter::EncodableValue("surfaceId"));
    if (id_iterator == surface->end()) {
      continue;
    }
    const auto* surface_id =
        std::get_if<std::string>(&id_iterator->second);
    if (!surface_id || surface_id->empty() || surface_id->size() > 512 ||
        (surface_id->rfind("master:", 0) != 0 &&
         surface_id->rfind("proxy:", 0) != 0)) {
      continue;
    }
    next_surfaces[*surface_id] = *surface;
    auto existing = native_capsule_windows_.find(*surface_id);
    if (existing == native_capsule_windows_.end()) {
      auto capsule = std::make_unique<NativeCapsuleWindow>(
          [this](const std::string& method,
                 const flutter::EncodableValue& arguments) {
            SendPaperWindowEvent(method, arguments);
          });
      Win32Window::Point origin(0, 0);
      Win32Window::Size size(112, 46);
      if (!capsule->Create(L"RePaperTodo Native Capsule", origin, size)) {
        continue;
      }
      capsule->SetQuitOnClose(false);
      capsule->SetAvoidFullscreenTopmost(avoid_fullscreen_topmost_);
      existing = native_capsule_windows_
                     .emplace(*surface_id, std::move(capsule))
                     .first;
    }
    existing->second->ApplySurface(*surface);
  }

  // Re-assert the master HWND after all proxy HWNDs have been reconciled.
  // Each capsule is topmost within its queue, so a proxy created later in the
  // batch could otherwise sit above the master for one or more frames and
  // make the collapse/expand button appear to flicker or miss clicks.
  for (auto& entry : native_capsule_windows_) {
    if (entry.second->is_master()) {
      entry.second->RefreshVisibility();
    }
  }

  for (auto iterator = native_capsule_windows_.begin();
       iterator != native_capsule_windows_.end();) {
    if (next_surfaces.find(iterator->first) != next_surfaces.end()) {
      ++iterator;
      continue;
    }
    iterator->second->Destroy();
    iterator = native_capsule_windows_.erase(iterator);
  }
}

PaperFlutterWindow* FlutterWindow::EnsurePaperWindow(
    const std::string& paper_id, const flutter::EncodableMap* surface) {
  if (!ValidatePaperIdArgumentValue(paper_id).valid) {
    return nullptr;
  }
  const auto existing = paper_windows_.find(paper_id);
  if (existing != paper_windows_.end()) {
    if (surface) {
      existing->second->ApplySurface(*surface);
    }
    return existing->second.get();
  }
  flutter::DartProject child_project(L"data");
  child_project.set_dart_entrypoint_arguments(
      {"--repapertodo-paper-window", paper_id});
  auto paper_window = std::make_unique<PaperFlutterWindow>(
      child_project, paper_id,
      [this](const std::string& method,
             const flutter::EncodableValue& arguments) {
        SendPaperWindowEvent(method, arguments);
      });
  Win32Window::Point origin(0, 0);
  Win32Window::Size size(360, 420);
  if (!paper_window->Create(L"RePaperTodo", origin, size)) {
    return nullptr;
  }
  paper_window->SetQuitOnClose(false);
  paper_window->SetHideFromWindowSwitcher(
      hide_papers_from_window_switcher_);
  paper_window->SetAvoidFullscreenTopmost(avoid_fullscreen_topmost_);
  paper_window->ApplyState(paper_window_state_);
  if (surface) {
    paper_window->ApplySurface(*surface);
  }
  PaperFlutterWindow* result = paper_window.get();
  paper_windows_[paper_id] = std::move(paper_window);
  return result;
}

PaperFlutterWindow* FlutterWindow::PaperWindowForId(
    const std::string& paper_id) const {
  const auto iterator = paper_windows_.find(paper_id);
  return iterator == paper_windows_.end() ? nullptr : iterator->second.get();
}

void FlutterWindow::SendPaperWindowEvent(
    const std::string& method, const flutter::EncodableValue& arguments) {
  if (method == "capsuleMasterDragUpdated" ||
      method == "capsuleMasterDragFinished") {
    if (const auto* drag = std::get_if<flutter::EncodableMap>(&arguments)) {
      const std::string monitor =
          GetStringArgument(*drag, "monitorDeviceName", "");
      const std::string side = GetStringArgument(*drag, "side", "right");
      if (method == "capsuleMasterDragUpdated") {
        const int delta_y = static_cast<int>(
            std::round(GetNumberArgument(*drag, "deltaY", 0)));
        const double target_top_value = GetNumberArgument(
            *drag, "targetTop", std::numeric_limits<double>::quiet_NaN());
        if (!std::isfinite(target_top_value)) {
          // Compatibility path for an older native capsule sender that moved
          // its own HWND before emitting the queue update.
          for (auto& entry : native_capsule_windows_) {
            if (!entry.second->is_master() &&
                entry.second->IsInQueue(monitor, side)) {
              entry.second->ApplyQueueDragOffset(delta_y);
            }
          }
          for (auto& entry : paper_windows_) {
            if (entry.second->IsInCapsuleQueue(monitor, side)) {
              entry.second->ApplyQueueDragOffset(delta_y);
            }
          }
          return;
        }

        struct QueueDragMove {
          HWND window = nullptr;
          RECT target = {};
          PaperFlutterWindow* paper_window = nullptr;
        };
        const int target_top =
            static_cast<int>(std::round(target_top_value));
        std::vector<QueueDragMove> moves;
        moves.reserve(native_capsule_windows_.size() + paper_windows_.size());
        for (auto& entry : native_capsule_windows_) {
          if (!entry.second->IsInQueue(monitor, side)) {
            continue;
          }
          RECT target = {};
          const bool should_move = entry.second->is_master()
                                       ? entry.second->PrepareMasterDragTop(
                                             target_top, &target)
                                       : entry.second->PrepareQueueDragOffset(
                                             delta_y, &target);
          if (should_move) {
            moves.push_back(
                QueueDragMove{entry.second->GetHandle(), target, nullptr});
          }
        }
        for (auto& entry : paper_windows_) {
          if (!entry.second->IsInCapsuleQueue(monitor, side)) {
            continue;
          }
          RECT target = {};
          if (entry.second->PrepareQueueDragOffset(delta_y, &target)) {
            moves.push_back(QueueDragMove{entry.second->GetHandle(), target,
                                          entry.second.get()});
          }
        }

        // USER32 applies every HWND in one positioning transaction. This
        // prevents DWM from composing a frame where the master has moved but
        // only part of its queue has followed it.
        bool applied = moves.empty();
        HDWP deferred = moves.empty()
                            ? nullptr
                            : BeginDeferWindowPos(
                                  static_cast<int>(moves.size()));
        if (deferred) {
          for (const auto& move : moves) {
            deferred = DeferWindowPos(
                deferred, move.window, nullptr, move.target.left,
                move.target.top, 0, 0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                    SWP_NOOWNERZORDER);
            if (!deferred) {
              break;
            }
          }
          if (deferred) {
            for (const auto& move : moves) {
              if (move.paper_window) {
                move.paper_window->SetQueueDragBoundsApplying(true);
              }
            }
            applied = EndDeferWindowPos(deferred) != FALSE;
            for (const auto& move : moves) {
              if (move.paper_window) {
                move.paper_window->SetQueueDragBoundsApplying(false);
              }
            }
          }
        }
        if (!applied) {
          // DeferWindowPos can fail under resource pressure. Preserve the
          // gesture with an idempotent per-window fallback.
          for (const auto& move : moves) {
            if (move.paper_window) {
              move.paper_window->SetQueueDragBoundsApplying(true);
            }
            SetWindowPos(move.window, nullptr, move.target.left,
                         move.target.top, 0, 0,
                         SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                             SWP_NOOWNERZORDER);
            if (move.paper_window) {
              move.paper_window->SetQueueDragBoundsApplying(false);
            }
          }
        }
      } else {
        const bool commit = GetBoolArgument(*drag, "commit", false);
        for (auto& entry : native_capsule_windows_) {
          if (!entry.second->is_master() &&
              entry.second->IsInQueue(monitor, side)) {
            entry.second->FinishQueueDrag(commit);
          }
        }
        for (auto& entry : paper_windows_) {
          if (entry.second->IsInCapsuleQueue(monitor, side)) {
            entry.second->FinishQueueDrag(commit);
          }
        }
      }
    }
    return;
  }

  flutter::EncodableValue routed_arguments = arguments;

  // Native expanded-paper proxies must activate their paper synchronously
  // while handling the real mouse input. Waiting for the event to cross the
  // platform channel and return through Dart can miss Windows' foreground
  // activation window, leaving the previously focused app in front even
  // though the proxy click was accepted.
  if (method == "paperActionRequested") {
    if (auto* action =
            std::get_if<flutter::EncodableMap>(&routed_arguments)) {
      const std::string kind = GetStringArgument(*action, "kind", "");
      const std::string target_id = GetStringArgument(*action, "value", "");
      const PaperIdArgument target = ValidatePaperIdArgumentValue(target_id);
      if (kind == "openPaper" && target.valid) {
        if (PaperFlutterWindow* paper_window =
                PaperWindowForId(target.value)) {
          // Only native proxy capsules point at a visible, expanded paper.
          // Hidden/collapsed targets must remain entirely Dart-owned so an
          // early ShowWindow cannot expose their old surface for one frame.
          if (paper_window->IsVisible() && !paper_window->IsCollapsed()) {
            // A proxy click on a desktop-pinned paper is the explicit escape
            // route from desktop mode. Clear the native pin before activation
            // so the HWND never visits HWND_BOTTOM between two show passes.
            RememberPaperPinnedToDesktop(target.value, false);
            auto& surface = paper_window_surfaces_[target.value];
            surface[flutter::EncodableValue("isPinnedToDesktop")] =
                flutter::EncodableValue(false);
            paper_window->SetPinnedToDesktop(false);
            paper_window->ShowPaper(true);
            (*action)[flutter::EncodableValue("nativeActivated")] =
                flutter::EncodableValue(true);
          }
        }
      }
    }
  }

  // A child HWND owns its live geometry. Keep both coordinator-side caches in
  // sync before Dart handles the event so a content/title refresh that races
  // the final WM_EXITSIZEMOVE notification can never replay stale bounds via
  // ApplySurface.
  if (method == "boundsChanged") {
    if (const auto* bounds =
            std::get_if<flutter::EncodableMap>(&arguments)) {
      const PaperIdArgument paper_id_argument =
          GetPaperIdArgument(&arguments);
      if (paper_id_argument.valid) {
        const std::string& paper_id = paper_id_argument.value;
        const double x = GetNumberArgument(*bounds, "x", 0);
        const double y = GetNumberArgument(*bounds, "y", 0);
        const double width = GetNumberArgument(*bounds, "width", 0);
        const double height = GetNumberArgument(*bounds, "height", 0);
        if (width > 0 && height > 0) {
          RECT native_bounds = {};
          PaperFlutterWindow* paper_window = PaperWindowForId(paper_id);
          if (!paper_window ||
              !GetWindowRect(paper_window->GetHandle(), &native_bounds)) {
            const POINT point = {static_cast<LONG>(std::round(x)),
                                 static_cast<LONG>(std::round(y))};
            const HMONITOR monitor =
                MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST);
            const UINT dpi =
                monitor ? FlutterDesktopGetDpiForMonitor(monitor) : 96;
            const double scale = static_cast<double>(dpi > 0 ? dpi : 96) / 96.0;
            native_bounds = {
                static_cast<LONG>(std::round(x * scale)),
                static_cast<LONG>(std::round(y * scale)),
                static_cast<LONG>(std::round((x + width) * scale)),
                static_cast<LONG>(std::round((y + height) * scale)),
            };
          }
          RememberPaperBounds(paper_id, native_bounds);
          auto& surface = paper_window_surfaces_[paper_id];
          surface[flutter::EncodableValue("id")] =
              flutter::EncodableValue(paper_id);
          surface[flutter::EncodableValue("x")] = flutter::EncodableValue(x);
          surface[flutter::EncodableValue("y")] = flutter::EncodableValue(y);
          surface[flutter::EncodableValue("width")] =
              flutter::EncodableValue(width);
          surface[flutter::EncodableValue("height")] =
              flutter::EncodableValue(height);
        }
      }
    }
  }
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(
      method, std::make_unique<flutter::EncodableValue>(routed_arguments));
}

void FlutterWindow::DestroyPaperWindows() {
  for (auto& entry : paper_windows_) {
    entry.second->Destroy();
  }
  paper_windows_.clear();
}

void FlutterWindow::DestroyNativeCapsuleWindows() {
  for (auto& entry : native_capsule_windows_) {
    entry.second->Destroy();
  }
  native_capsule_windows_.clear();
}

void FlutterWindow::OnDestroy() {
  DestroyNativeCapsuleWindows();
  DestroyPaperWindows();
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
  // The coordinator is a fully client-drawn paper window. These messages must
  // be handled before the Flutter controller, otherwise the embedder can let
  // the creation-time overlapped frame repaint a classic caption strip even
  // after WS_CAPTION has been removed.
  if (message == WM_NCCALCSIZE && wparam == TRUE) {
    return 0;
  }
  if (message == WM_NCPAINT) {
    return 0;
  }
  if (message == WM_NCACTIVATE) {
    return TRUE;
  }
  // The settings coordinator is a borderless, thick-frame window. Resolve
  // resize and drag hit tests before the Flutter embedder sees the message;
  // otherwise an embedder/plugin handler can consume WM_NCHITTEST and leave
  // the paper-looking settings page apparently immovable.
  if (message == WM_NCHITTEST) {
    return SettingsCoordinatorHitTest(hwnd, lparam);
  }
  if (message == WM_GETMINMAXINFO) {
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    if (info) {
      const UINT dpi = GetDpiForWindow(hwnd) > 0 ? GetDpiForWindow(hwnd) : 96;
      info->ptMinTrackSize.x =
          ScaleSettingsMetric(dpi, kSettingsWindowMinWidth);
      info->ptMinTrackSize.y =
          ScaleSettingsMetric(dpi, kSettingsWindowMinHeight);
      return 0;
    }
  }

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
    case WM_ERASEBKGND:
      PaintSettingsCoordinatorBackground(
          hwnd, reinterpret_cast<HDC>(wparam));
      return 1;
    case WM_MEASUREITEM:
      if (MeasureTrayMenuItem(
              reinterpret_cast<MEASUREITEMSTRUCT*>(lparam))) {
        return TRUE;
      }
      break;
    case WM_DRAWITEM:
      if (DrawTrayMenuItem(reinterpret_cast<DRAWITEMSTRUCT*>(lparam))) {
        return TRUE;
      }
      break;
    case WM_INITMENUPOPUP:
      PostMessageW(hwnd, kStyleTrayMenuMessage, 0, 0);
      break;
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case WM_MOVE:
      if (paper_windows_.empty() && !IsIconic(hwnd)) {
        SendBoundsChanged();
      }
      break;
    case WM_SIZE:
      if (paper_windows_.empty() && wparam != SIZE_MINIMIZED &&
          !IsIconic(hwnd)) {
        SendBoundsChanged();
      }
      break;
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
      z_order_state_initialized_ = false;
      RefreshActivePaperZOrder(hwnd);
      break;
    case WM_POWERBROADCAST:
      if (wparam == PBT_APMRESUMEAUTOMATIC ||
          wparam == PBT_APMRESUMESUSPEND ||
          wparam == PBT_APMRESUMECRITICAL) {
        z_order_state_initialized_ = false;
        RefreshActivePaperZOrder(hwnd);
      }
      return TRUE;
    case WM_QUERYENDSESSION:
      SendSessionEndingExitRequested();
      return TRUE;
    case WM_ENDSESSION:
      if (wparam == TRUE) {
        SendSessionEndingExitRequested();
      }
      return 0;
    case WM_CLOSE:
      if (!paper_windows_.empty()) {
        SendWindowEvent("coordinatorCloseRequested");
        ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      SendCloseRequested();
      if (!active_paper_id_.empty()) {
        const std::string closed_paper_id = active_paper_id_;
        RememberPaperVisibility(closed_paper_id, false);
        if (RetargetActivePaperToVisibleSurface(hwnd, closed_paper_id)) {
          return 0;
        }
      }
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
        for (auto& entry : native_capsule_windows_) {
          entry.second->RefreshVisibility();
        }
        for (auto& entry : paper_windows_) {
          entry.second->RefreshZOrder();
        }
        RefreshActivePaperZOrder(hwnd);
        return 0;
      }
      break;
    case kSingleInstanceCommandMessage: {
      std::unique_ptr<std::string> command(
          reinterpret_cast<std::string*>(lparam));
      if (command && !command->empty()) {
        SendStartupCommandRequested(*command);
        if (*command == "settings") {
          ShowSettingsCoordinatorWindow(hwnd);
        }
      }
      return 0;
    }
    case kStyleTrayMenuMessage:
      ApplyTrayMenuWindowChrome();
      return 0;
    case kTrayIconMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONDBLCLK:
          SendStartupCommandRequested("show");
          return 0;
        case WM_RBUTTONUP:
          ShowTrayMenu();
          return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
