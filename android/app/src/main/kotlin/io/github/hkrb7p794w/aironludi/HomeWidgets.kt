package io.github.hkrb7p794w.aironludi

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.LocalDate
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Homescreen-Widgets unter Android (Gegenstück zu `HomeWidgets.swift`): Heute, Ernährung mit Wasser-Knopf,
 * Mahlzeiten mit „+“ je Mahlzeit, Health und Gym. Sie lesen nur den Stand, den die App schreibt
 * (`widget-snapshot.json` im Datenordner, Format wie unter iOS), und merken Wasser in `widget-actions.json` vor – die
 * App übernimmt es beim nächsten Öffnen.
 */
object WidgetData {
    const val SNAPSHOT = "widget-snapshot.json"
    const val QUEUE = "widget-actions.json"

    /** Sekunden zwischen 1970 und 2001 (Referenzdatum von `JSONEncoder` unter iOS). */
    private const val REFERENCE_OFFSET = 978_307_200.0

    private val lock = Any()

    fun snapshot(context: Context): JSONObject? = read(File(context.filesDir, SNAPSHOT))

    private fun read(file: File): JSONObject? = try {
        if (file.exists()) JSONObject(file.readText()) else null
    } catch (error: Exception) {
        null
    }

    private fun write(file: File, json: JSONObject) {
        val temp = File(file.parentFile, file.name + ".tmp")
        temp.writeText(json.toString())
        temp.renameTo(file)
    }

    fun day(json: JSONObject?): LocalDate? = json?.let {
        try {
            LocalDate.of(it.getInt("year"), it.getInt("month"), it.getInt("day"))
        } catch (error: Exception) {
            null
        }
    }

    fun dayJson(day: LocalDate) = JSONObject().put("year", day.year).put("month", day.monthValue).put("day", day.dayOfMonth)

    /** Wasser vormerken (wie `WidgetActionQueue.addWater`). */
    fun addWater(context: Context, milliliters: Double) {
        synchronized(lock) {
            val file = File(context.filesDir, QUEUE)
            val queue = read(file) ?: JSONObject()
            val entries = queue.optJSONArray("entries") ?: JSONArray()
            val now = System.currentTimeMillis() / 1000.0
            entries.put(
                JSONObject()
                    .put("id", UUID.randomUUID().toString().uppercase(Locale.ROOT))
                    .put("day", dayJson(LocalDate.now()))
                    .put("at", now - REFERENCE_OFFSET)
                    .put("waterMilliliters", milliliters),
            )
            write(file, queue.put("entries", entries))
        }
    }

    /** Vorgemerktes Wasser eines Tages, das die App noch nicht übernommen hat. */
    fun pendingWater(context: Context, day: LocalDate): Double {
        val entries = read(File(context.filesDir, QUEUE))?.optJSONArray("entries") ?: return 0.0
        var total = 0.0
        for (index in 0 until entries.length()) {
            val entry = entries.optJSONObject(index) ?: continue
            if (day(entry.optJSONObject("day")) == day) total += entry.optDouble("waterMilliliters", 0.0)
        }
        return total
    }

    fun number(value: Double): String = String.format(Locale.GERMANY, "%,d", value.roundToInt())

    /** Eine Nachkommastelle mit Komma, ohne „,0“ (wie `GermanFormat.decimal`). */
    fun decimal(value: Double): String {
        val rounded = (value * 10).roundToInt() / 10.0
        return if (rounded == rounded.toInt().toDouble()) rounded.toInt().toString()
        else String.format(Locale.GERMANY, "%.1f", rounded)
    }

    fun liters(milliliters: Double) = "${decimal(milliliters / 1000)} l"

    fun mealLabel(raw: String) = when (raw) {
        "fruehstueck" -> "Frühstück"
        "mittagessen" -> "Mittagessen"
        "abendessen" -> "Abendessen"
        else -> "Snack"
    }

    fun open(context: Context, route: String, code: Int): PendingIntent = PendingIntent.getActivity(
        context,
        code,
        Intent(Intent.ACTION_VIEW, Uri.parse("coach://open/$route"), context, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Alle Widgets neu zeichnen (nach neuem Stand der App oder getipptem Wasser). */
    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (provider in listOf(
            TodayWidget::class.java,
            NutritionWidget::class.java,
            MealsWidget::class.java,
            HealthWidget::class.java,
            GymWidget::class.java,
        )) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) continue
            context.sendBroadcast(
                Intent(context, provider)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            )
        }
    }
}

/** Stand für die Anzeige heute (wie `WidgetSnapshot.display(on:)`): am neuen Tag nichts Geschätztes. */
class WidgetDisplay(context: Context) {
    val snapshot: JSONObject? = WidgetData.snapshot(context)
    private val today: LocalDate = LocalDate.now()
    private val day: LocalDate? = WidgetData.day(snapshot?.optJSONObject("day"))

    /** Stand ist von heute. */
    val isCurrent = day == today

    /** Gesundheitswerte stammen nicht von der letzten Nacht. */
    val healthIsOld = day != null && today.isAfter(day)
    private val pendingWater = WidgetData.pendingWater(context, today)

    /** Serie („🔥 5“) – am Folgetag läuft sie weiter, älter ist sie unbekannt. */
    fun streak(key: String): String? {
        val streak = snapshot?.optJSONObject(key) ?: return null
        if (day == null || (!isCurrent && day.plusDays(1) != today)) return null
        val days = streak.optInt("days")
        return if (days > 0) "🔥 $days" else null
    }

    val todayPart: JSONObject? get() = if (isCurrent) snapshot?.optJSONObject("today") else null

    /** Ernährung von heute; am neuen Tag leer. */
    val nutrition: JSONObject?
        get() {
            val nutrition = snapshot?.optJSONObject("nutrition") ?: return null
            val result = if (isCurrent) JSONObject(nutrition.toString()) else JSONObject().put("kcal", 0).put("protein", 0)
                .put("waterMilliliters", 0)
            result.put("waterMilliliters", result.optDouble("waterMilliliters", 0.0) + pendingWater)
            return result
        }

    val gym: JSONObject?
        get() {
            val gym = snapshot?.optJSONObject("gym") ?: return null
            if (isCurrent) return gym
            val copy = JSONObject(gym.toString()).put("running", false)
            copy.remove("runningTitle")
            if (gym.optBoolean("nextIsForDay", false)) {
                copy.put("next", "App öffnen")
                copy.remove("nextDetail")
            }
            val monday = { date: LocalDate -> date.minusDays((date.dayOfWeek.value - 1).toLong()) }
            if (day == null || monday(day) != monday(today)) copy.put("weekDone", 0)
            return copy
        }
}

private fun RemoteViews.show(id: Int, text: String?) {
    if (text.isNullOrEmpty()) {
        setViewVisibility(id, View.GONE)
    } else {
        setViewVisibility(id, View.VISIBLE)
        setTextViewText(id, text)
    }
}

/** Farben wie die Ringe der iPhone-Widgets. */
object WidgetColors {
    val good = Color.rgb(52, 199, 89)
    val caution = Color.rgb(255, 159, 10)
    val alert = Color.rgb(255, 69, 58)
    val info = Color.rgb(10, 132, 255)
    val neutral = Color.rgb(142, 142, 147)

    fun status(raw: String?) = when (raw) {
        "good" -> good
        "attention" -> caution
        "missing" -> neutral
        else -> info
    }
}

/** Ein Ring der Ringreihe: Anteil 0–1 (`null` = kein Wert), Farbe, Titel und Wert darunter. */
data class WidgetRing(
    val fraction: Double?,
    val color: Int,
    val title: String,
    val value: String,
    val route: String? = null,
)

/** Zeichnet Ringe als Bild (RemoteViews kennen keine eigenen Zeichnungen). */
object WidgetRings {
    private val slots = intArrayOf(R.id.widget_slot1, R.id.widget_slot2, R.id.widget_slot3, R.id.widget_slot4)
    private val images = intArrayOf(R.id.widget_ring1, R.id.widget_ring2, R.id.widget_ring3, R.id.widget_ring4)
    private val titles =
        intArrayOf(R.id.widget_ring_title1, R.id.widget_ring_title2, R.id.widget_ring_title3, R.id.widget_ring_title4)
    private val values =
        intArrayOf(R.id.widget_ring_value1, R.id.widget_ring_value2, R.id.widget_ring_value3, R.id.widget_ring_value4)

    fun bitmap(context: Context, fraction: Double?, color: Int): Bitmap {
        val size = (44 * context.resources.displayMetrics.density).toInt().coerceAtLeast(24)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val stroke = size * 0.14f
        val inset = stroke / 2 + 1
        val bounds = RectF(inset, inset, size - inset, size - inset)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }
        paint.color = Color.argb(46, Color.red(color), Color.green(color), Color.blue(color))
        canvas.drawArc(bounds, 0f, 360f, false, paint)
        if (fraction != null && fraction > 0) {
            paint.color = color
            canvas.drawArc(bounds, -90f, (360 * fraction.coerceIn(0.0, 1.0)).toFloat(), false, paint)
        }
        return bitmap
    }

    fun show(context: Context, views: RemoteViews, rings: List<WidgetRing>) {
        views.setViewVisibility(R.id.widget_rings, if (rings.isEmpty()) View.GONE else View.VISIBLE)
        for (index in slots.indices) {
            val ring = rings.getOrNull(index)
            if (ring == null) {
                views.setViewVisibility(slots[index], View.GONE)
                continue
            }
            views.setViewVisibility(slots[index], View.VISIBLE)
            views.setImageViewBitmap(images[index], bitmap(context, ring.fraction, ring.color))
            views.setTextViewText(titles[index], ring.title)
            views.setTextViewText(values[index], ring.value)
            if (ring.route != null) {
                views.setOnClickPendingIntent(slots[index], WidgetData.open(context, ring.route, 200 + index))
            }
        }
    }
}

/**
 * Einstellung je Widget (wie die Widget-Optionen unter iOS): gespeichert je Widget-ID; ohne Einstellung gilt der
 * Standard der iOS-Widgets.
 */
object WidgetSettings {
    private const val PREFERENCES = "aironludi.widgets"

    private fun preferences(context: Context) = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun string(context: Context, id: Int, key: String, default: String): String =
        preferences(context).getString("$id.$key", null) ?: default

    fun bool(context: Context, id: Int, key: String, default: Boolean): Boolean =
        preferences(context).getBoolean("$id.$key", default)

    fun put(context: Context, id: Int, key: String, value: Any) {
        val editor = preferences(context).edit()
        when (value) {
            is Boolean -> editor.putBoolean("$id.$key", value)
            else -> editor.putString("$id.$key", value.toString())
        }
        editor.apply()
    }

    fun remove(context: Context, ids: IntArray) {
        val editor = preferences(context).edit()
        val all = preferences(context).all.keys
        for (id in ids) all.filter { it.startsWith("$id.") }.forEach(editor::remove)
        editor.apply()
    }
}

/** Gemeinsamer Ablauf: ohne Stand bittet das Widget ums Öffnen der App. */
abstract class CoachWidget(private val layout: Int, private val route: String) : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val display = WidgetDisplay(context)
        for (id in ids) {
            val views = RemoteViews(context.packageName, layout)
            views.setOnClickPendingIntent(R.id.widget_root, WidgetData.open(context, route, layout))
            if (display.snapshot == null) {
                views.show(R.id.widget_headline, "App öffnen, um das Widget zu füllen")
                for (row in rows) views.show(row, null)
                WidgetRings.show(context, views, emptyList())
            } else {
                fill(context, views, display, id)
            }
            manager.updateAppWidget(id, views)
        }
    }

    override fun onDeleted(context: Context, ids: IntArray) = WidgetSettings.remove(context, ids)

    abstract fun fill(context: Context, views: RemoteViews, display: WidgetDisplay, id: Int)

    companion object {
        val rows = intArrayOf(R.id.widget_row1, R.id.widget_row2, R.id.widget_row3, R.id.widget_row4)

        fun hideRows(views: RemoteViews) {
            for (row in rows) views.show(row, null)
        }

        /** Wert eines Health-Eintrags (`gauge` 0–100) als Anteil. */
        fun gauge(item: JSONObject?): Double? =
            item?.optDouble("gauge", Double.NaN)?.takeUnless { it.isNaN() }?.let { it / 100 }

        fun healthItem(display: WidgetDisplay, metric: String): JSONObject? {
            val health = display.snapshot?.optJSONArray("health") ?: return null
            for (index in 0 until health.length()) {
                val item = health.optJSONObject(index)
                if (item?.optString("metric") == metric) return item
            }
            return null
        }
    }
}

class TodayWidget : CoachWidget(R.layout.widget_today, "today") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay, id: Int) {
        views.show(R.id.widget_badge, display.streak("streak"))
        val today = display.todayPart
        if (today == null) {
            views.show(R.id.widget_headline, "Neuer Tag – App öffnen")
            hideRows(views)
            WidgetRings.show(context, views, emptyList())
            return
        }
        val color = when (today.optString("level")) {
            "normal" -> WidgetColors.good
            "locker" -> WidgetColors.caution
            "pause" -> WidgetColors.alert
            else -> WidgetColors.neutral
        }
        views.setTextColor(R.id.widget_badge_level, color)
        views.show(R.id.widget_badge_level, "●")
        views.show(R.id.widget_headline, today.optString("headline"))
        hideRows(views)
        // Ringe wie unter iOS: Training, Kalorien und Body Battery (je nach Einstellung), Woche.
        val sessions = today.optJSONArray("sessions") ?: JSONArray()
        var done = 0
        var next: String? = null
        for (index in 0 until sessions.length()) {
            val session = sessions.optJSONObject(index) ?: continue
            if (session.optBoolean("done")) done++ else if (next == null) next = session.optString("title")
        }
        val total = sessions.length()
        val rings = mutableListOf(
            WidgetRing(
                if (total > 0) done.toDouble() / total else null,
                WidgetColors.good,
                "Training",
                next ?: if (total > 0) "erledigt" else "frei",
            ),
        )
        val nutrition = display.nutrition
        if (WidgetSettings.bool(context, id, "showsNutrition", true) && nutrition != null) {
            val kcal = nutrition.optDouble("kcal", 0.0)
            val target = nutrition.optDouble("kcalTarget", Double.NaN)
            rings += WidgetRing(
                if (target.isNaN() || target <= 0) null else kcal / target,
                WidgetColors.info,
                "Kalorien",
                if (target.isNaN()) "${WidgetData.number(kcal)} kcal" else "${WidgetData.number(target - kcal)} übrig",
                "nutrition",
            )
        }
        if (WidgetSettings.bool(context, id, "showsBodyBattery", true)) {
            healthItem(display, "bodyBattery")?.let {
                rings += WidgetRing(gauge(it), WidgetColors.status(it.optString("status")), "Battery", it.optString("value", "–"))
            }
        }
        val week = today.optString("week")
        rings += WidgetRing(
            today.optDouble("weekFraction", Double.NaN).takeUnless { it.isNaN() },
            WidgetColors.info,
            "Woche",
            week.substringBefore("·").trim().ifEmpty { "–" },
        )
        WidgetRings.show(context, views, rings.take(4))
    }
}

class NutritionWidget : CoachWidget(R.layout.widget_nutrition, "nutrition") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay, id: Int) {
        views.show(R.id.widget_badge, display.streak("mealStreak"))
        val nutrition = display.nutrition
        if (nutrition == null) {
            views.show(R.id.widget_headline, "Ernährung – App öffnen")
            hideRows(views)
            WidgetRings.show(context, views, emptyList())
            return
        }
        val kcal = nutrition.optDouble("kcal", 0.0)
        val target = nutrition.optDouble("kcalTarget", Double.NaN)
        val protein = nutrition.optDouble("protein", 0.0)
        val proteinTarget = nutrition.optDouble("proteinTarget", Double.NaN)
        val water = nutrition.optDouble("waterMilliliters", 0.0)
        val waterTarget = nutrition.optDouble("waterTarget", Double.NaN)
        val last = nutrition.optJSONObject("lastMeal")
        // Anzeige wie unter iOS: verbleibende Kalorien (Standard), Tageskalorien, Protein oder letzte Mahlzeit.
        views.show(
            R.id.widget_headline,
            when (WidgetSettings.string(context, id, "display", "remaining")) {
                "eaten" -> if (target.isNaN()) "${WidgetData.number(kcal)} kcal"
                else "${WidgetData.number(kcal)} / ${WidgetData.number(target)} kcal"
                "protein" -> if (proteinTarget.isNaN()) "${protein.roundToInt()} g Protein"
                else "${protein.roundToInt()} / ${proteinTarget.roundToInt()} g Protein"
                "lastMeal" -> last?.let { "Zuletzt: ${it.optString("title")} · ${it.optDouble("kcal").roundToInt()} kcal" }
                    ?: "Noch keine Mahlzeit"
                else -> when {
                    target.isNaN() -> "${WidgetData.number(kcal)} kcal"
                    target - kcal >= 0 -> "Noch ${WidgetData.number(target - kcal)} kcal"
                    else -> "${WidgetData.number(kcal - target)} kcal über Ziel"
                }
            },
        )
        hideRows(views)
        fun ratio(value: Double, goal: Double) = if (goal.isNaN() || goal <= 0) null else value / goal
        WidgetRings.show(
            context,
            views,
            listOf(
                WidgetRing(ratio(kcal, target), WidgetColors.info, "Kalorien", WidgetData.number(kcal)),
                WidgetRing(ratio(protein, proteinTarget), WidgetColors.good, "Protein", "${protein.roundToInt()} g"),
                WidgetRing(ratio(water, waterTarget), Color.rgb(50, 173, 230), "Wasser", WidgetData.liters(water)),
            ),
        )
        val water250 = PendingIntent.getBroadcast(
            context,
            250,
            Intent(context, WaterReceiver::class.java).setAction(WaterReceiver.ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_button, water250)
    }
}

class MealsWidget : CoachWidget(R.layout.widget_meals, "logMeal") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay, id: Int) {
        views.show(R.id.widget_badge, display.streak("mealStreak"))
        val nutrition = display.nutrition
        val meals = if (display.isCurrent) nutrition?.optJSONArray("meals") else null
        val kcal = nutrition?.optDouble("kcal", 0.0) ?: 0.0
        val target = if (display.isCurrent) nutrition?.optDouble("kcalTarget", Double.NaN) ?: Double.NaN else Double.NaN
        views.show(
            R.id.widget_headline,
            when {
                target.isNaN() -> "Mahlzeiten"
                target - kcal >= 0 -> "Noch ${WidgetData.number(target - kcal)} kcal frei"
                else -> "${WidgetData.number(abs(target - kcal))} kcal über Ziel"
            },
        )
        hideRows(views)
        // Je Mahlzeit ein Ring (gegessen gegen Richtwert); Tippen öffnet das Erfassen dieser Mahlzeit.
        val order = listOf("fruehstueck", "mittagessen", "abendessen", "snack")
        val rings = order.map { raw ->
            var part: JSONObject? = null
            for (item in 0 until (meals?.length() ?: 0)) {
                val candidate = meals!!.optJSONObject(item)
                if (candidate?.optString("category") == raw) part = candidate
            }
            val eaten = part?.optDouble("kcal", 0.0) ?: 0.0
            val mealTarget = part?.optDouble("target", Double.NaN) ?: Double.NaN
            WidgetRing(
                if (mealTarget.isNaN() || mealTarget <= 0) (if (eaten > 0) 1.0 else null) else eaten / mealTarget,
                WidgetColors.info,
                WidgetData.mealLabel(raw),
                if (eaten > 0) "${WidgetData.number(eaten)} kcal" else "＋",
                "logMeal?mahlzeit=$raw",
            )
        }
        WidgetRings.show(context, views, rings)
    }
}

class HealthWidget : CoachWidget(R.layout.widget_health, "health") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay, id: Int) {
        views.show(R.id.widget_badge, if (display.healthIsOld) "von gestern" else null)
        val health = display.snapshot?.optJSONArray("health") ?: JSONArray()
        val titles = mapOf(
            "bodyBattery" to "Body Battery",
            "sleep" to "Schlaf",
            "hrv" to "HRV",
            "recovery" to "Erholung",
            "restingHeartRate" to "Ruhepuls",
            "stress" to "Stress",
        )
        // Gewählter Wert als Überschrift (Standard Body Battery), darunter bis zu vier Ringe.
        val chosen = WidgetSettings.string(context, id, "metric", "bodyBattery")
        val main = healthItem(display, chosen)
        views.show(
            R.id.widget_headline,
            main?.let { "${titles[chosen] ?: chosen}: ${it.optString("value", "–")}" } ?: "Health",
        )
        hideRows(views)
        val items = (0 until health.length()).mapNotNull { health.optJSONObject(it) }
            .sortedBy { if (it.optString("metric") == chosen) 0 else 1 }
        WidgetRings.show(
            context,
            views,
            items.take(4).map {
                val metric = it.optString("metric")
                WidgetRing(gauge(it), WidgetColors.status(it.optString("status")), titles[metric] ?: metric, it.optString("value", "–"))
            },
        )
    }
}

class GymWidget : CoachWidget(R.layout.widget_gym, "gym") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay, id: Int) {
        val gym = display.gym
        if (gym == null) {
            views.show(R.id.widget_headline, "Gym – nur mit Krafttraining im Profil")
            hideRows(views)
            WidgetRings.show(context, views, emptyList())
            return
        }
        val running = gym.optBoolean("running")
        val last = gym.optJSONObject("last")
        val lastText = last?.let {
            val day = WidgetData.day(it.optJSONObject("day"))
            val date = day?.let { value -> String.format(Locale.GERMANY, "%02d.%02d.", value.dayOfMonth, value.monthValue) }
            "${it.optString("title")} · ${date ?: ""} · ${it.optInt("sets")} Sätze"
        }
        val planned = gym.optInt("weekPlanned", 0)
        val done = gym.optInt("weekDone", 0)
        val weekText = if (planned > 0) "$done von $planned" else "$done"
        // Anzeige wie unter iOS: nächstes Training (Standard), letzte Einheit oder Wochenfortschritt.
        views.show(
            R.id.widget_headline,
            when {
                running -> "Läuft: ${gym.optString("runningTitle", "Einheit")}"
                else -> when (WidgetSettings.string(context, id, "focus", "next")) {
                    "last" -> lastText?.let { "Zuletzt: $it" } ?: "Noch keine Einheit"
                    "week" -> "Woche: $weekText"
                    else -> gym.optString("next").ifEmpty { "Gym" }
                }
            },
        )
        hideRows(views)
        views.show(R.id.widget_row1, if (running) null else gym.optString("nextDetail").ifEmpty { null })
        WidgetRings.show(
            context,
            views,
            listOf(
                WidgetRing(
                    if (planned > 0) done.toDouble() / planned else null,
                    WidgetColors.good,
                    "Woche",
                    weekText,
                ),
            ),
        )
        views.setOnClickPendingIntent(R.id.widget_root, WidgetData.open(context, "startWorkout", 5))
    }
}

/**
 * Einstellung eines Widgets beim Hinzufügen und über „Widget bearbeiten“ (wie die Widget-Optionen unter iOS). Zeigt
 * eine Auswahl, speichert sie je Widget und zeichnet die Widgets neu.
 */
class WidgetConfigActivity : Activity() {
    private var widgetID = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        widgetID = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Abbrechen fügt das Widget mit der Standard-Anzeige hinzu (Einstellung ist optional).
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetID))
        if (widgetID == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetID)?.provider?.className ?: ""
        when {
            provider.endsWith("TodayWidget") -> multiChoice(
                "Heute",
                listOf("showsNutrition" to "Kalorien zeigen", "showsBodyBattery" to "Body Battery zeigen"),
            )
            provider.endsWith("NutritionWidget") -> singleChoice(
                "Ernährung",
                "display",
                listOf(
                    "remaining" to "Verbleibende Kalorien",
                    "eaten" to "Tageskalorien",
                    "protein" to "Protein",
                    "lastMeal" to "Letzte Mahlzeit",
                ),
            )
            provider.endsWith("HealthWidget") -> singleChoice(
                "Health",
                "metric",
                listOf(
                    "bodyBattery" to "Body Battery",
                    "sleep" to "Schlaf",
                    "hrv" to "HRV",
                    "recovery" to "Erholung",
                    "restingHeartRate" to "Ruhepuls",
                    "stress" to "Stress",
                ),
            )
            provider.endsWith("GymWidget") -> singleChoice(
                "Gym",
                "focus",
                listOf("next" to "Nächstes Training", "last" to "Letzte Einheit", "week" to "Wochenfortschritt"),
            )
            else -> finish()
        }
    }

    private fun done() {
        WidgetData.updateAll(this)
        finish()
    }

    private fun singleChoice(title: String, key: String, options: List<Pair<String, String>>) {
        val current = WidgetSettings.string(this, widgetID, key, options.first().first)
        AlertDialog.Builder(this)
            .setTitle(title)
            .setSingleChoiceItems(
                options.map { it.second }.toTypedArray(),
                options.indexOfFirst { it.first == current }.coerceAtLeast(0),
            ) { dialog, which ->
                WidgetSettings.put(this, widgetID, key, options[which].first)
                dialog.dismiss()
            }
            .setOnDismissListener { done() }
            .show()
    }

    private fun multiChoice(title: String, options: List<Pair<String, String>>) {
        val checked = options.map { WidgetSettings.bool(this, widgetID, it.first, true) }.toBooleanArray()
        AlertDialog.Builder(this)
            .setTitle(title)
            .setMultiChoiceItems(options.map { it.second }.toTypedArray(), checked) { _, which, on ->
                WidgetSettings.put(this, widgetID, options[which].first, on)
            }
            .setPositiveButton("Fertig") { dialog, _ -> dialog.dismiss() }
            .setOnDismissListener { done() }
            .show()
    }
}

/** „+250 ml“ im Ernährungs-Widget (wie `AddWaterIntent`). */
class WaterReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        WidgetData.addWater(context, 250.0)
        WidgetData.updateAll(context)
    }

    companion object {
        const val ACTION = "io.github.hkrb7p794w.aironludi.ADD_WATER"
    }
}
