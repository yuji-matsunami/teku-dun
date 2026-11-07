import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// The kind of event a queued row carries.
enum QueuedEventKind {
  /// A walking session start; must reach the server before its events.
  session,

  /// A single location fix.
  location,

  /// A step-count sample.
  steps,
}

/// The delivery state of a queued event on its way to the server.
enum QueuedEventStatus {
  /// Not yet sent.
  pending,

  /// Currently being sent; not yet acknowledged.
  sending,

  /// Sent and acknowledged by the server.
  sent,
}

/// Events captured on-device, waiting to be sent to the server.
///
/// Rows are appended as events are captured and marked
/// [QueuedEventStatus.sent] once the server has acknowledged them, so the
/// table doubles as a durable retry queue across app restarts.
///
/// The `(status, captured_at)` index only makes oldest-first scans cheap. It
/// does not guarantee that a session is sent before its events; the code that
/// sends rows has to enforce that order itself.
@TableIndex(
  name: 'queued_events_status_captured_at',
  columns: {#status, #capturedAt},
)
class QueuedEvents extends Table {
  /// Device-generated identifier (UUID). Assigned by the caller so an event
  /// keeps the same id across retries.
  TextColumn get id => text()();

  /// UUID of the walking session this event belongs to. For a [kind] of
  /// [QueuedEventKind.session], this is the same value as [id].
  TextColumn get sessionId => text()();

  /// The kind of event carried by [payload].
  TextColumn get kind => textEnum<QueuedEventKind>()();

  /// When the reading was captured: the session start time for
  /// [QueuedEventKind.session], the fix time for [QueuedEventKind.location],
  /// or the interval start time for [QueuedEventKind.steps].
  ///
  /// Callers must pass UTC values (`DateTime.toUtc`); this is not enforced.
  /// Dates are stored as ISO-8601 text, in which UTC ends in `Z` but local
  /// time carries a UTC offset. Mixing the two would make the text order used
  /// by the `(status, captured_at)` index differ from chronological order.
  DateTimeColumn get capturedAt => dateTime()();

  /// The JSON that the API request body is built from; API-specific fields
  /// live here rather than as their own columns. It must not contain the
  /// revision: the [revision] column is the only place that value is kept.
  TextColumn get payload => text()();

  /// Client-assigned revision, used so a steps event can be resent with the
  /// same event id and still overwrite the server's copy. Session and
  /// location events are expected to stay at the default of 1, but the schema
  /// does not enforce that.
  IntColumn get revision => integer().withDefault(const Constant(1))();

  /// Current delivery state; see [QueuedEventStatus].
  TextColumn get status => textEnum<QueuedEventStatus>().withDefault(
    Constant(QueuedEventStatus.pending.name),
  )();

  /// When this row was inserted into the queue.
  ///
  /// Set by SQLite's `CURRENT_TIMESTAMP`, so it has whole-second precision and
  /// is stored as `YYYY-MM-DD HH:MM:SS` (UTC) rather than the ISO-8601 form
  /// the other date columns use.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the event was successfully sent, if it has been. Callers must pass
  /// UTC values, as for [capturedAt].
  DateTimeColumn get sentAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The local SQLite database used as an event store and retry queue.
///
/// The executor is injected via the constructor so tests can supply an
/// in-memory database while the app uses a persisted one (see
/// `appDatabaseProvider`).
@DriftDatabase(tables: [QueuedEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
