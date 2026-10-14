import 'package:flutter/foundation.dart';

/// Event dispatched when an application's daily usage limit is enforced
/// (either when the limit is first reached, or when the user attempts
/// to reopen a blocked application).
@immutable
class AppBlockEvent {
  /// The user-facing readable display name of the application.
  final String appName;

  /// The executable path of the application, if known.
  final String? exePath;

  /// The configured daily limit duration.
  final Duration limitDuration;

  /// The recorded usage duration for today when the block occurred.
  final Duration usedDuration;

  /// The local calendar time when this application's limit will reset (next midnight).
  final DateTime resetTime;

  /// The timestamp when the block event was triggered.
  final DateTime timestamp;

  const AppBlockEvent({
    required this.appName,
    this.exePath,
    required this.limitDuration,
    required this.usedDuration,
    required this.resetTime,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBlockEvent &&
          runtimeType == other.runtimeType &&
          appName.toLowerCase() == other.appName.toLowerCase() &&
          limitDuration == other.limitDuration &&
          usedDuration == other.usedDuration &&
          resetTime == other.resetTime;

  @override
  int get hashCode =>
      appName.toLowerCase().hashCode ^
      limitDuration.hashCode ^
      usedDuration.hashCode ^
      resetTime.hashCode;

  @override
  String toString() =>
      'AppBlockEvent(appName: $appName, limit: $limitDuration, used: $usedDuration, reset: $resetTime)';
}
