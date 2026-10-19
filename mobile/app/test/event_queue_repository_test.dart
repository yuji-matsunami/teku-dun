import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:teku_dun/src/data/local/app_database.dart';
import 'package:teku_dun/src/data/local/event_queue_repository.dart';
import 'package:teku_dun/src/providers/app_providers.dart';

String _uuid(int n) {
  return '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
}

Future<QueuedEvent> _row(AppDatabase database, String id) {
  return (database.select(
    database.queuedEvents,
  )..where((t) => t.id.equals(id))).getSingle();
}

Map<String, Object?> _payload(QueuedEvent row) {
  return jsonDecode(row.payload) as Map<String, Object?>;
}

Map<QueuedEventStatus, int> _counts({
  int pending = 0,
  int sending = 0,
  int sent = 0,
  int rejected = 0,
}) {
  return {
    QueuedEventStatus.pending: pending,
    QueuedEventStatus.sending: sending,
    QueuedEventStatus.sent: sent,
    QueuedEventStatus.rejected: rejected,
  };
}

void main() {
  final sessionStart = DateTime.utc(2026, 9, 29, 9, 0, 0);

  late AppDatabase database;
  late EventQueueRepository repository;
  late DateTime now;
  var idCount = 0;

  setUp(() {
    now = DateTime.utc(2026, 9, 29, 12, 0, 0);
    idCount = 0;
    database = AppDatabase(NativeDatabase.memory());
    repository = EventQueueRepository(
      database,
      now: () => now,
      generateId: () => _uuid(++idCount),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> enqueueSession([DateTime? startedAt]) {
    return repository.enqueueSession(startedAt ?? sessionStart);
  }

  Future<String> enqueueLocation(String sessionId, {int second = 5}) {
    return repository.enqueueLocation(
      sessionId: sessionId,
      recordedAt: sessionStart.add(Duration(seconds: second)),
      latitude: 35.681236,
      longitude: 139.767125,
      accuracyM: 4.5,
    );
  }

  Future<String> upsertSteps(
    String sessionId, {
    String? eventId,
    int minute = 1,
    int steps = 100,
  }) {
    return repository.upsertSteps(
      sessionId: sessionId,
      eventId: eventId,
      start: sessionStart.add(Duration(minutes: minute)),
      end: sessionStart.add(Duration(minutes: minute + 1)),
      steps: steps,
    );
  }

  // The helpers below move a row through the repository the way a sender
  // would.
  Future<QueuedEvent> claim(String id) async {
    return (await repository.markSending(id))!;
  }

  Future<void> accept(String id) async {
    final row = await claim(id);
    await repository.markSent(row.id, row.revision);
  }

  Future<void> reject(String id) async {
    final row = await claim(id);
    await repository.markRejected(row.id, row.revision, 'HTTP 400');
  }

  group('enqueueSession', () {
    test('セッションを追加するとidとsessionIdが同じpending行になる', () async {
      final id = await enqueueSession();

      expect(id, _uuid(1));
      final row = await _row(database, id);
      expect(row.id, id);
      expect(row.sessionId, id);
      expect(row.kind, QueuedEventKind.session);
      expect(row.capturedAt, DateTime.utc(2026, 9, 29, 9));
      expect(_payload(row), {'start_datetime': '2026-09-29T09:00:00.000Z'});
      expect(row.revision, 1);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.createdAt, now);
      expect(row.sentAt, isNull);
      expect(row.attemptCount, 0);
      expect(row.lastError, isNull);
      expect(row.lastAttemptedAt, isNull);
    });

    test('既定のIDは小文字ハイフン形式のUUID v4で毎回異なる', () async {
      final defaultRepository = EventQueueRepository(database);

      final first = await defaultRepository.enqueueSession(sessionStart);
      final second = await defaultRepository.enqueueSession(sessionStart);

      final uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(first, matches(uuidV4));
      expect(second, matches(uuidV4));
      expect(first, isNot(second));
    });

    test('ローカル時刻もUTCのRFC3339としてpayloadとcapturedAtに保存する', () async {
      final startedAt = DateTime.utc(2026, 9, 29, 9, 0, 0).toLocal();

      final id = await enqueueSession(startedAt);

      final row = await _row(database, id);
      expect(row.capturedAt, DateTime.utc(2026, 9, 29, 9));
      expect(_payload(row)['start_datetime'], '2026-09-29T09:00:00.000Z');
    });

    test('ミリ秒より細かい桁は切り捨てて保存する', () async {
      final id = await enqueueSession(
        DateTime.utc(2026, 9, 29, 9, 0, 0, 123, 456),
      );

      final row = await _row(database, id);
      expect(row.capturedAt, DateTime.utc(2026, 9, 29, 9, 0, 0, 123));
      expect(_payload(row)['start_datetime'], '2026-09-29T09:00:00.123Z');
    });
  });

  group('enqueueLocation', () {
    test('位置を追加するとAPIのリクエスト項目名でpayloadを保存する', () async {
      final sessionId = await enqueueSession();

      final id = await enqueueLocation(sessionId, second: 5);

      expect(id, _uuid(2));
      final row = await _row(database, id);
      expect(row.sessionId, sessionId);
      expect(row.kind, QueuedEventKind.location);
      expect(row.capturedAt, DateTime.utc(2026, 9, 29, 9, 0, 5));
      expect(_payload(row), {
        'recorded_at': '2026-09-29T09:00:05.000Z',
        'latitude': 35.681236,
        'longitude': 139.767125,
        'accuracy_m': 4.5,
      });
      expect(row.revision, 1);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.createdAt, now);
    });

    test('キューにないセッションの位置は追加できない', () async {
      await expectLater(enqueueLocation(_uuid(99)), throwsArgumentError);

      expect(await database.select(database.queuedEvents).get(), isEmpty);
    });

    test('session以外の行のidはセッションとして指定できない', () async {
      final sessionId = await enqueueSession();
      final locationId = await enqueueLocation(sessionId);

      await expectLater(enqueueLocation(locationId), throwsArgumentError);
    });
  });

  group('upsertSteps', () {
    test('eventIdなしなら新しい歩数イベントをrevision1で追加する', () async {
      final sessionId = await enqueueSession();

      final id = await upsertSteps(sessionId, minute: 1, steps: 120);

      expect(id, _uuid(2));
      final row = await _row(database, id);
      expect(row.sessionId, sessionId);
      expect(row.kind, QueuedEventKind.steps);
      expect(row.capturedAt, DateTime.utc(2026, 9, 29, 9, 1));
      expect(row.revision, 1);
      expect(row.status, QueuedEventStatus.pending);
      // The revision lives only in its column, never in the payload.
      expect(_payload(row), {
        'start_datetime': '2026-09-29T09:01:00.000Z',
        'end_datetime': '2026-09-29T09:02:00.000Z',
        'steps': 120,
      });
    });

    test('同じeventIdで呼ぶとrevisionを1ずつ上げてpayloadを更新する', () async {
      final sessionId = await enqueueSession();
      final id = await upsertSteps(sessionId, steps: 10);

      final second = await upsertSteps(sessionId, eventId: id, steps: 25);
      expect(second, id);
      final third = await upsertSteps(sessionId, eventId: id, steps: 40);
      expect(third, id);

      final row = await _row(database, id);
      expect(row.revision, 3);
      expect(_payload(row)['steps'], 40);
      expect(row.status, QueuedEventStatus.pending);
      // The session row and a single steps row; updating did not add a row.
      expect(await database.select(database.queuedEvents).get(), hasLength(2));
    });

    test('キューにないeventIdを渡すとそのidで新しく追加する', () async {
      final sessionId = await enqueueSession();

      final id = await upsertSteps(sessionId, eventId: _uuid(50));

      expect(id, _uuid(50));
      final row = await _row(database, id);
      expect(row.revision, 1);
      expect(row.status, QueuedEventStatus.pending);
    });

    test('送信済みの歩数を更新するとpendingに戻りsentAtが消える', () async {
      final sessionId = await enqueueSession();
      final id = await upsertSteps(sessionId);
      await accept(id);
      expect((await _row(database, id)).sentAt, now);

      await upsertSteps(sessionId, eventId: id, steps: 150);

      final row = await _row(database, id);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.revision, 2);
      expect(row.sentAt, isNull);
    });

    test('送信中の歩数を更新するとpendingに戻る', () async {
      final sessionId = await enqueueSession();
      final id = await upsertSteps(sessionId);
      await claim(id);

      await upsertSteps(sessionId, eventId: id, steps: 150);

      final row = await _row(database, id);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.revision, 2);
    });

    test('rejectedの歩数を更新するとpendingに戻る', () async {
      final sessionId = await enqueueSession();
      final id = await upsertSteps(sessionId);
      await reject(id);

      await upsertSteps(sessionId, eventId: id, steps: 150);

      final row = await _row(database, id);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.revision, 2);
    });

    test('更新しても試行回数とエラー履歴は引き継ぐ', () async {
      final sessionId = await enqueueSession();
      final id = await upsertSteps(sessionId);
      final claimed = await claim(id);
      await repository.markRetryable(id, claimed.revision, 'HTTP 503');

      await upsertSteps(sessionId, eventId: id, steps: 150);

      final row = await _row(database, id);
      expect(row.attemptCount, 1);
      expect(row.lastError, 'HTTP 503');
      expect(row.lastAttemptedAt, now);
    });

    test('他セッションや歩数以外の行のeventIdは更新できない', () async {
      final sessionId = await enqueueSession();
      final otherSessionId = await enqueueSession();
      final locationId = await enqueueLocation(sessionId);
      final stepsId = await upsertSteps(sessionId);

      await expectLater(
        upsertSteps(sessionId, eventId: locationId),
        throwsArgumentError,
      );
      await expectLater(
        upsertSteps(otherSessionId, eventId: stepsId, steps: 999),
        throwsArgumentError,
      );

      final location = await _row(database, locationId);
      expect(location.kind, QueuedEventKind.location);
      expect(location.revision, 1);
      final steps = await _row(database, stepsId);
      expect(steps.sessionId, sessionId);
      expect(steps.revision, 1);
      expect(_payload(steps)['steps'], 100);
    });

    test('キューにないセッションの歩数は追加できない', () async {
      await expectLater(upsertSteps(_uuid(99)), throwsArgumentError);

      expect(await database.select(database.queuedEvents).get(), isEmpty);
    });
  });

  group('送信対象の取得', () {
    test('pendingのセッションをセッション開始が古い順に返す', () async {
      final later = await enqueueSession(
        sessionStart.add(const Duration(hours: 1)),
      );
      final earlier = await enqueueSession(sessionStart);

      final sessions = await repository.sessionsAwaitingSend();

      expect(sessions.map((s) => s.id), [earlier, later]);
      expect(sessions.every((s) => s.kind == QueuedEventKind.session), isTrue);
    });

    test('送信済みでも未送信の子があるセッションは含め、子がすべて送信済みなら含めない', () async {
      final withPendingChild = await enqueueSession();
      final allSent = await enqueueSession(
        sessionStart.add(const Duration(hours: 1)),
      );
      final pendingOnly = await enqueueSession(
        sessionStart.add(const Duration(hours: 2)),
      );
      await accept(withPendingChild);
      await accept(allSent);
      await enqueueLocation(withPendingChild);
      await accept(await enqueueLocation(allSent));

      final sessions = await repository.sessionsAwaitingSend();

      expect(sessions.map((s) => s.id), [withPendingChild, pendingOnly]);
      expect(sessions.first.status, QueuedEventStatus.sent);
      expect(sessions.last.status, QueuedEventStatus.pending);
    });

    test('rejectedのセッションは子がpendingでも含めない', () async {
      final rejected = await enqueueSession();
      await enqueueLocation(rejected);
      await reject(rejected);

      expect(await repository.sessionsAwaitingSend(), isEmpty);
    });

    test('sendingのセッションは含めない', () async {
      final session = await enqueueSession();
      await enqueueLocation(session);
      await claim(session);

      expect(await repository.sessionsAwaitingSend(), isEmpty);
    });

    test('requeueRejectedで戻したセッションはもう一度対象になる', () async {
      final session = await enqueueSession();
      await reject(session);
      expect(await repository.sessionsAwaitingSend(), isEmpty);

      await repository.requeueRejected();

      final sessions = await repository.sessionsAwaitingSend();
      expect(sessions.map((s) => s.id), [session]);
    });

    test('pendingEventsは位置と歩数をcapturedAtの昇順に返す', () async {
      final session = await enqueueSession();
      final stepsAt1Min = await upsertSteps(session, minute: 1);
      final locationAt30Sec = await enqueueLocation(session, second: 30);
      final locationAt10Sec = await enqueueLocation(session, second: 10);
      final stepsAt2Min = await upsertSteps(session, minute: 2);

      final events = await repository.pendingEvents(session);

      expect(events.map((e) => e.id), [
        locationAt10Sec,
        locationAt30Sec,
        stepsAt1Min,
        stepsAt2Min,
      ]);
    });

    test('pendingEventsはセッション行・他セッション・pending以外の行を含めない', () async {
      final session = await enqueueSession();
      final other = await enqueueSession();
      final pendingLocation = await enqueueLocation(session, second: 10);
      final sentLocation = await enqueueLocation(session, second: 20);
      final rejectedSteps = await upsertSteps(session, minute: 1);
      final sendingSteps = await upsertSteps(session, minute: 2);
      await enqueueLocation(other, second: 5);
      await accept(sentLocation);
      await reject(rejectedSteps);
      await claim(sendingSteps);

      final events = await repository.pendingEvents(session);

      expect(events.map((e) => e.id), [pendingLocation]);
    });

    test('capturedAtが同じイベントはidの昇順で返す', () async {
      final session = await enqueueSession();
      final first = await enqueueLocation(session, second: 5);
      final second = await enqueueLocation(session, second: 5);

      final events = await repository.pendingEvents(session);

      expect(events.map((e) => e.id), [first, second]);
    });
  });

  group('状態遷移', () {
    test('markSendingはpendingの行をsendingにして、その行を返す', () async {
      final id = await enqueueSession();

      final claimed = await repository.markSending(id);

      expect(claimed, isNotNull);
      expect(claimed!.id, id);
      expect(claimed.status, QueuedEventStatus.sending);
      expect((await _row(database, id)).status, QueuedEventStatus.sending);
    });

    test('markSendingは更新後の最新のpayloadとrevisionを返す', () async {
      final session = await enqueueSession();
      final id = await upsertSteps(session, steps: 10);
      await upsertSteps(session, eventId: id, steps: 25);

      final claimed = await repository.markSending(id);

      expect(claimed!.revision, 2);
      expect(_payload(claimed)['steps'], 25);
    });

    test('markSendingはpending以外の行や存在しない行ではnullを返し行を変えない', () async {
      final sending = await enqueueSession();
      final sent = await enqueueSession();
      final rejected = await enqueueSession();
      await claim(sending);
      await accept(sent);
      await reject(rejected);
      final before = await database.select(database.queuedEvents).get();

      expect(await repository.markSending(sending), isNull);
      expect(await repository.markSending(sent), isNull);
      expect(await repository.markSending(rejected), isNull);
      expect(await repository.markSending(_uuid(99)), isNull);

      expect(await database.select(database.queuedEvents).get(), before);
    });

    test('markSentはsendingの行をsentにして時刻を記録する', () async {
      final id = await enqueueSession();
      await claim(id);
      now = DateTime.utc(2026, 9, 29, 12, 5);

      final applied = await repository.markSent(id, 1);

      expect(applied, isTrue);
      final row = await _row(database, id);
      expect(row.status, QueuedEventStatus.sent);
      expect(row.sentAt, now);
      expect(row.lastAttemptedAt, now);
      expect(row.attemptCount, 0);
      expect(row.lastError, isNull);
    });

    test('markSentは直近の失敗理由を消し、失敗回数は残す', () async {
      final id = await enqueueSession();
      final first = await claim(id);
      await repository.markRetryable(id, first.revision, 'HTTP 503');
      await claim(id);

      await repository.markSent(id, 1);

      final row = await _row(database, id);
      expect(row.status, QueuedEventStatus.sent);
      expect(row.attemptCount, 1);
      expect(row.lastError, isNull);
    });

    test('markSentはsendingでない行をsentにしない', () async {
      final pending = await enqueueSession();
      final sent = await enqueueSession();
      final rejected = await enqueueSession();
      await accept(sent);
      await reject(rejected);
      final before = await database.select(database.queuedEvents).get();

      expect(await repository.markSent(pending, 1), isFalse);
      expect(await repository.markSent(sent, 1), isFalse);
      expect(await repository.markSent(rejected, 1), isFalse);
      expect(await repository.markSent(_uuid(99), 1), isFalse);

      expect(await database.select(database.queuedEvents).get(), before);
    });

    test('markSentはrevisionが違うsendingの行をsentにしない', () async {
      final id = await enqueueSession();
      await claim(id);

      expect(await repository.markSent(id, 2), isFalse);

      final row = await _row(database, id);
      expect(row.status, QueuedEventStatus.sending);
      expect(row.sentAt, isNull);
    });

    test('送信中に歩数が更新されたらmarkSentはsentにせず、新しいrevisionは再送される', () async {
      final session = await enqueueSession();
      await accept(session);
      final id = await upsertSteps(session, steps: 10);
      final sending = await claim(id);
      await upsertSteps(session, eventId: id, steps: 25);

      // The result of sending revision 1 arrives after revision 2 was queued.
      final applied = await repository.markSent(id, sending.revision);

      expect(applied, isFalse);
      var row = await _row(database, id);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.revision, 2);
      expect(row.sentAt, isNull);
      expect((await repository.pendingEvents(session)).map((e) => e.id), [id]);

      final resending = await claim(id);
      expect(resending.revision, 2);
      expect(await repository.markSent(id, resending.revision), isTrue);
      row = await _row(database, id);
      expect(row.status, QueuedEventStatus.sent);
      expect(row.revision, 2);
      expect(await repository.pendingEvents(session), isEmpty);
    });

    test('markRetryableはpendingに戻して失敗回数・理由・時刻を記録する', () async {
      final id = await enqueueSession();
      await claim(id);
      now = DateTime.utc(2026, 9, 29, 12, 5);

      expect(await repository.markRetryable(id, 1, 'timeout'), isTrue);

      var row = await _row(database, id);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.attemptCount, 1);
      expect(row.lastError, 'timeout');
      expect(row.lastAttemptedAt, now);
      expect(row.sentAt, isNull);

      await claim(id);
      now = DateTime.utc(2026, 9, 29, 12, 10);
      expect(await repository.markRetryable(id, 1, 'HTTP 503'), isTrue);

      row = await _row(database, id);
      expect(row.status, QueuedEventStatus.pending);
      expect(row.attemptCount, 2);
      expect(row.lastError, 'HTTP 503');
      expect(row.lastAttemptedAt, now);
      expect((await repository.sessionsAwaitingSend()).map((s) => s.id), [id]);
    });

    test('markRejectedはrejectedにして失敗回数・理由・時刻を記録し、行は残す', () async {
      final id = await enqueueSession();
      await claim(id);
      now = DateTime.utc(2026, 9, 29, 12, 5);

      expect(await repository.markRejected(id, 1, 'HTTP 409'), isTrue);

      final row = await _row(database, id);
      expect(row.status, QueuedEventStatus.rejected);
      expect(row.attemptCount, 1);
      expect(row.lastError, 'HTTP 409');
      expect(row.lastAttemptedAt, now);
      expect(row.payload, isNotEmpty);
      expect(await repository.sessionsAwaitingSend(), isEmpty);
    });

    test('送信中に歩数が更新されたらmarkRetryableとmarkRejectedは新しい行を変えない', () async {
      final session = await enqueueSession();
      final id = await upsertSteps(session, steps: 10);
      final sending = await claim(id);
      await upsertSteps(session, eventId: id, steps: 25);
      final before = await _row(database, id);

      expect(
        await repository.markRetryable(id, sending.revision, 'timeout'),
        isFalse,
      );
      expect(
        await repository.markRejected(id, sending.revision, 'HTTP 400'),
        isFalse,
      );

      expect(await _row(database, id), before);
      expect(before.status, QueuedEventStatus.pending);
    });

    test('古いrevisionの結果は、新しいrevisionを送信中の行に反映しない', () async {
      final session = await enqueueSession();
      final id = await upsertSteps(session, steps: 10);
      final stale = await claim(id);
      await upsertSteps(session, eventId: id, steps: 25);
      final current = await claim(id);
      final before = await _row(database, id);

      expect(await repository.markSent(id, stale.revision), isFalse);
      expect(
        await repository.markRetryable(id, stale.revision, 'timeout'),
        isFalse,
      );
      expect(
        await repository.markRejected(id, stale.revision, 'HTTP 400'),
        isFalse,
      );

      expect(await _row(database, id), before);
      expect(before.status, QueuedEventStatus.sending);
      expect(await repository.markSent(id, current.revision), isTrue);
    });

    test('sendingでない行へのmarkRetryableとmarkRejectedは何もしない', () async {
      final pending = await enqueueSession();
      final sent = await enqueueSession();
      await accept(sent);
      final before = await database.select(database.queuedEvents).get();

      expect(await repository.markRetryable(pending, 1, 'timeout'), isFalse);
      expect(await repository.markRejected(pending, 1, 'HTTP 400'), isFalse);
      expect(await repository.markRetryable(sent, 1, 'timeout'), isFalse);
      expect(await repository.markRejected(sent, 1, 'HTTP 400'), isFalse);
      expect(await repository.markRetryable(_uuid(99), 1, 'timeout'), isFalse);

      expect(await database.select(database.queuedEvents).get(), before);
    });

    test('requeueRejectedはrejectedの行をすべてpendingに戻し、試行履歴は残す', () async {
      final session = await enqueueSession();
      final rejectedLocation = await enqueueLocation(session, second: 5);
      final rejectedSteps = await upsertSteps(session);
      final pendingLocation = await enqueueLocation(session, second: 10);
      final sentLocation = await enqueueLocation(session, second: 15);
      await reject(rejectedLocation);
      await reject(rejectedSteps);
      await accept(sentLocation);

      final requeued = await repository.requeueRejected();

      expect(requeued, 2);
      for (final id in [rejectedLocation, rejectedSteps]) {
        final row = await _row(database, id);
        expect(row.status, QueuedEventStatus.pending);
        expect(row.attemptCount, 1);
        expect(row.lastError, 'HTTP 400');
      }
      expect(
        (await _row(database, pendingLocation)).status,
        QueuedEventStatus.pending,
      );
      expect(
        (await _row(database, sentLocation)).status,
        QueuedEventStatus.sent,
      );
      expect(await repository.requeueRejected(), 0);
    });

    test('requeueRejectedにidを渡すとその行だけをpendingに戻す', () async {
      final session = await enqueueSession();
      final first = await enqueueLocation(session, second: 5);
      final second = await enqueueLocation(session, second: 10);
      await reject(first);
      await reject(second);

      expect(await repository.requeueRejected(id: first), 1);

      expect((await _row(database, first)).status, QueuedEventStatus.pending);
      expect((await _row(database, second)).status, QueuedEventStatus.rejected);
    });

    test('requeueRejectedはrejectedでない行をidで指定しても変えない', () async {
      final id = await enqueueSession();

      expect(await repository.requeueRejected(id: id), 0);
      expect(await repository.requeueRejected(id: _uuid(99)), 0);

      expect((await _row(database, id)).status, QueuedEventStatus.pending);
    });

    test('resetSendingToPendingはsendingだけをpendingに戻して件数を返す', () async {
      final session = await enqueueSession();
      final sending1 = await enqueueLocation(session, second: 5);
      final sending2 = await enqueueLocation(session, second: 10);
      final sent = await enqueueLocation(session, second: 15);
      final rejected = await enqueueLocation(session, second: 20);
      await claim(sending1);
      await claim(sending2);
      await accept(sent);
      await reject(rejected);

      final reset = await repository.resetSendingToPending();

      expect(reset, 2);
      expect(
        (await _row(database, sending1)).status,
        QueuedEventStatus.pending,
      );
      expect(
        (await _row(database, sending2)).status,
        QueuedEventStatus.pending,
      );
      expect((await _row(database, sent)).status, QueuedEventStatus.sent);
      expect(
        (await _row(database, rejected)).status,
        QueuedEventStatus.rejected,
      );
      expect(await repository.resetSendingToPending(), 0);
    });

    test('resetSendingToPendingは失敗回数を増やさない', () async {
      final id = await enqueueSession();
      await claim(id);

      await repository.resetSendingToPending();

      final row = await _row(database, id);
      expect(row.attemptCount, 0);
      expect(row.lastError, isNull);
      expect(row.lastAttemptedAt, isNull);
    });
  });

  group('watchStatusCounts', () {
    test('状態ごとの件数を、変化するたびに流す', () async {
      final counts = StreamIterator(repository.watchStatusCounts());
      addTearDown(counts.cancel);
      Future<Map<QueuedEventStatus, int>> next() async {
        expect(await counts.moveNext(), isTrue);
        return counts.current;
      }

      expect(await next(), _counts());

      final session = await enqueueSession();
      expect(await next(), _counts(pending: 1));

      final location = await enqueueLocation(session);
      expect(await next(), _counts(pending: 2));

      await claim(session);
      expect(await next(), _counts(pending: 1, sending: 1));

      final sending = await claim(location);
      expect(await next(), _counts(sending: 2));

      await repository.markSent(session, 1);
      expect(await next(), _counts(sending: 1, sent: 1));

      await repository.markRejected(location, sending.revision, 'HTTP 400');
      expect(await next(), _counts(sent: 1, rejected: 1));

      await repository.requeueRejected();
      expect(await next(), _counts(pending: 1, sent: 1));
    });
  });

  group('永続化', () {
    late Directory directory;
    late File file;

    // These tests open the database file while the in-memory database from the
    // outer setUp is still open. Drift warns about that as a possible
    // accidental second instance, but the two share nothing.
    setUpAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });
    tearDownAll(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
    });

    setUp(() {
      directory = Directory.systemTemp.createTempSync('teku_dun_event_queue_');
      file = File('${directory.path}/teku_dun.sqlite');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    /// Runs [body] against the database file and then closes it, like one run
    /// of the app; calling this again is a restart.
    Future<T> runApp<T>(
      Future<T> Function(EventQueueRepository repository) body,
    ) async {
      final db = AppDatabase(NativeDatabase(file));
      try {
        return await body(EventQueueRepository(db));
      } finally {
        await db.close();
      }
    }

    test('DBを閉じて開き直しても未送信のイベントが残る', () async {
      late String sessionId;
      late String locationId;
      late String stepsId;
      await runApp((repository) async {
        sessionId = await repository.enqueueSession(sessionStart);
        locationId = await repository.enqueueLocation(
          sessionId: sessionId,
          recordedAt: sessionStart.add(const Duration(seconds: 5)),
          latitude: 35.681236,
          longitude: 139.767125,
          accuracyM: 4.5,
        );
        stepsId = await repository.upsertSteps(
          sessionId: sessionId,
          start: sessionStart.add(const Duration(minutes: 1)),
          end: sessionStart.add(const Duration(minutes: 2)),
          steps: 100,
        );
        await repository.upsertSteps(
          sessionId: sessionId,
          eventId: stepsId,
          start: sessionStart.add(const Duration(minutes: 1)),
          end: sessionStart.add(const Duration(minutes: 2)),
          steps: 150,
        );
      });

      await runApp((repository) async {
        final sessions = await repository.sessionsAwaitingSend();
        expect(sessions.map((s) => s.id), [sessionId]);
        expect(sessions.single.status, QueuedEventStatus.pending);
        expect(sessions.single.capturedAt, sessionStart);

        final events = await repository.pendingEvents(sessionId);
        expect(events.map((e) => e.id), [locationId, stepsId]);
        expect(events.first.status, QueuedEventStatus.pending);
        expect(_payload(events.first)['latitude'], 35.681236);
        expect(events.last.revision, 2);
        expect(_payload(events.last)['steps'], 150);

        expect(await repository.watchStatusCounts().first, _counts(pending: 3));
      });
    });

    test('sent・rejectedの状態と試行履歴も開き直した後に残る', () async {
      late String sessionId;
      late String locationId;
      late String stepsId;
      await runApp((repository) async {
        sessionId = await repository.enqueueSession(sessionStart);
        locationId = await repository.enqueueLocation(
          sessionId: sessionId,
          recordedAt: sessionStart.add(const Duration(seconds: 5)),
          latitude: 35.0,
          longitude: 139.0,
          accuracyM: 5,
        );
        stepsId = await repository.upsertSteps(
          sessionId: sessionId,
          start: sessionStart.add(const Duration(minutes: 1)),
          end: sessionStart.add(const Duration(minutes: 2)),
          steps: 100,
        );
        final session = (await repository.markSending(sessionId))!;
        await repository.markSent(session.id, session.revision);
        final location = (await repository.markSending(locationId))!;
        await repository.markRejected(
          location.id,
          location.revision,
          'HTTP 400',
        );
        final steps = (await repository.markSending(stepsId))!;
        await repository.markRetryable(steps.id, steps.revision, 'timeout');
      });

      await runApp((repository) async {
        expect(
          await repository.watchStatusCounts().first,
          _counts(pending: 1, sent: 1, rejected: 1),
        );
        final pending = await repository.pendingEvents(sessionId);
        expect(pending.map((e) => e.id), [stepsId]);
        expect(pending.single.attemptCount, 1);
        expect(pending.single.lastError, 'timeout');
        expect(pending.single.lastAttemptedAt, isNotNull);
        expect(await repository.requeueRejected(id: locationId), 1);
      });
    });

    test('送信中に止まった行は開き直してもsendingで、resetSendingToPendingで再送対象に戻る', () async {
      late String sessionId;
      await runApp((repository) async {
        sessionId = await repository.enqueueSession(sessionStart);
        await repository.markSending(sessionId);
      });

      await runApp((repository) async {
        expect(await repository.sessionsAwaitingSend(), isEmpty);
        expect(await repository.watchStatusCounts().first, _counts(sending: 1));

        expect(await repository.resetSendingToPending(), 1);

        final sessions = await repository.sessionsAwaitingSend();
        expect(sessions.map((s) => s.id), [sessionId]);
        expect(sessions.single.status, QueuedEventStatus.pending);
      });
    });
  });

  group('eventQueueRepositoryProvider', () {
    test('appDatabaseProviderのデータベースを使う', () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      final id = await container
          .read(eventQueueRepositoryProvider)
          .enqueueSession(sessionStart);

      final row = await _row(database, id);
      expect(row.kind, QueuedEventKind.session);
      expect(row.status, QueuedEventStatus.pending);
    });
  });
}
