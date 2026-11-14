package io.github.hkrb7p794w.aironludi

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import java.util.Calendar

/**
 * Wecker zur Aufstehzeit unter Android (Kanal `aironludi/alarm`, Gegenstück zu AlarmKit): `AlarmManager.setAlarmClock`
 * klingelt pünktlich, auch im Ruhemodus, und erscheint als nächster Wecker in der Statusleiste. Beim Klingeln eine
 * Vollbild-Mitteilung mit Weckton, bis „Aus“ getippt wird; Wiederholungen stellt der Empfänger für den nächsten Tag
 * neu, nach einem Neustart ebenso. Es gibt höchstens einen Wecker der App.
 */
object WakeAlarm {
    private const val PREFERENCES = "aironludi.alarm"
    private const val CHANNEL_ID = "wake_alarm"
    private const val NOTIFICATION_ID = 4712
    const val RING = "io.github.hkrb7p794w.aironludi.WAKE_ALARM"
    const val STOP = "io.github.hkrb7p794w.aironludi.WAKE_ALARM_STOP"

    fun handle(context: Context, method: String, arguments: Map<*, *>?): Any? = when (method) {
        "state" -> if (canSchedule(context)) "authorized" else "denied"
        "alarms" -> listOfNotNull(preferences(context).getString("id", null))
        "schedule" -> schedule(context, arguments)
        "cancel" -> {
            cancel(context)
            null
        }
        else -> throw IllegalArgumentException(method)
    }

    private fun preferences(context: Context) = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun manager(context: Context) = context.getSystemService(AlarmManager::class.java)

    private fun canSchedule(context: Context) =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager(context).canScheduleExactAlarms()

    private fun schedule(context: Context, arguments: Map<*, *>?): Boolean {
        val id = arguments?.get("id") as? String ?: return false
        val hour = (arguments["hour"] as? Number)?.toInt() ?: return false
        val minute = (arguments["minute"] as? Number)?.toInt() ?: return false
        val weekdays = (arguments["weekdays"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() } ?: emptyList()
        if (!canSchedule(context)) return false
        preferences(context).edit()
            .putString("id", id)
            .putInt("hour", hour)
            .putInt("minute", minute)
            .putString("weekdays", weekdays.joinToString(","))
            .apply()
        return arm(context)
    }

    /** Nächsten Termin stellen (nach dem Stellen, nach dem Klingeln einer Wiederholung, nach einem Neustart). */
    fun arm(context: Context): Boolean {
        val stored = preferences(context)
        if (stored.getString("id", null) == null || !canSchedule(context)) return false
        val hour = stored.getInt("hour", 7)
        val minute = stored.getInt("minute", 0)
        val weekdays = stored.getString("weekdays", "")!!.split(",").mapNotNull { it.toIntOrNull() }.toSet()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
            // Kalender-Wochentage wie in Swift: 1 = Sonntag … 7 = Samstag.
            while (weekdays.isNotEmpty() && get(Calendar.DAY_OF_WEEK) !in weekdays) add(Calendar.DAY_OF_YEAR, 1)
        }
        val show = PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        manager(context).setAlarmClock(AlarmManager.AlarmClockInfo(next.timeInMillis, show), ringIntent(context))
        return true
    }

    private fun ringIntent(context: Context) = PendingIntent.getBroadcast(
        context,
        2,
        Intent(context, WakeAlarmReceiver::class.java).setAction(RING),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun cancel(context: Context) {
        manager(context).cancel(ringIntent(context))
        preferences(context).edit().clear().apply()
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    /** Klingeln: Vollbild-Mitteilung mit Weckton (wiederholt, bis „Aus“), dann den nächsten Termin stellen. */
    fun ring(context: Context) {
        val stored = preferences(context)
        if (stored.getString("id", null) == null) return
        val notifications = context.getSystemService(NotificationManager::class.java)
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Wecker", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Wecker zur empfohlenen Aufstehzeit"
                setSound(
                    sound,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(true)
                setBypassDnd(true)
            },
        )
        val open = PendingIntent.getActivity(
            context,
            3,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getBroadcast(
            context,
            4,
            Intent(context, WakeAlarmReceiver::class.java).setAction(STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Guten Morgen – Zeit aufzustehen")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setFullScreenIntent(open, true)
            .setContentIntent(open)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, "Aus", stop).build())
            .build()
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        notifications.notify(NOTIFICATION_ID, notification)
        // Einmaliger Wecker ist damit erledigt; Wiederholungen klingeln am nächsten passenden Tag.
        if (stored.getString("weekdays", "").isNullOrEmpty()) {
            stored.edit().clear().apply()
        } else {
            arm(context)
        }
    }

    fun stop(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }
}

/** Klingeln, „Aus“ und Neustart des Geräts. */
class WakeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            WakeAlarm.RING -> WakeAlarm.ring(context)
            WakeAlarm.STOP -> WakeAlarm.stop(context)
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> WakeAlarm.arm(context)
        }
    }
}
