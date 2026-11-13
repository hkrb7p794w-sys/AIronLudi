import '../nutrition/nutrition_settings.dart';
import '../util/enum_codec.dart';

enum TemplateItemKind implements RawEnum {
  strength,
  swimOrLegs,
  bike,
  run,
  optional;

  @override
  String get rawValue => name;
}

/// Fester Punkt der Musterwoche (z. B. „Push (Home-Gym)“ am Montag).
final class TemplateItem {
  TemplateItem({required this.kind, required this.text, this.done = false, this.minutes, this.plannedType});

  final TemplateItemKind kind;
  String text;
  bool done;

  /// Geplante Minuten, wenn der eigene Wochenplan sie kennt.
  int? minutes;

  /// Tagestyp aus Sportart und Intensität; im Saisonplan `null`, dort entscheidet der Text.
  DayType? plannedType;

  Map<String, Object?> toJson() => {
    'kind': kind.rawValue,
    'text': text,
    'done': done,
    'minutes': ?minutes,
    'plannedType': ?plannedType?.rawValue,
  };

  static TemplateItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = enumFromRaw(TemplateItemKind.values, json['kind']);
    final text = json['text'];
    if (kind == null || text is! String) return null;
    return TemplateItem(
      kind: kind,
      text: text,
      done: json['done'] == true,
      minutes: jsonInt(json['minutes']),
      plannedType: DayType.fromRaw(json['plannedType']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TemplateItem &&
      other.kind == kind &&
      other.text == text &&
      other.done == done &&
      other.minutes == minutes &&
      other.plannedType == plannedType;

  @override
  int get hashCode => Object.hash(kind, text, done, minutes, plannedType);
}
