package io.github.hkrb7p794w.aironludi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
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
            } else {
                fill(context, views, display)
            }
            manager.updateAppWidget(id, views)
        }
    }

    abstract fun fill(context: Context, views: RemoteViews, display: WidgetDisplay)

    companion object {
        val rows = intArrayOf(R.id.widget_row1, R.id.widget_row2, R.id.widget_row3, R.id.widget_row4)
    }
}

class TodayWidget : CoachWidget(R.layout.widget_today, "today") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay) {
        views.show(R.id.widget_badge, display.streak("streak"))
        val today = display.todayPart
        if (today == null) {
            views.show(R.id.widget_headline, "Neuer Tag – App öffnen")
            for (row in rows) views.show(row, null)
            return
        }
        val color = when (today.optString("level")) {
            "normal" -> Color.rgb(52, 199, 89)
            "locker" -> Color.rgb(255, 159, 10)
            "pause" -> Color.rgb(255, 69, 58)
            else -> Color.GRAY
        }
        views.setTextColor(R.id.widget_badge_level, color)
        views.show(R.id.widget_badge_level, "●")
        views.show(R.id.widget_headline, today.optString("headline"))
        val sessions = today.optJSONArray("sessions") ?: JSONArray()
        for ((index, row) in rows.take(3).withIndex()) {
            val session = sessions.optJSONObject(index)
            views.show(
                row,
                session?.let {
                    val mark = if (it.optBoolean("done")) "✓" else "○"
                    listOf(it.optString("title"), it.optString("target")).filter { text -> text.isNotEmpty() }
                        .joinToString(" · ").let { text -> "$mark $text" }
                },
            )
        }
        views.show(R.id.widget_row4, today.optString("week").ifEmpty { null })
    }
}

class NutritionWidget : CoachWidget(R.layout.widget_nutrition, "nutrition") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay) {
        views.show(R.id.widget_badge, display.streak("mealStreak"))
        val nutrition = display.nutrition
        if (nutrition == null) {
            views.show(R.id.widget_headline, "Ernährung – App öffnen")
            for (row in rows) views.show(row, null)
            return
        }
        val kcal = nutrition.optDouble("kcal", 0.0)
        val target = nutrition.optDouble("kcalTarget", Double.NaN)
        views.show(
            R.id.widget_headline,
            if (target.isNaN()) "${WidgetData.number(kcal)} kcal"
            else "${WidgetData.number(kcal)} / ${WidgetData.number(target)} kcal",
        )
        val protein = nutrition.optDouble("protein", 0.0)
        val proteinTarget = nutrition.optDouble("proteinTarget", Double.NaN)
        views.show(
            R.id.widget_row1,
            if (proteinTarget.isNaN()) "${protein.roundToInt()} g Protein"
            else "${protein.roundToInt()} / ${proteinTarget.roundToInt()} g Protein",
        )
        val water = nutrition.optDouble("waterMilliliters", 0.0)
        val waterTarget = nutrition.optDouble("waterTarget", Double.NaN)
        views.show(
            R.id.widget_row2,
            if (waterTarget.isNaN()) "💧 ${WidgetData.liters(water)}"
            else "💧 ${WidgetData.liters(water)} / ${WidgetData.liters(waterTarget)}",
        )
        val last = nutrition.optJSONObject("lastMeal")
        views.show(
            R.id.widget_row3,
            last?.let { "Zuletzt: ${it.optString("title")} · ${it.optDouble("kcal").roundToInt()} kcal" },
        )
        views.show(R.id.widget_row4, null)
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
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay) {
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
        val order = listOf("fruehstueck", "mittagessen", "abendessen", "snack")
        for ((index, raw) in order.withIndex()) {
            var part: JSONObject? = null
            for (item in 0 until (meals?.length() ?: 0)) {
                val candidate = meals!!.optJSONObject(item)
                if (candidate?.optString("category") == raw) part = candidate
            }
            val eaten = part?.optDouble("kcal", 0.0) ?: 0.0
            val mealTarget = part?.optDouble("target", Double.NaN) ?: Double.NaN
            val text = if (mealTarget.isNaN()) "${WidgetData.number(eaten)} kcal"
            else "${WidgetData.number(eaten)} / ${WidgetData.number(mealTarget)} kcal"
            views.show(rows[index], "＋ ${WidgetData.mealLabel(raw)} · $text")
            views.setOnClickPendingIntent(rows[index], WidgetData.open(context, "logMeal?mahlzeit=$raw", 100 + index))
        }
    }
}

class HealthWidget : CoachWidget(R.layout.widget_health, "health") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay) {
        views.show(R.id.widget_badge, if (display.healthIsOld) "von gestern" else null)
        val health = display.snapshot?.optJSONArray("health") ?: JSONArray()
        views.show(R.id.widget_headline, "Health")
        val titles = mapOf(
            "bodyBattery" to "Body Battery",
            "sleep" to "Schlaf",
            "hrv" to "HRV",
            "recovery" to "Recovery",
            "restingHeartRate" to "Ruhepuls",
            "stress" to "Stress",
        )
        for ((index, row) in rows.withIndex()) {
            val item = health.optJSONObject(index)
            views.show(
                row,
                item?.let {
                    val mark = when (it.optString("status")) {
                        "good" -> "🟢"
                        "attention" -> "🟠"
                        "missing" -> "⚪"
                        else -> "🔵"
                    }
                    "$mark ${titles[it.optString("metric")] ?: it.optString("metric")}: ${it.optString("value", "–")}"
                },
            )
        }
    }
}

class GymWidget : CoachWidget(R.layout.widget_gym, "gym") {
    override fun fill(context: Context, views: RemoteViews, display: WidgetDisplay) {
        val gym = display.gym
        if (gym == null) {
            views.show(R.id.widget_headline, "Gym – nur mit Krafttraining im Profil")
            for (row in rows) views.show(row, null)
            return
        }
        val running = gym.optBoolean("running")
        views.show(
            R.id.widget_headline,
            if (running) "Läuft: ${gym.optString("runningTitle", "Einheit")}"
            else gym.optString("next").ifEmpty { "Gym" },
        )
        views.show(R.id.widget_row1, if (running) null else gym.optString("nextDetail").ifEmpty { null })
        val last = gym.optJSONObject("last")
        views.show(
            R.id.widget_row2,
            last?.let {
                val day = WidgetData.day(it.optJSONObject("day"))
                val date = day?.let { value -> String.format(Locale.GERMANY, "%02d.%02d.", value.dayOfMonth, value.monthValue) }
                "Zuletzt: ${it.optString("title")} · ${date ?: ""} · ${it.optInt("sets")} Sätze"
            },
        )
        val planned = gym.optInt("weekPlanned", 0)
        val done = gym.optInt("weekDone", 0)
        views.show(R.id.widget_row3, if (planned > 0) "Woche: $done von $planned" else "Woche: $done")
        views.show(R.id.widget_row4, null)
        views.setOnClickPendingIntent(R.id.widget_root, WidgetData.open(context, "startWorkout", 5))
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
