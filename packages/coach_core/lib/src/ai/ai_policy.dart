import '../util/enum_codec.dart';

/// Wie viel KI die App nutzen darf. Regeln, eigene Auswertungen, Importe und der Export funktionieren in jeder
/// Stufe – die KI formuliert nur, sie entscheidet nichts.
enum AIMode implements RawEnum {
  /// Alles, auch automatische Notizen und Hinweise beim Öffnen.
  full('voll'),

  /// Nur, wenn ausdrücklich angetippt (Analyse starten, Chat, Mahlzeit auswerten …).
  onRequest('auf_anfrage'),

  /// Keine KI-Empfehlungen; die KI hilft nur bei der Datenerfassung (Mahlzeit, Etikett), auf Anfrage.
  captureOnly('nur_erfassung'),

  /// Keine KI-Aufrufe.
  off('aus');

  const AIMode(this.rawValue);

  @override
  final String rawValue;

  String get label => switch (this) {
    full => 'Vollständig',
    onRequest => 'Nur auf Anfrage',
    captureOnly => 'Keine KI-Empfehlungen',
    off => 'Aus',
  };

  String get detail => switch (this) {
    full => 'Notizen, Hinweise und Analysen kommen auch automatisch, z. B. beim Öffnen von „Heute“.',
    onRequest => 'Die KI arbeitet nur, wenn du etwas antippst. Bis dahin stehen die Hinweise der Regeln.',
    captureOnly =>
      'Keine Empfehlungen, Notizen oder Chat von der KI. Sie liest nur Mahlzeiten und Etiketten aus, wenn du '
          'darum bittest. Auswertungen der App und der Export bleiben.',
    off => 'Keine Anfrage an eine KI. Alle Regeln, Auswertungen, Importe und der Export funktionieren weiter.',
  };
}

/// Wofür eine Worker-Aufgabe die KI nutzt.
enum AITaskKind implements RawEnum {
  /// Daten erfassen: Mahlzeit zerlegen, Etikett ablesen.
  capture,

  /// Empfehlungen, Notizen, Analysen, Chat.
  recommendation,

  /// Pläne und Rezepte vorschlagen.
  planning,

  /// Verbindungstest ohne persönliche Daten.
  system;

  @override
  String get rawValue => name;
}

/// Wer eine Anfrage auslöst.
enum AITrigger implements RawEnum {
  automatic,
  user;

  @override
  String get rawValue => name;
}

/// Zentrale Regel, ob eine KI-Anfrage erlaubt ist – gilt für alle Aufgaben im KI-Dienst.
abstract final class AIPolicy {
  static AITaskKind kind(String task) => switch (task) {
    'meal_analyze' || 'meal_amend' || 'nutrition_label' => AITaskKind.capture,
    'gym_plan' || 'weekly_recipes' || 'meal_now' || 'cook_plan' => AITaskKind.planning,
    'ping' => AITaskKind.system,
    _ => AITaskKind.recommendation,
  };

  static bool allows(AIMode mode, {required String task, required AITrigger trigger}) {
    final kind = AIPolicy.kind(task);
    if (kind == AITaskKind.system) return trigger == AITrigger.user;
    return switch (mode) {
      AIMode.full => true,
      AIMode.onRequest => trigger == AITrigger.user,
      AIMode.captureOnly => trigger == AITrigger.user && kind == AITaskKind.capture,
      AIMode.off => false,
    };
  }

  /// Hinweis, wenn die Einstellung eine Anfrage verhindert.
  static String blockedMessage(AIMode mode) => switch (mode) {
    AIMode.full || AIMode.onRequest => 'Die KI läuft in dieser Einstellung nur auf Anfrage.',
    AIMode.captureOnly => 'KI-Empfehlungen sind ausgeschaltet (Einstellungen › KI).',
    AIMode.off => 'Die KI ist ausgeschaltet (Einstellungen › KI).',
  };
}

/// Bevorzugter KI-Anbieter. Welche eingerichtet sind, weiß der Worker; er weicht bei Ausfall auf die übrigen aus.
enum AIProviderChoice implements RawEnum {
  auto('auto'),

  /// Nur Anbieter, die Eingaben nicht zum Training nutzen (kein kostenloses Gemini).
  privat('privat'),
  workersAI('workers_ai'),
  gemini('gemini'),
  cerebras('cerebras'),
  groq('groq'),
  mistral('mistral'),
  github('github'),
  ownServer('openai_compat');

  const AIProviderChoice(this.rawValue);

  @override
  final String rawValue;

  String get label => switch (this) {
    auto => 'Automatisch',
    privat => 'Datenschutz zuerst',
    workersAI => 'Cloudflare Workers AI',
    gemini => 'Google Gemini',
    cerebras => 'Cerebras',
    groq => 'Groq',
    mistral => 'Mistral',
    github => 'GitHub Models',
    ownServer => 'Eigener Server',
  };

  String get detail => switch (this) {
    auto =>
      'Je Aufgabe der passende Anbieter: Fotos an Gemini, Pläne und Rezepte an Cerebras, Gespräche an Gemini. '
          'Ist ein Kontingent aufgebraucht, übernimmt der nächste.',
    privat =>
      'Nur Anbieter ohne Training mit deinen Eingaben: eigener Server, Cerebras, Groq, GitHub Models, Workers AI. '
          'Nie das kostenlose Gemini oder Mistral.',
    workersAI =>
      'Offene Modelle (Gemma 4) bei Cloudflare. 10.000 Neurons pro Tag frei (rund 150 Anfragen), keine Speicherung.',
    gemini => 'Stark bei Fotos und langen Texten. Im kostenlosen Kontingent darf Google Eingaben auswerten.',
    cerebras =>
      'Sehr schnell, GPT-OSS 120B, großes kostenloses Tageskontingent. Ohne Fotos. Laut Anbieter kein Training.',
    groq => 'Sehr schnell, Llama und GPT-OSS. Kostenloses Kontingent mit Tageslimits.',
    mistral =>
      'Europäischer Anbieter, sehr gutes Deutsch, auch Fotos. '
          'In der kostenlosen Stufe darf Mistral Eingaben auswerten.',
    github =>
      'GPT-4.1 über dein GitHub-Konto, auch Fotos. Kostenlos mit knappen Tageslimits. Laut GitHub kein Training.',
    ownServer => 'Eigenes Modell (z. B. Ollama auf dem PC) – nur, wenn im Worker eingerichtet. Ohne Fotos.',
  };
}

/// KI-Einstellungen der App.
final class AISettings {
  const AISettings({this.mode = AIMode.full, this.provider = AIProviderChoice.auto});

  final AIMode mode;
  final AIProviderChoice provider;

  AISettings copyWith({AIMode? mode, AIProviderChoice? provider}) =>
      AISettings(mode: mode ?? this.mode, provider: provider ?? this.provider);

  Map<String, Object?> toJson() => {'mode': mode.rawValue, 'provider': provider.rawValue};

  /// Tolerant: unbekannte oder fehlende Werte fallen auf die Standards zurück.
  static AISettings fromJson(Object? json) {
    if (json is! Map) return const AISettings();
    return AISettings(
      mode: enumFromRaw(AIMode.values, json['mode']) ?? AIMode.full,
      provider: enumFromRaw(AIProviderChoice.values, json['provider']) ?? AIProviderChoice.auto,
    );
  }

  @override
  bool operator ==(Object other) => other is AISettings && other.mode == mode && other.provider == provider;

  @override
  int get hashCode => Object.hash(mode, provider);

  @override
  String toString() => 'AISettings(${mode.rawValue}, ${provider.rawValue})';
}
