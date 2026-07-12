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

class ScopedComInitializer {
 public:
  ScopedComInitializer()
      : initialized_(SUCCEEDED(
            ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {}

  ~ScopedComInitializer() {
    if (initialized_) {
      ::CoUninitialize();
    }
  }

  ScopedComInitializer(const ScopedComInitializer&) = delete;
  ScopedComInitializer& operator=(const ScopedComInitializer&) = delete;

 private:
  bool initialized_ = false;
};

class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle) : handle_(handle) {}

  ~ScopedHandle() { Reset(); }

  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  bool is_valid() const {
    return handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE;
  }

 private:
  void Reset() {
    if (is_valid()) {
      CloseHandle(handle_);
      handle_ = nullptr;
    }
  }

  HANDLE handle_ = nullptr;
};

bool IsExplicitExitStartupCommand(const std::vector<std::string>& args) {
  return StartupCommandFromArgs(args) == "exit";
}

void SignalPrimaryInstance(const std::vector<std::string>& args) {
  SignalStartupCommandPipe(kSingleInstancePipeName, args, 6, 180, 70);
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
  ScopedComInitializer com_initializer;

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (IsExplicitExitStartupCommand(command_line_arguments)) {
    ScopedHandle existing_instance(
        OpenMutexW(SYNCHRONIZE, FALSE, kSingleInstanceMutexName));
    if (!existing_instance.is_valid()) {
      return EXIT_SUCCESS;
    }
  }

  HANDLE single_instance_mutex_handle =
      CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  const DWORD single_instance_mutex_error = GetLastError();
  ScopedHandle single_instance_mutex(single_instance_mutex_handle);
  if (!single_instance_mutex.is_valid() ||
      single_instance_mutex_error == ERROR_ALREADY_EXISTS) {
    SignalPrimaryInstance(command_line_arguments);
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

  return EXIT_SUCCESS;
}
