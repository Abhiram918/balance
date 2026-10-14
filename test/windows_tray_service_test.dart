import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/services/windows_tray_service.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  group('WindowsTrayService Unit Tests', () {
    test('handleTrayClick detects double-click within threshold and restores window', () {
      bool restored = false;
      final service = WindowsTrayService(
        onRestore: () => restored = true,
        doubleClickThreshold: const Duration(milliseconds: 500),
        isPlatformSupported: false,
      );

      final click1 = DateTime(2026, 10, 15, 12, 0, 0, 0);
      service.handleTrayClick(click1);
      expect(restored, isFalse, reason: 'First click should not trigger restore');

      // Second click 200ms later (within 500ms threshold)
      final click2 = DateTime(2026, 10, 15, 12, 0, 0, 200);
      service.handleTrayClick(click2);
      expect(restored, isTrue, reason: 'Second click within threshold should trigger restore');
    });

    test('handleTrayClick does not detect double-click if clicks are too far apart', () {
      bool restored = false;
      final service = WindowsTrayService(
        onRestore: () => restored = true,
        doubleClickThreshold: const Duration(milliseconds: 500),
        isPlatformSupported: false,
      );

      final click1 = DateTime(2026, 10, 15, 12, 0, 0, 0);
      service.handleTrayClick(click1);
      expect(restored, isFalse);

      // Second click 700ms later (exceeds 500ms threshold)
      final click2 = DateTime(2026, 10, 15, 12, 0, 0, 700);
      service.handleTrayClick(click2);
      expect(restored, isFalse, reason: 'Slow click should not be recognized as double-click');
    });

    test('Context menu open_balance menuItem restores window', () {
      bool restored = false;
      final service = WindowsTrayService(
        onRestore: () => restored = true,
        isPlatformSupported: false,
      );

      service.onTrayMenuItemClick(MenuItem(key: 'open_balance', label: 'Open Balance'));
      expect(restored, isTrue);
    });

    test('onWindowClose hides window to tray without terminating', () async {
      bool hiddenToTray = false;
      final service = WindowsTrayService(
        onCloseToTray: () => hiddenToTray = true,
        isPlatformSupported: false,
      );

      expect(service.isWindowHidden, isFalse);

      service.onWindowClose();

      expect(service.isWindowHidden, isTrue);
      expect(hiddenToTray, isTrue);
    });

    test('restoreWindow resets isWindowHidden and fires onRestore', () async {
      bool restored = false;
      final service = WindowsTrayService(
        onRestore: () => restored = true,
        isPlatformSupported: false,
      );

      await service.hideToTray();
      expect(service.isWindowHidden, isTrue);

      await service.restoreWindow();
      expect(service.isWindowHidden, isFalse);
      expect(restored, isTrue);
    });

    test('cleanShutdown invokes onShutdown callback and guards against duplicate execution', () async {
      int shutdownCalls = 0;
      final service = WindowsTrayService(
        onShutdown: () async {
          shutdownCalls++;
        },
        isPlatformSupported: false,
      );

      // Verify initial state
      expect(service.isShuttingDown, isFalse);

      // First shutdown attempt
      await service.cleanShutdown();
      expect(shutdownCalls, equals(1));
      expect(service.isShuttingDown, isTrue);

      // Second shutdown attempt should be a no-op
      await service.cleanShutdown();
      expect(shutdownCalls, equals(1));
    });
  });
}
