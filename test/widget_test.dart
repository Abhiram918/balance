import 'package:flutter_test/flutter_test.dart';
import 'package:balance/core/models/app_session.dart';
import 'package:balance/core/services/usage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Usage Data and Persistence Tests', () {
    late UsageRepository repository;

    setUp(() {
      repository = UsageRepository(dbName: inMemoryDatabasePath);
    });

    test('Insert and retrieve sessions for the same day', () async {
      final now = DateTime.now();
      
      final session1 = AppSession(
        appName: 'Test App 1',
        exePath: 'C:\\test1.exe',
        startTime: now.subtract(const Duration(minutes: 30)),
        endTime: now.subtract(const Duration(minutes: 20)),
      );
      
      final session2 = AppSession(
        appName: 'Test App 2',
        exePath: 'C:\\test2.exe',
        startTime: now.subtract(const Duration(minutes: 15)),
        endTime: now.subtract(const Duration(minutes: 5)),
      );

      await repository.insertSession(session1);
      await repository.insertSession(session2);

      final sessions = await repository.getSessionsForDay(now);
      expect(sessions.length, greaterThanOrEqualTo(2));
      
      final found1 = sessions.any((s) => s.appName == 'Test App 1' && s.duration == const Duration(minutes: 10));
      final found2 = sessions.any((s) => s.appName == 'Test App 2' && s.duration == const Duration(minutes: 10));
      
      expect(found1, isTrue);
      expect(found2, isTrue);
    });
  });
}
