#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

namespace {

class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle) : handle_(handle) {}

  ~ScopedHandle() { Reset(); }

  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

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

std::string NormalizeStartupArgument(std::string arg) {
  const auto begin = std::find_if_not(
      arg.begin(), arg.end(),
      [](unsigned char character) { return std::isspace(character); });
  const auto end = std::find_if_not(
                       arg.rbegin(), arg.rend(),
                       [](unsigned char character) {
                         return std::isspace(character);
                       })
                       .base();
  if (begin >= end) {
    return std::string();
  }
  arg = std::string(begin, end);
  while (!arg.empty() && (arg.front() == '-' || arg.front() == '/')) {
    arg.erase(arg.begin());
  }

  std::string normalized;
  bool previous_separator = false;
  for (const char character : arg) {
    const unsigned char ascii = static_cast<unsigned char>(character);
    if (std::isspace(ascii) || character == '_' || character == '-') {
      if (!normalized.empty() && !previous_separator) {
        normalized.push_back('-');
        previous_separator = true;
      }
      continue;
    }
    normalized.push_back(static_cast<char>(std::tolower(ascii)));
    previous_separator = false;
  }
  if (!normalized.empty() && normalized.back() == '-') {
    normalized.pop_back();
  }
  return normalized;
}

std::string CanonicalStartupCommand(const std::string& normalized) {
  if (normalized == "show" || normalized == "open") {
    return "show";
  }
  if (normalized == "hide" || normalized == "close") {
    return "hide";
  }
  if (normalized == "toggle") {
    return "toggle";
  }
  if (normalized == "new-todo" || normalized == "newtodo" ||
      normalized == "add-todo" || normalized == "addtodo" ||
      normalized == "todo") {
    return "new-todo";
  }
  if (normalized == "new-note" || normalized == "newnote" ||
      normalized == "add-note" || normalized == "addnote" ||
      normalized == "note" || normalized == "paper") {
    return "new-note";
  }
  if (normalized == "reveal-pinned-todo" ||
      normalized == "reveal-pinnedtodo" ||
      normalized == "show-pinned-todo" || normalized == "pinned-todo") {
    return "reveal-pinned-todo";
  }
  if (normalized == "reveal-pinned-note" ||
      normalized == "reveal-pinnednote" ||
      normalized == "show-pinned-note" || normalized == "pinned-note") {
    return "reveal-pinned-note";
  }
  if (normalized == "settings" || normalized == "setting" ||
      normalized == "preferences" || normalized == "preference" ||
      normalized == "prefs") {
    return "settings";
  }
  if (normalized == "exit" || normalized == "quit") {
    return "exit";
  }
  return std::string();
}

std::string CreatedPaperStartupCommand(const std::string& normalized) {
  if (normalized == "todo" || normalized == "task") {
    return "new-todo";
  }
  if (normalized == "note" || normalized == "paper") {
    return "new-note";
  }
  return std::string();
}

bool WriteStartupCommandToPipe(HANDLE pipe, const std::string& command) {
  if (!pipe || pipe == INVALID_HANDLE_VALUE || command.empty()) {
    return false;
  }
  DWORD bytes_written = 0;
  if (!WriteFile(pipe, command.data(), static_cast<DWORD>(command.size()),
                 &bytes_written, nullptr) ||
      bytes_written != static_cast<DWORD>(command.size())) {
    return false;
  }
  const char newline = '\n';
  bytes_written = 0;
  return WriteFile(pipe, &newline, 1, &bytes_written, nullptr) &&
         bytes_written == 1;
}

bool WritePipeWake(HANDLE pipe) {
  if (!pipe || pipe == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD bytes_written = 0;
  const char newline = '\n';
  return WriteFile(pipe, &newline, 1, &bytes_written, nullptr) &&
         bytes_written == 1;
}

}  // namespace

std::string StartupCommandFromArgs(const std::vector<std::string>& args) {
  std::vector<std::string> normalized_args;
  for (const std::string& raw_arg : args) {
    size_t segment_start = 0;
    while (segment_start <= raw_arg.size()) {
      const size_t segment_end = raw_arg.find_first_of("=:", segment_start);
      const std::string segment = raw_arg.substr(
          segment_start,
          segment_end == std::string::npos ? std::string::npos
                                           : segment_end - segment_start);
      const std::string normalized = NormalizeStartupArgument(segment);
      if (!normalized.empty()) {
        normalized_args.push_back(normalized);
      }
      if (segment_end == std::string::npos) {
        break;
      }
      segment_start = segment_end + 1;
    }
  }
  for (size_t index = 0; index < normalized_args.size(); index++) {
    if (normalized_args[index] == "new" && index + 1 < normalized_args.size()) {
      const std::string created_command =
          CreatedPaperStartupCommand(normalized_args[index + 1]);
      if (!created_command.empty()) {
        return created_command;
      }
    }
    const std::string command = CanonicalStartupCommand(normalized_args[index]);
    if (!command.empty()) {
      return command;
    }
  }
  if (normalized_args.empty()) {
    return "show";
  }
  return std::string();
}

bool SignalStartupCommandPipe(const wchar_t* pipe_name,
                              const std::vector<std::string>& args,
                              int attempts,
                              unsigned long wait_milliseconds,
                              unsigned long sleep_milliseconds) {
  const std::string command = StartupCommandFromArgs(args);
  if (command.empty()) {
    return true;
  }
  if (!pipe_name || attempts <= 0) {
    return false;
  }
  for (int attempt = 0; attempt < attempts; attempt++) {
    ScopedHandle pipe(CreateFileW(pipe_name, GENERIC_WRITE, 0, nullptr,
                                  OPEN_EXISTING, 0, nullptr));
    if (pipe.is_valid() && WriteStartupCommandToPipe(pipe.get(), command)) {
      return true;
    }
    WaitNamedPipeW(pipe_name, wait_milliseconds);
    Sleep(sleep_milliseconds);
  }
  return false;
}

bool SignalPipeWake(const wchar_t* pipe_name,
                    int attempts,
                    unsigned long wait_milliseconds,
                    unsigned long sleep_milliseconds) {
  if (!pipe_name || attempts <= 0) {
    return false;
  }
  for (int attempt = 0; attempt < attempts; attempt++) {
    ScopedHandle pipe(CreateFileW(pipe_name, GENERIC_WRITE, 0, nullptr,
                                  OPEN_EXISTING, 0, nullptr));
    if (pipe.is_valid() && WritePipeWake(pipe.get())) {
      return true;
    }
    WaitNamedPipeW(pipe_name, wait_milliseconds);
    Sleep(sleep_milliseconds);
  }
  return false;
}
