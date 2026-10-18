import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/focus_preset.dart';
import '../models/focus_session.dart';
import 'focus_notification_service.dart';
import 'usage_repository.dart';

/// Core controller managing custom presets, Pomodoro cycle engine, timer lifecycle,
/// SQLite persistence, session history, and desktop notifications.
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

  // Preset management
  List<FocusPreset> _presets = [];
  FocusPreset? _selectedPreset;

  // Pomodoro cycle engine state
  int _currentCycle = 1;
  int _totalCycles = 4;
  bool _isLongBreak = false;

  // Active session snapshot (preserves settings for a running/paused session even if preset is edited/deleted)
  int? _activePresetId;
  String? _activePresetName;
  int _activeCyclesBeforeLongBreak = 4;
  bool _activeAutoStartBreaks = false;
  bool _activeAutoStartFocus = false;
  bool _activeAllowSkipBreak = true;
  bool _activeSoundEnabled = true;
  bool _activeUnblockDuringBreaks = true;
  Duration _activeFocusDuration = const Duration(minutes: 25);
  Duration _activeShortBreakDuration = const Duration(minutes: 5);
  Duration _activeLongBreakDuration = const Duration(minutes: 15);

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

  static const Set<String> builtInPresetNames = {
    'standard pomodoro',
    'deep work',
    'quick sprint',
  };

  /// Minimum focus duration threshold (5 seconds). Sessions stopped earlier
  /// are discarded to prevent accidental clutter in history.
  static const Duration minSessionDuration = Duration(seconds: 5);

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

  // Preset getters
  List<FocusPreset> get presets => List.unmodifiable(_presets);
  FocusPreset? get selectedPreset => _selectedPreset;

  // Pomodoro cycle getters
  int get currentCycle => _currentCycle;
  int get totalCycles => _totalCycles;
  bool get isLongBreak => _isLongBreak;

  // Configuration getters reflecting active snapshot during session, or selected preset when idle
  bool get autoStartBreaks => isRunning || isPaused
      ? _activeAutoStartBreaks
      : (_selectedPreset?.autoStartBreaks ?? false);
  bool get autoStartFocus => isRunning || isPaused
      ? _activeAutoStartFocus
      : (_selectedPreset?.autoStartFocus ?? false);
  bool get allowSkipBreak => isRunning || isPaused
      ? _activeAllowSkipBreak
      : (_selectedPreset?.allowSkipBreak ?? true);
  bool get soundEnabled => isRunning || isPaused
      ? _activeSoundEnabled
      : (_selectedPreset?.soundEnabled ?? true);
  bool get unblockDuringBreaks => isRunning || isPaused
      ? _activeUnblockDuringBreaks
      : (_selectedPreset?.unblockDuringBreaks ?? true);

  bool get canSkipBreak => _sessionType == FocusSessionType.breakSession && allowSkipBreak;

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

  final List<({Future<void> Function() op, Completer<void> completer})> _dbOps = [];
  bool _isProcessingDbQueue = false;
  Future<void>? _pendingDbOp;

  /// Exposes the pending database write queue for deterministic test synchronization.
  Future<void> get pendingDbOp => _pendingDbOp ?? Future.value();

  /// Enqueues database operations sequentially to prevent write races.
  Future<void> _enqueueDbOp(Future<void> Function() op) {
    final completer = Completer<void>();
    _dbOps.add((op: op, completer: completer));
    _pendingDbOp = completer.future;
    _processDbQueue();
    return completer.future;
  }

  void _processDbQueue() async {
    if (_isProcessingDbQueue) return;
    _isProcessingDbQueue = true;
    try {
      while (_dbOps.isNotEmpty) {
        final item = _dbOps.removeAt(0);
        if (!_isDisposed) {
          try {
            await item.op();
          } catch (e, stack) {
            debugPrint('FocusService persistence error: $e\n$stack');
          }
        }
        if (!item.completer.isCompleted) {
          item.completer.complete();
        }
      }
    } finally {
      _isProcessingDbQueue = false;
    }
  }

  /// Initializes the service, loads presets, restores active session state if valid,
  /// handles recovery of interrupted sessions without false notifications,
  /// and loads recent session history.
  Future<void> init() async {
    _recentSessions = await repository.getRecentFocusSessions();

    // 1. Load presets from repository
    _presets = await repository.getAllFocusPresets();
    if (_presets.isEmpty) {
      for (final p in FocusPreset.defaultPresets) {
        await repository.insertFocusPreset(p);
      }
      _presets = await repository.getAllFocusPresets();
    }

    _selectedPreset = _presets.cast<FocusPreset?>().firstWhere(
      (p) => p!.isDefault,
      orElse: () => _presets.isNotEmpty ? _presets.first : null,
    );

    if (_selectedPreset != null) {
      _totalCycles = _selectedPreset!.cyclesBeforeLongBreak;
      _targetDuration = _selectedPreset!.focusDuration;
      _remainingDuration = _selectedPreset!.focusDuration;
    }

    // 2. Load active session state from SQLite
    final active = await repository.getActiveFocusState();
    if (active != null) {
      _sessionType = active.type;
      _targetDuration = active.targetDuration;
      _startTime = active.startTime;
      _currentCycle = active.currentCycle;
      _totalCycles = active.totalCycles;
      _isLongBreak = active.isLongBreak;

      // Link preset if recorded in active state
      if (active.presetId != null) {
        _selectedPreset = _presets.cast<FocusPreset?>().firstWhere(
          (p) => p!.id == active.presetId,
          orElse: () => _selectedPreset,
        );
      } else if (active.presetName != null) {
        _selectedPreset = _presets.cast<FocusPreset?>().firstWhere(
          (p) => p!.name.toLowerCase() == active.presetName!.toLowerCase(),
          orElse: () => _selectedPreset,
        );
      }

      // Snapshot active parameters from restored state
      _activePresetId = active.presetId ?? _selectedPreset?.id;
      _activePresetName = active.presetName ?? _selectedPreset?.name;
      _activeCyclesBeforeLongBreak = active.totalCycles;
      _activeAutoStartBreaks = _selectedPreset?.autoStartBreaks ?? false;
      _activeAutoStartFocus = _selectedPreset?.autoStartFocus ?? false;
      _activeAllowSkipBreak = _selectedPreset?.allowSkipBreak ?? true;
      _activeSoundEnabled = _selectedPreset?.soundEnabled ?? true;
      _activeUnblockDuringBreaks = _selectedPreset?.unblockDuringBreaks ?? true;
      _activeFocusDuration = _selectedPreset?.focusDuration ?? (active.type == FocusSessionType.focus ? active.targetDuration : const Duration(minutes: 25));
      _activeShortBreakDuration = _selectedPreset?.shortBreakDuration ?? const Duration(minutes: 5);
      _activeLongBreakDuration = _selectedPreset?.longBreakDuration ?? const Duration(minutes: 15);

      if (active.status == FocusStatus.running) {
        final now = _clock();
        if (now.isAfter(active.expectedEndTime) || now.isAtSameMomentAs(active.expectedEndTime)) {
          // Session expired while Balance was closed or PC was off.
          // This was an INTERRUPTED session. Do NOT claim natural completion,
          // do NOT emit audio/toast notifications, and do NOT credit unearned full duration.
          final rawActual = active.targetDuration - active.remainingDuration;
          final actual = rawActual > active.targetDuration
              ? active.targetDuration
              : (rawActual.isNegative ? Duration.zero : rawActual);

          if (actual >= minSessionDuration) {
            final record = FocusSessionRecord(
              type: active.type,
              plannedDuration: active.targetDuration,
              actualDuration: actual,
              startTime: active.startTime,
              endTime: active.startTime.add(actual),
              completedNaturally: false,
              presetName: _activePresetName,
              cycleIndex: _currentCycle,
              interruptionReason: 'App closed / interrupted',
            );
            await _enqueueDbOp(() async {
              await repository.insertFocusSession(record);
              await repository.clearActiveFocusState();
              _recentSessions = await repository.getRecentFocusSessions();
            });
          } else {
            await _enqueueDbOp(() => repository.clearActiveFocusState());
          }

          _status = FocusStatus.idle;
          _remainingDuration = _targetDuration;
          _startTime = null;
          _expectedEndTime = null;
          _lastCompletedSession = null;
        } else {
          // Session is still running within its target window. Resume ticking.
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

  // --- Preset Management ---

  /// Reloads all presets from repository.
  Future<void> loadPresets() async {
    _presets = await repository.getAllFocusPresets();
    if (_selectedPreset != null) {
      _selectedPreset = _presets.cast<FocusPreset?>().firstWhere(
        (p) => p!.id == _selectedPreset!.id,
        orElse: () => _presets.firstWhereOrNull((p) => p.isDefault) ?? (_presets.isNotEmpty ? _presets.first : null),
      );
    }
    notifyListeners();
  }

  /// Selects an existing focus preset. Throws [StateError] if session is active.
  Future<void> selectPreset(FocusPreset preset) async {
    if (isRunning || isPaused) {
      throw StateError('Cannot change preset during an active session.');
    }
    _selectedPreset = preset;
    _totalCycles = preset.cyclesBeforeLongBreak;

    if (_sessionType == FocusSessionType.focus) {
      _targetDuration = preset.focusDuration;
      _remainingDuration = preset.focusDuration;
    } else {
      if (_isLongBreak) {
        _targetDuration = preset.longBreakDuration;
        _remainingDuration = preset.longBreakDuration;
      } else {
        _targetDuration = preset.shortBreakDuration;
        _remainingDuration = preset.shortBreakDuration;
      }
    }
    _status = FocusStatus.idle;
    notifyListeners();
  }

  /// Creates and persists a new custom preset.
  Future<FocusPreset> createPreset(FocusPreset preset) async {
    _validatePreset(preset);
    final normalizedName = preset.name.trim().toLowerCase();
    if (_presets.any((p) => p.name.trim().toLowerCase() == normalizedName)) {
      throw ArgumentError('A preset with the name "${preset.name.trim()}" already exists.');
    }

    final created = await repository.insertFocusPreset(preset);
    _presets = await repository.getAllFocusPresets();
    notifyListeners();
    return created;
  }

  /// Duplicates an existing preset with a new unique name and persists it.
  Future<FocusPreset> duplicatePreset(FocusPreset preset, {String? newName}) async {
    String candidateName;
    if (newName != null && newName.trim().isNotEmpty) {
      candidateName = newName.trim();
    } else {
      candidateName = '${preset.name} (Copy)';
      int counter = 2;
      while (_presets.any((p) => p.name.trim().toLowerCase() == candidateName.toLowerCase())) {
        candidateName = '${preset.name} (Copy $counter)';
        counter++;
      }
    }

    final duplicate = preset.copyWith(
      clearId: true,
      name: candidateName,
      isDefault: false,
      blockedApps: preset.blockedApps
          .map((a) => a.copyWith(clearId: true, clearPresetId: true))
          .toList(),
      createdAt: _clock(),
      updatedAt: _clock(),
    );
    return await createPreset(duplicate);
  }

  /// Updates an existing preset. Editing a preset does not mutate the running session.
  Future<void> updatePreset(FocusPreset preset) async {
    if (preset.id == null) {
      throw ArgumentError('Preset id cannot be null for update.');
    }
    _validatePreset(preset);
    final normalizedName = preset.name.trim().toLowerCase();
    if (_presets.any((p) => p.id != preset.id && p.name.trim().toLowerCase() == normalizedName)) {
      throw ArgumentError('A preset with the name "${preset.name.trim()}" already exists.');
    }

    await repository.updateFocusPreset(preset);
    _presets = await repository.getAllFocusPresets();

    // If currently selected and idle/completed, update settings and duration
    if (_selectedPreset?.id == preset.id) {
      _selectedPreset = _presets.cast<FocusPreset?>().firstWhere(
        (p) => p!.id == preset.id,
        orElse: () => preset,
      );
      if (_status == FocusStatus.idle || _status == FocusStatus.completed) {
        _totalCycles = preset.cyclesBeforeLongBreak;
        if (_sessionType == FocusSessionType.focus) {
          _targetDuration = preset.focusDuration;
          _remainingDuration = preset.focusDuration;
        } else {
          _targetDuration = _isLongBreak ? preset.longBreakDuration : preset.shortBreakDuration;
          _remainingDuration = _targetDuration;
        }
      }
    }
    notifyListeners();
  }

  /// Deletes a custom preset. Protects built-in system presets from deletion.
  Future<void> deletePreset(int presetId) async {
    final target = _presets.cast<FocusPreset?>().firstWhere(
      (p) => p!.id == presetId,
      orElse: () => null,
    );
    if (target == null) {
      throw ArgumentError('Preset not found.');
    }
    if (builtInPresetNames.contains(target.name.trim().toLowerCase())) {
      throw StateError('Built-in system presets cannot be deleted.');
    }

    await repository.deleteFocusPreset(presetId);
    _presets = await repository.getAllFocusPresets();

    // If deleted preset was selected, fallback to default or first preset
    if (_selectedPreset?.id == presetId) {
      _selectedPreset = _presets.cast<FocusPreset?>().firstWhere(
        (p) => p!.isDefault,
        orElse: () => _presets.isNotEmpty ? _presets.first : null,
      );
      if (_status == FocusStatus.idle || _status == FocusStatus.completed) {
        if (_selectedPreset != null) {
          _totalCycles = _selectedPreset!.cyclesBeforeLongBreak;
          if (_sessionType == FocusSessionType.focus) {
            _targetDuration = _selectedPreset!.focusDuration;
            _remainingDuration = _selectedPreset!.focusDuration;
          } else {
            _targetDuration = _isLongBreak
                ? _selectedPreset!.longBreakDuration
                : _selectedPreset!.shortBreakDuration;
            _remainingDuration = _targetDuration;
          }
        }
      }
    }
    notifyListeners();
  }

  void _validatePreset(FocusPreset preset) {
    if (preset.name.trim().isEmpty) {
      throw ArgumentError('Preset name cannot be empty.');
    }
    if (preset.focusDuration <= Duration.zero) {
      throw ArgumentError('Focus duration must be greater than zero.');
    }
    if (preset.shortBreakDuration <= Duration.zero) {
      throw ArgumentError('Short break duration must be greater than zero.');
    }
    if (preset.longBreakDuration <= Duration.zero) {
      throw ArgumentError('Long break duration must be greater than zero.');
    }
    if (preset.cyclesBeforeLongBreak < 1) {
      throw ArgumentError('Cycles before long break must be at least 1.');
    }
  }

  // --- Session Control ---

  /// Sets session type (Focus or Break). Only permitted when idle or completed.
  Future<void> setSessionType(FocusSessionType type) async {
    if (isRunning || isPaused) return;
    if (_sessionType == type) return;

    _sessionType = type;
    if (type == FocusSessionType.focus) {
      _targetDuration = _selectedPreset?.focusDuration ?? const Duration(minutes: 25);
    } else {
      _targetDuration = _isLongBreak
          ? (_selectedPreset?.longBreakDuration ?? const Duration(minutes: 15))
          : (_selectedPreset?.shortBreakDuration ?? const Duration(minutes: 5));
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

  /// Starts a new focus or break session.
  Future<void> start() async {
    if (isRunning) return;

    if (_status == FocusStatus.completed) {
      if (_sessionType == FocusSessionType.focus) {
        _sessionType = FocusSessionType.breakSession;
        _targetDuration = _isLongBreak ? _activeLongBreakDuration : _activeShortBreakDuration;
      } else {
        _sessionType = FocusSessionType.focus;
        _targetDuration = _activeFocusDuration;
      }
      _remainingDuration = _targetDuration;
    }

    final now = _clock();
    _startTime = now;
    _expectedEndTime = now.add(_targetDuration);
    _remainingDuration = _targetDuration;
    _status = FocusStatus.running;
    _lastCompletedSession = null;

    // Snapshot current preset configuration for the session
    _activePresetId = _selectedPreset?.id;
    _activePresetName = _selectedPreset?.name;
    _activeCyclesBeforeLongBreak = _selectedPreset?.cyclesBeforeLongBreak ?? _totalCycles;
    _activeAutoStartBreaks = _selectedPreset?.autoStartBreaks ?? false;
    _activeAutoStartFocus = _selectedPreset?.autoStartFocus ?? false;
    _activeAllowSkipBreak = _selectedPreset?.allowSkipBreak ?? true;
    _activeSoundEnabled = _selectedPreset?.soundEnabled ?? true;
    _activeUnblockDuringBreaks = _selectedPreset?.unblockDuringBreaks ?? true;
    _activeFocusDuration = _selectedPreset?.focusDuration ?? _targetDuration;
    _activeShortBreakDuration = _selectedPreset?.shortBreakDuration ?? const Duration(minutes: 5);
    _activeLongBreakDuration = _selectedPreset?.longBreakDuration ?? const Duration(minutes: 15);

    _startTicker();
    notifyListeners();

    final activeState = ActiveFocusState(
      type: _sessionType,
      status: _status,
      targetDuration: _targetDuration,
      startTime: _startTime!,
      expectedEndTime: _expectedEndTime!,
      remainingDuration: _remainingDuration,
      presetId: _activePresetId,
      presetName: _activePresetName,
      currentCycle: _currentCycle,
      totalCycles: _activeCyclesBeforeLongBreak,
      isLongBreak: _isLongBreak,
      lastTickTime: now,
    );
    await _enqueueDbOp(() => repository.saveActiveFocusState(activeState));
  }

  /// Starts the next phase when waiting between completed/idle phases.
  Future<void> startNextPhase() async {
    if (isRunning) return;
    await start();
  }

  /// Pauses the running session.
  Future<void> pause() async {
    if (!isRunning) return;

    _ticker?.cancel();
    _ticker = null;

    final now = _clock();
    if (_expectedEndTime != null) {
      final remaining = _expectedEndTime!.difference(now);
      _remainingDuration = remaining.isNegative
          ? Duration.zero
          : (remaining > _targetDuration ? _targetDuration : remaining);
    }

    _status = FocusStatus.paused;
    notifyListeners();

    final activeState = ActiveFocusState(
      type: _sessionType,
      status: _status,
      targetDuration: _targetDuration,
      startTime: _startTime ?? now,
      expectedEndTime: _expectedEndTime ?? now,
      remainingDuration: _remainingDuration,
      presetId: _activePresetId,
      presetName: _activePresetName,
      currentCycle: _currentCycle,
      totalCycles: _activeCyclesBeforeLongBreak,
      isLongBreak: _isLongBreak,
      lastTickTime: now,
    );
    await _enqueueDbOp(() => repository.saveActiveFocusState(activeState));
  }

  /// Resumes a paused session.
  Future<void> resume() async {
    if (!isPaused) return;

    final now = _clock();
    _expectedEndTime = now.add(_remainingDuration);
    _status = FocusStatus.running;

    _startTicker();
    notifyListeners();

    final activeState = ActiveFocusState(
      type: _sessionType,
      status: _status,
      targetDuration: _targetDuration,
      startTime: _startTime ?? now,
      expectedEndTime: _expectedEndTime!,
      remainingDuration: _remainingDuration,
      presetId: _activePresetId,
      presetName: _activePresetName,
      currentCycle: _currentCycle,
      totalCycles: _activeCyclesBeforeLongBreak,
      isLongBreak: _isLongBreak,
      lastTickTime: now,
    );
    await _enqueueDbOp(() => repository.saveActiveFocusState(activeState));
  }

  /// Stops an active session early.
  ///
  /// Correctly excludes all paused time from actual focus duration. Discards
  /// accidental near-zero-duration sessions (< 5s) to prevent cluttering history.
  Future<void> stop() async {
    if (_isFinalizing) return;
    if (_status == FocusStatus.idle) return;

    _ticker?.cancel();
    _ticker = null;
    _isFinalizing = true;

    final now = _clock();
    if (isRunning && _expectedEndTime != null) {
      final remaining = _expectedEndTime!.difference(now);
      _remainingDuration = remaining.isNegative
          ? Duration.zero
          : (remaining > _targetDuration ? _targetDuration : remaining);
    }

    // Active time strictly excludes paused intervals:
    final rawActual = _targetDuration - _remainingDuration;
    final actual = rawActual > _targetDuration
        ? _targetDuration
        : (rawActual.isNegative ? Duration.zero : rawActual);

    final sessionStartTime = _startTime ?? now.subtract(actual);
    final sessionEndTime = now;
    final currentType = _sessionType;
    final planned = _targetDuration;
    final pName = _activePresetName;
    final cIndex = _currentCycle;

    // Immediately update in-memory state so UI updates without waiting for DB I/O
    _status = FocusStatus.idle;
    _remainingDuration = _targetDuration;
    _startTime = null;
    _expectedEndTime = null;
    _lastCompletedSession = null;
    notifyListeners();

    await _enqueueDbOp(() async {
      try {
        if (actual >= minSessionDuration) {
          final record = FocusSessionRecord(
            type: currentType,
            plannedDuration: planned,
            actualDuration: actual,
            startTime: sessionStartTime,
            endTime: sessionEndTime,
            completedNaturally: false,
            presetName: pName,
            cycleIndex: cIndex,
            interruptionReason: currentType == FocusSessionType.focus
                ? 'Focus stopped early'
                : 'Break ended early',
          );
          await repository.insertFocusSession(record);
        }
        await repository.clearActiveFocusState();
        _recentSessions = await repository.getRecentFocusSessions();
      } finally {
        _isFinalizing = false;
        notifyListeners();
      }
    });
  }

  /// Skips the current break and advances directly to the next focus cycle.
  Future<void> skipBreak() async {
    if (_sessionType != FocusSessionType.breakSession) {
      throw StateError('Can only skip during a break session.');
    }
    if (!allowSkipBreak) {
      throw StateError('Skipping break is disabled for this preset.');
    }

    _ticker?.cancel();
    _ticker = null;

    final now = _clock();
    // If break was running or paused and lasted at least minSessionDuration, record it
    if (_status == FocusStatus.running || _status == FocusStatus.paused) {
      final rawActual = _targetDuration - _remainingDuration;
      final actual = rawActual > _targetDuration
          ? _targetDuration
          : (rawActual.isNegative ? Duration.zero : rawActual);
      if (actual >= minSessionDuration) {
        final record = FocusSessionRecord(
          type: FocusSessionType.breakSession,
          plannedDuration: _targetDuration,
          actualDuration: actual,
          startTime: _startTime ?? now.subtract(actual),
          endTime: now,
          completedNaturally: false,
          presetName: _activePresetName,
          cycleIndex: _currentCycle,
          interruptionReason: 'Break skipped by user',
        );
        await _enqueueDbOp(() => repository.insertFocusSession(record));
      }
    }

    // Advance Pomodoro cycle
    if (_isLongBreak) {
      _currentCycle = 1;
      _isLongBreak = false;
    } else {
      _currentCycle += 1;
    }

    _sessionType = FocusSessionType.focus;
    _targetDuration = _activeFocusDuration;
    _remainingDuration = _activeFocusDuration;
    _status = FocusStatus.idle;
    _startTime = null;
    _expectedEndTime = null;
    _lastCompletedSession = null;
    notifyListeners();

    await _enqueueDbOp(() async {
      await repository.clearActiveFocusState();
      _recentSessions = await repository.getRecentFocusSessions();
    });
  }

  /// Resets state back to ready/idle for the current duration and type.
  Future<void> reset() async {
    _ticker?.cancel();
    _ticker = null;
    _status = FocusStatus.idle;
    _remainingDuration = _targetDuration;
    _startTime = null;
    _expectedEndTime = null;
    _lastCompletedSession = null;
    notifyListeners();
    await _enqueueDbOp(() => repository.clearActiveFocusState());
  }

  /// Resets cycle counter back to 1 and returns to the initial focus phase.
  Future<void> resetCycle() async {
    if (isRunning || isPaused) {
      await stop();
    }
    _currentCycle = 1;
    _isLongBreak = false;
    _sessionType = FocusSessionType.focus;
    _targetDuration = _selectedPreset?.focusDuration ?? const Duration(minutes: 25);
    _remainingDuration = _targetDuration;
    _status = FocusStatus.idle;
    _startTime = null;
    _expectedEndTime = null;
    _lastCompletedSession = null;
    notifyListeners();
    await _enqueueDbOp(() => repository.clearActiveFocusState());
  }

  /// Restarts the current phase from the beginning without advancing the cycle.
  Future<void> restartCurrentPhase() async {
    _ticker?.cancel();
    _ticker = null;
    _remainingDuration = _targetDuration;
    _status = FocusStatus.idle;
    _startTime = null;
    _expectedEndTime = null;
    notifyListeners();
    await start();
  }

  /// Gracefully flushes and persists state during application shutdown.
  Future<void> handleAppShutdown() async {
    if (_status == FocusStatus.running) {
      await pause();
    }
    await pendingDbOp;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _tick();
    });
  }

  /// Persists current active timer state to SQLite immediately.
  Future<void> syncActiveState() async {
    if (_status == FocusStatus.idle) return;
    final now = _clock();
    final activeState = ActiveFocusState(
      type: _sessionType,
      status: _status,
      targetDuration: _targetDuration,
      startTime: _startTime ?? now,
      expectedEndTime: _expectedEndTime ?? now,
      remainingDuration: _remainingDuration,
      presetId: _activePresetId,
      presetName: _activePresetName,
      currentCycle: _currentCycle,
      totalCycles: _activeCyclesBeforeLongBreak,
      isLongBreak: _isLongBreak,
      lastTickTime: now,
    );
    await _enqueueDbOp(() => repository.saveActiveFocusState(activeState));
  }

  /// Manually triggers a clock tick. Visible for deterministic testing.
  @visibleForTesting
  void tick() => _tick();

  int _tickCount = 0;

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
      _tickCount++;
      if (_tickCount % 15 == 0) {
        syncActiveState();
      }
      notifyListeners();
    }
  }

  Future<void> _handleNaturalCompletion({
    required DateTime activeStartTime,
    required DateTime activeEndTime,
  }) async {
    if (_isFinalizing) return;
    _isFinalizing = true;

    final currentType = _sessionType;
    final planned = _targetDuration;
    final pName = _activePresetName;
    final cIndex = _currentCycle;
    final sound = _activeSoundEnabled;

    final record = FocusSessionRecord(
      type: currentType,
      plannedDuration: planned,
      actualDuration: planned,
      startTime: activeStartTime,
      endTime: activeEndTime,
      completedNaturally: true,
      presetName: pName,
      cycleIndex: cIndex,
    );

    _lastCompletedSession = record;
    _status = FocusStatus.completed;
    _remainingDuration = Duration.zero;

    // Advance Pomodoro phases
    bool shouldAutoStartNext = false;
    if (currentType == FocusSessionType.focus) {
      // Focus completed -> Prepare break
      if (_currentCycle >= _activeCyclesBeforeLongBreak) {
        _isLongBreak = true;
        _targetDuration = _activeLongBreakDuration;
      } else {
        _isLongBreak = false;
        _targetDuration = _activeShortBreakDuration;
      }
      shouldAutoStartNext = _activeAutoStartBreaks;
      if (shouldAutoStartNext) {
        _sessionType = FocusSessionType.breakSession;
        _remainingDuration = _targetDuration;
      }
    } else {
      // Break completed -> Prepare next focus cycle
      if (_isLongBreak) {
        _currentCycle = 1;
        _isLongBreak = false;
      } else {
        _currentCycle += 1;
      }
      _targetDuration = _activeFocusDuration;
      shouldAutoStartNext = _activeAutoStartFocus;
      if (shouldAutoStartNext) {
        _sessionType = FocusSessionType.focus;
        _remainingDuration = _targetDuration;
      }
    }

    notifyListeners();

    await _enqueueDbOp(() async {
      try {
        await repository.insertFocusSession(record);
        if (sound) {
          notificationService?.notifySessionCompleted(
            type: currentType,
            completedNaturally: true,
            soundEnabled: sound,
          );
        }
        _recentSessions = await repository.getRecentFocusSessions();

        if (shouldAutoStartNext) {
          final now = activeEndTime;
          _startTime = now;
          _expectedEndTime = now.add(_targetDuration);
          _status = FocusStatus.running;
          _startTicker();

          final nextActiveState = ActiveFocusState(
            type: _sessionType,
            status: _status,
            targetDuration: _targetDuration,
            startTime: _startTime!,
            expectedEndTime: _expectedEndTime!,
            remainingDuration: _remainingDuration,
            presetId: _activePresetId,
            presetName: _activePresetName,
            currentCycle: _currentCycle,
            totalCycles: _activeCyclesBeforeLongBreak,
            isLongBreak: _isLongBreak,
            lastTickTime: now,
          );
          await repository.saveActiveFocusState(nextActiveState);
        } else {
          await repository.clearActiveFocusState();
        }
      } finally {
        _isFinalizing = false;
        notifyListeners();
      }
    });
  }

  /// Development-only method to safely test desktop notifications.
  Future<bool> triggerTestNotification({FocusSessionType? type}) async {
    assert(kDebugMode, 'triggerTestNotification must only be invoked in debug/development mode');
    if (!kDebugMode) return false;

    if (notificationService == null) return false;
    return await notificationService!.notifySessionCompleted(
      type: type ?? _sessionType,
      completedNaturally: true,
      soundEnabled: soundEnabled,
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

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
