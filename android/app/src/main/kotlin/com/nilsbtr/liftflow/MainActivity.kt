package com.nilsbtr.liftflow

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.plugin.common.MethodChannel

// local_auth shows its prompt from a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    // An activity restored or reopened from recents gets its first intent again.
    // If that was a widget tap, it must not start another workout.
    override fun onCreate(savedInstanceState: Bundle?) {
        val replayed =
            savedInstanceState != null ||
                intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (replayed && intent.action == HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) {
            intent = Intent(Intent.ACTION_MAIN).setClass(this, javaClass)
        }
        super.onCreate(savedInstanceState)
    }

    // A tap that reopens a task whose process was killed arrives here before
    // Dart listens. Kept as the intent, Dart reads it as the launch tap.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lift_flow/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method == "setRecentsHidden") {
                    setRecentsHidden(call.arguments as? Boolean ?: false)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // Android 13+ can drop just the recents thumbnail. Older versions only have
    // FLAG_SECURE, which also blocks screenshots and screen recording.
    private fun setRecentsHidden(hidden: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(!hidden)
        } else if (hidden) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
