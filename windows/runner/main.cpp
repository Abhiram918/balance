#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "win32_window.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Prevent multiple instances: check session-scoped named mutex before any
  // Dart/Flutter initialization or resource allocation.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is already running. Find its window and activate it.
    HWND existing_window = nullptr;
    for (int i = 0; i < 10; ++i) {
      existing_window = ::FindWindowW(kWindowClassName, nullptr);
      if (existing_window != nullptr) {
        break;
      }
      ::Sleep(50);
    }

    if (existing_window != nullptr) {
      DWORD existing_pid = 0;
      ::GetWindowThreadProcessId(existing_window, &existing_pid);
      if (existing_pid != 0) {
        ::AllowSetForegroundWindow(existing_pid);
      }
      ::SetForegroundWindow(existing_window);

      const UINT wm_restore_balance =
          ::RegisterWindowMessageW(kRestoreMessageName);
      if (wm_restore_balance != 0) {
        ::PostMessageW(existing_window, wm_restore_balance, 0, 0);
      }
    }

    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"balance", origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (single_instance_mutex != nullptr) {
    ::CloseHandle(single_instance_mutex);
  }

  return EXIT_SUCCESS;
}
