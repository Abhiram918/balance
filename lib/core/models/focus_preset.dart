import 'package:flutter/foundation.dart';

/// Represents an application targeted for distraction blocking during a focus preset.
@immutable
class FocusPresetBlockedApp {
  final int? id;
  final int? presetId;
  final String appName;
  final String? exePath;

  const FocusPresetBlockedApp({
    this.id,
    this.presetId,
    required this.appName,
    this.exePath,
  });

  Map<String, dynamic> toMap({int? overridePresetId}) {
    return {
      if (id != null) 'id': id,
      'presetId': overridePresetId ?? presetId,
      'appName': appName.trim(),
      'exePath': exePath?.trim(),
    };
  }

  factory FocusPresetBlockedApp.fromMap(Map<String, dynamic> map) {
    return FocusPresetBlockedApp(
      id: map['id'] as int?,
      presetId: map['presetId'] as int?,
      appName: map['appName'] as String? ?? '',
      exePath: map['exePath'] as String?,
    );
  }

  FocusPresetBlockedApp copyWith({
    int? id,
    bool clearId = false,
    int? presetId,
    bool clearPresetId = false,
    String? appName,
    String? exePath,
  }) {
    return FocusPresetBlockedApp(
      id: clearId ? null : (id ?? this.id),
      presetId: clearPresetId ? null : (presetId ?? this.presetId),
      appName: appName ?? this.appName,
      exePath: exePath ?? this.exePath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusPresetBlockedApp &&
          runtimeType == other.runtimeType &&
          appName.trim().toLowerCase() == other.appName.trim().toLowerCase();

  @override
  int get hashCode => appName.trim().toLowerCase().hashCode;

  @override
  String toString() => 'FocusPresetBlockedApp(name: $appName, exe: $exePath)';
}

/// Reusable focus and Pomodoro preset configuration.
@immutable
class FocusPreset {
  final int? id;
  final String name;
  final Duration focusDuration;
  final Duration shortBreakDuration;
  final Duration longBreakDuration;
  final int cyclesBeforeLongBreak;
  final bool autoStartBreaks;
  final bool autoStartFocus;
  final bool allowSkipBreak;
  final bool soundEnabled;
  final bool unblockDuringBreaks;
  final bool isDefault;
  final List<FocusPresetBlockedApp> blockedApps;
  final DateTime createdAt;
  final DateTime updatedAt;

  FocusPreset({
    this.id,
    required this.name,
    required this.focusDuration,
    required this.shortBreakDuration,
    required this.longBreakDuration,
    this.cyclesBeforeLongBreak = 4,
    this.autoStartBreaks = false,
    this.autoStartFocus = false,
    this.allowSkipBreak = true,
    this.soundEnabled = true,
    this.unblockDuringBreaks = true,
    this.isDefault = false,
    List<FocusPresetBlockedApp>? blockedApps,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : blockedApps = List.unmodifiable(blockedApps ?? const []),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now() {
    _validate();
  }

  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError('Preset name cannot be empty.');
    }
    if (focusDuration <= Duration.zero) {
      throw ArgumentError('Focus duration must be greater than zero.');
    }
    if (shortBreakDuration <= Duration.zero) {
      throw ArgumentError('Short break duration must be greater than zero.');
    }
    if (longBreakDuration <= Duration.zero) {
      throw ArgumentError('Long break duration must be greater than zero.');
    }
    if (cyclesBeforeLongBreak < 1) {
      throw ArgumentError('Cycles before long break must be at least 1.');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name.trim(),
      'focusDurationSeconds': focusDuration.inSeconds,
      'shortBreakDurationSeconds': shortBreakDuration.inSeconds,
      'longBreakDurationSeconds': longBreakDuration.inSeconds,
      'cyclesBeforeLongBreak': cyclesBeforeLongBreak,
      'autoStartBreaks': autoStartBreaks ? 1 : 0,
      'autoStartFocus': autoStartFocus ? 1 : 0,
      'allowSkipBreak': allowSkipBreak ? 1 : 0,
      'soundEnabled': soundEnabled ? 1 : 0,
      'unblockDuringBreaks': unblockDuringBreaks ? 1 : 0,
      'isDefault': isDefault ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory FocusPreset.fromMap(
    Map<String, dynamic> map, {
    List<FocusPresetBlockedApp>? blockedApps,
  }) {
    return FocusPreset(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      focusDuration: Duration(seconds: map['focusDurationSeconds'] as int? ?? 1500),
      shortBreakDuration: Duration(seconds: map['shortBreakDurationSeconds'] as int? ?? 300),
      longBreakDuration: Duration(seconds: map['longBreakDurationSeconds'] as int? ?? 900),
      cyclesBeforeLongBreak: map['cyclesBeforeLongBreak'] as int? ?? 4,
      autoStartBreaks: (map['autoStartBreaks'] as int? ?? 0) == 1,
      autoStartFocus: (map['autoStartFocus'] as int? ?? 0) == 1,
      allowSkipBreak: (map['allowSkipBreak'] as int? ?? 1) == 1,
      soundEnabled: (map['soundEnabled'] as int? ?? 1) == 1,
      unblockDuringBreaks: (map['unblockDuringBreaks'] as int? ?? 1) == 1,
      isDefault: (map['isDefault'] as int? ?? 0) == 1,
      blockedApps: blockedApps,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] as int? ?? 0),
    );
  }

  FocusPreset copyWith({
    int? id,
    bool clearId = false,
    String? name,
    Duration? focusDuration,
    Duration? shortBreakDuration,
    Duration? longBreakDuration,
    int? cyclesBeforeLongBreak,
    bool? autoStartBreaks,
    bool? autoStartFocus,
    bool? allowSkipBreak,
    bool? soundEnabled,
    bool? unblockDuringBreaks,
    bool? isDefault,
    List<FocusPresetBlockedApp>? blockedApps,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FocusPreset(
      id: clearId ? null : (id ?? this.id),
      name: name ?? this.name,
      focusDuration: focusDuration ?? this.focusDuration,
      shortBreakDuration: shortBreakDuration ?? this.shortBreakDuration,
      longBreakDuration: longBreakDuration ?? this.longBreakDuration,
      cyclesBeforeLongBreak: cyclesBeforeLongBreak ?? this.cyclesBeforeLongBreak,
      autoStartBreaks: autoStartBreaks ?? this.autoStartBreaks,
      autoStartFocus: autoStartFocus ?? this.autoStartFocus,
      allowSkipBreak: allowSkipBreak ?? this.allowSkipBreak,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      unblockDuringBreaks: unblockDuringBreaks ?? this.unblockDuringBreaks,
      isDefault: isDefault ?? this.isDefault,
      blockedApps: blockedApps ?? this.blockedApps,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Default system presets.
  static List<FocusPreset> get defaultPresets {
    final now = DateTime.now();
    return [
      FocusPreset(
        name: 'Standard Pomodoro',
        focusDuration: const Duration(minutes: 25),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 15),
        cyclesBeforeLongBreak: 4,
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ),
      FocusPreset(
        name: 'Deep Work',
        focusDuration: const Duration(minutes: 50),
        shortBreakDuration: const Duration(minutes: 10),
        longBreakDuration: const Duration(minutes: 30),
        cyclesBeforeLongBreak: 2,
        isDefault: false,
        createdAt: now,
        updatedAt: now,
      ),
      FocusPreset(
        name: 'Quick Sprint',
        focusDuration: const Duration(minutes: 15),
        shortBreakDuration: const Duration(minutes: 3),
        longBreakDuration: const Duration(minutes: 10),
        cyclesBeforeLongBreak: 4,
        isDefault: false,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusPreset &&
          runtimeType == other.runtimeType &&
          name.trim().toLowerCase() == other.name.trim().toLowerCase();

  @override
  int get hashCode => name.trim().toLowerCase().hashCode;

  @override
  String toString() => 'FocusPreset(name: $name, focus: ${focusDuration.inMinutes}m, break: ${shortBreakDuration.inMinutes}m, apps: ${blockedApps.length})';
}
