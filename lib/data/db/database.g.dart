// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DailyMetricsRecordsTable extends DailyMetricsRecords with TableInfo<$DailyMetricsRecordsTable, DailyMetricsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyMetricsRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
    'day_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [dayKey, payload, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_metrics_records';
  @override
  VerificationContext validateIntegrity(Insertable<DailyMetricsRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta, dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta, updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {dayKey};
  @override
  DailyMetricsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyMetricsRow(
      dayKey: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}payload'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $DailyMetricsRecordsTable createAlias(String alias) {
    return $DailyMetricsRecordsTable(attachedDatabase, alias);
  }
}

class DailyMetricsRow extends DataClass implements Insertable<DailyMetricsRow> {
  final String dayKey;
  final Uint8List payload;
  final DateTime updatedAt;
  const DailyMetricsRow({required this.dayKey, required this.payload, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day_key'] = Variable<String>(dayKey);
    map['payload'] = Variable<Uint8List>(payload);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DailyMetricsRecordsCompanion toCompanion(bool nullToAbsent) {
    return DailyMetricsRecordsCompanion(dayKey: Value(dayKey), payload: Value(payload), updatedAt: Value(updatedAt));
  }

  factory DailyMetricsRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyMetricsRow(
      dayKey: serializer.fromJson<String>(json['dayKey']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dayKey': serializer.toJson<String>(dayKey),
      'payload': serializer.toJson<Uint8List>(payload),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DailyMetricsRow copyWith({String? dayKey, Uint8List? payload, DateTime? updatedAt}) => DailyMetricsRow(
    dayKey: dayKey ?? this.dayKey,
    payload: payload ?? this.payload,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DailyMetricsRow copyWithCompanion(DailyMetricsRecordsCompanion data) {
    return DailyMetricsRow(
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      payload: data.payload.present ? data.payload.value : this.payload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyMetricsRow(')
          ..write('dayKey: $dayKey, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(dayKey, $driftBlobEquality.hash(payload), updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyMetricsRow &&
          other.dayKey == this.dayKey &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.updatedAt == this.updatedAt);
}

class DailyMetricsRecordsCompanion extends UpdateCompanion<DailyMetricsRow> {
  final Value<String> dayKey;
  final Value<Uint8List> payload;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DailyMetricsRecordsCompanion({
    this.dayKey = const Value.absent(),
    this.payload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyMetricsRecordsCompanion.insert({
    required String dayKey,
    required Uint8List payload,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : dayKey = Value(dayKey),
       payload = Value(payload),
       updatedAt = Value(updatedAt);
  static Insertable<DailyMetricsRow> custom({
    Expression<String>? dayKey,
    Expression<Uint8List>? payload,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dayKey != null) 'day_key': dayKey,
      if (payload != null) 'payload': payload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyMetricsRecordsCompanion copyWith({
    Value<String>? dayKey,
    Value<Uint8List>? payload,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DailyMetricsRecordsCompanion(
      dayKey: dayKey ?? this.dayKey,
      payload: payload ?? this.payload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyMetricsRecordsCompanion(')
          ..write('dayKey: $dayKey, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivityRecordsTable extends ActivityRecords with TableInfo<$ActivityRecordsTable, ActivityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivityRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _garminIDMeta = const VerificationMeta('garminID');
  @override
  late final GeneratedColumn<int> garminID = GeneratedColumn<int>(
    'garmin_i_d',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
    'day_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startLocalMeta = const VerificationMeta('startLocal');
  @override
  late final GeneratedColumn<String> startLocal = GeneratedColumn<String>(
    'start_local',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [garminID, dayKey, startLocal, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activity_records';
  @override
  VerificationContext validateIntegrity(Insertable<ActivityRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('garmin_i_d')) {
      context.handle(_garminIDMeta, garminID.isAcceptableOrUnknown(data['garmin_i_d']!, _garminIDMeta));
    }
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta, dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('start_local')) {
      context.handle(_startLocalMeta, startLocal.isAcceptableOrUnknown(data['start_local']!, _startLocalMeta));
    } else if (isInserting) {
      context.missing(_startLocalMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {garminID};
  @override
  ActivityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivityRow(
      garminID: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}garmin_i_d'])!,
      dayKey: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
      startLocal: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}start_local'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}payload'])!,
    );
  }

  @override
  $ActivityRecordsTable createAlias(String alias) {
    return $ActivityRecordsTable(attachedDatabase, alias);
  }
}

class ActivityRow extends DataClass implements Insertable<ActivityRow> {
  final int garminID;
  final String dayKey;
  final String startLocal;
  final Uint8List payload;
  const ActivityRow({required this.garminID, required this.dayKey, required this.startLocal, required this.payload});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['garmin_i_d'] = Variable<int>(garminID);
    map['day_key'] = Variable<String>(dayKey);
    map['start_local'] = Variable<String>(startLocal);
    map['payload'] = Variable<Uint8List>(payload);
    return map;
  }

  ActivityRecordsCompanion toCompanion(bool nullToAbsent) {
    return ActivityRecordsCompanion(
      garminID: Value(garminID),
      dayKey: Value(dayKey),
      startLocal: Value(startLocal),
      payload: Value(payload),
    );
  }

  factory ActivityRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivityRow(
      garminID: serializer.fromJson<int>(json['garminID']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
      startLocal: serializer.fromJson<String>(json['startLocal']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'garminID': serializer.toJson<int>(garminID),
      'dayKey': serializer.toJson<String>(dayKey),
      'startLocal': serializer.toJson<String>(startLocal),
      'payload': serializer.toJson<Uint8List>(payload),
    };
  }

  ActivityRow copyWith({int? garminID, String? dayKey, String? startLocal, Uint8List? payload}) => ActivityRow(
    garminID: garminID ?? this.garminID,
    dayKey: dayKey ?? this.dayKey,
    startLocal: startLocal ?? this.startLocal,
    payload: payload ?? this.payload,
  );
  ActivityRow copyWithCompanion(ActivityRecordsCompanion data) {
    return ActivityRow(
      garminID: data.garminID.present ? data.garminID.value : this.garminID,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      startLocal: data.startLocal.present ? data.startLocal.value : this.startLocal,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivityRow(')
          ..write('garminID: $garminID, ')
          ..write('dayKey: $dayKey, ')
          ..write('startLocal: $startLocal, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(garminID, dayKey, startLocal, $driftBlobEquality.hash(payload));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivityRow &&
          other.garminID == this.garminID &&
          other.dayKey == this.dayKey &&
          other.startLocal == this.startLocal &&
          $driftBlobEquality.equals(other.payload, this.payload));
}

class ActivityRecordsCompanion extends UpdateCompanion<ActivityRow> {
  final Value<int> garminID;
  final Value<String> dayKey;
  final Value<String> startLocal;
  final Value<Uint8List> payload;
  const ActivityRecordsCompanion({
    this.garminID = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.startLocal = const Value.absent(),
    this.payload = const Value.absent(),
  });
  ActivityRecordsCompanion.insert({
    this.garminID = const Value.absent(),
    required String dayKey,
    required String startLocal,
    required Uint8List payload,
  }) : dayKey = Value(dayKey),
       startLocal = Value(startLocal),
       payload = Value(payload);
  static Insertable<ActivityRow> custom({
    Expression<int>? garminID,
    Expression<String>? dayKey,
    Expression<String>? startLocal,
    Expression<Uint8List>? payload,
  }) {
    return RawValuesInsertable({
      if (garminID != null) 'garmin_i_d': garminID,
      if (dayKey != null) 'day_key': dayKey,
      if (startLocal != null) 'start_local': startLocal,
      if (payload != null) 'payload': payload,
    });
  }

  ActivityRecordsCompanion copyWith({
    Value<int>? garminID,
    Value<String>? dayKey,
    Value<String>? startLocal,
    Value<Uint8List>? payload,
  }) {
    return ActivityRecordsCompanion(
      garminID: garminID ?? this.garminID,
      dayKey: dayKey ?? this.dayKey,
      startLocal: startLocal ?? this.startLocal,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (garminID.present) {
      map['garmin_i_d'] = Variable<int>(garminID.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (startLocal.present) {
      map['start_local'] = Variable<String>(startLocal.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivityRecordsCompanion(')
          ..write('garminID: $garminID, ')
          ..write('dayKey: $dayKey, ')
          ..write('startLocal: $startLocal, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class $RawResponseRecordsTable extends RawResponseRecords with TableInfo<$RawResponseRecordsTable, RawResponseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RawResponseRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _endpointMeta = const VerificationMeta('endpoint');
  @override
  late final GeneratedColumn<String> endpoint = GeneratedColumn<String>(
    'endpoint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta('fetchedAt');
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<Uint8List> body = GeneratedColumn<Uint8List>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [endpoint, fetchedAt, body];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_response_records';
  @override
  VerificationContext validateIntegrity(Insertable<RawResponseRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('endpoint')) {
      context.handle(_endpointMeta, endpoint.isAcceptableOrUnknown(data['endpoint']!, _endpointMeta));
    } else if (isInserting) {
      context.missing(_endpointMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(_fetchedAtMeta, fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta));
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('body')) {
      context.handle(_bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {endpoint};
  @override
  RawResponseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawResponseRow(
      endpoint: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}endpoint'])!,
      fetchedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}fetched_at'])!,
      body: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}body'])!,
    );
  }

  @override
  $RawResponseRecordsTable createAlias(String alias) {
    return $RawResponseRecordsTable(attachedDatabase, alias);
  }
}

class RawResponseRow extends DataClass implements Insertable<RawResponseRow> {
  final String endpoint;
  final DateTime fetchedAt;
  final Uint8List body;
  const RawResponseRow({required this.endpoint, required this.fetchedAt, required this.body});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['endpoint'] = Variable<String>(endpoint);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    map['body'] = Variable<Uint8List>(body);
    return map;
  }

  RawResponseRecordsCompanion toCompanion(bool nullToAbsent) {
    return RawResponseRecordsCompanion(endpoint: Value(endpoint), fetchedAt: Value(fetchedAt), body: Value(body));
  }

  factory RawResponseRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawResponseRow(
      endpoint: serializer.fromJson<String>(json['endpoint']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
      body: serializer.fromJson<Uint8List>(json['body']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'endpoint': serializer.toJson<String>(endpoint),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
      'body': serializer.toJson<Uint8List>(body),
    };
  }

  RawResponseRow copyWith({String? endpoint, DateTime? fetchedAt, Uint8List? body}) => RawResponseRow(
    endpoint: endpoint ?? this.endpoint,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    body: body ?? this.body,
  );
  RawResponseRow copyWithCompanion(RawResponseRecordsCompanion data) {
    return RawResponseRow(
      endpoint: data.endpoint.present ? data.endpoint.value : this.endpoint,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      body: data.body.present ? data.body.value : this.body,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawResponseRow(')
          ..write('endpoint: $endpoint, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('body: $body')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(endpoint, fetchedAt, $driftBlobEquality.hash(body));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawResponseRow &&
          other.endpoint == this.endpoint &&
          other.fetchedAt == this.fetchedAt &&
          $driftBlobEquality.equals(other.body, this.body));
}

class RawResponseRecordsCompanion extends UpdateCompanion<RawResponseRow> {
  final Value<String> endpoint;
  final Value<DateTime> fetchedAt;
  final Value<Uint8List> body;
  final Value<int> rowid;
  const RawResponseRecordsCompanion({
    this.endpoint = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.body = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RawResponseRecordsCompanion.insert({
    required String endpoint,
    required DateTime fetchedAt,
    required Uint8List body,
    this.rowid = const Value.absent(),
  }) : endpoint = Value(endpoint),
       fetchedAt = Value(fetchedAt),
       body = Value(body);
  static Insertable<RawResponseRow> custom({
    Expression<String>? endpoint,
    Expression<DateTime>? fetchedAt,
    Expression<Uint8List>? body,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (endpoint != null) 'endpoint': endpoint,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (body != null) 'body': body,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RawResponseRecordsCompanion copyWith({
    Value<String>? endpoint,
    Value<DateTime>? fetchedAt,
    Value<Uint8List>? body,
    Value<int>? rowid,
  }) {
    return RawResponseRecordsCompanion(
      endpoint: endpoint ?? this.endpoint,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      body: body ?? this.body,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (endpoint.present) {
      map['endpoint'] = Variable<String>(endpoint.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (body.present) {
      map['body'] = Variable<Uint8List>(body.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawResponseRecordsCompanion(')
          ..write('endpoint: $endpoint, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('body: $body, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourceRecordsTable extends SourceRecords with TableInfo<$SourceRecordsTable, SourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta('provider');
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _externalIDMeta = const VerificationMeta('externalID');
  @override
  late final GeneratedColumn<String> externalID = GeneratedColumn<String>(
    'external_i_d',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
    'day_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<DateTime> start = GeneratedColumn<DateTime>(
    'start',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta('importedAt');
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta('contentHash');
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    key,
    provider,
    kind,
    externalID,
    dayKey,
    start,
    importedAt,
    updatedAt,
    contentHash,
    status,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_records';
  @override
  VerificationContext validateIntegrity(Insertable<SourceRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(_providerMeta, provider.isAcceptableOrUnknown(data['provider']!, _providerMeta));
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(_kindMeta, kind.isAcceptableOrUnknown(data['kind']!, _kindMeta));
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('external_i_d')) {
      context.handle(_externalIDMeta, externalID.isAcceptableOrUnknown(data['external_i_d']!, _externalIDMeta));
    } else if (isInserting) {
      context.missing(_externalIDMeta);
    }
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta, dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('start')) {
      context.handle(_startMeta, start.isAcceptableOrUnknown(data['start']!, _startMeta));
    }
    if (data.containsKey('imported_at')) {
      context.handle(_importedAtMeta, importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta));
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta, updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(_contentHashMeta, contentHash.isAcceptableOrUnknown(data['content_hash']!, _contentHashMeta));
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta, status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRow(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      provider: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}provider'])!,
      kind: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}kind'])!,
      externalID: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}external_i_d'])!,
      dayKey: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
      start: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}start']),
      importedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}imported_at'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      contentHash: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}content_hash'])!,
      status: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}payload']),
    );
  }

  @override
  $SourceRecordsTable createAlias(String alias) {
    return $SourceRecordsTable(attachedDatabase, alias);
  }
}

class SourceRow extends DataClass implements Insertable<SourceRow> {
  /// `provider|kind|externalID`
  final String key;
  final String provider;
  final String kind;
  final String externalID;
  final String dayKey;
  final DateTime? start;
  final DateTime importedAt;
  final DateTime updatedAt;
  final String contentHash;
  final String status;
  final Uint8List? payload;
  const SourceRow({
    required this.key,
    required this.provider,
    required this.kind,
    required this.externalID,
    required this.dayKey,
    this.start,
    required this.importedAt,
    required this.updatedAt,
    required this.contentHash,
    required this.status,
    this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['provider'] = Variable<String>(provider);
    map['kind'] = Variable<String>(kind);
    map['external_i_d'] = Variable<String>(externalID);
    map['day_key'] = Variable<String>(dayKey);
    if (!nullToAbsent || start != null) {
      map['start'] = Variable<DateTime>(start);
    }
    map['imported_at'] = Variable<DateTime>(importedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['content_hash'] = Variable<String>(contentHash);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<Uint8List>(payload);
    }
    return map;
  }

  SourceRecordsCompanion toCompanion(bool nullToAbsent) {
    return SourceRecordsCompanion(
      key: Value(key),
      provider: Value(provider),
      kind: Value(kind),
      externalID: Value(externalID),
      dayKey: Value(dayKey),
      start: start == null && nullToAbsent ? const Value.absent() : Value(start),
      importedAt: Value(importedAt),
      updatedAt: Value(updatedAt),
      contentHash: Value(contentHash),
      status: Value(status),
      payload: payload == null && nullToAbsent ? const Value.absent() : Value(payload),
    );
  }

  factory SourceRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRow(
      key: serializer.fromJson<String>(json['key']),
      provider: serializer.fromJson<String>(json['provider']),
      kind: serializer.fromJson<String>(json['kind']),
      externalID: serializer.fromJson<String>(json['externalID']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
      start: serializer.fromJson<DateTime?>(json['start']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      status: serializer.fromJson<String>(json['status']),
      payload: serializer.fromJson<Uint8List?>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'provider': serializer.toJson<String>(provider),
      'kind': serializer.toJson<String>(kind),
      'externalID': serializer.toJson<String>(externalID),
      'dayKey': serializer.toJson<String>(dayKey),
      'start': serializer.toJson<DateTime?>(start),
      'importedAt': serializer.toJson<DateTime>(importedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'contentHash': serializer.toJson<String>(contentHash),
      'status': serializer.toJson<String>(status),
      'payload': serializer.toJson<Uint8List?>(payload),
    };
  }

  SourceRow copyWith({
    String? key,
    String? provider,
    String? kind,
    String? externalID,
    String? dayKey,
    Value<DateTime?> start = const Value.absent(),
    DateTime? importedAt,
    DateTime? updatedAt,
    String? contentHash,
    String? status,
    Value<Uint8List?> payload = const Value.absent(),
  }) => SourceRow(
    key: key ?? this.key,
    provider: provider ?? this.provider,
    kind: kind ?? this.kind,
    externalID: externalID ?? this.externalID,
    dayKey: dayKey ?? this.dayKey,
    start: start.present ? start.value : this.start,
    importedAt: importedAt ?? this.importedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    contentHash: contentHash ?? this.contentHash,
    status: status ?? this.status,
    payload: payload.present ? payload.value : this.payload,
  );
  SourceRow copyWithCompanion(SourceRecordsCompanion data) {
    return SourceRow(
      key: data.key.present ? data.key.value : this.key,
      provider: data.provider.present ? data.provider.value : this.provider,
      kind: data.kind.present ? data.kind.value : this.kind,
      externalID: data.externalID.present ? data.externalID.value : this.externalID,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      start: data.start.present ? data.start.value : this.start,
      importedAt: data.importedAt.present ? data.importedAt.value : this.importedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      contentHash: data.contentHash.present ? data.contentHash.value : this.contentHash,
      status: data.status.present ? data.status.value : this.status,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRow(')
          ..write('key: $key, ')
          ..write('provider: $provider, ')
          ..write('kind: $kind, ')
          ..write('externalID: $externalID, ')
          ..write('dayKey: $dayKey, ')
          ..write('start: $start, ')
          ..write('importedAt: $importedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('contentHash: $contentHash, ')
          ..write('status: $status, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    key,
    provider,
    kind,
    externalID,
    dayKey,
    start,
    importedAt,
    updatedAt,
    contentHash,
    status,
    $driftBlobEquality.hash(payload),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRow &&
          other.key == this.key &&
          other.provider == this.provider &&
          other.kind == this.kind &&
          other.externalID == this.externalID &&
          other.dayKey == this.dayKey &&
          other.start == this.start &&
          other.importedAt == this.importedAt &&
          other.updatedAt == this.updatedAt &&
          other.contentHash == this.contentHash &&
          other.status == this.status &&
          $driftBlobEquality.equals(other.payload, this.payload));
}

class SourceRecordsCompanion extends UpdateCompanion<SourceRow> {
  final Value<String> key;
  final Value<String> provider;
  final Value<String> kind;
  final Value<String> externalID;
  final Value<String> dayKey;
  final Value<DateTime?> start;
  final Value<DateTime> importedAt;
  final Value<DateTime> updatedAt;
  final Value<String> contentHash;
  final Value<String> status;
  final Value<Uint8List?> payload;
  final Value<int> rowid;
  const SourceRecordsCompanion({
    this.key = const Value.absent(),
    this.provider = const Value.absent(),
    this.kind = const Value.absent(),
    this.externalID = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.start = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.status = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceRecordsCompanion.insert({
    required String key,
    required String provider,
    required String kind,
    required String externalID,
    required String dayKey,
    this.start = const Value.absent(),
    required DateTime importedAt,
    required DateTime updatedAt,
    required String contentHash,
    required String status,
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       provider = Value(provider),
       kind = Value(kind),
       externalID = Value(externalID),
       dayKey = Value(dayKey),
       importedAt = Value(importedAt),
       updatedAt = Value(updatedAt),
       contentHash = Value(contentHash),
       status = Value(status);
  static Insertable<SourceRow> custom({
    Expression<String>? key,
    Expression<String>? provider,
    Expression<String>? kind,
    Expression<String>? externalID,
    Expression<String>? dayKey,
    Expression<DateTime>? start,
    Expression<DateTime>? importedAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? contentHash,
    Expression<String>? status,
    Expression<Uint8List>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (provider != null) 'provider': provider,
      if (kind != null) 'kind': kind,
      if (externalID != null) 'external_i_d': externalID,
      if (dayKey != null) 'day_key': dayKey,
      if (start != null) 'start': start,
      if (importedAt != null) 'imported_at': importedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (contentHash != null) 'content_hash': contentHash,
      if (status != null) 'status': status,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceRecordsCompanion copyWith({
    Value<String>? key,
    Value<String>? provider,
    Value<String>? kind,
    Value<String>? externalID,
    Value<String>? dayKey,
    Value<DateTime?>? start,
    Value<DateTime>? importedAt,
    Value<DateTime>? updatedAt,
    Value<String>? contentHash,
    Value<String>? status,
    Value<Uint8List?>? payload,
    Value<int>? rowid,
  }) {
    return SourceRecordsCompanion(
      key: key ?? this.key,
      provider: provider ?? this.provider,
      kind: kind ?? this.kind,
      externalID: externalID ?? this.externalID,
      dayKey: dayKey ?? this.dayKey,
      start: start ?? this.start,
      importedAt: importedAt ?? this.importedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      contentHash: contentHash ?? this.contentHash,
      status: status ?? this.status,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (externalID.present) {
      map['external_i_d'] = Variable<String>(externalID.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (start.present) {
      map['start'] = Variable<DateTime>(start.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceRecordsCompanion(')
          ..write('key: $key, ')
          ..write('provider: $provider, ')
          ..write('kind: $kind, ')
          ..write('externalID: $externalID, ')
          ..write('dayKey: $dayKey, ')
          ..write('start: $start, ')
          ..write('importedAt: $importedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('contentHash: $contentHash, ')
          ..write('status: $status, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MealRecordsTable extends MealRecords with TableInfo<$MealRecordsTable, MealRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MealRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
    'day_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryRawMeta = const VerificationMeta('categoryRaw');
  @override
  late final GeneratedColumn<String> categoryRaw = GeneratedColumn<String>(
    'category_raw',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hintMeta = const VerificationMeta('hint');
  @override
  late final GeneratedColumn<String> hint = GeneratedColumn<String>(
    'hint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemsPayloadMeta = const VerificationMeta('itemsPayload');
  @override
  late final GeneratedColumn<Uint8List> itemsPayload = GeneratedColumn<Uint8List>(
    'items_payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, dayKey, createdAt, categoryRaw, title, hint, itemsPayload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meal_records';
  @override
  VerificationContext validateIntegrity(Insertable<MealRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta, dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta, createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('category_raw')) {
      context.handle(_categoryRawMeta, categoryRaw.isAcceptableOrUnknown(data['category_raw']!, _categoryRawMeta));
    } else if (isInserting) {
      context.missing(_categoryRawMeta);
    }
    if (data.containsKey('title')) {
      context.handle(_titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('hint')) {
      context.handle(_hintMeta, hint.isAcceptableOrUnknown(data['hint']!, _hintMeta));
    } else if (isInserting) {
      context.missing(_hintMeta);
    }
    if (data.containsKey('items_payload')) {
      context.handle(_itemsPayloadMeta, itemsPayload.isAcceptableOrUnknown(data['items_payload']!, _itemsPayloadMeta));
    } else if (isInserting) {
      context.missing(_itemsPayloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MealRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MealRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      dayKey: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      categoryRaw: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}category_raw'])!,
      title: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      hint: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}hint'])!,
      itemsPayload: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}items_payload'])!,
    );
  }

  @override
  $MealRecordsTable createAlias(String alias) {
    return $MealRecordsTable(attachedDatabase, alias);
  }
}

class MealRow extends DataClass implements Insertable<MealRow> {
  final String id;
  final String dayKey;
  final DateTime createdAt;
  final String categoryRaw;
  final String title;
  final String hint;
  final Uint8List itemsPayload;
  const MealRow({
    required this.id,
    required this.dayKey,
    required this.createdAt,
    required this.categoryRaw,
    required this.title,
    required this.hint,
    required this.itemsPayload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['day_key'] = Variable<String>(dayKey);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['category_raw'] = Variable<String>(categoryRaw);
    map['title'] = Variable<String>(title);
    map['hint'] = Variable<String>(hint);
    map['items_payload'] = Variable<Uint8List>(itemsPayload);
    return map;
  }

  MealRecordsCompanion toCompanion(bool nullToAbsent) {
    return MealRecordsCompanion(
      id: Value(id),
      dayKey: Value(dayKey),
      createdAt: Value(createdAt),
      categoryRaw: Value(categoryRaw),
      title: Value(title),
      hint: Value(hint),
      itemsPayload: Value(itemsPayload),
    );
  }

  factory MealRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MealRow(
      id: serializer.fromJson<String>(json['id']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      categoryRaw: serializer.fromJson<String>(json['categoryRaw']),
      title: serializer.fromJson<String>(json['title']),
      hint: serializer.fromJson<String>(json['hint']),
      itemsPayload: serializer.fromJson<Uint8List>(json['itemsPayload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dayKey': serializer.toJson<String>(dayKey),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'categoryRaw': serializer.toJson<String>(categoryRaw),
      'title': serializer.toJson<String>(title),
      'hint': serializer.toJson<String>(hint),
      'itemsPayload': serializer.toJson<Uint8List>(itemsPayload),
    };
  }

  MealRow copyWith({
    String? id,
    String? dayKey,
    DateTime? createdAt,
    String? categoryRaw,
    String? title,
    String? hint,
    Uint8List? itemsPayload,
  }) => MealRow(
    id: id ?? this.id,
    dayKey: dayKey ?? this.dayKey,
    createdAt: createdAt ?? this.createdAt,
    categoryRaw: categoryRaw ?? this.categoryRaw,
    title: title ?? this.title,
    hint: hint ?? this.hint,
    itemsPayload: itemsPayload ?? this.itemsPayload,
  );
  MealRow copyWithCompanion(MealRecordsCompanion data) {
    return MealRow(
      id: data.id.present ? data.id.value : this.id,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      categoryRaw: data.categoryRaw.present ? data.categoryRaw.value : this.categoryRaw,
      title: data.title.present ? data.title.value : this.title,
      hint: data.hint.present ? data.hint.value : this.hint,
      itemsPayload: data.itemsPayload.present ? data.itemsPayload.value : this.itemsPayload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MealRow(')
          ..write('id: $id, ')
          ..write('dayKey: $dayKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('categoryRaw: $categoryRaw, ')
          ..write('title: $title, ')
          ..write('hint: $hint, ')
          ..write('itemsPayload: $itemsPayload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, dayKey, createdAt, categoryRaw, title, hint, $driftBlobEquality.hash(itemsPayload));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MealRow &&
          other.id == this.id &&
          other.dayKey == this.dayKey &&
          other.createdAt == this.createdAt &&
          other.categoryRaw == this.categoryRaw &&
          other.title == this.title &&
          other.hint == this.hint &&
          $driftBlobEquality.equals(other.itemsPayload, this.itemsPayload));
}

class MealRecordsCompanion extends UpdateCompanion<MealRow> {
  final Value<String> id;
  final Value<String> dayKey;
  final Value<DateTime> createdAt;
  final Value<String> categoryRaw;
  final Value<String> title;
  final Value<String> hint;
  final Value<Uint8List> itemsPayload;
  final Value<int> rowid;
  const MealRecordsCompanion({
    this.id = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.categoryRaw = const Value.absent(),
    this.title = const Value.absent(),
    this.hint = const Value.absent(),
    this.itemsPayload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MealRecordsCompanion.insert({
    required String id,
    required String dayKey,
    required DateTime createdAt,
    required String categoryRaw,
    required String title,
    required String hint,
    required Uint8List itemsPayload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dayKey = Value(dayKey),
       createdAt = Value(createdAt),
       categoryRaw = Value(categoryRaw),
       title = Value(title),
       hint = Value(hint),
       itemsPayload = Value(itemsPayload);
  static Insertable<MealRow> custom({
    Expression<String>? id,
    Expression<String>? dayKey,
    Expression<DateTime>? createdAt,
    Expression<String>? categoryRaw,
    Expression<String>? title,
    Expression<String>? hint,
    Expression<Uint8List>? itemsPayload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dayKey != null) 'day_key': dayKey,
      if (createdAt != null) 'created_at': createdAt,
      if (categoryRaw != null) 'category_raw': categoryRaw,
      if (title != null) 'title': title,
      if (hint != null) 'hint': hint,
      if (itemsPayload != null) 'items_payload': itemsPayload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MealRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? dayKey,
    Value<DateTime>? createdAt,
    Value<String>? categoryRaw,
    Value<String>? title,
    Value<String>? hint,
    Value<Uint8List>? itemsPayload,
    Value<int>? rowid,
  }) {
    return MealRecordsCompanion(
      id: id ?? this.id,
      dayKey: dayKey ?? this.dayKey,
      createdAt: createdAt ?? this.createdAt,
      categoryRaw: categoryRaw ?? this.categoryRaw,
      title: title ?? this.title,
      hint: hint ?? this.hint,
      itemsPayload: itemsPayload ?? this.itemsPayload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (categoryRaw.present) {
      map['category_raw'] = Variable<String>(categoryRaw.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (hint.present) {
      map['hint'] = Variable<String>(hint.value);
    }
    if (itemsPayload.present) {
      map['items_payload'] = Variable<Uint8List>(itemsPayload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MealRecordsCompanion(')
          ..write('id: $id, ')
          ..write('dayKey: $dayKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('categoryRaw: $categoryRaw, ')
          ..write('title: $title, ')
          ..write('hint: $hint, ')
          ..write('itemsPayload: $itemsPayload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoodRecordsTable extends FoodRecords with TableInfo<$FoodRecordsTable, FoodRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedMeta = const VerificationMeta('lastUsed');
  @override
  late final GeneratedColumn<DateTime> lastUsed = GeneratedColumn<DateTime>(
    'last_used',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _useCountMeta = const VerificationMeta('useCount');
  @override
  late final GeneratedColumn<int> useCount = GeneratedColumn<int>(
    'use_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, name, payload, lastUsed, useCount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'food_records';
  @override
  VerificationContext validateIntegrity(Insertable<FoodRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('last_used')) {
      context.handle(_lastUsedMeta, lastUsed.isAcceptableOrUnknown(data['last_used']!, _lastUsedMeta));
    } else if (isInserting) {
      context.missing(_lastUsedMeta);
    }
    if (data.containsKey('use_count')) {
      context.handle(_useCountMeta, useCount.isAcceptableOrUnknown(data['use_count']!, _useCountMeta));
    } else if (isInserting) {
      context.missing(_useCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  FoodRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodRow(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}payload'])!,
      lastUsed: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}last_used'])!,
      useCount: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}use_count'])!,
    );
  }

  @override
  $FoodRecordsTable createAlias(String alias) {
    return $FoodRecordsTable(attachedDatabase, alias);
  }
}

class FoodRow extends DataClass implements Insertable<FoodRow> {
  final String key;
  final String name;
  final Uint8List payload;
  final DateTime lastUsed;
  final int useCount;
  const FoodRow({
    required this.key,
    required this.name,
    required this.payload,
    required this.lastUsed,
    required this.useCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['name'] = Variable<String>(name);
    map['payload'] = Variable<Uint8List>(payload);
    map['last_used'] = Variable<DateTime>(lastUsed);
    map['use_count'] = Variable<int>(useCount);
    return map;
  }

  FoodRecordsCompanion toCompanion(bool nullToAbsent) {
    return FoodRecordsCompanion(
      key: Value(key),
      name: Value(name),
      payload: Value(payload),
      lastUsed: Value(lastUsed),
      useCount: Value(useCount),
    );
  }

  factory FoodRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodRow(
      key: serializer.fromJson<String>(json['key']),
      name: serializer.fromJson<String>(json['name']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      lastUsed: serializer.fromJson<DateTime>(json['lastUsed']),
      useCount: serializer.fromJson<int>(json['useCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'name': serializer.toJson<String>(name),
      'payload': serializer.toJson<Uint8List>(payload),
      'lastUsed': serializer.toJson<DateTime>(lastUsed),
      'useCount': serializer.toJson<int>(useCount),
    };
  }

  FoodRow copyWith({String? key, String? name, Uint8List? payload, DateTime? lastUsed, int? useCount}) => FoodRow(
    key: key ?? this.key,
    name: name ?? this.name,
    payload: payload ?? this.payload,
    lastUsed: lastUsed ?? this.lastUsed,
    useCount: useCount ?? this.useCount,
  );
  FoodRow copyWithCompanion(FoodRecordsCompanion data) {
    return FoodRow(
      key: data.key.present ? data.key.value : this.key,
      name: data.name.present ? data.name.value : this.name,
      payload: data.payload.present ? data.payload.value : this.payload,
      lastUsed: data.lastUsed.present ? data.lastUsed.value : this.lastUsed,
      useCount: data.useCount.present ? data.useCount.value : this.useCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodRow(')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('lastUsed: $lastUsed, ')
          ..write('useCount: $useCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, name, $driftBlobEquality.hash(payload), lastUsed, useCount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodRow &&
          other.key == this.key &&
          other.name == this.name &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.lastUsed == this.lastUsed &&
          other.useCount == this.useCount);
}

class FoodRecordsCompanion extends UpdateCompanion<FoodRow> {
  final Value<String> key;
  final Value<String> name;
  final Value<Uint8List> payload;
  final Value<DateTime> lastUsed;
  final Value<int> useCount;
  final Value<int> rowid;
  const FoodRecordsCompanion({
    this.key = const Value.absent(),
    this.name = const Value.absent(),
    this.payload = const Value.absent(),
    this.lastUsed = const Value.absent(),
    this.useCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodRecordsCompanion.insert({
    required String key,
    required String name,
    required Uint8List payload,
    required DateTime lastUsed,
    required int useCount,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       name = Value(name),
       payload = Value(payload),
       lastUsed = Value(lastUsed),
       useCount = Value(useCount);
  static Insertable<FoodRow> custom({
    Expression<String>? key,
    Expression<String>? name,
    Expression<Uint8List>? payload,
    Expression<DateTime>? lastUsed,
    Expression<int>? useCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (name != null) 'name': name,
      if (payload != null) 'payload': payload,
      if (lastUsed != null) 'last_used': lastUsed,
      if (useCount != null) 'use_count': useCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodRecordsCompanion copyWith({
    Value<String>? key,
    Value<String>? name,
    Value<Uint8List>? payload,
    Value<DateTime>? lastUsed,
    Value<int>? useCount,
    Value<int>? rowid,
  }) {
    return FoodRecordsCompanion(
      key: key ?? this.key,
      name: name ?? this.name,
      payload: payload ?? this.payload,
      lastUsed: lastUsed ?? this.lastUsed,
      useCount: useCount ?? this.useCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (lastUsed.present) {
      map['last_used'] = Variable<DateTime>(lastUsed.value);
    }
    if (useCount.present) {
      map['use_count'] = Variable<int>(useCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodRecordsCompanion(')
          ..write('key: $key, ')
          ..write('name: $name, ')
          ..write('payload: $payload, ')
          ..write('lastUsed: $lastUsed, ')
          ..write('useCount: $useCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GymSessionRecordsTable extends GymSessionRecords with TableInfo<$GymSessionRecordsTable, GymSessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GymSessionRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
    'day_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startMeta = const VerificationMeta('start');
  @override
  late final GeneratedColumn<DateTime> start = GeneratedColumn<DateTime>(
    'start',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedToHealthMeta = const VerificationMeta('savedToHealth');
  @override
  late final GeneratedColumn<bool> savedToHealth = GeneratedColumn<bool>(
    'saved_to_health',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("saved_to_health" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _uploadedToGarminMeta = const VerificationMeta('uploadedToGarmin');
  @override
  late final GeneratedColumn<bool> uploadedToGarmin = GeneratedColumn<bool>(
    'uploaded_to_garmin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("uploaded_to_garmin" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [id, dayKey, start, payload, savedToHealth, uploadedToGarmin];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gym_session_records';
  @override
  VerificationContext validateIntegrity(Insertable<GymSessionRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta, dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('start')) {
      context.handle(_startMeta, start.isAcceptableOrUnknown(data['start']!, _startMeta));
    } else if (isInserting) {
      context.missing(_startMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('saved_to_health')) {
      context.handle(
        _savedToHealthMeta,
        savedToHealth.isAcceptableOrUnknown(data['saved_to_health']!, _savedToHealthMeta),
      );
    }
    if (data.containsKey('uploaded_to_garmin')) {
      context.handle(
        _uploadedToGarminMeta,
        uploadedToGarmin.isAcceptableOrUnknown(data['uploaded_to_garmin']!, _uploadedToGarminMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GymSessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GymSessionRow(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      dayKey: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
      start: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}start'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}payload'])!,
      savedToHealth: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}saved_to_health'])!,
      uploadedToGarmin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}uploaded_to_garmin'],
      )!,
    );
  }

  @override
  $GymSessionRecordsTable createAlias(String alias) {
    return $GymSessionRecordsTable(attachedDatabase, alias);
  }
}

class GymSessionRow extends DataClass implements Insertable<GymSessionRow> {
  final String id;
  final String dayKey;
  final DateTime start;
  final Uint8List payload;

  /// In Apple Health bzw. Health Connect gespeichert.
  final bool savedToHealth;

  /// Als Krafttraining nach Garmin Connect übertragen.
  final bool uploadedToGarmin;
  const GymSessionRow({
    required this.id,
    required this.dayKey,
    required this.start,
    required this.payload,
    required this.savedToHealth,
    required this.uploadedToGarmin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['day_key'] = Variable<String>(dayKey);
    map['start'] = Variable<DateTime>(start);
    map['payload'] = Variable<Uint8List>(payload);
    map['saved_to_health'] = Variable<bool>(savedToHealth);
    map['uploaded_to_garmin'] = Variable<bool>(uploadedToGarmin);
    return map;
  }

  GymSessionRecordsCompanion toCompanion(bool nullToAbsent) {
    return GymSessionRecordsCompanion(
      id: Value(id),
      dayKey: Value(dayKey),
      start: Value(start),
      payload: Value(payload),
      savedToHealth: Value(savedToHealth),
      uploadedToGarmin: Value(uploadedToGarmin),
    );
  }

  factory GymSessionRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GymSessionRow(
      id: serializer.fromJson<String>(json['id']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
      start: serializer.fromJson<DateTime>(json['start']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      savedToHealth: serializer.fromJson<bool>(json['savedToHealth']),
      uploadedToGarmin: serializer.fromJson<bool>(json['uploadedToGarmin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'dayKey': serializer.toJson<String>(dayKey),
      'start': serializer.toJson<DateTime>(start),
      'payload': serializer.toJson<Uint8List>(payload),
      'savedToHealth': serializer.toJson<bool>(savedToHealth),
      'uploadedToGarmin': serializer.toJson<bool>(uploadedToGarmin),
    };
  }

  GymSessionRow copyWith({
    String? id,
    String? dayKey,
    DateTime? start,
    Uint8List? payload,
    bool? savedToHealth,
    bool? uploadedToGarmin,
  }) => GymSessionRow(
    id: id ?? this.id,
    dayKey: dayKey ?? this.dayKey,
    start: start ?? this.start,
    payload: payload ?? this.payload,
    savedToHealth: savedToHealth ?? this.savedToHealth,
    uploadedToGarmin: uploadedToGarmin ?? this.uploadedToGarmin,
  );
  GymSessionRow copyWithCompanion(GymSessionRecordsCompanion data) {
    return GymSessionRow(
      id: data.id.present ? data.id.value : this.id,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      start: data.start.present ? data.start.value : this.start,
      payload: data.payload.present ? data.payload.value : this.payload,
      savedToHealth: data.savedToHealth.present ? data.savedToHealth.value : this.savedToHealth,
      uploadedToGarmin: data.uploadedToGarmin.present ? data.uploadedToGarmin.value : this.uploadedToGarmin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GymSessionRow(')
          ..write('id: $id, ')
          ..write('dayKey: $dayKey, ')
          ..write('start: $start, ')
          ..write('payload: $payload, ')
          ..write('savedToHealth: $savedToHealth, ')
          ..write('uploadedToGarmin: $uploadedToGarmin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, dayKey, start, $driftBlobEquality.hash(payload), savedToHealth, uploadedToGarmin);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GymSessionRow &&
          other.id == this.id &&
          other.dayKey == this.dayKey &&
          other.start == this.start &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.savedToHealth == this.savedToHealth &&
          other.uploadedToGarmin == this.uploadedToGarmin);
}

class GymSessionRecordsCompanion extends UpdateCompanion<GymSessionRow> {
  final Value<String> id;
  final Value<String> dayKey;
  final Value<DateTime> start;
  final Value<Uint8List> payload;
  final Value<bool> savedToHealth;
  final Value<bool> uploadedToGarmin;
  final Value<int> rowid;
  const GymSessionRecordsCompanion({
    this.id = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.start = const Value.absent(),
    this.payload = const Value.absent(),
    this.savedToHealth = const Value.absent(),
    this.uploadedToGarmin = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GymSessionRecordsCompanion.insert({
    required String id,
    required String dayKey,
    required DateTime start,
    required Uint8List payload,
    this.savedToHealth = const Value.absent(),
    this.uploadedToGarmin = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       dayKey = Value(dayKey),
       start = Value(start),
       payload = Value(payload);
  static Insertable<GymSessionRow> custom({
    Expression<String>? id,
    Expression<String>? dayKey,
    Expression<DateTime>? start,
    Expression<Uint8List>? payload,
    Expression<bool>? savedToHealth,
    Expression<bool>? uploadedToGarmin,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dayKey != null) 'day_key': dayKey,
      if (start != null) 'start': start,
      if (payload != null) 'payload': payload,
      if (savedToHealth != null) 'saved_to_health': savedToHealth,
      if (uploadedToGarmin != null) 'uploaded_to_garmin': uploadedToGarmin,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GymSessionRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? dayKey,
    Value<DateTime>? start,
    Value<Uint8List>? payload,
    Value<bool>? savedToHealth,
    Value<bool>? uploadedToGarmin,
    Value<int>? rowid,
  }) {
    return GymSessionRecordsCompanion(
      id: id ?? this.id,
      dayKey: dayKey ?? this.dayKey,
      start: start ?? this.start,
      payload: payload ?? this.payload,
      savedToHealth: savedToHealth ?? this.savedToHealth,
      uploadedToGarmin: uploadedToGarmin ?? this.uploadedToGarmin,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (start.present) {
      map['start'] = Variable<DateTime>(start.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (savedToHealth.present) {
      map['saved_to_health'] = Variable<bool>(savedToHealth.value);
    }
    if (uploadedToGarmin.present) {
      map['uploaded_to_garmin'] = Variable<bool>(uploadedToGarmin.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GymSessionRecordsCompanion(')
          ..write('id: $id, ')
          ..write('dayKey: $dayKey, ')
          ..write('start: $start, ')
          ..write('payload: $payload, ')
          ..write('savedToHealth: $savedToHealth, ')
          ..write('uploadedToGarmin: $uploadedToGarmin, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingRecordsTable extends SettingRecords with TableInfo<$SettingRecordsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<Uint8List> value = GeneratedColumn<Uint8List>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, type, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setting_records';
  @override
  VerificationContext validateIntegrity(Insertable<SettingRow> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('type')) {
      context.handle(_typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      type: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      value: attachedDatabase.typeMapping.read(DriftSqlType.blob, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $SettingRecordsTable createAlias(String alias) {
    return $SettingRecordsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;

  /// `data`, `string`, `bool`, `int` oder `double`.
  final String type;

  /// Bei `data` die Bytes (meist JSON), sonst der Wert als UTF-8-Text.
  final Uint8List value;
  const SettingRow({required this.key, required this.type, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['type'] = Variable<String>(type);
    map['value'] = Variable<Uint8List>(value);
    return map;
  }

  SettingRecordsCompanion toCompanion(bool nullToAbsent) {
    return SettingRecordsCompanion(key: Value(key), type: Value(type), value: Value(value));
  }

  factory SettingRow.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      type: serializer.fromJson<String>(json['type']),
      value: serializer.fromJson<Uint8List>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'type': serializer.toJson<String>(type),
      'value': serializer.toJson<Uint8List>(value),
    };
  }

  SettingRow copyWith({String? key, String? type, Uint8List? value}) =>
      SettingRow(key: key ?? this.key, type: type ?? this.type, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingRecordsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      type: data.type.present ? data.type.value : this.type,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('type: $type, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, type, $driftBlobEquality.hash(value));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.type == this.type &&
          $driftBlobEquality.equals(other.value, this.value));
}

class SettingRecordsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> type;
  final Value<Uint8List> value;
  final Value<int> rowid;
  const SettingRecordsCompanion({
    this.key = const Value.absent(),
    this.type = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingRecordsCompanion.insert({
    required String key,
    required String type,
    required Uint8List value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       type = Value(type),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? type,
    Expression<Uint8List>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (type != null) 'type': type,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingRecordsCompanion copyWith({
    Value<String>? key,
    Value<String>? type,
    Value<Uint8List>? value,
    Value<int>? rowid,
  }) {
    return SettingRecordsCompanion(
      key: key ?? this.key,
      type: type ?? this.type,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (value.present) {
      map['value'] = Variable<Uint8List>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingRecordsCompanion(')
          ..write('key: $key, ')
          ..write('type: $type, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CoachDatabase extends GeneratedDatabase {
  _$CoachDatabase(QueryExecutor e) : super(e);
  $CoachDatabaseManager get managers => $CoachDatabaseManager(this);
  late final $DailyMetricsRecordsTable dailyMetricsRecords = $DailyMetricsRecordsTable(this);
  late final $ActivityRecordsTable activityRecords = $ActivityRecordsTable(this);
  late final $RawResponseRecordsTable rawResponseRecords = $RawResponseRecordsTable(this);
  late final $SourceRecordsTable sourceRecords = $SourceRecordsTable(this);
  late final $MealRecordsTable mealRecords = $MealRecordsTable(this);
  late final $FoodRecordsTable foodRecords = $FoodRecordsTable(this);
  late final $GymSessionRecordsTable gymSessionRecords = $GymSessionRecordsTable(this);
  late final $SettingRecordsTable settingRecords = $SettingRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dailyMetricsRecords,
    activityRecords,
    rawResponseRecords,
    sourceRecords,
    mealRecords,
    foodRecords,
    gymSessionRecords,
    settingRecords,
  ];
}

typedef $$DailyMetricsRecordsTableCreateCompanionBuilder = DailyMetricsRecordsCompanion Function({
  required String dayKey,
  required Uint8List payload,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$DailyMetricsRecordsTableUpdateCompanionBuilder = DailyMetricsRecordsCompanion Function({
  Value<String> dayKey,
  Value<Uint8List> payload,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$DailyMetricsRecordsTableFilterComposer extends Composer<_$CoachDatabase, $DailyMetricsRecordsTable> {
  $$DailyMetricsRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$DailyMetricsRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $DailyMetricsRecordsTable> {
  $$DailyMetricsRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$DailyMetricsRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $DailyMetricsRecordsTable> {
  $$DailyMetricsRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get dayKey => $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt => $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DailyMetricsRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $DailyMetricsRecordsTable,
          DailyMetricsRow,
          $$DailyMetricsRecordsTableFilterComposer,
          $$DailyMetricsRecordsTableOrderingComposer,
          $$DailyMetricsRecordsTableAnnotationComposer,
          $$DailyMetricsRecordsTableCreateCompanionBuilder,
          $$DailyMetricsRecordsTableUpdateCompanionBuilder,
          (DailyMetricsRow, BaseReferences<_$CoachDatabase, $DailyMetricsRecordsTable, DailyMetricsRow>),
          DailyMetricsRow,
          PrefetchHooks Function()
        > {
  $$DailyMetricsRecordsTableTableManager(_$CoachDatabase db, $DailyMetricsRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$DailyMetricsRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$DailyMetricsRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$DailyMetricsRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> dayKey = const Value.absent(),
            Value<Uint8List> payload = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => DailyMetricsRecordsCompanion(dayKey: dayKey, payload: payload, updatedAt: updatedAt, rowid: rowid),
          createCompanionCallback:
              ({
                required String dayKey,
                required Uint8List payload,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DailyMetricsRecordsCompanion.insert(
                dayKey: dayKey,
                payload: payload,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailyMetricsRecordsTable, DailyMetricsRow>(table),
                  BaseReferences<_$CoachDatabase, $DailyMetricsRecordsTable, DailyMetricsRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyMetricsRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $DailyMetricsRecordsTable,
      DailyMetricsRow,
      $$DailyMetricsRecordsTableFilterComposer,
      $$DailyMetricsRecordsTableOrderingComposer,
      $$DailyMetricsRecordsTableAnnotationComposer,
      $$DailyMetricsRecordsTableCreateCompanionBuilder,
      $$DailyMetricsRecordsTableUpdateCompanionBuilder,
      (DailyMetricsRow, BaseReferences<_$CoachDatabase, $DailyMetricsRecordsTable, DailyMetricsRow>),
      DailyMetricsRow,
      PrefetchHooks Function()
    >;
typedef $$ActivityRecordsTableCreateCompanionBuilder = ActivityRecordsCompanion Function({
  Value<int> garminID,
  required String dayKey,
  required String startLocal,
  required Uint8List payload,
});
typedef $$ActivityRecordsTableUpdateCompanionBuilder = ActivityRecordsCompanion Function({
  Value<int> garminID,
  Value<String> dayKey,
  Value<String> startLocal,
  Value<Uint8List> payload,
});

class $$ActivityRecordsTableFilterComposer extends Composer<_$CoachDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get garminID =>
      $composableBuilder(column: $table.garminID, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get startLocal =>
      $composableBuilder(column: $table.startLocal, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$ActivityRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get garminID =>
      $composableBuilder(column: $table.garminID, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get startLocal =>
      $composableBuilder(column: $table.startLocal, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$ActivityRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $ActivityRecordsTable> {
  $$ActivityRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get garminID => $composableBuilder(column: $table.garminID, builder: (column) => column);

  GeneratedColumn<String> get dayKey => $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<String> get startLocal => $composableBuilder(column: $table.startLocal, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$ActivityRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $ActivityRecordsTable,
          ActivityRow,
          $$ActivityRecordsTableFilterComposer,
          $$ActivityRecordsTableOrderingComposer,
          $$ActivityRecordsTableAnnotationComposer,
          $$ActivityRecordsTableCreateCompanionBuilder,
          $$ActivityRecordsTableUpdateCompanionBuilder,
          (ActivityRow, BaseReferences<_$CoachDatabase, $ActivityRecordsTable, ActivityRow>),
          ActivityRow,
          PrefetchHooks Function()
        > {
  $$ActivityRecordsTableTableManager(_$CoachDatabase db, $ActivityRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ActivityRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ActivityRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$ActivityRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> garminID = const Value.absent(),
            Value<String> dayKey = const Value.absent(),
            Value<String> startLocal = const Value.absent(),
            Value<Uint8List> payload = const Value.absent(),
          }) => ActivityRecordsCompanion(garminID: garminID, dayKey: dayKey, startLocal: startLocal, payload: payload),
          createCompanionCallback:
              ({
                Value<int> garminID = const Value.absent(),
                required String dayKey,
                required String startLocal,
                required Uint8List payload,
              }) => ActivityRecordsCompanion.insert(
                garminID: garminID,
                dayKey: dayKey,
                startLocal: startLocal,
                payload: payload,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ActivityRecordsTable, ActivityRow>(table),
                  BaseReferences<_$CoachDatabase, $ActivityRecordsTable, ActivityRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ActivityRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $ActivityRecordsTable,
      ActivityRow,
      $$ActivityRecordsTableFilterComposer,
      $$ActivityRecordsTableOrderingComposer,
      $$ActivityRecordsTableAnnotationComposer,
      $$ActivityRecordsTableCreateCompanionBuilder,
      $$ActivityRecordsTableUpdateCompanionBuilder,
      (ActivityRow, BaseReferences<_$CoachDatabase, $ActivityRecordsTable, ActivityRow>),
      ActivityRow,
      PrefetchHooks Function()
    >;
typedef $$RawResponseRecordsTableCreateCompanionBuilder = RawResponseRecordsCompanion Function({
  required String endpoint,
  required DateTime fetchedAt,
  required Uint8List body,
  Value<int> rowid,
});
typedef $$RawResponseRecordsTableUpdateCompanionBuilder = RawResponseRecordsCompanion Function({
  Value<String> endpoint,
  Value<DateTime> fetchedAt,
  Value<Uint8List> body,
  Value<int> rowid,
});

class $$RawResponseRecordsTableFilterComposer extends Composer<_$CoachDatabase, $RawResponseRecordsTable> {
  $$RawResponseRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get endpoint =>
      $composableBuilder(column: $table.endpoint, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get body =>
      $composableBuilder(column: $table.body, builder: (column) => ColumnFilters(column));
}

class $$RawResponseRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $RawResponseRecordsTable> {
  $$RawResponseRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get endpoint =>
      $composableBuilder(column: $table.endpoint, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get body =>
      $composableBuilder(column: $table.body, builder: (column) => ColumnOrderings(column));
}

class $$RawResponseRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $RawResponseRecordsTable> {
  $$RawResponseRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get endpoint => $composableBuilder(column: $table.endpoint, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt => $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<Uint8List> get body => $composableBuilder(column: $table.body, builder: (column) => column);
}

class $$RawResponseRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $RawResponseRecordsTable,
          RawResponseRow,
          $$RawResponseRecordsTableFilterComposer,
          $$RawResponseRecordsTableOrderingComposer,
          $$RawResponseRecordsTableAnnotationComposer,
          $$RawResponseRecordsTableCreateCompanionBuilder,
          $$RawResponseRecordsTableUpdateCompanionBuilder,
          (RawResponseRow, BaseReferences<_$CoachDatabase, $RawResponseRecordsTable, RawResponseRow>),
          RawResponseRow,
          PrefetchHooks Function()
        > {
  $$RawResponseRecordsTableTableManager(_$CoachDatabase db, $RawResponseRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$RawResponseRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$RawResponseRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$RawResponseRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> endpoint = const Value.absent(),
            Value<DateTime> fetchedAt = const Value.absent(),
            Value<Uint8List> body = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => RawResponseRecordsCompanion(endpoint: endpoint, fetchedAt: fetchedAt, body: body, rowid: rowid),
          createCompanionCallback: ({
            required String endpoint,
            required DateTime fetchedAt,
            required Uint8List body,
            Value<int> rowid = const Value.absent(),
          }) => RawResponseRecordsCompanion.insert(endpoint: endpoint, fetchedAt: fetchedAt, body: body, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RawResponseRecordsTable, RawResponseRow>(table),
                  BaseReferences<_$CoachDatabase, $RawResponseRecordsTable, RawResponseRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RawResponseRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $RawResponseRecordsTable,
      RawResponseRow,
      $$RawResponseRecordsTableFilterComposer,
      $$RawResponseRecordsTableOrderingComposer,
      $$RawResponseRecordsTableAnnotationComposer,
      $$RawResponseRecordsTableCreateCompanionBuilder,
      $$RawResponseRecordsTableUpdateCompanionBuilder,
      (RawResponseRow, BaseReferences<_$CoachDatabase, $RawResponseRecordsTable, RawResponseRow>),
      RawResponseRow,
      PrefetchHooks Function()
    >;
typedef $$SourceRecordsTableCreateCompanionBuilder = SourceRecordsCompanion Function({
  required String key,
  required String provider,
  required String kind,
  required String externalID,
  required String dayKey,
  Value<DateTime?> start,
  required DateTime importedAt,
  required DateTime updatedAt,
  required String contentHash,
  required String status,
  Value<Uint8List?> payload,
  Value<int> rowid,
});
typedef $$SourceRecordsTableUpdateCompanionBuilder = SourceRecordsCompanion Function({
  Value<String> key,
  Value<String> provider,
  Value<String> kind,
  Value<String> externalID,
  Value<String> dayKey,
  Value<DateTime?> start,
  Value<DateTime> importedAt,
  Value<DateTime> updatedAt,
  Value<String> contentHash,
  Value<String> status,
  Value<Uint8List?> payload,
  Value<int> rowid,
});

class $$SourceRecordsTableFilterComposer extends Composer<_$CoachDatabase, $SourceRecordsTable> {
  $$SourceRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kind => $composableBuilder(column: $table.kind, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get externalID =>
      $composableBuilder(column: $table.externalID, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get start =>
      $composableBuilder(column: $table.start, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get importedAt =>
      $composableBuilder(column: $table.importedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentHash =>
      $composableBuilder(column: $table.contentHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$SourceRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $SourceRecordsTable> {
  $$SourceRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get externalID =>
      $composableBuilder(column: $table.externalID, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get start =>
      $composableBuilder(column: $table.start, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get importedAt =>
      $composableBuilder(column: $table.importedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentHash =>
      $composableBuilder(column: $table.contentHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$SourceRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $SourceRecordsTable> {
  $$SourceRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key => $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get provider => $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get kind => $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get externalID => $composableBuilder(column: $table.externalID, builder: (column) => column);

  GeneratedColumn<String> get dayKey => $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<DateTime> get start => $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<DateTime> get importedAt =>
      $composableBuilder(column: $table.importedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt => $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get contentHash =>
      $composableBuilder(column: $table.contentHash, builder: (column) => column);

  GeneratedColumn<String> get status => $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$SourceRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $SourceRecordsTable,
          SourceRow,
          $$SourceRecordsTableFilterComposer,
          $$SourceRecordsTableOrderingComposer,
          $$SourceRecordsTableAnnotationComposer,
          $$SourceRecordsTableCreateCompanionBuilder,
          $$SourceRecordsTableUpdateCompanionBuilder,
          (SourceRow, BaseReferences<_$CoachDatabase, $SourceRecordsTable, SourceRow>),
          SourceRow,
          PrefetchHooks Function()
        > {
  $$SourceRecordsTableTableManager(_$CoachDatabase db, $SourceRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$SourceRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$SourceRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$SourceRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> externalID = const Value.absent(),
                Value<String> dayKey = const Value.absent(),
                Value<DateTime?> start = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<Uint8List?> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceRecordsCompanion(
                key: key,
                provider: provider,
                kind: kind,
                externalID: externalID,
                dayKey: dayKey,
                start: start,
                importedAt: importedAt,
                updatedAt: updatedAt,
                contentHash: contentHash,
                status: status,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String provider,
                required String kind,
                required String externalID,
                required String dayKey,
                Value<DateTime?> start = const Value.absent(),
                required DateTime importedAt,
                required DateTime updatedAt,
                required String contentHash,
                required String status,
                Value<Uint8List?> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceRecordsCompanion.insert(
                key: key,
                provider: provider,
                kind: kind,
                externalID: externalID,
                dayKey: dayKey,
                start: start,
                importedAt: importedAt,
                updatedAt: updatedAt,
                contentHash: contentHash,
                status: status,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SourceRecordsTable, SourceRow>(table),
                  BaseReferences<_$CoachDatabase, $SourceRecordsTable, SourceRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourceRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $SourceRecordsTable,
      SourceRow,
      $$SourceRecordsTableFilterComposer,
      $$SourceRecordsTableOrderingComposer,
      $$SourceRecordsTableAnnotationComposer,
      $$SourceRecordsTableCreateCompanionBuilder,
      $$SourceRecordsTableUpdateCompanionBuilder,
      (SourceRow, BaseReferences<_$CoachDatabase, $SourceRecordsTable, SourceRow>),
      SourceRow,
      PrefetchHooks Function()
    >;
typedef $$MealRecordsTableCreateCompanionBuilder = MealRecordsCompanion Function({
  required String id,
  required String dayKey,
  required DateTime createdAt,
  required String categoryRaw,
  required String title,
  required String hint,
  required Uint8List itemsPayload,
  Value<int> rowid,
});
typedef $$MealRecordsTableUpdateCompanionBuilder = MealRecordsCompanion Function({
  Value<String> id,
  Value<String> dayKey,
  Value<DateTime> createdAt,
  Value<String> categoryRaw,
  Value<String> title,
  Value<String> hint,
  Value<Uint8List> itemsPayload,
  Value<int> rowid,
});

class $$MealRecordsTableFilterComposer extends Composer<_$CoachDatabase, $MealRecordsTable> {
  $$MealRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryRaw =>
      $composableBuilder(column: $table.categoryRaw, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hint => $composableBuilder(column: $table.hint, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get itemsPayload =>
      $composableBuilder(column: $table.itemsPayload, builder: (column) => ColumnFilters(column));
}

class $$MealRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $MealRecordsTable> {
  $$MealRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryRaw =>
      $composableBuilder(column: $table.categoryRaw, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hint =>
      $composableBuilder(column: $table.hint, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get itemsPayload =>
      $composableBuilder(column: $table.itemsPayload, builder: (column) => ColumnOrderings(column));
}

class $$MealRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $MealRecordsTable> {
  $$MealRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dayKey => $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get categoryRaw =>
      $composableBuilder(column: $table.categoryRaw, builder: (column) => column);

  GeneratedColumn<String> get title => $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get hint => $composableBuilder(column: $table.hint, builder: (column) => column);

  GeneratedColumn<Uint8List> get itemsPayload =>
      $composableBuilder(column: $table.itemsPayload, builder: (column) => column);
}

class $$MealRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $MealRecordsTable,
          MealRow,
          $$MealRecordsTableFilterComposer,
          $$MealRecordsTableOrderingComposer,
          $$MealRecordsTableAnnotationComposer,
          $$MealRecordsTableCreateCompanionBuilder,
          $$MealRecordsTableUpdateCompanionBuilder,
          (MealRow, BaseReferences<_$CoachDatabase, $MealRecordsTable, MealRow>),
          MealRow,
          PrefetchHooks Function()
        > {
  $$MealRecordsTableTableManager(_$CoachDatabase db, $MealRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$MealRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$MealRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$MealRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dayKey = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> categoryRaw = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> hint = const Value.absent(),
                Value<Uint8List> itemsPayload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MealRecordsCompanion(
                id: id,
                dayKey: dayKey,
                createdAt: createdAt,
                categoryRaw: categoryRaw,
                title: title,
                hint: hint,
                itemsPayload: itemsPayload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dayKey,
                required DateTime createdAt,
                required String categoryRaw,
                required String title,
                required String hint,
                required Uint8List itemsPayload,
                Value<int> rowid = const Value.absent(),
              }) => MealRecordsCompanion.insert(
                id: id,
                dayKey: dayKey,
                createdAt: createdAt,
                categoryRaw: categoryRaw,
                title: title,
                hint: hint,
                itemsPayload: itemsPayload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MealRecordsTable, MealRow>(table),
                  BaseReferences<_$CoachDatabase, $MealRecordsTable, MealRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MealRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $MealRecordsTable,
      MealRow,
      $$MealRecordsTableFilterComposer,
      $$MealRecordsTableOrderingComposer,
      $$MealRecordsTableAnnotationComposer,
      $$MealRecordsTableCreateCompanionBuilder,
      $$MealRecordsTableUpdateCompanionBuilder,
      (MealRow, BaseReferences<_$CoachDatabase, $MealRecordsTable, MealRow>),
      MealRow,
      PrefetchHooks Function()
    >;
typedef $$FoodRecordsTableCreateCompanionBuilder = FoodRecordsCompanion Function({
  required String key,
  required String name,
  required Uint8List payload,
  required DateTime lastUsed,
  required int useCount,
  Value<int> rowid,
});
typedef $$FoodRecordsTableUpdateCompanionBuilder = FoodRecordsCompanion Function({
  Value<String> key,
  Value<String> name,
  Value<Uint8List> payload,
  Value<DateTime> lastUsed,
  Value<int> useCount,
  Value<int> rowid,
});

class $$FoodRecordsTableFilterComposer extends Composer<_$CoachDatabase, $FoodRecordsTable> {
  $$FoodRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastUsed =>
      $composableBuilder(column: $table.lastUsed, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get useCount =>
      $composableBuilder(column: $table.useCount, builder: (column) => ColumnFilters(column));
}

class $$FoodRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $FoodRecordsTable> {
  $$FoodRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastUsed =>
      $composableBuilder(column: $table.lastUsed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get useCount =>
      $composableBuilder(column: $table.useCount, builder: (column) => ColumnOrderings(column));
}

class $$FoodRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $FoodRecordsTable> {
  $$FoodRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key => $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get name => $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsed => $composableBuilder(column: $table.lastUsed, builder: (column) => column);

  GeneratedColumn<int> get useCount => $composableBuilder(column: $table.useCount, builder: (column) => column);
}

class $$FoodRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $FoodRecordsTable,
          FoodRow,
          $$FoodRecordsTableFilterComposer,
          $$FoodRecordsTableOrderingComposer,
          $$FoodRecordsTableAnnotationComposer,
          $$FoodRecordsTableCreateCompanionBuilder,
          $$FoodRecordsTableUpdateCompanionBuilder,
          (FoodRow, BaseReferences<_$CoachDatabase, $FoodRecordsTable, FoodRow>),
          FoodRow,
          PrefetchHooks Function()
        > {
  $$FoodRecordsTableTableManager(_$CoachDatabase db, $FoodRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$FoodRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$FoodRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$FoodRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<DateTime> lastUsed = const Value.absent(),
                Value<int> useCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodRecordsCompanion(
                key: key,
                name: name,
                payload: payload,
                lastUsed: lastUsed,
                useCount: useCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String name,
                required Uint8List payload,
                required DateTime lastUsed,
                required int useCount,
                Value<int> rowid = const Value.absent(),
              }) => FoodRecordsCompanion.insert(
                key: key,
                name: name,
                payload: payload,
                lastUsed: lastUsed,
                useCount: useCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoodRecordsTable, FoodRow>(table),
                  BaseReferences<_$CoachDatabase, $FoodRecordsTable, FoodRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoodRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $FoodRecordsTable,
      FoodRow,
      $$FoodRecordsTableFilterComposer,
      $$FoodRecordsTableOrderingComposer,
      $$FoodRecordsTableAnnotationComposer,
      $$FoodRecordsTableCreateCompanionBuilder,
      $$FoodRecordsTableUpdateCompanionBuilder,
      (FoodRow, BaseReferences<_$CoachDatabase, $FoodRecordsTable, FoodRow>),
      FoodRow,
      PrefetchHooks Function()
    >;
typedef $$GymSessionRecordsTableCreateCompanionBuilder = GymSessionRecordsCompanion Function({
  required String id,
  required String dayKey,
  required DateTime start,
  required Uint8List payload,
  Value<bool> savedToHealth,
  Value<bool> uploadedToGarmin,
  Value<int> rowid,
});
typedef $$GymSessionRecordsTableUpdateCompanionBuilder = GymSessionRecordsCompanion Function({
  Value<String> id,
  Value<String> dayKey,
  Value<DateTime> start,
  Value<Uint8List> payload,
  Value<bool> savedToHealth,
  Value<bool> uploadedToGarmin,
  Value<int> rowid,
});

class $$GymSessionRecordsTableFilterComposer extends Composer<_$CoachDatabase, $GymSessionRecordsTable> {
  $$GymSessionRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get start =>
      $composableBuilder(column: $table.start, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get savedToHealth =>
      $composableBuilder(column: $table.savedToHealth, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get uploadedToGarmin =>
      $composableBuilder(column: $table.uploadedToGarmin, builder: (column) => ColumnFilters(column));
}

class $$GymSessionRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $GymSessionRecordsTable> {
  $$GymSessionRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get start =>
      $composableBuilder(column: $table.start, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get savedToHealth =>
      $composableBuilder(column: $table.savedToHealth, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get uploadedToGarmin =>
      $composableBuilder(column: $table.uploadedToGarmin, builder: (column) => ColumnOrderings(column));
}

class $$GymSessionRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $GymSessionRecordsTable> {
  $$GymSessionRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dayKey => $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<DateTime> get start => $composableBuilder(column: $table.start, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<bool> get savedToHealth =>
      $composableBuilder(column: $table.savedToHealth, builder: (column) => column);

  GeneratedColumn<bool> get uploadedToGarmin =>
      $composableBuilder(column: $table.uploadedToGarmin, builder: (column) => column);
}

class $$GymSessionRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $GymSessionRecordsTable,
          GymSessionRow,
          $$GymSessionRecordsTableFilterComposer,
          $$GymSessionRecordsTableOrderingComposer,
          $$GymSessionRecordsTableAnnotationComposer,
          $$GymSessionRecordsTableCreateCompanionBuilder,
          $$GymSessionRecordsTableUpdateCompanionBuilder,
          (GymSessionRow, BaseReferences<_$CoachDatabase, $GymSessionRecordsTable, GymSessionRow>),
          GymSessionRow,
          PrefetchHooks Function()
        > {
  $$GymSessionRecordsTableTableManager(_$CoachDatabase db, $GymSessionRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$GymSessionRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$GymSessionRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$GymSessionRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> dayKey = const Value.absent(),
                Value<DateTime> start = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<bool> savedToHealth = const Value.absent(),
                Value<bool> uploadedToGarmin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GymSessionRecordsCompanion(
                id: id,
                dayKey: dayKey,
                start: start,
                payload: payload,
                savedToHealth: savedToHealth,
                uploadedToGarmin: uploadedToGarmin,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String dayKey,
                required DateTime start,
                required Uint8List payload,
                Value<bool> savedToHealth = const Value.absent(),
                Value<bool> uploadedToGarmin = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GymSessionRecordsCompanion.insert(
                id: id,
                dayKey: dayKey,
                start: start,
                payload: payload,
                savedToHealth: savedToHealth,
                uploadedToGarmin: uploadedToGarmin,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GymSessionRecordsTable, GymSessionRow>(table),
                  BaseReferences<_$CoachDatabase, $GymSessionRecordsTable, GymSessionRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GymSessionRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $GymSessionRecordsTable,
      GymSessionRow,
      $$GymSessionRecordsTableFilterComposer,
      $$GymSessionRecordsTableOrderingComposer,
      $$GymSessionRecordsTableAnnotationComposer,
      $$GymSessionRecordsTableCreateCompanionBuilder,
      $$GymSessionRecordsTableUpdateCompanionBuilder,
      (GymSessionRow, BaseReferences<_$CoachDatabase, $GymSessionRecordsTable, GymSessionRow>),
      GymSessionRow,
      PrefetchHooks Function()
    >;
typedef $$SettingRecordsTableCreateCompanionBuilder = SettingRecordsCompanion Function({
  required String key,
  required String type,
  required Uint8List value,
  Value<int> rowid,
});
typedef $$SettingRecordsTableUpdateCompanionBuilder = SettingRecordsCompanion Function({
  Value<String> key,
  Value<String> type,
  Value<Uint8List> value,
  Value<int> rowid,
});

class $$SettingRecordsTableFilterComposer extends Composer<_$CoachDatabase, $SettingRecordsTable> {
  $$SettingRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SettingRecordsTableOrderingComposer extends Composer<_$CoachDatabase, $SettingRecordsTable> {
  $$SettingRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SettingRecordsTableAnnotationComposer extends Composer<_$CoachDatabase, $SettingRecordsTable> {
  $$SettingRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key => $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get type => $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<Uint8List> get value => $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingRecordsTableTableManager
    extends
        RootTableManager<
          _$CoachDatabase,
          $SettingRecordsTable,
          SettingRow,
          $$SettingRecordsTableFilterComposer,
          $$SettingRecordsTableOrderingComposer,
          $$SettingRecordsTableAnnotationComposer,
          $$SettingRecordsTableCreateCompanionBuilder,
          $$SettingRecordsTableUpdateCompanionBuilder,
          (SettingRow, BaseReferences<_$CoachDatabase, $SettingRecordsTable, SettingRow>),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingRecordsTableTableManager(_$CoachDatabase db, $SettingRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$SettingRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$SettingRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$SettingRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<Uint8List> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingRecordsCompanion(key: key, type: type, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String type,
            required Uint8List value,
            Value<int> rowid = const Value.absent(),
          }) => SettingRecordsCompanion.insert(key: key, type: type, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingRecordsTable, SettingRow>(table),
                  BaseReferences<_$CoachDatabase, $SettingRecordsTable, SettingRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$CoachDatabase,
      $SettingRecordsTable,
      SettingRow,
      $$SettingRecordsTableFilterComposer,
      $$SettingRecordsTableOrderingComposer,
      $$SettingRecordsTableAnnotationComposer,
      $$SettingRecordsTableCreateCompanionBuilder,
      $$SettingRecordsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$CoachDatabase, $SettingRecordsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $CoachDatabaseManager {
  final _$CoachDatabase _db;
  $CoachDatabaseManager(this._db);
  $$DailyMetricsRecordsTableTableManager get dailyMetricsRecords =>
      $$DailyMetricsRecordsTableTableManager(_db, _db.dailyMetricsRecords);
  $$ActivityRecordsTableTableManager get activityRecords =>
      $$ActivityRecordsTableTableManager(_db, _db.activityRecords);
  $$RawResponseRecordsTableTableManager get rawResponseRecords =>
      $$RawResponseRecordsTableTableManager(_db, _db.rawResponseRecords);
  $$SourceRecordsTableTableManager get sourceRecords => $$SourceRecordsTableTableManager(_db, _db.sourceRecords);
  $$MealRecordsTableTableManager get mealRecords => $$MealRecordsTableTableManager(_db, _db.mealRecords);
  $$FoodRecordsTableTableManager get foodRecords => $$FoodRecordsTableTableManager(_db, _db.foodRecords);
  $$GymSessionRecordsTableTableManager get gymSessionRecords =>
      $$GymSessionRecordsTableTableManager(_db, _db.gymSessionRecords);
  $$SettingRecordsTableTableManager get settingRecords => $$SettingRecordsTableTableManager(_db, _db.settingRecords);
}
