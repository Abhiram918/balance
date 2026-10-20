import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Representation of a discovered Windows process.
class RunningProcessInfo {
  final int pid;
  final String exePath;
  final String exeName;
  final List<HWND> windowHandles;

  const RunningProcessInfo({
    required this.pid,
    required this.exePath,
    required this.exeName,
    this.windowHandles = const [],
  });

  @override
  String toString() =>
      'RunningProcessInfo(pid: $pid, exeName: $exeName, windows: ${windowHandles.length})';
}

/// Target application criteria used for batch process matching.
@immutable
class TargetAppCriteria {
  final String appName;
  final String? exePath;

  const TargetAppCriteria({
    required this.appName,
    this.exePath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetAppCriteria &&
          runtimeType == other.runtimeType &&
          appName.trim().toLowerCase() == other.appName.trim().toLowerCase() &&
          (exePath?.trim().toLowerCase() ?? '') == (other.exePath?.trim().toLowerCase() ?? '');

  @override
  int get hashCode =>
      appName.trim().toLowerCase().hashCode ^ (exePath?.trim().toLowerCase() ?? '').hashCode;

  @override
  String toString() => 'TargetAppCriteria(appName: $appName, exePath: $exePath)';
}

/// Abstract contract for Windows process discovery, graceful closing, and termination.
/// Allows unit and widget tests to inject mock process operations without touching real OS processes.
abstract class ProcessManager {
  /// Gets the current running application process ID.
  int getCurrentProcessId();

  /// Finds running processes matching the specified application name or executable path.
  Future<List<RunningProcessInfo>> findProcessesForApp({
    required String appName,
    String? exePath,
  });

  /// Finds running processes for multiple target applications using a shared process enumeration.
  /// Returns a map associating each target criteria with its matching running processes.
  Future<Map<TargetAppCriteria, List<RunningProcessInfo>>> findProcessesForApps(
    List<TargetAppCriteria> targets,
  ) async {
    final result = <TargetAppCriteria, List<RunningProcessInfo>>{};
    for (final target in targets) {
      result[target] = await findProcessesForApp(
        appName: target.appName,
        exePath: target.exePath,
      );
    }
    return result;
  }

  /// Sends a graceful close signal (e.g. WM_CLOSE) to the target application's windows.
  Future<bool> closeProcessGracefully(RunningProcessInfo process);

  /// Checks if a process ID is currently alive.
  Future<bool> isProcessRunning(int pid);

  /// Forcefully terminates a process by PID.
  Future<bool> terminateProcess(int pid);
}

/// Production implementation of [ProcessManager] leveraging Win32 FFI APIs.
class WindowsProcessManager implements ProcessManager {
  final Map<int, List<HWND>> Function(int selfPid)? pidWindowsProvider;
  final List<int> Function()? processListProvider;
  final String Function(int pid)? processPathProvider;
  final int Function()? currentPidProvider;
  final bool Function(RunningProcessInfo proc)? closeProcessProvider;
  final bool Function(int pid)? isRunningProvider;
  final bool Function(int pid)? terminateProvider;

  WindowsProcessManager({
    this.pidWindowsProvider,
    this.processListProvider,
    this.processPathProvider,
    this.currentPidProvider,
    this.closeProcessProvider,
    this.isRunningProvider,
    this.terminateProvider,
  });

  static const Set<String> _protectedProcessNames = {
    'explorer.exe',
    'dwm.exe',
    'csrss.exe',
    'smss.exe',
    'lsass.exe',
    'services.exe',
    'wininit.exe',
    'winlogon.exe',
    'svchost.exe',
    'system',
    'system idle process',
    'taskmgr.exe',
    'cmd.exe',
    'powershell.exe',
    'pwsh.exe',
    'conhost.exe',
    'sihost.exe',
    'fontdrvhost.exe',
    'ctfmon.exe',
    'balance.exe',
    'flutter_tester.exe',
  };

  @override
  int getCurrentProcessId() {
    if (currentPidProvider != null) {
      return currentPidProvider!();
    }
    try {
      return GetCurrentProcessId();
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<Map<TargetAppCriteria, List<RunningProcessInfo>>> findProcessesForApps(
    List<TargetAppCriteria> targets,
  ) async {
    final result = <TargetAppCriteria, List<RunningProcessInfo>>{
      for (final target in targets) target: <RunningProcessInfo>[],
    };
    if (targets.isEmpty) return result;

    final selfPid = getCurrentProcessId();

    // 1. Gather all top-level window handles mapped by PID via EnumWindows (once for batch)
    final pidWindows = _collectPidWindows(selfPid);

    // 2. Enumerate system processes (using injected provider or EnumProcesses)
    if (processListProvider != null) {
      final pids = processListProvider!();
      for (final pid in pids) {
        if (pid <= 4 || pid == selfPid) continue;

        final procExePath = _queryProcessExePath(pid);
        if (procExePath.isEmpty) continue;

        final procExeName = procExePath.split(r'\').last;
        if (_isProtectedProcess(procExeName, procExePath, selfPid, pid)) {
          continue;
        }

        RunningProcessInfo? procInfo;

        for (final target in targets) {
          if (_matchesApp(
            candidateExePath: procExePath,
            candidateExeName: procExeName,
            targetAppName: target.appName,
            targetExePath: target.exePath,
          )) {
            procInfo ??= RunningProcessInfo(
              pid: pid,
              exePath: procExePath,
              exeName: procExeName,
              windowHandles: pidWindows[pid] ?? const [],
            );
            result[target]!.add(procInfo);
          }
        }
      }
      return result;
    }

    final pids = calloc<DWORD>(2048);
    final bytesNeeded = calloc<DWORD>();

    try {
      final success = EnumProcesses(pids, 2048 * sizeOf<DWORD>(), bytesNeeded);
      if (success.value) {
        final count = bytesNeeded.value ~/ sizeOf<DWORD>();
        for (var i = 0; i < count; i++) {
          final pid = pids[i];
          if (pid <= 4 || pid == selfPid) continue;

          final procExePath = _queryProcessExePath(pid);
          if (procExePath.isEmpty) continue;

          final procExeName = procExePath.split(r'\').last;
          if (_isProtectedProcess(procExeName, procExePath, selfPid, pid)) {
            continue;
          }

          RunningProcessInfo? procInfo;

          for (final target in targets) {
            if (_matchesApp(
              candidateExePath: procExePath,
              candidateExeName: procExeName,
              targetAppName: target.appName,
              targetExePath: target.exePath,
            )) {
              procInfo ??= RunningProcessInfo(
                pid: pid,
                exePath: procExePath,
                exeName: procExeName,
                windowHandles: pidWindows[pid] ?? const [],
              );
              result[target]!.add(procInfo);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error enumerating processes in batch: $e');
    } finally {
      free(pids);
      free(bytesNeeded);
    }

    return result;
  }

  @override
  Future<List<RunningProcessInfo>> findProcessesForApp({
    required String appName,
    String? exePath,
  }) async {
    final target = TargetAppCriteria(appName: appName, exePath: exePath);
    final batch = await findProcessesForApps([target]);
    return batch[target] ?? [];
  }

  @override
  Future<bool> closeProcessGracefully(RunningProcessInfo process) async {
    if (_isProtectedProcess(process.exeName, process.exePath, getCurrentProcessId(), process.pid)) {
      debugPrint('Attempted to close protected process: ${process.exeName} (PID ${process.pid})');
      return false;
    }

    if (closeProcessProvider != null) {
      return closeProcessProvider!(process);
    }

    bool sentAny = false;
    for (final hwnd in process.windowHandles) {
      try {
        final res = PostMessage(hwnd, WM_CLOSE, WPARAM(0), LPARAM(0));
        if (res.value) {
          sentAny = true;
        }
      } catch (e) {
        debugPrint('PostMessage WM_CLOSE failed for HWND $hwnd: $e');
      }
    }

    return sentAny;
  }

  @override
  Future<bool> isProcessRunning(int pid) async {
    if (pid <= 4) return false;

    if (isRunningProvider != null) {
      return isRunningProvider!(pid);
    }

    final hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
    if (hProcess.value.address == 0) {
      return false;
    }

    final exitCode = calloc<DWORD>();
    try {
      final success = GetExitCodeProcess(hProcess.value, exitCode);
      if (success.value) {
        return exitCode.value == STILL_ACTIVE;
      }
      return false;
    } finally {
      free(exitCode);
      CloseHandle(hProcess.value);
    }
  }

  @override
  Future<bool> terminateProcess(int pid) async {
    final selfPid = getCurrentProcessId();
    if (pid <= 4 || pid == selfPid) {
      return false;
    }

    final exePath = _queryProcessExePath(pid);
    final exeName = exePath.split(r'\').last;
    if (_isProtectedProcess(exeName, exePath, selfPid, pid)) {
      debugPrint('Protected process blocked from termination: $exeName (PID $pid)');
      return false;
    }

    if (terminateProvider != null) {
      return terminateProvider!(pid);
    }

    final hProcess = OpenProcess(PROCESS_TERMINATE, false, pid);
    if (hProcess.value.address == 0) {
      debugPrint('Unable to open process $pid for termination (access denied or already closed)');
      return false;
    }

    try {
      final result = TerminateProcess(hProcess.value, 1);
      return result.value;
    } catch (e) {
      debugPrint('TerminateProcess error for PID $pid: $e');
      return false;
    } finally {
      CloseHandle(hProcess.value);
    }
  }

  Map<int, List<HWND>> _collectPidWindows(int selfPid) {
    if (pidWindowsProvider != null) {
      return pidWindowsProvider!(selfPid);
    }

    final map = <int, List<HWND>>{};
    final pidPointer = calloc<DWORD>();
    NativeCallable<WNDENUMPROC>? callable;

    int enumCallback(Pointer<NativeType> hwndPtr, int lParam) {
      final hwnd = HWND(hwndPtr);
      GetWindowThreadProcessId(hwnd, pidPointer);
      final pid = pidPointer.value;
      if (pid > 4 && pid != selfPid) {
        map.putIfAbsent(pid, () => []).add(hwnd);
      }
      return 1; // continue
    }

    try {
      callable = NativeCallable<WNDENUMPROC>.isolateLocal(
        enumCallback,
        exceptionalReturn: 0,
      );
      EnumWindows(callable.nativeFunction, LPARAM(0));
    } catch (e) {
      debugPrint('EnumWindows failed: $e');
    } finally {
      callable?.close();
      free(pidPointer);
    }

    return map;
  }

  String _queryProcessExePath(int pid) {
    if (processPathProvider != null) {
      return processPathProvider!(pid);
    }

    final hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
    if (hProcess.value.address == 0) return '';

    final buffer = wsalloc(MAX_PATH);
    final size = calloc<DWORD>()..value = MAX_PATH;
    String path = '';

    try {
      final res = QueryFullProcessImageName(
        hProcess.value,
        PROCESS_NAME_FORMAT(0),
        buffer,
        size,
      );
      if (res.value) {
        path = buffer.toDartString();
      }
    } catch (_) {
    } finally {
      free(buffer);
      free(size);
      CloseHandle(hProcess.value);
    }

    return path;
  }

  bool _isProtectedProcess(String exeName, String exePath, int selfPid, int targetPid) {
    if (targetPid <= 4 || targetPid == selfPid) return true;

    final lowerName = exeName.toLowerCase();
    if (_protectedProcessNames.contains(lowerName)) {
      return true;
    }

    final lowerPath = exePath.toLowerCase();
    if (lowerPath.contains(r'\windows\system32\') || lowerPath.contains(r'\windows\syswow64\')) {
      if (lowerName.endsWith('host.exe') ||
          lowerName.startsWith('win') ||
          lowerName.startsWith('sec') ||
          lowerName.startsWith('srv')) {
        return true;
      }
    }

    return false;
  }

  @visibleForTesting
  bool matchesProcess({
    required String processName,
    required String appName,
    String? processExePath,
    String? targetExePath,
  }) {
    return _matchesApp(
      candidateExePath: processExePath ?? processName,
      candidateExeName: processName,
      targetAppName: appName,
      targetExePath: targetExePath,
    );
  }

  bool _matchesApp({
    required String candidateExePath,
    required String candidateExeName,
    required String targetAppName,
    String? targetExePath,
  }) {
    final candPathLower = candidateExePath.toLowerCase();
    final candNameLower = candidateExeName.toLowerCase();

    // 1. Direct executable path match
    if (targetExePath != null && targetExePath.trim().isNotEmpty) {
      final targetPathLower = targetExePath.trim().toLowerCase();
      if (candPathLower == targetPathLower) return true;
      final targetNameLower = targetExePath.split(r'\').last.toLowerCase();
      if (candNameLower == targetNameLower) return true;
    }

    // 2. Normalized app name match
    final cleanApp = targetAppName.trim().toLowerCase();
    if (cleanApp.isEmpty) return false;

    // e.g. "telegram.exe" matches "Telegram"
    final candBaseName = candNameLower.endsWith('.exe')
        ? candNameLower.substring(0, candNameLower.length - 4)
        : candNameLower;

    if (candBaseName == cleanApp) return true;
    if (candNameLower == '$cleanApp.exe') return true;

    // Handle common names
    if (cleanApp == 'google chrome' && candBaseName == 'chrome') return true;
    if (cleanApp == 'visual studio code' && candBaseName == 'code') return true;
    if (cleanApp == 'telegram desktop' && candBaseName == 'telegram') return true;
    if (cleanApp == 'microsoft edge' && candBaseName == 'msedge') return true;
    if (cleanApp == 'whatsapp' && (candBaseName == 'whatsapp.root' || candBaseName == 'whatsapp')) return true;
    if (cleanApp == 'snipping tool' && candBaseName == 'snippingtool') return true;
    if (cleanApp == 'mozilla firefox' && candBaseName == 'firefox') return true;

    return false;
  }
}
