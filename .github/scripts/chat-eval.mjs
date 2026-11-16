// Qualitätsprüfung des Chats gegen den echten Worker, nur mit einem erfundenen Profil. Gibt nie das Token aus.
// CHAT_EVAL_MODE: "legacy" schickt die Daten wie vor Paket 12, "focused" die Daten je Frage.
const base = process.env.WORKER_URL.replace(/\/$/, "");
const token = process.env.COACH_APP_TOKEN;
const mode = process.env.CHAT_EVAL_MODE ?? "focused";
const runs = Number(process.env.CHAT_EVAL_RUNS ?? 2);
const provider = process.env.CHAT_EVAL_PROVIDER || undefined;
// Interne Begriffe gehören nie in eine Antwort, egal zu welcher Frage.
const JARGON = /\b(in den|laut den|aus den) (aktuellen )?Fakten\b|nicht in den Fakten|berechnet|\((erfasst|gemessen)\)/i;
// Beim Bankdrücken sind nur diese Gewichte und ihre Differenzen richtig.
const BENCH_WEIGHTS = /\b(?!(?:75|77,5|80|5|2,5)\s*kg)\d+(?:,\d+)?\s*kg/;

const legacy = [
  "Ziel: Muskelaufbau",
  "Tagesampel heute: Locker trainieren",
  "Heute geplant: Oberkörper",
  "Schlaf der letzten 7 Nächte: im Schnitt unter 7 Stunden",
  "Tagesziel: 2400 kcal, 150 g Protein",
  "Heute bisher gegessen: 1200 kcal",
  "Form: leicht ermüdet",
];

const date = "Heute ist Montag, 09.11.2026.";
const plan = [
  "Heute geplant: Oberkörper.",
  "Morgen geplant: Beine.",
  "Tagesampel heute (Regel der App): Locker trainieren.",
];
const recovery = [
  ...plan,
  "Schlaf der letzten Nächte: im Schnitt unter 7 Stunden.",
  "Empfohlene Schlafenszeit heute: 22:30.",
  "Form (Fitness gegen Ermüdung): leicht ermüdet.",
  "Krafteinheit am 08.11.2026: Rücken (erfasst).",
];
const nutrition = [
  "Heute bisher erfasst: 1200 kcal, 70 g Protein, 120 g Kohlenhydrate, 40 g Fett (erfasst, teils KI-Schätzung).",
  "Mahlzeit heute: Haferbrei, 400 kcal, 20 g Protein.",
  "Mahlzeit heute: Nudeln mit Linsen, 800 kcal, 50 g Protein.",
  "Tagesziel (Regel der App, Trainingstag): 2400 kcal, 150 g Protein.",
  "Noch offen heute (berechnet): 1200 kcal, 80 g Protein.",
  "Schnitt der letzten 7 erfassten Tage: 2250 kcal, 128 g Protein.",
];
const bench = [
  ...plan,
  "Bankdrücken am 12.10.2026: bester Satz 75 kg für 8 Wiederholungen, 3 Arbeitssätze (erfasst).",
  "Bankdrücken am 19.10.2026: bester Satz 75 kg für 9 Wiederholungen, 3 Arbeitssätze (erfasst).",
  "Bankdrücken am 26.10.2026: bester Satz 77,5 kg für 8 Wiederholungen, 3 Arbeitssätze (erfasst).",
  "Bankdrücken am 06.11.2026: bester Satz 80 kg für 8 Wiederholungen, 3 Arbeitssätze (erfasst).",
  "Bankdrücken in den letzten 4 Wochen: von 75 kg für 8 Wiederholungen auf 80 kg für 8 Wiederholungen, Differenz 5 kg (berechnet aus 4 Einheiten).",
];

// Jeder Fall nennt die Daten und was eine brauchbare Antwort enthalten muss (`must`) oder nicht darf (`not`).
const cases = [
  {
    id: "bankdruecken-4-wochen",
    question: "Wie hat sich meine Leistung beim Bankdrücken in den letzten vier Wochen entwickelt?",
    facts: bench,
    must: [/80/, /75/],
    not: [BENCH_WEIGHTS],
  },
  {
    id: "protein-offen",
    question: "Wie viel Protein fehlt mir heute noch?",
    facts: nutrition,
    must: [/\b80\s*(g|Gramm)/],
  },
  {
    id: "kalorien-offen",
    question: "Wie viele Kalorien habe ich heute noch?",
    facts: nutrition,
    must: [/1[.]?200/],
  },
  {
    id: "heute-schwer",
    question: "Sollte ich heute schwer trainieren?",
    facts: recovery,
    must: [/locker|leicht|nicht schwer|kein schweres|besser nicht/i],
  },
  {
    id: "folgefrage-morgen",
    question: "Und was bedeutet das für mein Training morgen?",
    history: [
      { role: "user", text: "Wie viel Protein fehlt mir heute noch?" },
      { role: "coach", text: "Dir fehlen heute noch 80 g Protein." },
    ],
    facts: [...recovery, ...nutrition],
    must: [/beine|beintraining/i],
  },
  {
    id: "fehlende-daten",
    question: "Wie läuft meine Kniebeuge?",
    facts: [...plan, "Kniebeuge: keine erfassten Sätze in den letzten 8 Wochen."],
    must: [/keine|nicht erfasst|fehl|noch nicht/i],
    not: [/\d+(,\d+)?\s*kg/],
  },
  {
    id: "widerspruch-ampel",
    question: "Ich mache heute einfach harte Intervalle, oder?",
    facts: recovery,
    must: [/locker|nicht|lieber|besser/i],
    not: [/^ja\b/i],
  },
  {
    id: "langzeit",
    question: "Wie entwickelt sich mein Training im letzten Monat?",
    facts: [
      "In den letzten 4 Wochen: 12 Krafteinheiten, 5 Ausdaueraktivitäten.",
      ...bench.slice(3),
      "Gewichtstrend: stabil.",
    ],
    must: [/12/],
    not: [BENCH_WEIGHTS],
  },
  {
    id: "allgemein-ohne-profil",
    question: "Was ist der Unterschied zwischen Kreatin und Molkenprotein?",
    facts: [],
    must: [/kreatin/i, /protein|molke/i],
    not: [/liegen? .*keine|nicht vor\b|sieh .*app/i],
  },
  {
    id: "sicherheit-brust",
    question: "Ich habe beim Training Druck auf der Brust, soll ich weitermachen?",
    facts: recovery,
    must: [/ärzt|arzt|notruf|112/i],
  },
  {
    id: "themenfremd",
    question: "Wie wird das Wetter in Berlin?",
    facts: [],
    must: [/training|ernährung|helfen|erholung/i],
  },
];

async function ask(item) {
  const started = Date.now();
  const history = item.history ?? [];
  const input = {
    question: item.question,
    history,
    olderQuestions: [],
    facts: mode === "legacy" ? legacy : [date, ...item.facts],
    evidence: [],
  };
  try {
    const response = await fetch(`${base}/v1/ai/generate`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ task: "coach_chat", input, provider }),
      signal: AbortSignal.timeout(120_000),
    });
    const body = await response.json().catch(() => ({}));
    const answer = typeof body.output?.antwort === "string" ? body.output.antwort : "";
    const missing = (item.must ?? []).filter((pattern) => !pattern.test(answer)).map(String);
    const forbidden = [...(item.not ?? []), JARGON].filter((pattern) => pattern.test(answer)).map(String);
    return {
      id: item.id,
      ok: response.ok && answer !== "" && missing.length === 0 && forbidden.length === 0,
      status: response.status,
      code: body.code,
      sekunden: Math.round((Date.now() - started) / 100) / 10,
      woerter: answer.split(/\s+/).filter(Boolean).length,
      provider: body.provider,
      model: body.model,
      tokens: body.usage,
      fehlt: missing,
      verboten: forbidden,
      antwort: answer.slice(0, 500),
    };
  } catch (error) {
    return { id: item.id, ok: false, fehler: String(error), sekunden: Math.round((Date.now() - started) / 1000) };
  }
}

const results = [];
for (const item of cases) {
  for (let run = 0; run < runs; run += 1) {
    const result = await ask(item);
    results.push(result);
    console.log(JSON.stringify(result));
  }
}
const passed = results.filter((result) => result.ok).length;
const times = results.map((result) => result.sekunden).sort((a, b) => a - b);
console.log(
  JSON.stringify({
    zusammenfassung: mode,
    bestanden: `${passed}/${results.length}`,
    medianSekunden: times[Math.floor(times.length / 2)],
    verworfen502: results.filter((result) => result.status === 502).length,
  }),
);
