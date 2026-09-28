// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $QueuedEventsTable extends QueuedEvents
    with TableInfo<$QueuedEventsTable, QueuedEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueuedEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<QueuedEventKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<QueuedEventKind>($QueuedEventsTable.$converterkind);
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<QueuedEventStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: Constant(QueuedEventStatus.pending.name),
  ).withConverter<QueuedEventStatus>($QueuedEventsTable.$converterstatus);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    capturedAt,
    payload,
    status,
    createdAt,
    sentAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queued_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueuedEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueuedEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueuedEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: $QueuedEventsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      status: $QueuedEventsTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      ),
    );
  }

  @override
  $QueuedEventsTable createAlias(String alias) {
    return $QueuedEventsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<QueuedEventKind, String, String> $converterkind =
      const EnumNameConverter<QueuedEventKind>(QueuedEventKind.values);
  static JsonTypeConverter2<QueuedEventStatus, String, String>
  $converterstatus = const EnumNameConverter<QueuedEventStatus>(
    QueuedEventStatus.values,
  );
}

class QueuedEvent extends DataClass implements Insertable<QueuedEvent> {
  /// Device-generated identifier (UUID). Assigned by the caller so an event
  /// keeps the same id across retries.
  final String id;

  /// The kind of sensor data carried by [payload].
  final QueuedEventKind kind;

  /// When the sensor reading was captured, not when it was enqueued.
  final DateTime capturedAt;

  /// The event body, encoded as a JSON string.
  final String payload;

  /// Current delivery state; see [QueuedEventStatus].
  final QueuedEventStatus status;

  /// When this row was inserted into the queue.
  final DateTime createdAt;

  /// When the event was successfully sent, if it has been.
  final DateTime? sentAt;
  const QueuedEvent({
    required this.id,
    required this.kind,
    required this.capturedAt,
    required this.payload,
    required this.status,
    required this.createdAt,
    this.sentAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    {
      map['kind'] = Variable<String>(
        $QueuedEventsTable.$converterkind.toSql(kind),
      );
    }
    map['captured_at'] = Variable<DateTime>(capturedAt);
    map['payload'] = Variable<String>(payload);
    {
      map['status'] = Variable<String>(
        $QueuedEventsTable.$converterstatus.toSql(status),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || sentAt != null) {
      map['sent_at'] = Variable<DateTime>(sentAt);
    }
    return map;
  }

  QueuedEventsCompanion toCompanion(bool nullToAbsent) {
    return QueuedEventsCompanion(
      id: Value(id),
      kind: Value(kind),
      capturedAt: Value(capturedAt),
      payload: Value(payload),
      status: Value(status),
      createdAt: Value(createdAt),
      sentAt: sentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sentAt),
    );
  }

  factory QueuedEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueuedEvent(
      id: serializer.fromJson<String>(json['id']),
      kind: $QueuedEventsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      payload: serializer.fromJson<String>(json['payload']),
      status: $QueuedEventsTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sentAt: serializer.fromJson<DateTime?>(json['sentAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(
        $QueuedEventsTable.$converterkind.toJson(kind),
      ),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'payload': serializer.toJson<String>(payload),
      'status': serializer.toJson<String>(
        $QueuedEventsTable.$converterstatus.toJson(status),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sentAt': serializer.toJson<DateTime?>(sentAt),
    };
  }

  QueuedEvent copyWith({
    String? id,
    QueuedEventKind? kind,
    DateTime? capturedAt,
    String? payload,
    QueuedEventStatus? status,
    DateTime? createdAt,
    Value<DateTime?> sentAt = const Value.absent(),
  }) => QueuedEvent(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    capturedAt: capturedAt ?? this.capturedAt,
    payload: payload ?? this.payload,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    sentAt: sentAt.present ? sentAt.value : this.sentAt,
  );
  QueuedEvent copyWithCompanion(QueuedEventsCompanion data) {
    return QueuedEvent(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueuedEvent(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('sentAt: $sentAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, capturedAt, payload, status, createdAt, sentAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueuedEvent &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.capturedAt == this.capturedAt &&
          other.payload == this.payload &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.sentAt == this.sentAt);
}

class QueuedEventsCompanion extends UpdateCompanion<QueuedEvent> {
  final Value<String> id;
  final Value<QueuedEventKind> kind;
  final Value<DateTime> capturedAt;
  final Value<String> payload;
  final Value<QueuedEventStatus> status;
  final Value<DateTime> createdAt;
  final Value<DateTime?> sentAt;
  final Value<int> rowid;
  const QueuedEventsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueuedEventsCompanion.insert({
    required String id,
    required QueuedEventKind kind,
    required DateTime capturedAt,
    required String payload,
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       capturedAt = Value(capturedAt),
       payload = Value(payload);
  static Insertable<QueuedEvent> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<DateTime>? capturedAt,
    Expression<String>? payload,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? sentAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (payload != null) 'payload': payload,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (sentAt != null) 'sent_at': sentAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueuedEventsCompanion copyWith({
    Value<String>? id,
    Value<QueuedEventKind>? kind,
    Value<DateTime>? capturedAt,
    Value<String>? payload,
    Value<QueuedEventStatus>? status,
    Value<DateTime>? createdAt,
    Value<DateTime?>? sentAt,
    Value<int>? rowid,
  }) {
    return QueuedEventsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      capturedAt: capturedAt ?? this.capturedAt,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt ?? this.sentAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $QueuedEventsTable.$converterkind.toSql(kind.value),
      );
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $QueuedEventsTable.$converterstatus.toSql(status.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueuedEventsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('payload: $payload, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('sentAt: $sentAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $QueuedEventsTable queuedEvents = $QueuedEventsTable(this);
  late final Index queuedEventsStatusCapturedAt = Index(
    'queued_events_status_captured_at',
    'CREATE INDEX queued_events_status_captured_at ON queued_events (status, captured_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    queuedEvents,
    queuedEventsStatusCapturedAt,
  ];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$QueuedEventsTableCreateCompanionBuilder =
    QueuedEventsCompanion Function({
      required String id,
      required QueuedEventKind kind,
      required DateTime capturedAt,
      required String payload,
      Value<QueuedEventStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime?> sentAt,
      Value<int> rowid,
    });
typedef $$QueuedEventsTableUpdateCompanionBuilder =
    QueuedEventsCompanion Function({
      Value<String> id,
      Value<QueuedEventKind> kind,
      Value<DateTime> capturedAt,
      Value<String> payload,
      Value<QueuedEventStatus> status,
      Value<DateTime> createdAt,
      Value<DateTime?> sentAt,
      Value<int> rowid,
    });

class $$QueuedEventsTableFilterComposer
    extends Composer<_$AppDatabase, $QueuedEventsTable> {
  $$QueuedEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<QueuedEventKind, QueuedEventKind, String>
  get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<QueuedEventStatus, QueuedEventStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueuedEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $QueuedEventsTable> {
  $$QueuedEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueuedEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueuedEventsTable> {
  $$QueuedEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<QueuedEventKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumnWithTypeConverter<QueuedEventStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);
}

class $$QueuedEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QueuedEventsTable,
          QueuedEvent,
          $$QueuedEventsTableFilterComposer,
          $$QueuedEventsTableOrderingComposer,
          $$QueuedEventsTableAnnotationComposer,
          $$QueuedEventsTableCreateCompanionBuilder,
          $$QueuedEventsTableUpdateCompanionBuilder,
          (
            QueuedEvent,
            BaseReferences<_$AppDatabase, $QueuedEventsTable, QueuedEvent>,
          ),
          QueuedEvent,
          PrefetchHooks Function()
        > {
  $$QueuedEventsTableTableManager(_$AppDatabase db, $QueuedEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueuedEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueuedEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueuedEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<QueuedEventKind> kind = const Value.absent(),
                Value<DateTime> capturedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<QueuedEventStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedEventsCompanion(
                id: id,
                kind: kind,
                capturedAt: capturedAt,
                payload: payload,
                status: status,
                createdAt: createdAt,
                sentAt: sentAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required QueuedEventKind kind,
                required DateTime capturedAt,
                required String payload,
                Value<QueuedEventStatus> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedEventsCompanion.insert(
                id: id,
                kind: kind,
                capturedAt: capturedAt,
                payload: payload,
                status: status,
                createdAt: createdAt,
                sentAt: sentAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QueuedEventsTable, QueuedEvent>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $QueuedEventsTable,
                    QueuedEvent
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueuedEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QueuedEventsTable,
      QueuedEvent,
      $$QueuedEventsTableFilterComposer,
      $$QueuedEventsTableOrderingComposer,
      $$QueuedEventsTableAnnotationComposer,
      $$QueuedEventsTableCreateCompanionBuilder,
      $$QueuedEventsTableUpdateCompanionBuilder,
      (
        QueuedEvent,
        BaseReferences<_$AppDatabase, $QueuedEventsTable, QueuedEvent>,
      ),
      QueuedEvent,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$QueuedEventsTableTableManager get queuedEvents =>
      $$QueuedEventsTableTableManager(_db, _db.queuedEvents);
}
