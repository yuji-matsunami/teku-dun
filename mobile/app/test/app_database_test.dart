import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teku_dun/src/data/local/app_database.dart';

void main() {
  // Each test opens its own in-memory database, so drift's default
  // guard against accidentally sharing one database across instances
  // does not apply here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('挿入した全カラムを読み出せる', () async {
    final capturedAt = DateTime.utc(2026, 9, 29, 12, 0, 0, 123);

    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: 'event-1',
            kind: QueuedEventKind.location,
            capturedAt: capturedAt,
            payload: '{"lat":35.0,"lng":139.0}',
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals('event-1'))).getSingle();

    expect(row.id, 'event-1');
    expect(row.kind, QueuedEventKind.location);
    expect(row.capturedAt, capturedAt);
    expect(row.payload, '{"lat":35.0,"lng":139.0}');
  });

  test('statusの既定値はpending、sentAtはnull', () async {
    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: 'event-2',
            kind: QueuedEventKind.steps,
            capturedAt: DateTime.utc(2026, 9, 29),
            payload: '{"steps":100}',
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals('event-2'))).getSingle();

    expect(row.status, QueuedEventStatus.pending);
    expect(row.sentAt, isNull);
  });

  test('同じidの二重挿入は失敗する', () async {
    final insertable = QueuedEventsCompanion.insert(
      id: 'event-3',
      kind: QueuedEventKind.location,
      capturedAt: DateTime.utc(2026, 9, 29),
      payload: '{}',
    );

    await database.into(database.queuedEvents).insert(insertable);

    await expectLater(
      database.into(database.queuedEvents).insert(insertable),
      throwsA(isA<SqliteException>()),
    );
  });

  test('capturedAtはミリ秒精度で往復する', () async {
    final capturedAt = DateTime.utc(2026, 9, 29, 1, 2, 3, 456);

    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: 'event-4',
            kind: QueuedEventKind.steps,
            capturedAt: capturedAt,
            payload: '{}',
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals('event-4'))).getSingle();

    expect(
      row.capturedAt.millisecondsSinceEpoch,
      capturedAt.millisecondsSinceEpoch,
    );
  });
}
