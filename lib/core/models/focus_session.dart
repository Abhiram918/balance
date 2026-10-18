enum FocusSessionType {
  focus,
  breakSession;

  String get label {
    switch (this) {
      case FocusSessionType.focus:
        return 'Focus';
      case FocusSessionType.breakSession:
        return 'Break';
    }
  }

  static FocusSessionType fromString(String value) {
    if (value.toLowerCase() == 'break' || value.toLowerCase() == 'breaksession') {
      return FocusSessionType.breakSession;
    }
    return FocusSessionType.focus;
  }
}

enum FocusStatus {
  idle,
  running,
  paused,
  completed;

  static FocusStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'running':
        return FocusStatus.running;
      case 'paused':
        return FocusStatus.paused;
      case 'completed':
        return FocusStatus.completed;
      case 'idle':
      default:
        return FocusStatus.idle;
    }
  }
}

/// Represents a completed or terminated focus session stored in history.
class FocusSessionRecord {
  final int? id;
  final FocusSessionType type;
  final Duration plannedDuration;
  final Duration actualDuration;
  final DateTime startTime;
  final DateTime endTime;
  final bool completedNaturally;
  final String? presetName;
  final int? cycleIndex;
  final String? interruptionReason;

  FocusSessionRecord({
    this.id,
    required this.type,
    required this.plannedDuration,
    required this.actualDuration,
    required this.startTime,
    required this.endTime,
    required this.completedNaturally,
    this.presetName,
    this.cycleIndex,
    this.interruptionReason,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type.name,
      'plannedSeconds': plannedDuration.inSeconds,
      'actualSeconds': actualDuration.inSeconds,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'completedNaturally': completedNaturally ? 1 : 0,
      if (presetName != null) 'presetName': presetName,
      if (cycleIndex != null) 'cycleIndex': cycleIndex,
      if (interruptionReason != null) 'interruptionReason': interruptionReason,
    };
  }

  factory FocusSessionRecord.fromMap(Map<String, dynamic> map) {
    return FocusSessionRecord(
      id: map['id'] as int?,
      type: FocusSessionType.fromString(map['type'] as String? ?? 'focus'),
      plannedDuration: Duration(seconds: map['plannedSeconds'] as int? ?? 0),
      actualDuration: Duration(seconds: map['actualSeconds'] as int? ?? 0),
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int? ?? 0),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int? ?? 0),
      completedNaturally: (map['completedNaturally'] as int? ?? 0) == 1,
      presetName: map['presetName'] as String?,
      cycleIndex: map['cycleIndex'] as int?,
      interruptionReason: map['interruptionReason'] as String?,
    );
  }

  FocusSessionRecord copyWith({
    int? id,
    FocusSessionType? type,
    Duration? plannedDuration,
    Duration? actualDuration,
    DateTime? startTime,
    DateTime? endTime,
    bool? completedNaturally,
    String? presetName,
    int? cycleIndex,
    String? interruptionReason,
  }) {
    return FocusSessionRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      plannedDuration: plannedDuration ?? this.plannedDuration,
      actualDuration: actualDuration ?? this.actualDuration,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      completedNaturally: completedNaturally ?? this.completedNaturally,
      presetName: presetName ?? this.presetName,
      cycleIndex: cycleIndex ?? this.cycleIndex,
      interruptionReason: interruptionReason ?? this.interruptionReason,
    );
  }
}

/// Active focus session state persisted in SQLite so the timer can survive app restarts and crashes.
class ActiveFocusState {
  final FocusSessionType type;
  final FocusStatus status;
  final Duration targetDuration;
  final DateTime startTime;
  final DateTime expectedEndTime;
  final Duration remainingDuration;
  final int? presetId;
  final String? presetName;
  final int currentCycle;
  final int totalCycles;
  final bool isLongBreak;
  final DateTime? lastTickTime;

  ActiveFocusState({
    required this.type,
    required this.status,
    required this.targetDuration,
    required this.startTime,
    required this.expectedEndTime,
    required this.remainingDuration,
    this.presetId,
    this.presetName,
    this.currentCycle = 1,
    this.totalCycles = 4,
    this.isLongBreak = false,
    this.lastTickTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'status': status.name,
      'targetSeconds': targetDuration.inSeconds,
      'startTime': startTime.millisecondsSinceEpoch,
      'expectedEndTime': expectedEndTime.millisecondsSinceEpoch,
      'remainingSeconds': remainingDuration.inSeconds,
      if (presetId != null) 'presetId': presetId,
      if (presetName != null) 'presetName': presetName,
      'currentCycle': currentCycle,
      'totalCycles': totalCycles,
      'isLongBreak': isLongBreak ? 1 : 0,
      if (lastTickTime != null) 'lastTickTime': lastTickTime!.millisecondsSinceEpoch,
    };
  }

  factory ActiveFocusState.fromMap(Map<String, dynamic> map) {
    return ActiveFocusState(
      type: FocusSessionType.fromString(map['type'] as String? ?? 'focus'),
      status: FocusStatus.fromString(map['status'] as String? ?? 'idle'),
      targetDuration: Duration(seconds: map['targetSeconds'] as int? ?? 0),
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int? ?? 0),
      expectedEndTime: DateTime.fromMillisecondsSinceEpoch(map['expectedEndTime'] as int? ?? 0),
      remainingDuration: Duration(seconds: map['remainingSeconds'] as int? ?? 0),
      presetId: map['presetId'] as int?,
      presetName: map['presetName'] as String?,
      currentCycle: map['currentCycle'] as int? ?? 1,
      totalCycles: map['totalCycles'] as int? ?? 4,
      isLongBreak: (map['isLongBreak'] as int? ?? 0) == 1,
      lastTickTime: map['lastTickTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastTickTime'] as int)
          : null,
    );
  }

  ActiveFocusState copyWith({
    FocusSessionType? type,
    FocusStatus? status,
    Duration? targetDuration,
    DateTime? startTime,
    DateTime? expectedEndTime,
    Duration? remainingDuration,
    int? presetId,
    String? presetName,
    int? currentCycle,
    int? totalCycles,
    bool? isLongBreak,
    DateTime? lastTickTime,
  }) {
    return ActiveFocusState(
      type: type ?? this.type,
      status: status ?? this.status,
      targetDuration: targetDuration ?? this.targetDuration,
      startTime: startTime ?? this.startTime,
      expectedEndTime: expectedEndTime ?? this.expectedEndTime,
      remainingDuration: remainingDuration ?? this.remainingDuration,
      presetId: presetId ?? this.presetId,
      presetName: presetName ?? this.presetName,
      currentCycle: currentCycle ?? this.currentCycle,
      totalCycles: totalCycles ?? this.totalCycles,
      isLongBreak: isLongBreak ?? this.isLongBreak,
      lastTickTime: lastTickTime ?? this.lastTickTime,
    );
  }
}
