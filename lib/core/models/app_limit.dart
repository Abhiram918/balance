/// Model representing a daily usage limit configured for an application.
class AppLimit {
  final int? id;
  final String appName;
  final String? exePath;
  final Duration limitDuration;
  final int warningThresholdPercentage;
  final bool isEnabled;
  final bool isEnforced;
  final DateTime createdAt;
  final DateTime updatedAt;

  AppLimit({
    this.id,
    required this.appName,
    this.exePath,
    required this.limitDuration,
    this.warningThresholdPercentage = 80,
    this.isEnabled = true,
    this.isEnforced = false,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(!limitDuration.isNegative, 'Limit duration cannot be negative'),
       assert(
         warningThresholdPercentage >= 10 && warningThresholdPercentage <= 100,
         'Warning threshold must be between 10% and 100%',
       );

  int get limitMinutes => limitDuration.inMinutes;

  /// Duration at which the warning notification should trigger.
  Duration get warningDuration {
    final warningMicros = (limitDuration.inMicroseconds * (warningThresholdPercentage / 100.0)).round();
    return Duration(microseconds: warningMicros);
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'appName': appName,
      'exePath': exePath,
      'limitMinutes': limitMinutes,
      'warningPercentage': warningThresholdPercentage,
      'isEnabled': isEnabled ? 1 : 0,
      'isEnforced': isEnforced ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory AppLimit.fromMap(Map<String, dynamic> map) {
    return AppLimit(
      id: map['id'] as int?,
      appName: map['appName'] as String,
      exePath: map['exePath'] as String?,
      limitDuration: Duration(minutes: map['limitMinutes'] as int),
      warningThresholdPercentage: (map['warningPercentage'] as int?) ?? 80,
      isEnabled: (map['isEnabled'] as int) == 1,
      isEnforced: ((map['isEnforced'] as int?) ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int),
    );
  }

  AppLimit copyWith({
    int? id,
    String? appName,
    String? exePath,
    Duration? limitDuration,
    int? warningThresholdPercentage,
    bool? isEnabled,
    bool? isEnforced,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppLimit(
      id: id ?? this.id,
      appName: appName ?? this.appName,
      exePath: exePath ?? this.exePath,
      limitDuration: limitDuration ?? this.limitDuration,
      warningThresholdPercentage: warningThresholdPercentage ?? this.warningThresholdPercentage,
      isEnabled: isEnabled ?? this.isEnabled,
      isEnforced: isEnforced ?? this.isEnforced,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppLimit &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          appName == other.appName &&
          limitDuration == other.limitDuration &&
          warningThresholdPercentage == other.warningThresholdPercentage &&
          isEnabled == other.isEnabled &&
          isEnforced == other.isEnforced;

  @override
  int get hashCode =>
      id.hashCode ^
      appName.hashCode ^
      limitDuration.hashCode ^
      warningThresholdPercentage.hashCode ^
      isEnabled.hashCode ^
      isEnforced.hashCode;
}
