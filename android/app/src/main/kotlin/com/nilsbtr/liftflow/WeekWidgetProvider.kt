package com.nilsbtr.liftflow

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONObject

// The week strip and a start button. Dart only stores a snapshot (see
// lib/domain/home_widget.dart); the week is worked out here from today's
// date, so it is right after midnight without the app running.
class WeekWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val snapshot = Snapshot.read(widgetData)
        for (id in appWidgetIds) {
            val options = appWidgetManager.getAppWidgetOptions(id)
            appWidgetManager.updateAppWidget(id, views(context, snapshot, options))
        }
        scheduleMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) = onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))

    // The day or the clock changed.
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
                if (ids.isNotEmpty()) onUpdate(context, manager, ids)
            }
            else -> super.onReceive(context, intent)
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        context.getSystemService(AlarmManager::class.java)?.cancel(refreshIntent(context))
    }

    private fun refreshIntent(context: Context) =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, javaClass).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    // Inexact and not waking the device: it runs when the phone is next awake.
    private fun scheduleMidnight(context: Context) {
        val zone = ZoneId.systemDefault()
        val midnight = LocalDate.now(zone).plusDays(1).atStartOfDay(zone).toInstant()
        context
            .getSystemService(AlarmManager::class.java)
            ?.set(AlarmManager.RTC, midnight.toEpochMilli() + 1000, refreshIntent(context))
    }

    private fun views(context: Context, snapshot: Snapshot, options: Bundle): RemoteViews {
        val compact = layout(context, snapshot, R.layout.widget_week)
        val tall = layout(context, snapshot, R.layout.widget_week_tall)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(mapOf(SizeF(120f, 40f) to compact, SizeF(120f, TALL_DP) to tall))
        }
        val portrait =
            context.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT
        val height =
            options.getInt(
                if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT
                else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
            )
        return if (height >= TALL_DP) tall else compact
    }

    private fun layout(context: Context, snapshot: Snapshot, layoutId: Int): RemoteViews {
        val pkg = context.packageName
        val views = RemoteViews(pkg, layoutId)

        val today = LocalDate.now()
        val first = today.minusDays(((today.dayOfWeek.value - snapshot.firstDay + 7) % 7).toLong())
        views.removeAllViews(R.id.widget_week)
        for (i in 0L..6L) {
            val day = first.plusDays(i)
            val done = day.toString() in snapshot.days
            val cell = RemoteViews(pkg, R.layout.widget_day)
            cell.setTextViewText(R.id.widget_day_letter, LETTERS[day.dayOfWeek.value - 1])
            cell.setImageViewResource(
                R.id.widget_day_dot,
                when {
                    done && day == today -> R.drawable.widget_dot_done_today
                    done -> R.drawable.widget_dot_done
                    day == today -> R.drawable.widget_dot_today
                    else -> R.drawable.widget_dot
                },
            )
            views.addView(R.id.widget_week, cell)
        }

        val uri =
            when {
                snapshot.live -> "liftflow://widget/workout"
                snapshot.templateId != null ->
                    "liftflow://widget/start?template=${snapshot.templateId}"
                else -> "liftflow://widget/start"
            }
        views.setTextViewText(
            R.id.widget_label,
            when {
                snapshot.live -> context.getString(R.string.widget_continue)
                snapshot.templateId != null && snapshot.templateName != null ->
                    snapshot.templateName
                else -> context.getString(R.string.widget_start)
            },
        )
        views.setInt(
            R.id.widget_button,
            "setBackgroundResource",
            if (snapshot.live) R.drawable.widget_button_live else R.drawable.widget_button,
        )
        views.setOnClickPendingIntent(R.id.widget_button, launch(context, uri))
        views.setOnClickPendingIntent(
            android.R.id.background,
            launch(context, "liftflow://widget/open"),
        )
        return views
    }

    private fun launch(context: Context, uri: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

    private class Snapshot(
        val firstDay: Int,
        val days: Set<String>,
        val templateId: Int?,
        val templateName: String?,
        val live: Boolean,
    ) {
        companion object {
            // Lenient: after an app update the stored snapshot may be an older shape.
            fun read(prefs: SharedPreferences): Snapshot {
                val json =
                    runCatching { JSONObject(prefs.getString("snapshot", null) ?: "{}") }
                        .getOrDefault(JSONObject())
                val days = json.optJSONArray("days")
                val id = json.optInt("templateId", 0)
                return Snapshot(
                    firstDay = json.optInt("firstDay", 1).coerceIn(1, 7),
                    days =
                        buildSet {
                            for (i in 0 until (days?.length() ?: 0)) add(days!!.optString(i))
                        },
                    templateId = id.takeIf { it > 0 },
                    templateName = json.optString("templateName").ifBlank { null },
                    live = json.optBoolean("live", false),
                )
            }
        }
    }

    private companion object {
        const val ACTION_REFRESH = "com.nilsbtr.liftflow.widget.REFRESH"

        // From this height the button fits below the week instead of beside it.
        const val TALL_DP = 120f

        // By ISO weekday, Monday first. English like the rest of the app.
        val LETTERS = arrayOf("M", "T", "W", "T", "F", "S", "S")
    }
}
