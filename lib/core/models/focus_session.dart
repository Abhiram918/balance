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

  FocusSessionRecord({
    this.id,
    required this.type,
    required this.plannedDuration,
    required this.actualDuration,
    required this.startTime,
    required this.endTime,
    required this.completedNaturally,
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

  ActiveFocusState({
    required this.type,
    required this.status,
    required this.targetDuration,
    required this.startTime,
    required this.expectedEndTime,
    required this.remainingDuration,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'status': status.name,
      'targetSeconds': targetDuration.inSeconds,
      'startTime': startTime.millisecondsSinceEpoch,
      'expectedEndTime': expectedEndTime.millisecondsSinceEpoch,
      'remainingSeconds': remainingDuration.inSeconds,
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
    );
  }
}
