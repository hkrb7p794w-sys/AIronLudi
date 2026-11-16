// Prüft die Rezeptideen gegen den echten Worker mit erfundenen Profilen. Gibt nie das Token aus.
const base = process.env.WORKER_URL.replace(/\/$/, "");
const token = process.env.COACH_APP_TOKEN;

const names = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];
const days = names.map((wochentag, index) => ({
  datum: `2026-11-${String(9 + index).padStart(2, "0")}`,
  wochentag,
  training: index % 2 ? "frei" : "Lockerer Lauf",
  tagestyp: index % 2 ? "Ruhetag" : "Moderater Trainingstag",
  kcal: index % 2 ? 2100 : 2500,
  protein_g: 150,
  kohlenhydrate_g: index % 2 ? 230 : 330,
  fett_g: 70,
}));
const input = (count) => ({
  days: days.slice(0, count),
  diet: "pescetarisch",
  dietLabel: "Pescetarisch",
  goal: "Gewicht halten",
  allergens: [],
  dislikes: "",
  maxMinutes: 30,
  snacks: true,
  mealPrep: false,
  gaps: ["Ballaststoffe: im Schnitt 18 von 30 g (60 %)"],
  favorites: ["Skyr", "Haferflocken", "Lachs"],
  evidence: [],
});

async function run(label, count, provider) {
  const started = Date.now();
  try {
    const response = await fetch(`${base}/v1/ai/generate`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ task: "weekly_recipes", input: input(count), provider }),
      signal: AbortSignal.timeout(150_000),
    });
    const text = await response.text();
    let body = {};
    try {
      body = JSON.parse(text);
    } catch {
      body = { error: `keine JSON-Antwort: ${text.slice(0, 200)}` };
    }
    const tage = body.output?.tage;
    const dishes = Array.isArray(tage) ? tage.reduce((sum, day) => sum + (day.gerichte?.length ?? 0), 0) : 0;
    console.log(
      JSON.stringify({
        label,
        tage: count,
        status: response.status,
        sekunden: Math.round((Date.now() - started) / 1000),
        provider: body.provider,
        model: body.model,
        usage: body.usage,
        erhalteneTage: Array.isArray(tage) ? tage.length : 0,
        gerichte: dishes,
        error: typeof body.error === "string" ? body.error.slice(0, 1200) : undefined,
      }),
    );
  } catch (error) {
    console.log(JSON.stringify({ label, fehler: String(error), sekunden: Math.round((Date.now() - started) / 1000) }));
  }
}

async function cook(label, plates, partner, prep) {
  const started = Date.now();
  const personen = [{ bezeichnung: "Person 1", teller: plates, kcal: 720, protein_g: 48, kohlenhydrate_g: 84, fett_g: 24 }];
  if (partner) personen.push({ bezeichnung: "Person 2", teller: partner, kcal: 540, protein_g: 30, kohlenhydrate_g: 60, fett_g: 18 });
  let response;
  try {
    response = await fetch(`${base}/v1/ai/generate`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({
      task: "cook_plan",
      provider: "auto",
      input: { personen, mahlzeit: "abendessen", mahlzeiten_je_person: plates, vorkochen: prep, diet: "vegetarisch", allergens: ["Erdnüsse"], dislikes: "Pilze", maxMinutes: 40, favorites: [] },
    }),
    signal: AbortSignal.timeout(150_000),
  });
  } catch (error) {
    console.log(JSON.stringify({ label, fehler: String(error), sekunden: Math.round((Date.now() - started) / 1000) }));
    return;
  }
  const body = await response.json().catch(() => ({}));
  const rezepte = body.output?.rezepte ?? [];
  console.log(JSON.stringify({
    label, status: response.status, sekunden: Math.round((Date.now() - started) / 1000), provider: body.provider, model: body.model,
    tokens: body.usage?.outputTokens, code: body.code, error: body.error,
    rezepte: rezepte.map((r) => ({ titel: r.titel, zutaten: r.zutaten?.length, vorkochen: r.vorkochen_geeignet, haltbar: r.haltbarkeit_tage, einfrierbar: r.einfrierbar, kompromiss: (r.kompromiss ?? "").slice(0, 160) })),
  }));
}

const health = await (await fetch(`${base}/v1/health`)).json();
console.log(JSON.stringify({ version: health.version, anbieter: health.providerList?.map((p) => [p.id, p.enabled, p.model]) }));
await run("wie die App (auto), zwei Tage", 2, "auto");
await run("ohne Gemini (privat), zwei Tage", 2, "privat");
await cook("zwei Personen, zwei Portionen", 2, 2, false);
await cook("zwei Personen, drei Tage vorkochen", 3, 3, true);
await cook("eine Person, vier Tage vorkochen", 4, 0, true);
