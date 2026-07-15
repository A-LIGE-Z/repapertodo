#include <windows.h>

#include <cstdlib>

namespace {

constexpr size_t kPathCapacity = 32768;
constexpr size_t kCommandCapacity = 65536;

bool Append(wchar_t* target, size_t capacity, const wchar_t* value) {
  const size_t current = static_cast<size_t>(lstrlenW(target));
  const size_t length = static_cast<size_t>(lstrlenW(value));
  if (current + length + 1 >= capacity) {
    return false;
  }
  lstrcatW(target, value);
  return true;
}

bool SetRootFromModulePath(wchar_t* path, size_t capacity) {
  const DWORD length = GetModuleFileNameW(nullptr, path,
                                          static_cast<DWORD>(capacity));
  if (length == 0 || length >= capacity) {
    return false;
  }
  wchar_t* separator = path + length;
  while (separator > path && separator[-1] != L'\\' &&
         separator[-1] != L'/') {
    separator -= 1;
  }
  if (separator == path) {
    return false;
  }
  separator[-1] = L'\0';
  return true;
}

bool BuildCommandLine(const wchar_t* runtime_executable,
                      const wchar_t* arguments, wchar_t* command,
                      size_t capacity) {
  command[0] = L'\0';
  if (!Append(command, capacity, L"\"") ||
      !Append(command, capacity, runtime_executable) ||
      !Append(command, capacity, L"\"")) {
    return false;
  }
  if (arguments && arguments[0] != L'\0') {
    if (!Append(command, capacity, L" ") ||
        !Append(command, capacity, arguments)) {
      return false;
    }
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE,
                      _In_ wchar_t* command_line, _In_ int) {
  wchar_t root[kPathCapacity] = {};
  if (!SetRootFromModulePath(root, kPathCapacity)) {
    return EXIT_FAILURE;
  }
  wchar_t runtime_directory[kPathCapacity] = {};
  lstrcpyW(runtime_directory, root);
  if (!Append(runtime_directory, kPathCapacity, L"\\runtime")) {
    return EXIT_FAILURE;
  }
  wchar_t runtime_executable[kPathCapacity] = {};
  lstrcpyW(runtime_executable, runtime_directory);
  if (!Append(runtime_executable, kPathCapacity,
              L"\\repapertodo.runtime.exe") ||
      GetFileAttributesW(runtime_executable) == INVALID_FILE_ATTRIBUTES) {
    MessageBoxW(nullptr,
                L"RePaperTodo runtime files are missing. Extract the complete "
                L"ZIP before starting the application.",
                L"RePaperTodo", MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
    return EXIT_FAILURE;
  }

  wchar_t command[kCommandCapacity] = {};
  if (!BuildCommandLine(runtime_executable, command_line, command,
                        kCommandCapacity)) {
    return EXIT_FAILURE;
  }
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  const BOOL started = CreateProcessW(
      runtime_executable, command, nullptr, nullptr, FALSE,
      CREATE_UNICODE_ENVIRONMENT, nullptr, runtime_directory, &startup,
      &process);
  if (!started) {
    MessageBoxW(nullptr,
                L"RePaperTodo could not start its runtime process. Re-extract "
                L"the complete ZIP and try again.",
                L"RePaperTodo", MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
    return EXIT_FAILURE;
  }
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return EXIT_SUCCESS;
}
