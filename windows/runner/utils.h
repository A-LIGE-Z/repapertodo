#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Canonicalizes PaperTodo-style startup arguments for both the process entry
// point and the Flutter platform channel. Empty arguments default to "show";
// arguments containing only unknown commands return an empty string.
std::string StartupCommandFromArgs(const std::vector<std::string>& args);

#endif  // RUNNER_UTILS_H_
