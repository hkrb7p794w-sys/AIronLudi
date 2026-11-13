/// Die ersten [count] Zeichen wie `String(text.prefix(count))` in Swift (nach Unicode-Zeichen, nicht nach
/// UTF-16-Einheiten, damit kein Umlaut oder Emoji halbiert wird).
String textPrefix(String text, int count) => String.fromCharCodes(text.runes.take(count));
