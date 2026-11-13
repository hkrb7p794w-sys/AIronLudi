import 'package:collection/collection.dart';

import '../util/enum_codec.dart';
import '../util/swift_date.dart';
import '../util/text_prefix.dart';
import 'ai_policy.dart';

/// Eine KI-Anfrage im internen Protokoll (Einstellungen › KI › Nutzung): wer, womit, wie viel – keine Inhalte.
final class AIUsageEntry {
  AIUsageEntry({
    required this.date,
    required this.task,
    required this.trigger,
    required this.provider,
    required this.model,
    required this.ok,
    this.inputTokens,
    this.outputTokens,
    this.listPriceUsd,
    required this.milliseconds,
    String? error,
  }) : error = error == null ? null : textPrefix(error, 160);

  const AIUsageEntry._raw({
    required this.date,
    required this.task,
    required this.trigger,
    required this.provider,
    required this.model,
    required this.ok,
    required this.inputTokens,
    required this.outputTokens,
    required this.listPriceUsd,
    required this.milliseconds,
    required this.error,
  });

  final DateTime date;
  final String task;
  final AITrigger trigger;
  final String? provider;
  final String? model;
  final bool ok;
  final int? inputTokens;
  final int? outputTokens;

  /// Listenpreis in US-Dollar, falls die Anfrage bezahlt würde (im kostenlosen Kontingent 0 € tatsächlich).
  final double? listPriceUsd;
  final int milliseconds;

  /// Kurzer Fehlertext (ohne Daten).
  final String? error;

  Map<String, Object?> toJson() => {
    'date': swiftDateToJson(date),
    'task': task,
    'trigger': trigger.rawValue,
    'provider': ?provider,
    'model': ?model,
    'ok': ok,
    'inputTokens': ?inputTokens,
    'outputTokens': ?outputTokens,
    'listPriceUsd': ?listPriceUsd,
    'milliseconds': milliseconds,
    'error': ?error,
  };

  /// Wie das synthetisierte `Decodable` (ohne Kürzen des Fehlertexts, das passiert nur beim Anlegen).
  static AIUsageEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final date = swiftDateFromJson(json['date']);
    final task = json['task'];
    final trigger = enumFromRaw(AITrigger.values, json['trigger']);
    final ok = json['ok'];
    final milliseconds = jsonInt(json['milliseconds']);
    if (date == null || task is! String || trigger == null || ok is! bool || milliseconds == null) return null;
    String? text(Object? value) => value is String ? value : null;
    return AIUsageEntry._raw(
      date: date,
      task: task,
      trigger: trigger,
      provider: text(json['provider']),
      model: text(json['model']),
      ok: ok,
      inputTokens: jsonInt(json['inputTokens']),
      outputTokens: jsonInt(json['outputTokens']),
      listPriceUsd: jsonDouble(json['listPriceUsd']),
      milliseconds: milliseconds,
      error: text(json['error']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AIUsageEntry &&
      other.date.isAtSameMomentAs(date) &&
      other.task == task &&
      other.trigger == trigger &&
      other.provider == provider &&
      other.model == model &&
      other.ok == ok &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.listPriceUsd == listPriceUsd &&
      other.milliseconds == milliseconds &&
      other.error == error;

  @override
  int get hashCode => Object.hash(date.microsecondsSinceEpoch, task, trigger, provider, model, ok, milliseconds);
}

/// Eine Zeile je Anbieter und Modell.
final class AIUsageLine {
  const AIUsageLine({
    required this.provider,
    required this.model,
    required this.requests,
    required this.failures,
    required this.inputTokens,
    required this.outputTokens,
    required this.listPriceUsd,
    required this.averageSeconds,
  });

  final String provider;
  final String model;
  final int requests;
  final int failures;
  final int inputTokens;
  final int outputTokens;
  final double listPriceUsd;
  final double averageSeconds;

  String get id => '$provider|$model';

  @override
  bool operator ==(Object other) =>
      other is AIUsageLine &&
      other.provider == provider &&
      other.model == model &&
      other.requests == requests &&
      other.failures == failures &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.listPriceUsd == listPriceUsd &&
      other.averageSeconds == averageSeconds;

  @override
  int get hashCode => Object.hash(provider, model, requests, failures, inputTokens, outputTokens);
}

/// Zusammenfassung des Protokolls für einen Zeitraum.
final class AIUsageSummary {
  const AIUsageSummary({
    required this.lines,
    required this.requests,
    required this.failures,
    required this.automatic,
    required this.listPriceUsd,
    required this.byTask,
  });

  final List<AIUsageLine> lines;
  final int requests;
  final int failures;
  final int automatic;
  final double listPriceUsd;
  final List<({String task, int count})> byTask;

  @override
  bool operator ==(Object other) =>
      other is AIUsageSummary &&
      const ListEquality<AIUsageLine>().equals(other.lines, lines) &&
      other.requests == requests &&
      other.failures == failures &&
      other.listPriceUsd == listPriceUsd &&
      const ListEquality<({String task, int count})>().equals(other.byTask, byTask) &&
      other.automatic == automatic;

  @override
  int get hashCode => Object.hash(requests, failures, automatic, listPriceUsd);
}

abstract final class AIUsageLog {
  static const maxEntries = 1000;
  static const maxAge = Duration(days: 180);

  /// Neuer Eintrag vorne; zu alte und überzählige fallen weg.
  static List<AIUsageEntry> appending(AIUsageEntry entry, List<AIUsageEntry> entries) {
    final cutoff = entry.date.subtract(maxAge);
    return [entry, ...entries].where((item) => !item.date.isBefore(cutoff)).take(maxEntries).toList();
  }

  static AIUsageSummary summary(List<AIUsageEntry> entries, {required DateTime since}) {
    final recent = entries.where((entry) => !entry.date.isBefore(since)).toList();
    final groups = groupBy(recent, (AIUsageEntry entry) => '${entry.provider ?? '–'}|${entry.model ?? '–'}');
    final lines = [
      for (final MapEntry(:key, value: group) in groups.entries)
        () {
          // Wie `split(separator: "|", maxSplits: 1)` in Swift: leere Teile fallen weg.
          final separator = key.indexOf('|');
          final parts = (separator < 0 ? [key] : [key.substring(0, separator), key.substring(separator + 1)])
              .where((part) => part.isNotEmpty)
              .toList();
          return AIUsageLine(
            provider: parts.isEmpty ? '–' : parts.first,
            model: parts.length > 1 ? parts[1] : '–',
            requests: group.length,
            failures: group.where((entry) => !entry.ok).length,
            inputTokens: group.map((entry) => entry.inputTokens ?? 0).sum,
            outputTokens: group.map((entry) => entry.outputTokens ?? 0).sum,
            listPriceUsd: group.map((entry) => entry.listPriceUsd ?? 0.0).sum,
            averageSeconds: group.map((entry) => entry.milliseconds).sum / (group.isEmpty ? 1 : group.length) / 1000,
          );
        }(),
    ];
    lines.sort((a, b) {
      final byRequests = b.requests.compareTo(a.requests);
      return byRequests != 0 ? byRequests : b.id.compareTo(a.id);
    });
    final tasks =
        [
          for (final MapEntry(:key, :value) in groupBy(recent, (AIUsageEntry entry) => entry.task).entries)
            (task: key, count: value.length),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.task.compareTo(b.task);
        });
    return AIUsageSummary(
      lines: lines,
      requests: recent.length,
      failures: recent.where((entry) => !entry.ok).length,
      automatic: recent.where((entry) => entry.trigger == AITrigger.automatic).length,
      listPriceUsd: lines.map((line) => line.listPriceUsd).sum,
      byTask: tasks,
    );
  }

  /// Anzeigename des Anbieters aus der Worker-Kennung.
  static String providerLabel(String id) =>
      enumFromRaw(AIProviderChoice.values, id)?.label ?? (id == '–' ? 'ohne Antwort' : id);
}
