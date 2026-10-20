import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';
import '../models/app_session.dart';
import '../models/focus_session.dart';
import '../models/usage_data.dart';
import 'focus_service.dart';
import 'usage_calculator.dart';
import 'usage_repository.dart';
import 'windows_app_discovery_service.dart';

class WindowsUsageTracker extends ChangeNotifier {
  final UsageRepository repository;
  final WindowsAppDiscoveryService? discoveryService;
  final FocusService? focusService;

  // Optional custom providers for unit testing without Windows FFI
  final Duration Function()? idleTimeProvider;
  final String? Function()? foregroundWindowProvider;

  Timer? _timer;
  bool _isRunning = false;
  bool _hasError = false;
  String _errorMessage = '';

  String? _currentExePath;
  String? _currentAppName;
  DateTime? _sessionStartTime;
  DateTime _lastActiveTime = DateTime.now();
  int? _currentSessionId;
  DateTime? _lastCheckpointTime;
  bool _isUserIdle = false;

  DailyUsageSummary? _todaySummary;

  Duration _idleThreshold = const Duration(minutes: 2);
  final Duration _pollingInterval = const Duration(seconds: 2);
  final Duration checkpointInterval;
  final DateTime Function()? clock;

  DateTime get _now => clock != null ? clock!() : DateTime.now();

  FocusStatus? _lastFocusStatus;
  FocusSessionType? _lastFocusSessionType;
  DateTime? _lastFocusStartTime;
  FocusSessionRecord? _lastCompletedSession;

  List<AppSession>? _cachedCommittedSessions;
  List<FocusSessionRecord>? _cachedCommittedFocusSessions;

  WindowsUsageTracker({
    required this.repository,
    this.discoveryService,
    this.focusService,
    this.idleTimeProvider,
    this.foregroundWindowProvider,
    this.clock,
    this.checkpointInterval = const Duration(seconds: 15),
  }) {
    _lastActiveTime = _now;
    _lastFocusStatus = focusService?.status;
    _lastFocusSessionType = focusService?.sessionType;
    _lastFocusStartTime = focusService?.startTime;
    _lastCompletedSession = focusService?.lastCompletedSession;
    focusService?.addListener(_onFocusServiceChanged);
  }

  void _onFocusServiceChanged() {
    if (focusService == null) return;

    final currentStatus = focusService!.status;
    final currentType = focusService!.sessionType;
    final currentStartTime = focusService!.startTime;
    final currentCompleted = focusService!.lastCompletedSession;

    final hasLifecycleChanged = currentStatus != _lastFocusStatus ||
        currentType != _lastFocusSessionType ||
        currentStartTime != _lastFocusStartTime ||
        currentCompleted != _lastCompletedSession;

    if (hasLifecycleChanged) {
      _lastFocusStatus = currentStatus;
      _lastFocusSessionType = currentType;
      _lastFocusStartTime = currentStartTime;
      _lastCompletedSession = currentCompleted;
      _cachedCommittedFocusSessions = null;
      _refreshSummary();
    }
  }

  bool get isRunning => _isRunning;
  bool get hasError => _hasError;
  bool get isUserIdle => _isUserIdle;
  String get errorMessage => _errorMessage;
  DailyUsageSummary? get todaySummary => _todaySummary;
  Duration get idleThreshold => _idleThreshold;
  String? get currentAppName => _currentAppName;
  String? get currentExePath => _currentExePath;

  /// Returns the currently active in-progress session, if tracking an active application.
  AppSession? get liveSession {
    if (_currentExePath != null && _sessionStartTime != null) {
      return AppSession(
        id: _currentSessionId,
        appName: _currentAppName ?? 'Unknown',
        exePath: _currentExePath!,
        startTime: _sessionStartTime!,
        endTime: _lastActiveTime,
      );
    }
    return null;
  }

  /// Updates the idle threshold duration (e.g. from Settings).
  void setIdleThreshold(Duration threshold) {
    if (_idleThreshold == threshold) return;
    _idleThreshold = threshold;
    notifyListeners();
  }

  Future<void> init() async {
    await _refreshSummary();
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _hasError = false;
    _errorMessage = '';
    notifyListeners();

    _timer = Timer.periodic(_pollingInterval, (timer) => _checkForegroundWindow());
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    await _finalizeCurrentSession();
    await _refreshSummary();
    notifyListeners();
  }

  Future<void> _checkForegroundWindow() async {
    try {
      final idleTime = idleTimeProvider != null ? idleTimeProvider!() : _getIdleTime();
      final isIdle = idleTime >= _idleThreshold;

      if (isIdle) {
        if (!_isUserIdle) {
          // Transitioned from active to idle.
          // Cut off session at exact time of last input, not crediting idle time.
          final lastInputTime = _now.subtract(idleTime);
          await _finalizeCurrentSession(overrideEndTime: lastInputTime);
          _isUserIdle = true;
          _cachedCommittedSessions = null;
          await _refreshSummary();
        }
        return;
      } else {
        if (_isUserIdle) {
          _isUserIdle = false;
        }
      }

      String exePath = '';
      if (foregroundWindowProvider != null) {
        exePath = foregroundWindowProvider!() ?? '';
      } else {
        exePath = _queryForegroundExePath();
      }

      if (exePath.isEmpty) {
        // Window could not be resolved or desktop/task-switching active;
        // do not terminate tracking.
        return;
      }

      final appName = _getAppNameFromExe(exePath);
      final now = _now;

      // Check for midnight crossing
      if (_sessionStartTime != null && _sessionStartTime!.day != now.day) {
        final endOfPrevDay = DateTime(
          _sessionStartTime!.year,
          _sessionStartTime!.month,
          _sessionStartTime!.day,
          23,
          59,
          59,
          999,
        );
        await _finalizeCurrentSession(overrideEndTime: endOfPrevDay);
        _sessionStartTime = DateTime(now.year, now.month, now.day);
        _currentExePath = exePath;
        _currentAppName = appName;
        _lastActiveTime = now;
        _currentSessionId = null;
        _lastCheckpointTime = _sessionStartTime;
        _cachedCommittedSessions = null;
        _cachedCommittedFocusSessions = null;
      }

      if (_currentExePath != exePath) {
        // Application switched
        await _finalizeCurrentSession();

        _currentExePath = exePath;
        _currentAppName = appName;
        _sessionStartTime = now;
        _lastActiveTime = now;
        _currentSessionId = null;
        _lastCheckpointTime = now;
        _cachedCommittedSessions = null;
      } else {
        // Same application continuing
        _lastActiveTime = now;

        // Checkpoint active session to SQLite once it exceeds 2 seconds and checkpoint interval elapsed
        if (_sessionStartTime != null &&
            _lastActiveTime.difference(_sessionStartTime!) > const Duration(seconds: 2)) {
          final timeSinceCheckpoint = _lastCheckpointTime == null
              ? _lastActiveTime.difference(_sessionStartTime!)
              : _lastActiveTime.difference(_lastCheckpointTime!);

          if (timeSinceCheckpoint >= checkpointInterval) {
            if (_currentSessionId == null) {
              final session = AppSession(
                appName: _currentAppName ?? 'Unknown',
                exePath: _currentExePath!,
                startTime: _sessionStartTime!,
                endTime: _lastActiveTime,
              );
              final inserted = await repository.insertSession(session);
              _currentSessionId = inserted.id;
            } else {
              await repository.updateSessionEndTime(_currentSessionId!, _lastActiveTime);
            }
            _lastCheckpointTime = _lastActiveTime;
            _cachedCommittedSessions = null;
          }
        }
      }

      await _refreshSummary();
    } catch (e) {
      // Do not permanently stop tracking on transient Win32 errors
      _hasError = true;
      _errorMessage = "Tracking warning: ${e.toString()}";
      notifyListeners();
    }
  }

  String _queryForegroundExePath() {
    final hwnd = GetForegroundWindow();
    if (hwnd.address == 0) return '';

    int pid = 0;
    final pidPointer = calloc<DWORD>();
    try {
      GetWindowThreadProcessId(hwnd, pidPointer);
      pid = pidPointer.value;
    } finally {
      free(pidPointer);
    }

    if (pid == 0) return '';

    final processHandle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
    if (processHandle.value.address == 0) return '';

    String exePath = '';
    final buffer = wsalloc(MAX_PATH);
    final size = calloc<DWORD>()..value = MAX_PATH;

    try {
      final res = QueryFullProcessImageName(
        processHandle.value,
        PROCESS_NAME_FORMAT(0),
        buffer,
        size,
      );
      if (res.value) {
        exePath = buffer.toDartString();
      }
    } finally {
      free(buffer);
      free(size);
      CloseHandle(processHandle.value);
    }

    return exePath;
  }

  Future<void> _finalizeCurrentSession({DateTime? overrideEndTime}) async {
    if (_currentExePath != null && _sessionStartTime != null) {
      final targetEnd = overrideEndTime ?? _lastActiveTime;
      // Ensure target end is not before session start
      final effectiveEnd = targetEnd.isBefore(_sessionStartTime!)
          ? _sessionStartTime!
          : targetEnd;

      if (effectiveEnd.difference(_sessionStartTime!) > const Duration(seconds: 2)) {
        if (_currentSessionId != null) {
          await repository.updateSessionEndTime(_currentSessionId!, effectiveEnd);
        } else {
          final session = AppSession(
            appName: _currentAppName ?? 'Unknown',
            exePath: _currentExePath!,
            startTime: _sessionStartTime!,
            endTime: effectiveEnd,
          );
          await repository.insertSession(session);
        }
      }
    }

    _currentExePath = null;
    _currentAppName = null;
    _sessionStartTime = null;
    _currentSessionId = null;
    _lastCheckpointTime = null;
    _cachedCommittedSessions = null;
  }

  Duration _getIdleTime() {
    final pLii = calloc<LASTINPUTINFO>();
    try {
      pLii.ref.cbSize = sizeOf<LASTINPUTINFO>();

      if (GetLastInputInfo(pLii)) {
        final tickCount = GetTickCount();
        final lastInputTick = pLii.ref.dwTime;
        // Unsigned 32-bit wrap-around safe difference
        final elapsedMs = (tickCount - lastInputTick) & 0xFFFFFFFF;
        return Duration(milliseconds: elapsedMs);
      }
      return Duration.zero;
    } finally {
      free(pLii);
    }
  }

  String _getAppNameFromExe(String exePath) {
    if (discoveryService != null) {
      final friendly = discoveryService!.getFriendlyNameForExe(exePath);
      if (friendly.isNotEmpty && friendly != 'Unknown Application') {
        return friendly;
      }
    }
    final fileName = exePath.split('\\').last;
    if (fileName.toLowerCase().endsWith('.exe')) {
      final name = fileName.substring(0, fileName.length - 4);
      return _capitalize(name);
    }
    return fileName;
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  @override
  void dispose() {
    focusService?.removeListener(_onFocusServiceChanged);
    _timer?.cancel();
    super.dispose();
  }

  /// Retrieves the daily usage summary for a specific calendar date.
  /// If [date] is today, incorporates any active in-progress app session and active focus session.
  /// If [date] is historical, queries recorded sessions and focus sessions from the database.
  Future<DailyUsageSummary> getSummaryForDay(DateTime date) async {
    final now = _now;
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

    List<AppSession> sessions;
    if (isToday && _cachedCommittedSessions != null) {
      sessions = List<AppSession>.from(_cachedCommittedSessions!);
    } else {
      sessions = await repository.getSessionsForDay(date);
      if (isToday) {
        _cachedCommittedSessions = List<AppSession>.from(sessions);
      }
    }

    // If an in-progress session exists and querying today, combine it safely without duplicate counting
    if (isToday && _currentExePath != null && _sessionStartTime != null) {
      final liveSession = AppSession(
        id: _currentSessionId,
        appName: _currentAppName ?? 'Unknown',
        exePath: _currentExePath!,
        startTime: _sessionStartTime!,
        endTime: _lastActiveTime,
      );

      if (_currentSessionId != null) {
        final idx = sessions.indexWhere((s) => s.id == _currentSessionId);
        if (idx >= 0) {
          sessions[idx] = liveSession;
        } else {
          sessions.add(liveSession);
        }
      } else {
        if (_lastActiveTime.isAfter(_sessionStartTime!)) {
          sessions.add(liveSession);
        }
      }
    }

    // Retrieve recorded focus & break sessions for the requested day
    List<FocusSessionRecord> focusSessions;
    if (isToday && _cachedCommittedFocusSessions != null) {
      focusSessions = _cachedCommittedFocusSessions!;
    } else {
      focusSessions = await repository.getFocusSessionsForDay(date);
      if (isToday) {
        _cachedCommittedFocusSessions = focusSessions;
      }
    }

    // Extract active focus/break session state if running or paused (only applies to today)
    ActiveFocusState? activeFocus;
    if (isToday) {
      if (focusService != null && (focusService!.isRunning || focusService!.isPaused)) {
        activeFocus = ActiveFocusState(
          type: focusService!.sessionType,
          status: focusService!.status,
          targetDuration: focusService!.targetDuration,
          startTime: focusService!.startTime ?? now,
          expectedEndTime: focusService!.expectedEndTime ?? now,
          remainingDuration: focusService!.remainingDuration,
        );
      } else {
        activeFocus = await repository.getActiveFocusState();
      }
    }

    final focusMetrics = UsageCalculator.calculateFocusMetrics(
      date: date,
      focusSessions: focusSessions,
      activeState: activeFocus,
      now: isToday ? now : DateTime(date.year, date.month, date.day, 23, 59, 59),
    );

    return UsageCalculator.calculateDailySummary(
      date: date,
      sessions: sessions,
      focusTime: focusMetrics.focusTime,
      breaksTaken: focusMetrics.breaksTaken,
      breakDuration: focusMetrics.breakDuration,
      focusIntervals: focusMetrics.focusIntervals,
      breakIntervals: focusMetrics.breakIntervals,
    );
  }

  Future<void> _refreshSummary() async {
    _todaySummary = await getSummaryForDay(_now);
    notifyListeners();
  }

  /// Visible for deterministic testing without waiting for periodic timers.
  @visibleForTesting
  Future<void> checkForegroundWindow() => _checkForegroundWindow();
}

