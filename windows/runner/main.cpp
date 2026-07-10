#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"RePaperTodo-SingleInstance-Mutex";
constexpr wchar_t kSingleInstancePipeName[] =
    L"\\\\.\\pipe\\RePaperTodo-SingleInstance-Activate";

bool IsExplicitExitStartupCommand(const std::vector<std::string>& args) {
  return StartupCommandFromArgs(args) == "exit";
}

void SignalPrimaryInstance(const std::vector<std::string>& args) {
  const std::string command = StartupCommandFromArgs(args);
  if (command.empty()) {
    return;
  }
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
