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
/// Rows are appended as events are captured and marked [sent] once the
/// server has acknowledged them, so the table doubles as a durable retry
/// queue across app restarts.
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
  DateTimeColumn get capturedAt => dateTime()();

  /// The JSON that the API request body is built from; API-specific fields
  /// live here rather than as their own columns.
  TextColumn get payload => text()();

  /// Client-assigned revision, used so a steps event can be resent with the
  /// same event id and still overwrite the server's copy. Always 1 for
  /// session and location events.
  IntColumn get revision => integer().withDefault(const Constant(1))();

  /// Current delivery state; see [QueuedEventStatus].
  TextColumn get status => textEnum<QueuedEventStatus>().withDefault(
    Constant(QueuedEventStatus.pending.name),
  )();

  /// When this row was inserted into the queue.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the event was successfully sent, if it has been.
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
