import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teku_dun/src/data/local/app_database.dart';

void main() {
  late AppDatabase database;

  const sessionId = '11111111-1111-1111-1111-111111111111';
  const eventId = '22222222-2222-2222-2222-222222222222';

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('全カラムに指定した値を保存して読み出せる', () async {
    final capturedAt = DateTime.utc(2026, 9, 29, 12, 0, 0, 123);
    final createdAt = DateTime.utc(2026, 9, 29, 12, 0, 1);
    final sentAt = DateTime.utc(2026, 9, 29, 12, 5, 0, 456);
    final lastAttemptedAt = DateTime.utc(2026, 9, 29, 12, 5, 0, 789);

    // Every column gets a non-default value. The combination is not a state
    // the queue produces (a sent row has no lastError); the test only checks
    // that each column is stored and read back as given.
    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: eventId,
            sessionId: sessionId,
            kind: QueuedEventKind.steps,
            capturedAt: capturedAt,
            payload: '{"steps":120}',
            revision: const Value(2),
            status: const Value(QueuedEventStatus.sent),
            createdAt: Value(createdAt),
            sentAt: Value(sentAt),
            attemptCount: const Value(3),
            lastError: const Value('HTTP 503'),
            lastAttemptedAt: Value(lastAttemptedAt),
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals(eventId))).getSingle();

    expect(row.id, eventId);
    expect(row.sessionId, sessionId);
    expect(row.kind, QueuedEventKind.steps);
    expect(row.capturedAt, capturedAt);
    expect(row.payload, '{"steps":120}');
    expect(row.revision, 2);
    expect(row.status, QueuedEventStatus.sent);
    expect(row.createdAt, createdAt);
    expect(row.sentAt, sentAt);
    expect(row.attemptCount, 3);
    expect(row.lastError, 'HTTP 503');
    expect(row.lastAttemptedAt, lastAttemptedAt);
  });

  test('省略したカラムには既定値が入る', () async {
    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: eventId,
            sessionId: sessionId,
            kind: QueuedEventKind.steps,
            capturedAt: DateTime.utc(2026, 9, 29),
            payload: '{"steps":100}',
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals(eventId))).getSingle();

    expect(row.status, QueuedEventStatus.pending);
    expect(row.revision, 1);
    expect(row.sentAt, isNull);
    expect(row.attemptCount, 0);
    expect(row.lastError, isNull);
    expect(row.lastAttemptedAt, isNull);
  });

  test('createdAtの既定値は挿入時刻になる', () async {
    final before = DateTime.now().toUtc();

    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: eventId,
            sessionId: sessionId,
            kind: QueuedEventKind.location,
            capturedAt: DateTime.utc(2026, 9, 29),
            payload: '{}',
          ),
        );

    final after = DateTime.now().toUtc();

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals(eventId))).getSingle();

    // CURRENT_TIMESTAMP drops the fractional seconds, so the stored value is a
    // whole second and can be up to a second earlier than the clock reading
    // taken before the insert.
    final createdAtMillis = row.createdAt.millisecondsSinceEpoch;
    expect(createdAtMillis % 1000, 0);
    expect(createdAtMillis, greaterThan(before.millisecondsSinceEpoch - 1000));
    expect(createdAtMillis, lessThanOrEqualTo(after.millisecondsSinceEpoch));

    // Unlike the other date columns, it is stored in SQLite's own format
    // rather than as ISO-8601.
    final raw = await database
        .customSelect('SELECT created_at FROM queued_events')
        .getSingle();
    expect(
      raw.read<String>('created_at'),
      matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')),
    );
  });

  test('同じidの二重挿入は失敗する', () async {
    final insertable = QueuedEventsCompanion.insert(
      id: eventId,
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

  test('UTCの日時はマイクロ秒精度のままUTCで往復する', () async {
    final instant = DateTime.utc(2026, 9, 29, 12, 0, 0, 123, 456);

    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: eventId,
            sessionId: sessionId,
            kind: QueuedEventKind.location,
            capturedAt: instant,
            payload: '{}',
            sentAt: Value(instant),
            lastAttemptedAt: Value(instant),
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals(eventId))).getSingle();

    // DateTime's == also compares isUtc, so this checks that the values come
    // back as UTC.
    expect(row.capturedAt, instant);
    expect(row.sentAt, instant);
    expect(row.lastAttemptedAt, instant);

    // The premise stated in app_database.dart: UTC is stored with a trailing Z.
    final raw = await database
        .customSelect('SELECT captured_at FROM queued_events')
        .getSingle();
    expect(raw.read<String>('captured_at'), endsWith('Z'));
  });

  test('UTC以外の日時も同じ瞬間として往復する', () async {
    // Build the local time from a fixed instant so the result doesn't depend
    // on the machine's time zone. toLocal() is not UTC even if the offset is 0.
    // Dart cannot build a DateTime with an arbitrary offset, so a non-zero
    // offset is only exercised when the machine's time zone isn't UTC.
    final instant = DateTime.utc(2026, 9, 29, 12, 0, 0, 123, 456);
    final local = instant.toLocal();

    await database
        .into(database.queuedEvents)
        .insert(
          QueuedEventsCompanion.insert(
            id: eventId,
            sessionId: sessionId,
            kind: QueuedEventKind.location,
            capturedAt: local,
            payload: '{}',
            sentAt: Value(local),
            lastAttemptedAt: Value(local),
          ),
        );

    final row = await (database.select(
      database.queuedEvents,
    )..where((t) => t.id.equals(eventId))).getSingle();

    // DateTime's == also compares isUtc, so compare the instants in UTC.
    expect(row.capturedAt.toUtc(), instant);
    expect(row.sentAt!.toUtc(), instant);
    expect(row.lastAttemptedAt!.toUtc(), instant);

    // The premise stated in app_database.dart: local time carries a UTC offset.
    final raw = await database
        .customSelect('SELECT captured_at FROM queued_events')
        .getSingle();
    expect(
      raw.read<String>('captured_at'),
      matches(RegExp(r'[+-]\d{2}:\d{2}$')),
    );
  });

  test('kindとstatusは列挙値の名前の文字列で保存される', () async {
    // The stored text outlives app versions, so the expectations are string
    // literals rather than the enum's name. Renaming a value would stop
    // existing rows from being read and need a migration.
    Future<void> insert(
      String id,
      QueuedEventKind kind,
      QueuedEventStatus status,
    ) {
      return database
          .into(database.queuedEvents)
          .insert(
            QueuedEventsCompanion.insert(
              id: id,
              sessionId: sessionId,
              kind: kind,
              capturedAt: DateTime.utc(2026, 9, 29),
              payload: '{}',
              status: Value(status),
            ),
          );
    }

    await insert(
      '33333333-3333-3333-3333-333333333331',
      QueuedEventKind.session,
      QueuedEventStatus.pending,
    );
    await insert(
      '33333333-3333-3333-3333-333333333332',
      QueuedEventKind.location,
      QueuedEventStatus.sending,
    );
    await insert(
      '33333333-3333-3333-3333-333333333333',
      QueuedEventKind.steps,
      QueuedEventStatus.sent,
    );
    await insert(
      '33333333-3333-3333-3333-333333333334',
      QueuedEventKind.session,
      QueuedEventStatus.rejected,
    );

    final rows = await database
        .customSelect('SELECT kind, status FROM queued_events ORDER BY id')
        .get();

    expect(
      [
        for (final row in rows)
          (row.read<String>('kind'), row.read<String>('status')),
      ],
      [
        ('session', 'pending'),
        ('location', 'sending'),
        ('steps', 'sent'),
        ('session', 'rejected'),
      ],
    );
  });
}
