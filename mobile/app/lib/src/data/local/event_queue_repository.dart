import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_database.dart';

/// Reads and writes the on-device event queue (the `queued_events` table).
///
/// This layer only stores events and tracks their delivery state; actually
/// sending them is left to a separate resend service, which relies on two
/// things:
///
/// - The outcome of a send ([markSent], [markRetryable], [markRejected]) is
///   recorded only if the row is still the same `sending` attempt, identified
///   by id and revision. A steps event updated while it was being sent is
///   pending again with a newer revision, and an old result must not
///   overwrite that.
/// - Each payload is the JSON the request body is built from, using the walk
///   API's field names and UTC RFC 3339 timestamps. The `revision` column is
///   the only copy of a steps event's revision; the sender adds it to the
///   request body instead of reading it from the payload.
class EventQueueRepository {
  /// Creates a repository over [_database].
  ///
  /// [now] and [generateId] can be replaced so tests get fixed times and ids.
  /// By default ids are random (version 4) UUIDs in the lowercase hyphenated
  /// form the API expects.
  EventQueueRepository(
    this._database, {
    DateTime Function()? now,
    String Function()? generateId,
  }) : _now = now ?? DateTime.now,
       _generateId = generateId ?? _newUuid;

  final AppDatabase _database;
  final DateTime Function() _now;
  final String Function() _generateId;

  static const _uuid = Uuid();

  static String _newUuid() => _uuid.v4();

  $QueuedEventsTable get _events => _database.queuedEvents;

  /// Queues the start of a walking session at [startedAt] and returns its id.
  ///
  /// The id also serves as the session id that the session's location and
  /// steps events refer to. The payload holds `start_datetime`.
  Future<String> enqueueSession(DateTime startedAt) async {
    final id = _generateId();
    final start = _utcMillis(startedAt);
    await _insert(
      id: id,
      sessionId: id,
      kind: QueuedEventKind.session,
      capturedAt: start,
      payload: {'start_datetime': start.toIso8601String()},
    );
    return id;
  }

  /// Queues a location fix for [sessionId] and returns the new event's id.
  /// The payload holds `recorded_at`, `latitude`, `longitude` and `accuracy_m`.
  ///
  /// Throws an [ArgumentError] if [sessionId] was not queued with
  /// [enqueueSession].
  Future<String> enqueueLocation({
    required String sessionId,
    required DateTime recordedAt,
    required double latitude,
    required double longitude,
    required double accuracyM,
  }) {
    return _database.transaction(() async {
      await _requireSession(sessionId);
      final id = _generateId();
      final recorded = _utcMillis(recordedAt);
      await _insert(
        id: id,
        sessionId: sessionId,
        kind: QueuedEventKind.location,
        capturedAt: recorded,
        payload: {
          'recorded_at': recorded.toIso8601String(),
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': accuracyM,
        },
      );
      return id;
    });
  }

  /// Queues the step count of the interval [start] to [end] for [sessionId]
  /// and returns the event's id.
  ///
  /// Without [eventId], or with an id that is not queued yet, a new event is
  /// added at revision 1. With the id of a queued steps event, that event is
  /// updated in place instead: its revision goes up by one, its payload is
  /// replaced, and it is pending again whatever state it was in (even sent, or
  /// being sent right now), so the server's copy gets overwritten. [start] and
  /// [end] must stay the same across revisions; the server rejects changes to
  /// them.
  ///
  /// The payload holds `start_datetime`, `end_datetime` and `steps`; the
  /// request's `revision` is taken from the revision column when sending.
  ///
  /// Throws an [ArgumentError] if [sessionId] was not queued with
  /// [enqueueSession], or if [eventId] belongs to something other than a steps
  /// event of [sessionId].
  Future<String> upsertSteps({
    required String sessionId,
    String? eventId,
    required DateTime start,
    required DateTime end,
    required int steps,
  }) {
    return _database.transaction(() async {
      await _requireSession(sessionId);
      final startUtc = _utcMillis(start);
      final payload = {
        'start_datetime': startUtc.toIso8601String(),
        'end_datetime': _utcMillis(end).toIso8601String(),
        'steps': steps,
      };

      final existing = eventId == null ? null : await _find(eventId);
      if (existing == null) {
        final id = eventId ?? _generateId();
        await _insert(
          id: id,
          sessionId: sessionId,
          kind: QueuedEventKind.steps,
          capturedAt: startUtc,
          payload: payload,
        );
        return id;
      }

      if (existing.kind != QueuedEventKind.steps ||
          existing.sessionId != sessionId) {
        throw ArgumentError.value(
          eventId,
          'eventId',
          'is not a steps event of session $sessionId',
        );
      }
      await (_database.update(
        _events,
      )..where((t) => t.id.equals(existing.id))).write(
        QueuedEventsCompanion(
          payload: Value(jsonEncode(payload)),
          revision: Value(existing.revision + 1),
          status: const Value(QueuedEventStatus.pending),
          sentAt: const Value(null),
        ),
      );
      return existing.id;
    });
  }

  /// The session rows that still have something to send, oldest first.
  ///
  /// A session qualifies when its own row is [QueuedEventStatus.pending], or
  /// when its row is already [QueuedEventStatus.sent] but some of its events
  /// are pending. Sessions in any other state are left out: one that is being
  /// sent is already taken care of, and a rejected one holds back its events
  /// too, since the server does not take a session's events before the session
  /// itself, so it waits for a manual [requeueRejected].
  ///
  /// The sender sends the session row first if it is pending, and only then
  /// the session's [pendingEvents].
  Future<List<QueuedEvent>> sessionsAwaitingSend() {
    final sessionIdsWithPendingRows = _database.selectOnly(_events)
      ..addColumns([_events.sessionId])
      ..where(_events.status.equalsValue(QueuedEventStatus.pending));

    return (_database.select(_events)
          ..where(
            (t) =>
                t.kind.equalsValue(QueuedEventKind.session) &
                t.status.isInValues(const [
                  QueuedEventStatus.pending,
                  QueuedEventStatus.sent,
                ]) &
                t.id.isInQuery(sessionIdsWithPendingRows),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.capturedAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// The location and steps events of [sessionId] that are waiting to be
  /// sent, oldest [QueuedEvent.capturedAt] first.
  ///
  /// The session's own row is not included; see [sessionsAwaitingSend].
  Future<List<QueuedEvent>> pendingEvents(String sessionId) {
    return (_database.select(_events)
          ..where(
            (t) =>
                t.sessionId.equals(sessionId) &
                t.kind.equalsValue(QueuedEventKind.session).not() &
                t.status.equalsValue(QueuedEventStatus.pending),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.capturedAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// Claims the pending row [id] for sending and returns it as it is now, or
  /// null if there is no such row or it is not pending.
  ///
  /// Send the returned row, not one read earlier: it carries the latest
  /// payload, and its revision is what [markSent], [markRetryable] and
  /// [markRejected] must be given afterwards.
  Future<QueuedEvent?> markSending(String id) {
    return _database.transaction(() async {
      final claimed =
          await (_database.update(_events)..where(
                (t) =>
                    t.id.equals(id) &
                    t.status.equalsValue(QueuedEventStatus.pending),
              ))
              .write(
                const QueuedEventsCompanion(
                  status: Value(QueuedEventStatus.sending),
                ),
              );
      return claimed == 0 ? null : _find(id);
    });
  }

  /// Records that the server accepted revision [revision] of the row [id].
  ///
  /// Returns false and leaves the row alone unless the row is still
  /// `sending` at exactly that revision. That is not an error: it means the row
  /// was changed while it was being sent (see [upsertSteps]), so the newer
  /// revision still has to be sent.
  Future<bool> markSent(String id, int revision) {
    final now = _nowUtc();
    return _recordOutcome(
      id,
      revision,
      QueuedEventsCompanion(
        status: const Value(QueuedEventStatus.sent),
        sentAt: Value(now),
        lastError: const Value(null),
        lastAttemptedAt: Value(now),
      ),
    );
  }

  /// Records that sending revision [revision] of the row [id] failed in a way
  /// worth retrying: the row goes back to pending, and [error] is kept.
  ///
  /// Returns false and leaves the row alone unless the row is still
  /// `sending` at exactly that revision, as for [markSent].
  Future<bool> markRetryable(String id, int revision, String error) {
    return _recordFailure(id, revision, QueuedEventStatus.pending, error);
  }

  /// Records that the server refused revision [revision] of the row [id] for
  /// good: the row becomes [QueuedEventStatus.rejected], and [error] is kept.
  /// A rejected row stays in the table until [requeueRejected] moves it back.
  ///
  /// Returns false and leaves the row alone unless the row is still
  /// `sending` at exactly that revision, as for [markSent].
  Future<bool> markRejected(String id, int revision, String error) {
    return _recordFailure(id, revision, QueuedEventStatus.rejected, error);
  }

  /// Puts rejected rows back to pending and returns how many were moved.
  ///
  /// Moves every rejected row, or only the row [id] when it is given. The
  /// attempt history stays as it is.
  Future<int> requeueRejected({String? id}) {
    return (_database.update(_events)..where(
          (t) =>
              t.status.equalsValue(QueuedEventStatus.rejected) &
              (id == null ? const Constant(true) : t.id.equals(id)),
        ))
        .write(
          const QueuedEventsCompanion(status: Value(QueuedEventStatus.pending)),
        );
  }

  /// Puts every `sending` row back to pending and returns how many were moved.
  ///
  /// Call this on startup before the first send: a row can only still be
  /// `sending` then if the app stopped in the middle of sending it. Sending is
  /// idempotent on the server, so it is safe to send such a row again.
  Future<int> resetSendingToPending() {
    return (_database.update(
      _events,
    )..where((t) => t.status.equalsValue(QueuedEventStatus.sending))).write(
      const QueuedEventsCompanion(status: Value(QueuedEventStatus.pending)),
    );
  }

  /// Emits how many rows are in each status, again whenever the counts change.
  ///
  /// Every status is present in each map, with 0 if no row has it.
  Stream<Map<QueuedEventStatus, int>> watchStatusCounts() {
    final count = _events.id.count();
    final query = _database.selectOnly(_events)
      ..addColumns([_events.status, count])
      ..groupBy([_events.status]);

    return query.watch().map((rows) {
      final counts = {for (final status in QueuedEventStatus.values) status: 0};
      for (final row in rows) {
        counts[row.readWithConverter(_events.status)!] = row.read(count)!;
      }
      return counts;
    });
  }

  Future<void> _insert({
    required String id,
    required String sessionId,
    required QueuedEventKind kind,
    required DateTime capturedAt,
    required Map<String, Object?> payload,
  }) {
    return _database
        .into(_events)
        .insert(
          QueuedEventsCompanion.insert(
            id: id,
            sessionId: sessionId,
            kind: kind,
            capturedAt: capturedAt,
            payload: jsonEncode(payload),
            createdAt: Value(_nowUtc()),
          ),
        );
  }

  Future<QueuedEvent?> _find(String id) {
    return (_database.select(
      _events,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> _requireSession(String sessionId) async {
    final session = await _find(sessionId);
    if (session == null || session.kind != QueuedEventKind.session) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'is not a queued session',
      );
    }
  }

  Future<bool> _recordFailure(
    String id,
    int revision,
    QueuedEventStatus status,
    String error,
  ) {
    return _recordOutcome(
      id,
      revision,
      QueuedEventsCompanion.custom(
        status: Variable<String>(status.name),
        attemptCount: _events.attemptCount + const Constant(1),
        lastError: Variable<String>(error),
        lastAttemptedAt: Variable<DateTime>(_nowUtc()),
      ),
    );
  }

  /// Applies [outcome] to the row [id] only if it is still the `sending`
  /// attempt at [revision]; returns whether it was applied.
  Future<bool> _recordOutcome(
    String id,
    int revision,
    Insertable<QueuedEvent> outcome,
  ) async {
    final updated =
        await (_database.update(_events)..where(
              (t) =>
                  t.id.equals(id) &
                  t.revision.equals(revision) &
                  t.status.equalsValue(QueuedEventStatus.sending),
            ))
            .write(outcome);
    return updated > 0;
  }

  DateTime _nowUtc() => _utcMillis(_now());
}

/// Converts [time] to UTC and drops anything below a millisecond.
///
/// Dart prints sub-millisecond digits only when they are not zero, so mixing
/// precisions would make the stored ISO-8601 text sort out of order; with one
/// precision, text order is time order. Truncating every time alike also keeps
/// a gap of whole minutes exactly that long, which the server requires between
/// a session start and the start of each of its steps intervals.
DateTime _utcMillis(DateTime time) {
  return DateTime.fromMillisecondsSinceEpoch(
    time.millisecondsSinceEpoch,
    isUtc: true,
  );
}
