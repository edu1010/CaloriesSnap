package com.example.calorie_snap

import android.app.Activity
import android.content.res.Configuration
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Privacy text Health Connect links to from its permission screens
 * ("read the privacy policy" on Android 9-13, permission usage on 14+).
 * Plain views so it opens without starting the Flutter engine.
 */
class HealthPermissionsRationaleActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        if (!night) {
            setTheme(android.R.style.Theme_DeviceDefault_Light_NoActionBar)
        }
        super.onCreate(savedInstanceState)
        if (!night) {
            // Dark system-bar icons; the light theme alone leaves them white.
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }

        val padding = dp(24)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
            addView(text(R.string.health_rationale_title, 22f).apply {
                setPadding(0, 0, 0, dp(16))
            })
            addView(text(R.string.health_rationale_body, 16f).apply {
                setLineSpacing(dp(4).toFloat(), 1f)
            })
        }
        setContentView(
            ScrollView(this).apply {
                // Android 15+ draws edge to edge; keep the text clear of the bars.
                fitsSystemWindows = true
                addView(content)
            },
        )
    }

    private fun text(resId: Int, sizeSp: Float) = TextView(this).apply {
        setText(resId)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setTextIsSelectable(true)
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()
}
