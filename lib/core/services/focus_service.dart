import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/focus_session.dart';
import 'focus_notification_service.dart';
import 'usage_repository.dart';

/// Core controller managing focus and break timer lifecycle, SQLite persistence,
/// session history, and desktop notifications.
class FocusService extends ChangeNotifier {
  final UsageRepository repository;
  final FocusNotificationService? notificationService;
  DateTime Function() _clock;

  FocusSessionType _sessionType = FocusSessionType.focus;
  FocusStatus _status = FocusStatus.idle;
  Duration _targetDuration = const Duration(minutes: 25);
  Duration _remainingDuration = const Duration(minutes: 25);
  DateTime? _startTime;
  DateTime? _expectedEndTime;

  Timer? _ticker;
  bool _isFinalizing = false;
  List<FocusSessionRecord> _recentSessions = [];
  FocusSessionRecord? _lastCompletedSession;

  static const List<Duration> focusPresets = [
    Duration(minutes: 15),
    Duration(minutes: 25),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  static const List<Duration> breakPresets = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
  ];

  FocusService({
    required this.repository,
    this.notificationService,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  // For deterministic testing
  void setClock(DateTime Function() clock) {
    _clock = clock;
  }

  // Getters
  FocusSessionType get sessionType => _sessionType;
  FocusStatus get status => _status;
  Duration get targetDuration => _targetDuration;
  Duration get remainingDuration => _remainingDuration;
  DateTime? get startTime => _startTime;
  DateTime? get expectedEndTime => _expectedEndTime;
  List<FocusSessionRecord> get recentSessions => List.unmodifiable(_recentSessions);
  FocusSessionRecord? get lastCompletedSession => _lastCompletedSession;

  bool get isRunning => _status == FocusStatus.running;
  bool get isPaused => _status == FocusStatus.paused;
  bool get isCompleted => _status == FocusStatus.completed;
  bool get isIdle => _status == FocusStatus.idle;

  /// Progress from 0.0 (just started) to 1.0 (completed)
  double get progress {
    if (_targetDuration.inSeconds <= 0) return 0.0;
    final elapsed = _targetDuration.inSeconds - _remainingDuration.inSeconds;
    return (elapsed / _targetDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Progress remaining from 1.0 down to 0.0
  double get progressRemaining {
    if (_targetDuration.inSeconds <= 0) return 1.0;
    return (_remainingDuration.inSeconds / _targetDuration.inSeconds).clamp(0.0, 1.0);
  }

  /// Initializes the service, restores any active session from SQLite,
  /// and loads recent session history.
  Future<void> init() async {
    _recentSessions = await repository.getRecentFocusSessions();

    final active = await repository.getActiveFocusState();
    if (active != null) {
      _sessionType = active.type;
      _targetDuration = active.targetDuration;
      _startTime = active.startTime;

      if (active.status == FocusStatus.running) {
        final now = _clock();
        if (now.isAfter(active.expectedEndTime) || now.isAtSameMomentAs(active.expectedEndTime)) {
          // Session expired while the app was closed
          _expectedEndTime = active.expectedEndTime;
          _remainingDuration = Duration.zero;
          await _handleNaturalCompletion(activeStartTime: active.startTime, activeEndTime: active.expectedEndTime);
        } else {
          // Session is still running
          _status = FocusStatus.running;
          _expectedEndTime = active.expectedEndTime;
          _remainingDuration = active.expectedEndTime.difference(now);
          _startTicker();
        }
      } else if (active.status == FocusStatus.paused) {
        _status = FocusStatus.paused;
        _expectedEndTime = active.expectedEndTime;
        _remainingDuration = active.remainingDuration;
      }
    } else {
      _remainingDuration = _targetDuration;
    }

    notifyListeners();
  }

  /// Sets session type (Focus or Break). Only permitted when idle or completed.
  Future<void> setSessionType(FocusSessionType type) async {
    if (isRunning || isPaused) return;
    if (_sessionType == type) return;

    _sessionType = type;
    if (type == FocusSessionType.focus) {
      if (!focusPresets.contains(_targetDuration)) {
        _targetDuration = const Duration(minutes: 25);
      }
    } else {
      if (!breakPresets.contains(_targetDuration)) {
        _targetDuration = const Duration(minutes: 5);
      }
    }
    _remainingDuration = _targetDuration;
    _status = FocusStatus.idle;
    notifyListeners();
  }

  /// Sets the planned duration. Only permitted when idle or completed.
  void setTargetDuration(Duration duration) {
    if (isRunning || isPaused) return;
    _targetDuration = duration;
    _remainingDuration = duration;
    _status = FocusStatus.idle;
    notifyListeners();
  }

  Future<void>? _pendingDbOp;
  Future<void> get pendingDbOp => _pendingDbOp ?? Future.value();

  /// Starts a new focus or break session.
  Future<void> start() async {
    if (isRunning) return;

    final now = _clock();
    _startTime = now;
    _expectedEndTime = now.add(_targetDuration);
    _remainingDuration = _targetDuration;
    _status = FocusStatus.running;
    _lastCompletedSession = null;

    _startTicker();
    notifyListeners();

    _pendingDbOp = repository.saveActiveFocusState(ActiveFocusState(
      type: _sessionType,
      status: _status,
      targetDuration: _targetDuration,
      startTime: _startTime!,
      expectedEndTime: _expectedEndTime!,
      remainingDuration: _remainingDuration,
    ));
    await _pendingDbOp;
  }

  /// Pauses the running session.
  Future<void> pause() async {
    if (!isRunning) return;

    _ticker?.cancel();
    _ticker = null;

    final now = _clock();
    if (_expectedEndTime != null) {
      _remainingDuration = _expectedEndTime!.difference(now);
      if (_remainingDuration.isNegative) {
        _remainingDuration = Duration.zero;
      }
    }

    _status = FocusStatus.paused;
    notifyListeners();

    _pendingDbOp = repository.saveActiveFocusState(ActiveFocusState(
      type: _sessionType,
      status: _status,
      targetDuration: _targetDuration,
      startTime: _startTime ?? now,
      expectedEndTime: _expectedEndTime ?? now,
      remainingDuration: _remainingDuration,
    ));
    await _pendingDbOp;
  }

  /// Resumes a paused session.
  Future<void> resume() async {
    if (!isPaused) return;

    final now = _clock();
    _expectedEndTime = now.add(_remainingDuration);
    _status = FocusStatus.running;

    _startTicker();
    notifyListeners();

    _pendingDbOp = repository.saveActiveFocusState(ActiveFocusState(
      type: _sessionType,
      status: _status,
      targetDuration: _targetDuration,
      startTime: _startTime ?? now,
      expectedEndTime: _expectedEndTime!,
      remainingDuration: _remainingDuration,
    ));
    await _pendingDbOp;
  }

  /// Stops an active session early.
  Future<void> stop() async {
    if (_isFinalizing) return;
    if (_status == FocusStatus.idle) return;

    _ticker?.cancel();
    _ticker = null;
    _isFinalizing = true;

    final now = _clock();
    final Duration actual;
    if (_startTime != null) {
      final elapsed = now.difference(_startTime!);
      actual = elapsed > _targetDuration ? _targetDuration : (elapsed.isNegative ? Duration.zero : elapsed);
    } else {
      actual = _targetDuration - _remainingDuration;
    }

    final record = FocusSessionRecord(
      type: _sessionType,
      plannedDuration: _targetDuration,
      actualDuration: actual,
      startTime: _startTime ?? now,
      endTime: now,
      completedNaturally: false,
    );

    // Immediately update in-memory state so UI updates without waiting for DB I/O
    _status = FocusStatus.idle;
    _remainingDuration = _targetDuration;
    _startTime = null;
    _expectedEndTime = null;
    _lastCompletedSession = null;
    notifyListeners();

    _pendingDbOp = () async {
      try {
        await repository.insertFocusSession(record);
        await repository.clearActiveFocusState();
        _recentSessions = await repository.getRecentFocusSessions();
        notifyListeners();
      } finally {
        _isFinalizing = false;
      }
    }();
    await _pendingDbOp;
  }

  /// Resets state back to ready/idle for the current duration and type.
  Future<void> reset() async {
    _ticker?.cancel();
    _ticker = null;
    await repository.clearActiveFocusState();
    _status = FocusStatus.idle;
    _remainingDuration = _targetDuration;
    _startTime = null;
    _expectedEndTime = null;
    _lastCompletedSession = null;
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  /// Periodic tick handler using wall-clock time difference to prevent drift.
  void _tick() {
    if (_status != FocusStatus.running || _expectedEndTime == null) return;

    final now = _clock();
    final remaining = _expectedEndTime!.difference(now);

    if (remaining <= Duration.zero) {
      _remainingDuration = Duration.zero;
      _ticker?.cancel();
      _ticker = null;
      _handleNaturalCompletion(
        activeStartTime: _startTime ?? now.subtract(_targetDuration),
        activeEndTime: _expectedEndTime ?? now,
      );
    } else {
      _remainingDuration = remaining;
      notifyListeners();
    }
  }

  Future<void> _handleNaturalCompletion({
    required DateTime activeStartTime,
    required DateTime activeEndTime,
  }) async {
    if (_isFinalizing) return;
    _isFinalizing = true;

    try {
      final record = FocusSessionRecord(
        type: _sessionType,
        plannedDuration: _targetDuration,
        actualDuration: _targetDuration,
        startTime: activeStartTime,
        endTime: activeEndTime,
        completedNaturally: true,
      );

      await repository.insertFocusSession(record);
      await repository.clearActiveFocusState();

      _lastCompletedSession = record;
      _recentSessions = await repository.getRecentFocusSessions();
      _status = FocusStatus.completed;
      _remainingDuration = Duration.zero;

      // Trigger Windows desktop & audio notification
      notificationService?.notifySessionCompleted(
        type: _sessionType,
        completedNaturally: true,
      );
    } finally {
      _isFinalizing = false;
    }

    notifyListeners();
  }

  /// Development-only method to safely test desktop notifications.
  ///
  /// Invokes the exact notification pipeline used upon natural session completion
  /// without modifying active timer state, completing real sessions, or adding
  /// fake history entries to SQLite.
  Future<bool> triggerTestNotification({FocusSessionType? type}) async {
    assert(kDebugMode, 'triggerTestNotification must only be invoked in debug/development mode');
    if (!kDebugMode) return false;

    if (notificationService == null) return false;
    return await notificationService!.notifySessionCompleted(
      type: type ?? _sessionType,
      completedNaturally: true,
    );
  }

  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}
