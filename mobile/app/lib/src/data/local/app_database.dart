import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// The kind of sensor event a queued event carries.
enum QueuedEventKind {
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

/// Sensor events captured on-device, waiting to be sent to the server.
///
/// Rows are appended as sensors produce data and removed (or marked [sent])
/// once the server has acknowledged them, so the table doubles as a
/// durable retry queue across app restarts.
@TableIndex(
  name: 'queued_events_status_captured_at',
  columns: {#status, #capturedAt},
)
class QueuedEvents extends Table {
  /// Device-generated identifier (UUID). Assigned by the caller so an event
  /// keeps the same id across retries.
  TextColumn get id => text()();

  /// The kind of sensor data carried by [payload].
  TextColumn get kind => textEnum<QueuedEventKind>()();

  /// When the sensor reading was captured, not when it was enqueued.
  DateTimeColumn get capturedAt => dateTime()();

  /// The event body, encoded as a JSON string.
  TextColumn get payload => text()();

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
