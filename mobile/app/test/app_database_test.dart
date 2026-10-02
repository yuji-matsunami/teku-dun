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

  const sessionId = '11111111-1111-1111-1111-111111111111';

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
            sessionId: sessionId,
            kind: QueuedEventKind.location,
            capturedAt: capturedAt,
            payload: '{"lat":35.0,"lng":139.0}',
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals('event-1'))).getSingle();

    expect(row.id, 'event-1');
    expect(row.sessionId, sessionId);
    expect(row.kind, QueuedEventKind.location);
    expect(row.capturedAt, capturedAt);
    expect(row.payload, '{"lat":35.0,"lng":139.0}');
    expect(row.revision, 1);
  });

  test('statusの既定値はpending、sentAtはnull', () async {
    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: 'event-2',
            sessionId: sessionId,
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

  test('revisionの既定値は1', () async {
    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: 'event-revision-default',
            sessionId: sessionId,
            kind: QueuedEventKind.steps,
            capturedAt: DateTime.utc(2026, 9, 29),
            payload: '{"steps":100}',
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals('event-revision-default'))).getSingle();

    expect(row.revision, 1);
  });

  test('同じidの二重挿入は失敗する', () async {
    final insertable = QueuedEventsCompanion.insert(
      id: 'event-3',
      sessionId: sessionId,
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
            sessionId: sessionId,
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

  test('session種別の行はidとsessionIdが同じ値で保存・読み出しできる', () async {
    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: sessionId,
            sessionId: sessionId,
            kind: QueuedEventKind.session,
            capturedAt: DateTime.utc(2026, 9, 29, 9, 0, 0),
            payload: '{"startedAt":"2026-09-29T09:00:00Z"}',
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals(sessionId))).getSingle();

    expect(row.id, sessionId);
    expect(row.sessionId, sessionId);
    expect(row.kind, QueuedEventKind.session);
  });

  test('stepsの行はrevision2で保存・読み出しできる', () async {
    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: 'event-steps-revision-2',
            sessionId: sessionId,
            kind: QueuedEventKind.steps,
            capturedAt: DateTime.utc(2026, 9, 29, 9, 1, 0),
            payload: '{"steps":120}',
            revision: const Value(2),
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals('event-steps-revision-2'))).getSingle();

    expect(row.revision, 2);
  });
}
