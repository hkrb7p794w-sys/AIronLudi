import 'package:collection/collection.dart';

import '../ai/insights.dart';
import '../gym/exercise_library.dart';
import '../gym/gym_coach.dart';
import '../gym/routine.dart';
import '../json/json_value.dart';
import '../nutrition/food_search.dart';
import '../profile/schedule_check.dart';
import '../profile/user_profile.dart';
import '../profile/week_schedule.dart';
import '../util/enum_codec.dart';
import '../util/text_prefix.dart';
import 'import_json.dart';

enum RoutineMode implements RawEnum {
  add('ergaenzen'),
  replace('ersetzen');

  const RoutineMode(this.rawValue);

  @override
  final String rawValue;
}

enum ScheduleScope implements RawEnum {
  permanent('dauerhaft'),
  nextWeek('naechste_woche');

  const ScheduleScope(this.rawValue);

  @override
  final String rawValue;
}

/// Vorschau eines Imports, bevor etwas übernommen wird.
final class ImportPreview {
  ImportPreview();

  List<Routine> routines = [];
  RoutineMode routineMode = RoutineMode.add;
  WeekSchedule? schedule;
  ScheduleScope scheduleScope = ScheduleScope.permanent;
  List<String> notes = [];

  /// Empfehlungen der externen KI für den Bereich „AI“ (gleiche ID wie eine bestehende = ersetzt sie).
  List<Insight> insights = [];

  /// IDs bestehender Empfehlungen, die die externe KI für falsch oder überholt hält.
  List<String> dismiss = [];

  /// Name des Modells laut Antwort (sonst „Externe KI“).
  String model = CoachImport.externalModel;

  /// Was die Regeln geändert oder verworfen haben.
  List<String> corrections = [];

  /// Hinweise der Regeln zum Ergebnis (z. B. Wochenvolumen, Plan-Prüfung).
  List<String> ruleNotes = [];

  bool get isEmpty => routines.isEmpty && schedule == null && notes.isEmpty && insights.isEmpty && dismiss.isEmpty;
}

/// Fehler beim Lesen der KI-Antwort.
enum ImportError implements Exception {
  noBlock(
    'Kein Plan im App-Format gefunden (Trainingspläne, Wochenplan oder Hinweise). Bitte die ganze Antwort der KI '
    'einfügen. Hilft das nicht: die KI bitten, das Ergebnis „als ironludi-Block wie in der Export-Datei“ auszugeben.',
  ),
  invalidJSON(
    'Der ironludi-Block ließ sich nicht lesen. Bitte die KI bitten, den Block noch einmal vollständig auszugeben.',
  );

  const ImportError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Was mit einer vorgeschlagenen Routine passiert.
enum RoutineChoice implements RawEnum {
  /// Gleichnamige bestehende Routine überschreiben.
  replace('Bestehende ersetzen'),

  /// Zusätzlich anlegen; bestehende bleiben unverändert.
  add('Zusätzlich anlegen'),

  /// Nicht übernehmen.
  skip('Nicht übernehmen');

  const RoutineChoice(this.label);

  final String label;

  @override
  String get rawValue => name;

  String get id => rawValue;
}

/// Entscheidung der Person, was aus dem Vorschlag übernommen wird.
final class ImportSelection {
  ImportSelection();

  Map<String, RoutineChoice> routines = {};

  /// Alle bisherigen Routinen löschen und nur die übernommenen behalten.
  bool replaceAllRoutines = false;
  bool schedule = true;
  ScheduleScope scheduleScope = ScheduleScope.permanent;

  /// Tage, deren Vorschlag übernommen wird (die anderen bleiben wie bisher).
  Set<Weekday> scheduleDays = {};

  /// Indizes der übernommenen Hinweise.
  Set<int> notes = {};

  /// IDs der übernommenen Empfehlungen (eine bestehende mit derselben ID wird überschrieben).
  Set<String> insights = {};

  /// IDs bestehender Empfehlungen, die als verworfen markiert werden.
  Set<String> dismiss = {};

  /// Vorschlag: gleichnamige Routinen ersetzen, neue hinzufügen; Wochenplan und Hinweise wie von der KI.
  static ImportSelection defaults(
    ImportPreview preview, {
    required List<Routine> existing,
    WeekSchedule? currentSchedule,
    List<Insight> existingInsights = const [],
  }) {
    final selection = ImportSelection();
    final names = {for (final routine in existing) routine.name};
    for (final routine in preview.routines) {
      selection.routines[routine.id] = names.contains(routine.name) ? RoutineChoice.replace : RoutineChoice.add;
    }
    selection
      ..replaceAllRoutines = preview.routineMode == RoutineMode.replace
      ..schedule = preview.schedule != null
      ..scheduleScope = preview.scheduleScope;
    if (preview.schedule case final schedule?) {
      selection.scheduleDays = CoachImport.changedDays(schedule, from: currentSchedule ?? WeekSchedule()).toSet();
    }
    selection.notes = {for (var index = 0; index < preview.notes.length; index++) index};
    // Empfehlungen: übernehmen, außer sie überschreiben eine noch gültige Empfehlung der Regeln (Regeln entscheiden –
    // überschreiben geht trotzdem, aber nur ausdrücklich). Verwerfen nur bei KI-Empfehlungen vorausgewählt.
    final byID = {for (final insight in existingInsights) insight.id: insight};
    selection.insights = {
      for (final insight in preview.insights)
        if (byID[insight.id]?.origin != InsightOrigin.rules) insight.id,
    };
    selection.dismiss = {
      for (final id in preview.dismiss)
        if (byID[id] case final existing? when existing.origin == InsightOrigin.ai) id,
    };
    return selection;
  }

  RoutineChoice choice(Routine routine) => routines[routine.id] ?? RoutineChoice.add;
}

/// Import der Antwort einer externen KI (ChatGPT, Gemini, Claude) aus dem Format, das `CoachExport` vorgibt: ein
/// Codeblock ```ironludi … ``` mit JSON. Die KI schlägt vor, die Regeln prüfen: nur bekannte Übungen der eigenen
/// Ausstattung, Grenzen für Sätze, Wiederholungen, Pausen und Gewicht, Wochenvolumen; Wochenplan nur im eigenen
/// Plan. Nichts wird übernommen, bevor die Vorschau bestätigt ist.
abstract final class CoachImport {
  /// Modellname, wenn die Antwort keinen nennt.
  static const externalModel = 'Externe KI';

  /// JSON der Antwort: bevorzugt der ```ironludi-Block, sonst jeder Block bzw. der ganze Text mit passenden
  /// Schlüsseln – nachsichtig gelesen ([ImportJson]: Kommentare, Kommas, „“, englische Schlüssel). Wirft [ImportError].
  static JsonValue block(String text) {
    final found = ImportJson.find(text);
    if (found.json case final json?) return JsonValue(json);
    if (found.invalidTagged) throw ImportError.invalidJSON;
    throw ImportError.noBlock;
  }

  /// Wirft [ImportError].
  static ImportPreview preview(
    String text, {
    required UserProfile profile,
    required Set<Equipment> equipment,
    required List<ExerciseInfo> custom,
    DateTime? now,
  }) {
    final json = block(text);
    final preview = ImportPreview();

    final routines = json['routinen'];
    if (routines != null) {
      preview.routineMode = enumFromRaw(RoutineMode.values, routines['modus']?.stringValue ?? '') ?? RoutineMode.add;
      final list = routines['liste']?.arrayValue ?? routines.arrayValue ?? const <JsonValue>[];
      final weights = <String, double>{};
      final normalized = [
        for (final raw in list)
          if (raw.raw case final Map<dynamic, dynamic> routine)
            {
              ...routine.cast<String, Object?>(),
              if (routine['name'] == null && routine['titel'] != null) 'name': routine['titel'],
              'uebungen': [
                for (final entry in raw['uebungen']?.arrayValue ?? const <JsonValue>[])
                  if (entry.raw case final Map<dynamic, dynamic> item)
                    () {
                      final original = entry['id']?.stringValue ?? entry['name']?.stringValue ?? '';
                      final id = resolve(original, custom: custom);
                      if (id != original.trim()) {
                        if (ExerciseLibrary.info(id, custom: custom) case final info?
                            when info.name.toLowerCase() != original.trim().toLowerCase()) {
                          preview.corrections.add('„$original“ als ${info.name} übernommen.');
                        }
                      }
                      final weight = entry['gewicht']?.doubleValue;
                      if (weight != null && weight >= 0 && weight <= 500) weights[id] = weight;
                      return {...item.cast<String, Object?>(), 'id': id};
                    }()
                  else
                    entry.raw,
              ],
            }
          else
            raw.raw,
      ];
      final request = PlanRequest()
        ..daysPerWeek = 10
        ..minutesPerSession = 120;
      final checked = GymCoach.validatePlan(
        JsonValue({'routinen': normalized}),
        request: request,
        equipment: equipment,
        custom: custom,
        lastWeights: weights,
      );
      preview
        ..routines = checked.routines
        ..corrections.addAll(checked.corrections)
        ..ruleNotes.addAll(checked.notes);
    }

    final plan = json['wochenplan'];
    if (plan != null) {
      if (profile.mode == ProfileMode.season) {
        preview.corrections.add('Wochenplan ignoriert: Im Saisonplan stehen die Tage fest.');
      } else {
        final scope = _plain(plan['gilt_fuer']?.stringValue ?? '');
        preview.scheduleScope = scope.contains('naechste') || scope.contains('next')
            ? ScheduleScope.nextWeek
            : ScheduleScope.permanent;
        var schedule = profile.schedule;
        // Tage unter „tage“ oder direkt im Wochenplan; je Tag eine Liste, ein Objekt oder ein Text („Laufen locker“).
        final days = plan['tage'] ?? plan;
        const keys = ['mo', 'di', 'mi', 'do', 'fr', 'sa', 'so'];
        for (var index = 0; index < keys.length; index++) {
          final value = days[keys[index]];
          if (value == null) continue;
          final entries = value.arrayValue ?? [value];
          final weekday = Weekday.values[index];
          final slots = <SessionSlot>[];
          for (final entry in entries.take(3)) {
            final text = entry.stringValue;
            if (text != null && RegExp('^(frei|ruhe|ruhetag|rest|off|pause)').hasMatch(_plain(text))) continue;
            final sportText = text ?? entry['sport']?.stringValue;
            final sport = _sport(sportText);
            if (sport == null) {
              preview.corrections.add('${weekday.long}: Sportart „${sportText ?? '?'}“ unbekannt.');
              continue;
            }
            slots.add(SessionSlot(sport, _intensity(entry['intensitaet']?.stringValue ?? sportText)));
          }
          schedule = schedule.withSlots(slots, weekday);
        }
        preview.schedule = schedule;
        final planned = {
          for (final weekday in Weekday.values)
            for (final slot in schedule.slots(weekday)) slot.sport,
        };
        final missing = planned.difference(profile.sports.toSet()).toList()
          ..sort((a, b) => a.rawValue.compareTo(b.rawValue));
        for (final sport in missing) {
          preview.ruleNotes.add('${sport.label} steht im Plan, ist aber nicht in deinem Profil gewählt.');
        }
        preview.ruleNotes.addAll(ScheduleCheck.hints(schedule, profile).map((hint) => hint.message));
      }
    }

    preview.notes = [for (final note in json['hinweise']?.arrayValue ?? const <JsonValue>[]) ?note.stringValue]
        .take(10)
        .map((note) => textPrefix(note, 400))
        .toList();

    if (json['modell']?.stringValue case final model? when model.trim().isNotEmpty) {
      preview.model = textPrefix(model.trim(), 40);
    }
    preview.insights = insights(
      json,
      model: preview.model,
      now: now ?? DateTime.now(),
      corrections: preview.corrections,
    );
    preview.dismiss = <String>{
      for (final entry in json['verwerfen']?.arrayValue ?? const <JsonValue>[])
        if (entry.stringValue case final id? when id.contains('.')) id.trim(),
    }.take(30).toList();
    return preview;
  }

  /// Empfehlungen aus `empfehlungen`. Mit `id` („thema.betreff“) ersetzen sie die Empfehlung mit dieser ID; die
  /// Begründung der KI steht als Beleg dabei. Unvollständige Einträge fallen mit Hinweis weg.
  static List<Insight> insights(
    JsonValue json, {
    required String model,
    required DateTime now,
    List<String>? corrections,
  }) {
    final result = <Insight>[];
    final seen = <String>{};
    for (final item in (json['empfehlungen']?.arrayValue ?? const <JsonValue>[]).take(20)) {
      final id = item['id']?.stringValue?.trim() ?? '';
      final dot = id.indexOf('.');
      final topic =
          enumFromRaw(InsightTopic.values, item['thema']?.stringValue) ??
          (dot > 0 ? enumFromRaw(InsightTopic.values, id.substring(0, dot)) : null);
      final title = item['titel']?.stringValue?.trim() ?? '';
      final text = item['text']?.stringValue?.trim() ?? '';
      if (topic == null || title.isEmpty || text.isEmpty) {
        corrections?.add('Empfehlung „${title.isEmpty ? id : title}“ ignoriert: Thema, Titel oder Text fehlt.');
        continue;
      }
      // Die ID gewinnt, damit die Empfehlung wirklich die gemeinte ersetzt.
      final subject = dot > 0 && id.substring(0, dot) == topic.rawValue
          ? id.substring(dot + 1)
          : item['betreff']?.stringValue ?? title;
      final reason = item['begruendung']?.stringValue?.trim() ?? '';
      final insight = Insight(
        topic: topic,
        subject: subject,
        title: textPrefix(title, 80),
        text: textPrefix(text, 400),
        direction: enumFromRaw(InsightDirection.values, item['richtung']?.stringValue) ?? InsightDirection.check,
        priority: item['prioritaet']?.clampedInt(1, 3) ?? 2,
        origin: InsightOrigin.ai,
        created: now,
        validUntil: now.add(Duration(days: item['gueltig_tage']?.clampedInt(1, 30) ?? 14)),
        basis: [if (reason.isNotEmpty) textPrefix(reason, 400) else 'Import aus $model'],
        model: model,
      );
      if (!seen.add(insight.id)) continue;
      result.add(insight);
    }
    return result;
  }

  /// Empfehlungen nach der Auswahl: gewählte Verwerfungen markieren, gewählte Empfehlungen übernehmen (eine
  /// bestehende mit gleicher ID wird überschrieben, auch wenn sie von den Regeln stammt – nur auf ausdrücklichen
  /// Wunsch); Widersprüche zu übernommenen Empfehlungen werden ersetzt.
  static List<Insight> applyInsights(
    ImportPreview preview, {
    required ImportSelection selection,
    required List<Insight> existing,
    required DateTime now,
  }) {
    var result = [
      for (final insight in existing)
        if (selection.dismiss.contains(insight.id) && preview.dismiss.contains(insight.id))
          insight.copyWith(status: InsightStatus.dismissed, statusChanged: () => now)
        else
          insight,
    ];
    for (final incoming in preview.insights) {
      if (!selection.insights.contains(incoming.id)) continue;
      result = [
        for (final insight in result)
          if (insight.id != incoming.id &&
              !(insight.contradicts(incoming) &&
                  insight.isCurrent(now) &&
                  insight.origin == InsightOrigin.ai &&
                  insight.status != InsightStatus.dismissed))
            insight,
        incoming,
      ];
    }
    return InsightInbox.prune(result, now: now);
  }

  /// Englische und gängige Namen, die KIs gern verwenden (normalisiert, ohne Umlaute) → ID der Bibliothek.
  static const exerciseAliases = <String, String>{
    'bench press': 'bankdruecken',
    'barbell bench press': 'bankdruecken',
    'dumbbell bench press': 'kurzhantel_bankdruecken',
    'incline bench press': 'schraegbankdruecken',
    'incline dumbbell press': 'kurzhantel_schraegbankdruecken',
    'chest press': 'brustpresse',
    'chest fly': 'fliegende',
    'push up': 'liegestuetze',
    'pushup': 'liegestuetze',
    'pull up': 'klimmzug',
    'pullup': 'klimmzug',
    'chin up': 'klimmzug',
    'lat pulldown': 'latziehen',
    'barbell row': 'rudern_langhantel',
    'bent over row': 'rudern_langhantel',
    'dumbbell row': 'rudern_kurzhantel',
    'cable row': 'rudern_kabel',
    'seated row': 'rudern_kabel',
    'seated cable row': 'rudern_kabel',
    'overhead press': 'schulterdruecken',
    'shoulder press': 'schulterdruecken',
    'military press': 'schulterdruecken',
    'dumbbell shoulder press': 'kurzhantel_schulterdruecken',
    'lateral raise': 'seitheben',
    'front raise': 'frontheben',
    'rear delt fly': 'reverse_fly',
    'upright row': 'aufrechtes_rudern',
    'bicep curl': 'bizeps_curl',
    'biceps curl': 'bizeps_curl',
    'barbell curl': 'bizeps_curl',
    'dumbbell curl': 'kurzhantel_curl',
    'tricep pushdown': 'trizeps_pushdown',
    'triceps pushdown': 'trizeps_pushdown',
    'skull crusher': 'trizepsstrecken',
    'squat': 'kniebeuge',
    'back squat': 'kniebeuge',
    'leg press': 'beinpresse',
    'lunge': 'ausfallschritt',
    'walking lunge': 'ausfallschritt',
    'bulgarian split squat': 'bulgarische_kniebeuge',
    'romanian deadlift': 'rumaenisches_kreuzheben',
    'rdl': 'rumaenisches_kreuzheben',
    'deadlift': 'kreuzheben',
    'hip thrust': 'hueftstoss',
    'leg extension': 'beinstrecken',
    'leg curl': 'beinbeugen',
    'calf raise': 'wadenheben',
    'hanging leg raise': 'beinheben',
    'back extension': 'rueckenstrecker',
    'hyperextension': 'rueckenstrecker',
    'side plank': 'seitstuetz',
    'russian twist': 'rotation',
  };

  static String _plain(String text) => FoodSearch.normalized(text).replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();

  /// Wortstamm für den Vergleich: Umlaut-Ersatz zurück auf den Grundvokal, Plural- und Fallendungen ab
  /// („Klimmzüge“ ≈ „Klimmzug“, „Kniebeugen“ ≈ „Kniebeuge“, „Kurzhanteln“ ≈ „Kurzhantel“).
  static String _stem(String word) {
    var result = word.replaceAll('ae', 'a').replaceAll('oe', 'o').replaceAll('ue', 'u');
    for (final suffix in const ['en', 'n', 'e', 's']) {
      if (result.length > 4 && result.endsWith(suffix)) {
        result = result.substring(0, result.length - suffix.length);
        break;
      }
    }
    return result;
  }

  static Set<String> _stems(String text) => {
    for (final word in _plain(text.replaceAll(RegExp(r'\(.*?\)'), ' ')).split(' '))
      if (word.length > 2 && word != 'mit' && word != 'und' && word != 'am' && word != 'the' && word != 'with')
        _stem(word),
  };

  /// ID aus der Bibliothek bzw. den eigenen Übungen. Reihenfolge: genaue ID, gleicher Name, bekannter englischer
  /// Name, gleicher Name ohne Klammerzusatz/Plural, sonst die Übung, deren Namenswörter alle im Text vorkommen (die
  /// mit den meisten Wörtern gewinnt). Ohne Treffer bleibt der Text (die Regeln entfernen ihn dann mit Hinweis).
  static String resolve(String text, {required List<ExerciseInfo> custom}) {
    final trimmed = text.trim();
    if (ExerciseLibrary.info(trimmed, custom: custom) != null) return trimmed;
    final all = [...ExerciseLibrary.all, ...custom];
    final lower = trimmed.toLowerCase();
    if (all.firstWhereOrNull((exercise) => exercise.name.toLowerCase() == lower) case final exact?) return exact.id;
    final plain = _plain(trimmed);
    final withoutParens = _plain(trimmed.replaceAll(RegExp(r'\(.*?\)'), ' '));
    if (exerciseAliases[plain] ?? exerciseAliases[withoutParens] case final alias?) return alias;
    final idLike = plain.replaceAll(' ', '_');
    if (ExerciseLibrary.info(idLike, custom: custom) != null) return idLike;
    final stems = _stems(trimmed);
    if (stems.isEmpty) return trimmed;
    ExerciseInfo? best;
    var bestCount = 0;
    for (final exercise in all) {
      final own = _stems(exercise.name);
      if (own.isEmpty) continue;
      if (own.length == stems.length && own.containsAll(stems)) return exercise.id;
      if (stems.containsAll(own) && own.length > bestCount) {
        best = exercise;
        bestCount = own.length;
      }
    }
    return best?.id ?? trimmed;
  }

  static TrainingSport? _sport(String? text) {
    final value = _plain(text ?? '');
    bool has(List<String> words) => words.any((word) => value == word || value.split(' ').contains(word));
    if (has(['run', 'running', 'laufen', 'lauf', 'dauerlauf', 'joggen', 'intervalle', 'intervall', 'tempolauf'])) {
      return TrainingSport.run;
    }
    if (has(['bike', 'cycling', 'rad', 'radfahren', 'rennrad', 'zwift', 'spinning', 'ergometer'])) {
      return TrainingSport.bike;
    }
    if (has(['swim', 'swimming', 'schwimmen'])) return TrainingSport.swim;
    if (has(['strength', 'kraft', 'krafttraining', 'gym', 'weights', 'ganzkoerper', 'oberkoerper', 'unterkoerper'])) {
      return TrainingSport.strength;
    }
    if (has(['other', 'anderes', 'yoga', 'mobilitaet', 'mobility', 'stretching', 'wandern', 'hiking'])) {
      return TrainingSport.other;
    }
    return null;
  }

  static SessionIntensity _intensity(String? text) {
    final value = _plain(text ?? '');
    if (RegExp('hard|hart|intensiv|intervall|tempo|schwelle|threshold|vo2').hasMatch(value)) {
      return SessionIntensity.hard;
    }
    if (RegExp('long|lang').hasMatch(value)) return SessionIntensity.long;
    return SessionIntensity.easy;
  }

  // Auswahl

  /// Routinen nach der Auswahl. Beim Hinzufügen bekommt ein schon vorhandener Name den Zusatz „(KI)“.
  static List<Routine> routines(
    ImportPreview preview, {
    required ImportSelection selection,
    required List<Routine> existing,
  }) {
    final result = selection.replaceAllRoutines ? <Routine>[] : [...existing];
    for (final routine in preview.routines) {
      switch (selection.choice(routine)) {
        case RoutineChoice.skip:
          continue;
        case RoutineChoice.replace:
          final index = result.indexWhere((item) => item.name == routine.name);
          if (index >= 0) {
            result[index] = routine;
          } else {
            result.add(routine);
          }
        case RoutineChoice.add:
          final copy = routine.copy();
          final names = {for (final item in result) item.name};
          if (names.contains(copy.name)) {
            var counter = 1;
            var name = '${routine.name} (KI)';
            while (names.contains(name)) {
              counter += 1;
              name = '${routine.name} (KI $counter)';
            }
            copy.name = name;
          }
          result.add(copy);
      }
    }
    return result;
  }

  /// Tage, an denen der Vorschlag vom bisherigen Plan abweicht.
  static List<Weekday> changedDays(WeekSchedule proposal, {required WeekSchedule from}) => [
    for (final weekday in Weekday.values)
      if (!const ListEquality<SessionSlot>().equals(proposal.slots(weekday), from.slots(weekday))) weekday,
  ];

  /// Wochenplan nach der Auswahl: gewählte Tage aus dem Vorschlag, die anderen wie bisher.
  static WeekSchedule? schedule(
    ImportPreview preview, {
    required ImportSelection selection,
    required WeekSchedule current,
  }) {
    final proposal = preview.schedule;
    if (!selection.schedule || proposal == null) return null;
    var result = current;
    for (final weekday in selection.scheduleDays) {
      result = result.withSlots(proposal.slots(weekday), weekday);
    }
    return result == current ? null : result;
  }

  /// Übernommene Hinweise in der Reihenfolge der KI.
  static List<String> notes(ImportPreview preview, {required ImportSelection selection}) => [
    for (var index = 0; index < preview.notes.length; index++)
      if (selection.notes.contains(index)) preview.notes[index],
  ];

  /// Gibt es überhaupt etwas zu übernehmen?
  static bool hasChanges(ImportPreview preview, {required ImportSelection selection}) =>
      selection.replaceAllRoutines ||
      preview.routines.any((routine) => selection.choice(routine) != RoutineChoice.skip) ||
      (selection.schedule && preview.schedule != null && selection.scheduleDays.isNotEmpty) ||
      selection.notes.isNotEmpty ||
      preview.insights.any((insight) => selection.insights.contains(insight.id)) ||
      preview.dismiss.any(selection.dismiss.contains);
}
