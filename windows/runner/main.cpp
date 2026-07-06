#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"RePaperTodo-SingleInstance-Mutex";
constexpr wchar_t kSingleInstancePipeName[] =
    L"\\\\.\\pipe\\RePaperTodo-SingleInstance-Activate";

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
  return "show";
}

bool IsExplicitExitStartupCommand(const std::vector<std::string>& args) {
  return StartupCommandFromArgs(args) == "exit";
}

void SignalPrimaryInstance(const std::vector<std::string>& args) {
  const std::string command = StartupCommandFromArgs(args);
  for (int attempt = 0; attempt < 6; attempt++) {
    HANDLE pipe = CreateFileW(kSingleInstancePipeName, GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, 0, nullptr);
    if (pipe != INVALID_HANDLE_VALUE) {
      DWORD bytes_written = 0;
      WriteFile(pipe, command.data(), static_cast<DWORD>(command.size()),
                &bytes_written, nullptr);
      const char newline = '\n';
      WriteFile(pipe, &newline, 1, &bytes_written, nullptr);
      CloseHandle(pipe);
      return;
    }
    WaitNamedPipeW(kSingleInstancePipeName, 180);
    Sleep(70);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (IsExplicitExitStartupCommand(command_line_arguments)) {
    HANDLE existing_instance =
        OpenMutexW(SYNCHRONIZE, FALSE, kSingleInstanceMutexName);
    if (!existing_instance) {
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
    CloseHandle(existing_instance);
  }

  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (!single_instance_mutex ||
      GetLastError() == ERROR_ALREADY_EXISTS) {
    SignalPrimaryInstance(command_line_arguments);
    if (single_instance_mutex) {
      CloseHandle(single_instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"RePaperTodo", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  CloseHandle(single_instance_mutex);
  return EXIT_SUCCESS;
}
