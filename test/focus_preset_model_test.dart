import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/focus_preset.dart';
import 'package:balance/core/models/focus_session.dart';

void main() {
  group('FocusPresetBlockedApp Model', () {
    test('constructs correctly and supports toMap and fromMap', () {
      const app = FocusPresetBlockedApp(
        id: 1,
        presetId: 10,
        appName: 'Discord',
        exePath: r'C:\Users\User\AppData\Local\Discord\app.exe',
      );

      final map = app.toMap();
      expect(map['id'], equals(1));
      expect(map['presetId'], equals(10));
      expect(map['appName'], equals('Discord'));
      expect(map['exePath'], equals(r'C:\Users\User\AppData\Local\Discord\app.exe'));

      final restored = FocusPresetBlockedApp.fromMap(map);
      expect(restored.id, equals(1));
      expect(restored.presetId, equals(10));
      expect(restored.appName, equals('Discord'));
      expect(restored.exePath, equals(r'C:\Users\User\AppData\Local\Discord\app.exe'));
    });

    test('supports overridePresetId in toMap', () {
      const app = FocusPresetBlockedApp(
        appName: 'Steam',
      );
      final map = app.toMap(overridePresetId: 42);
      expect(map['presetId'], equals(42));
      expect(map['appName'], equals('Steam'));
    });

    test('copyWith updates fields correctly', () {
      const app = FocusPresetBlockedApp(
        id: 1,
        presetId: 10,
        appName: 'Spotify',
      );
      final updated = app.copyWith(exePath: r'C:\spotify.exe', presetId: 12);
      expect(updated.id, equals(1));
      expect(updated.presetId, equals(12));
      expect(updated.appName, equals('Spotify'));
      expect(updated.exePath, equals(r'C:\spotify.exe'));
    });

    test('equality is case-insensitive on appName', () {
      const app1 = FocusPresetBlockedApp(appName: 'chrome.exe');
      const app2 = FocusPresetBlockedApp(appName: 'CHROME.EXE');
      const app3 = FocusPresetBlockedApp(appName: 'firefox.exe');

      expect(app1, equals(app2));
      expect(app1.hashCode, equals(app2.hashCode));
      expect(app1, isNot(equals(app3)));
    });
  });

  group('FocusPreset Model', () {
    test('validates name cannot be empty or whitespace only', () {
      expect(
        () => FocusPreset(
          name: '',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => FocusPreset(
          name: '   ',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validates durations must be greater than zero', () {
      expect(
        () => FocusPreset(
          name: 'Invalid Focus',
          focusDuration: Duration.zero,
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => FocusPreset(
          name: 'Invalid Short Break',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(seconds: -10),
          longBreakDuration: const Duration(minutes: 15),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => FocusPreset(
          name: 'Invalid Long Break',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: Duration.zero,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('validates cyclesBeforeLongBreak must be at least 1', () {
      expect(
        () => FocusPreset(
          name: 'Invalid Cycles',
          focusDuration: const Duration(minutes: 25),
          shortBreakDuration: const Duration(minutes: 5),
          longBreakDuration: const Duration(minutes: 15),
          cyclesBeforeLongBreak: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('serializes toMap and deserializes fromMap accurately', () {
      final now = DateTime.now();
      final preset = FocusPreset(
        id: 5,
        name: 'Custom Flow',
        focusDuration: const Duration(minutes: 45),
        shortBreakDuration: const Duration(minutes: 8),
        longBreakDuration: const Duration(minutes: 20),
        cyclesBeforeLongBreak: 3,
        autoStartBreaks: true,
        autoStartFocus: false,
        allowSkipBreak: true,
        soundEnabled: false,
        unblockDuringBreaks: true,
        isDefault: true,
        blockedApps: const [
          FocusPresetBlockedApp(appName: 'Game', exePath: r'C:\game.exe'),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final map = preset.toMap();
      expect(map['id'], equals(5));
      expect(map['name'], equals('Custom Flow'));
      expect(map['focusDurationSeconds'], equals(45 * 60));
      expect(map['shortBreakDurationSeconds'], equals(8 * 60));
      expect(map['longBreakDurationSeconds'], equals(20 * 60));
      expect(map['cyclesBeforeLongBreak'], equals(3));
      expect(map['autoStartBreaks'], equals(1));
      expect(map['autoStartFocus'], equals(0));
      expect(map['allowSkipBreak'], equals(1));
      expect(map['soundEnabled'], equals(0));
      expect(map['unblockDuringBreaks'], equals(1));
      expect(map['isDefault'], equals(1));

      final restored = FocusPreset.fromMap(map, blockedApps: preset.blockedApps);
      expect(restored.id, equals(5));
      expect(restored.name, equals('Custom Flow'));
      expect(restored.focusDuration, equals(const Duration(minutes: 45)));
      expect(restored.shortBreakDuration, equals(const Duration(minutes: 8)));
      expect(restored.longBreakDuration, equals(const Duration(minutes: 20)));
      expect(restored.cyclesBeforeLongBreak, equals(3));
      expect(restored.autoStartBreaks, isTrue);
      expect(restored.autoStartFocus, isFalse);
      expect(restored.allowSkipBreak, isTrue);
      expect(restored.soundEnabled, isFalse);
      expect(restored.unblockDuringBreaks, isTrue);
      expect(restored.isDefault, isTrue);
      expect(restored.blockedApps.length, equals(1));
      expect(restored.blockedApps.first.appName, equals('Game'));
    });

    test('copyWith produces expected updated instances', () {
      final preset = FocusPreset(
        id: 1,
        name: 'Sprint',
        focusDuration: const Duration(minutes: 20),
        shortBreakDuration: const Duration(minutes: 5),
        longBreakDuration: const Duration(minutes: 10),
      );

      final modified = preset.copyWith(
        name: 'Sprint Modified',
        focusDuration: const Duration(minutes: 25),
        autoStartBreaks: true,
      );

      expect(modified.id, equals(1));
      expect(modified.name, equals('Sprint Modified'));
      expect(modified.focusDuration, equals(const Duration(minutes: 25)));
      expect(modified.shortBreakDuration, equals(const Duration(minutes: 5)));
      expect(modified.autoStartBreaks, isTrue);
    });

    test('defaultPresets provides Standard Pomodoro, Deep Work, and Quick Sprint', () {
      final defaults = FocusPreset.defaultPresets;
      expect(defaults.length, equals(3));

      final pomodoro = defaults.firstWhere((p) => p.name == 'Standard Pomodoro');
      expect(pomodoro.focusDuration, equals(const Duration(minutes: 25)));
      expect(pomodoro.shortBreakDuration, equals(const Duration(minutes: 5)));
      expect(pomodoro.longBreakDuration, equals(const Duration(minutes: 15)));
      expect(pomodoro.cyclesBeforeLongBreak, equals(4));
      expect(pomodoro.isDefault, isTrue);

      final deepWork = defaults.firstWhere((p) => p.name == 'Deep Work');
      expect(deepWork.focusDuration, equals(const Duration(minutes: 50)));
      expect(deepWork.shortBreakDuration, equals(const Duration(minutes: 10)));
      expect(deepWork.longBreakDuration, equals(const Duration(minutes: 30)));
      expect(deepWork.cyclesBeforeLongBreak, equals(2));

      final quickSprint = defaults.firstWhere((p) => p.name == 'Quick Sprint');
      expect(quickSprint.focusDuration, equals(const Duration(minutes: 15)));
      expect(quickSprint.shortBreakDuration, equals(const Duration(minutes: 3)));
      expect(quickSprint.longBreakDuration, equals(const Duration(minutes: 10)));
      expect(quickSprint.cyclesBeforeLongBreak, equals(4));
    });
  });

  group('FocusSessionRecord Model Metadata Extensions', () {
    test('supports new metadata fields and remains backwards compatible', () {
      final now = DateTime.now();
      final recordWithMetadata = FocusSessionRecord(
        id: 101,
        type: FocusSessionType.focus,
        plannedDuration: const Duration(minutes: 25),
        actualDuration: const Duration(minutes: 20),
        startTime: now.subtract(const Duration(minutes: 20)),
        endTime: now,
        completedNaturally: false,
        presetName: 'Standard Pomodoro',
        cycleIndex: 2,
        interruptionReason: 'Urgent meeting call',
      );

      final map = recordWithMetadata.toMap();
      expect(map['presetName'], equals('Standard Pomodoro'));
      expect(map['cycleIndex'], equals(2));
      expect(map['interruptionReason'], equals('Urgent meeting call'));

      final restored = FocusSessionRecord.fromMap(map);
      expect(restored.presetName, equals('Standard Pomodoro'));
      expect(restored.cycleIndex, equals(2));
      expect(restored.interruptionReason, equals('Urgent meeting call'));

      // Test backwards compatibility with legacy map missing new fields
      final legacyMap = {
        'id': 102,
        'type': 'focus',
        'plannedSeconds': 1500,
        'actualSeconds': 1500,
        'startTime': now.millisecondsSinceEpoch,
        'endTime': now.add(const Duration(seconds: 1500)).millisecondsSinceEpoch,
        'completedNaturally': 1,
      };

      final legacyRestored = FocusSessionRecord.fromMap(legacyMap);
      expect(legacyRestored.presetName, isNull);
      expect(legacyRestored.cycleIndex, isNull);
      expect(legacyRestored.interruptionReason, isNull);
    });
  });

  group('ActiveFocusState Model Metadata Extensions', () {
    test('supports new Pomodoro cycle fields and remains backwards compatible', () {
      final now = DateTime.now();
      final active = ActiveFocusState(
        type: FocusSessionType.focus,
        status: FocusStatus.running,
        targetDuration: const Duration(minutes: 25),
        startTime: now,
        expectedEndTime: now.add(const Duration(minutes: 25)),
        remainingDuration: const Duration(minutes: 20),
        presetId: 2,
        presetName: 'Deep Work',
        currentCycle: 2,
        totalCycles: 4,
        isLongBreak: false,
        lastTickTime: now,
      );

      final map = active.toMap();
      expect(map['presetId'], equals(2));
      expect(map['presetName'], equals('Deep Work'));
      expect(map['currentCycle'], equals(2));
      expect(map['totalCycles'], equals(4));
      expect(map['isLongBreak'], equals(0));
      expect(map['lastTickTime'], equals(now.millisecondsSinceEpoch));

      final restored = ActiveFocusState.fromMap(map);
      expect(restored.presetId, equals(2));
      expect(restored.presetName, equals('Deep Work'));
      expect(restored.currentCycle, equals(2));
      expect(restored.totalCycles, equals(4));
      expect(restored.isLongBreak, isFalse);
      expect(restored.lastTickTime, isNotNull);

      // Backwards compatibility with legacy map missing new fields
      final legacyMap = {
        'type': 'focus',
        'status': 'running',
        'targetSeconds': 1500,
        'startTime': now.millisecondsSinceEpoch,
        'expectedEndTime': now.add(const Duration(seconds: 1500)).millisecondsSinceEpoch,
        'remainingSeconds': 1500,
      };

      final legacyRestored = ActiveFocusState.fromMap(legacyMap);
      expect(legacyRestored.presetId, isNull);
      expect(legacyRestored.presetName, isNull);
      expect(legacyRestored.currentCycle, equals(1));
      expect(legacyRestored.totalCycles, equals(4));
      expect(legacyRestored.isLongBreak, isFalse);
      expect(legacyRestored.lastTickTime, isNull);
    });
  });
}
