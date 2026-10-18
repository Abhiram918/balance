import 'package:flutter/foundation.dart';

/// The underlying cause triggering an application restriction.
enum AppBlockReason {
  /// Restriction triggered because the application exceeded its daily usage allowance.
  dailyLimit,

  /// Restriction triggered because the application is blocked during an active Focus Mode session.
  focusSession,
}

/// Event dispatched when an application restriction is enforced
/// (either when a limit is exceeded, a focus session is active, or when
/// the user attempts to reopen a blocked application).
@immutable
class AppBlockEvent {
  /// The user-facing readable display name of the application.
  final String appName;

  /// The executable path of the application, if known.
  final String? exePath;

  /// The configured daily limit duration (Duration.zero for focus blocks).
  final Duration limitDuration;

  /// The recorded usage duration for today when the block occurred (Duration.zero for focus blocks).
  final Duration usedDuration;

  /// The local calendar time when this application's restriction will lift.
  final DateTime resetTime;

  /// The timestamp when the block event was triggered.
  final DateTime timestamp;

  /// The underlying cause for this block event.
  final AppBlockReason reason;

  /// The active focus preset name (if blocked by Focus Mode).
  final String? focusPresetName;

  /// The remaining time in the active focus session (if blocked by Focus Mode).
  final Duration? remainingFocusDuration;

  const AppBlockEvent({
    required this.appName,
    this.exePath,
    this.limitDuration = Duration.zero,
    this.usedDuration = Duration.zero,
    required this.resetTime,
    required this.timestamp,
    this.reason = AppBlockReason.dailyLimit,
    this.focusPresetName,
    this.remainingFocusDuration,
  });

  /// Convenience getter indicating whether this block originated from a Focus Mode session.
  bool get isFocusBlock => reason == AppBlockReason.focusSession;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBlockEvent &&
          runtimeType == other.runtimeType &&
          appName.toLowerCase() == other.appName.toLowerCase() &&
          limitDuration == other.limitDuration &&
          usedDuration == other.usedDuration &&
          resetTime == other.resetTime &&
          reason == other.reason &&
          focusPresetName == other.focusPresetName &&
          remainingFocusDuration == other.remainingFocusDuration;

  @override
  int get hashCode =>
      appName.toLowerCase().hashCode ^
      limitDuration.hashCode ^
      usedDuration.hashCode ^
      resetTime.hashCode ^
      reason.hashCode ^
      (focusPresetName?.hashCode ?? 0) ^
      (remainingFocusDuration?.hashCode ?? 0);

  @override
  String toString() =>
      'AppBlockEvent(appName: $appName, reason: $reason, limit: $limitDuration, used: $usedDuration, reset: $resetTime, preset: $focusPresetName, remaining: $remainingFocusDuration)';
}

