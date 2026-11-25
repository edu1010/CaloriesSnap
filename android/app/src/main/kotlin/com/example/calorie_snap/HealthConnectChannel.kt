package com.example.calorie_snap

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.RemoteException
import androidx.activity.ComponentActivity
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.lifecycle.lifecycleScope
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.time.LocalDate
import java.time.Period
import java.time.format.DateTimeParseException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Read-only, foreground-only bridge to Health Connect.
 *
 * Must be constructed while the activity is being created: the permission
 * launcher can only be registered before the activity reaches STARTED.
 */
class HealthConnectChannel(private val activity: ComponentActivity) :
    MethodChannel.MethodCallHandler {

    private enum class Metric(
        val key: String,
        val permission: String,
        val aggregate: AggregateMetric<*>,
        val read: (AggregationResult) -> Any?,
    ) {
        ACTIVE_KCAL(
            "activeKcal",
            HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
            ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
            { it[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories },
        ),
        TOTAL_KCAL(
            "totalKcal",
            HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
            TotalCaloriesBurnedRecord.ENERGY_TOTAL,
            { it[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories },
        ),
        STEPS(
            "steps",
            HealthPermission.getReadPermission(StepsRecord::class),
            StepsRecord.COUNT_TOTAL,
            { it[StepsRecord.COUNT_TOTAL] },
        ),
        DISTANCE(
            "distanceMeters",
            HealthPermission.getReadPermission(DistanceRecord::class),
            DistanceRecord.DISTANCE_TOTAL,
            { it[DistanceRecord.DISTANCE_TOTAL]?.inMeters },
        ),
        ACTIVE_MINUTES(
            "activeMinutes",
            HealthPermission.getReadPermission(ExerciseSessionRecord::class),
            ExerciseSessionRecord.EXERCISE_DURATION_TOTAL,
            { it[ExerciseSessionRecord.EXERCISE_DURATION_TOTAL]?.toMinutes() },
        ),
    }

    private class ChannelException(val code: String, message: String) : Exception(message)

    private var pendingPermissionResult: MethodChannel.Result? = null

    private val permissionLauncher = activity.registerForActivityResult(
        PermissionController.createRequestPermissionResultContract(),
    ) {
        // Null after process death: the Dart caller that asked no longer exists.
        val result = pendingPermissionResult ?: return@registerForActivityResult
        pendingPermissionResult = null
        // The contract only reports the permissions of this request; ask the
        // provider for the full granted set instead.
        reply(result) { grantedMetrics() }
    }

    fun attach(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSdkStatus" -> reply(result) { sdkStatus() }
            "getGrantedPermissions" -> reply(result) { grantedMetrics() }
            "requestPermissions" -> requestPermissions(result)
            "aggregateDays" -> reply(result) {
                aggregateDays(call.dateArgument("start"), call.dateArgument("end"))
            }
            "openSetup" -> reply(result) { withContext(Dispatchers.Main) { openSetup() } }
            else -> result.notImplemented()
        }
    }

    /** Runs [block] off the main thread and answers [result] exactly once on it. */
    private fun reply(result: MethodChannel.Result, block: suspend () -> Any?) {
        activity.lifecycleScope.launch {
            try {
                result.success(withContext(Dispatchers.IO) { block() })
            } catch (e: CancellationException) {
                throw e
            } catch (e: ChannelException) {
                result.error(e.code, e.message, null)
            } catch (e: SecurityException) {
                result.error("permissionDenied", e.message, null)
            } catch (e: IOException) {
                result.error("io", e.message, null)
            } catch (e: RemoteException) {
                result.error("remote", e.message, null)
            } catch (e: IllegalStateException) {
                result.error("illegalState", e.message, null)
            } catch (e: Exception) {
                result.error("unknown", "${e.javaClass.simpleName}: ${e.message}", null)
            }
        }
    }

    private fun sdkStatus(): String {
        // Health Connect does not exist below Android 9 and cannot be added.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return "unsupported"
        val frameworkModule = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        return when (HealthConnectClient.getSdkStatus(activity)) {
            HealthConnectClient.SDK_AVAILABLE -> "available"
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> when {
                // On Android 14+ it ships with the system; only an update can fix it.
                frameworkModule -> "updateRequired"
                // The library reports "missing" and "too old" with the same status.
                isProviderInstalled() -> "updateRequired"
                else -> "notInstalled"
            }
            // A 14+ device without the system module cannot get it from the store.
            else -> if (frameworkModule) "unsupported" else "notInstalled"
        }
    }

    private fun isProviderInstalled(): Boolean = try {
        activity.packageManager.getPackageInfo(PROVIDER_PACKAGE, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun client(): HealthConnectClient {
        val status = sdkStatus()
        if (status != "available") {
            throw ChannelException("unavailable", "Health Connect is not available ($status)")
        }
        return HealthConnectClient.getOrCreate(activity)
    }

    private suspend fun grantedMetrics(): List<String> {
        val granted = client().permissionController.getGrantedPermissions()
        return Metric.entries.filter { it.permission in granted }.map { it.key }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("requestInProgress", "A permission request is already open", null)
            return
        }
        if (sdkStatus() != "available") {
            result.error("unavailable", "Health Connect is not available", null)
            return
        }
        pendingPermissionResult = result
        try {
            permissionLauncher.launch(Metric.entries.map { it.permission }.toSet())
        } catch (e: Exception) {
            pendingPermissionResult = null
            val code = if (e is ActivityNotFoundException) "unavailable" else "illegalState"
            result.error(code, e.message, null)
        }
    }

    private suspend fun aggregateDays(start: LocalDate, end: LocalDate): List<Map<String, Any?>> {
        if (!start.isBefore(end)) {
            throw ChannelException("invalidArgs", "start must be before end")
        }
        val client = client()
        val granted = client.permissionController.getGrantedPermissions()
        // Aggregating a metric without its permission fails the whole request.
        val metrics = Metric.entries.filter { it.permission in granted }
        if (metrics.isEmpty()) {
            throw ChannelException("permissionDenied", "No Health Connect read permission granted")
        }
        // Local date-times make each bucket a local calendar day, and the
        // provider's aggregation de-duplicates overlapping apps (phone + watch).
        val groups = client.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(
                metrics = metrics.map { it.aggregate }.toSet(),
                timeRangeFilter = TimeRangeFilter.between(start.atStartOfDay(), end.atStartOfDay()),
                timeRangeSlicer = Period.ofDays(1),
            ),
        )
        return groups.mapNotNull { group ->
            val values = metrics.mapNotNull { metric ->
                metric.read(group.result)?.let { metric.key to it }
            }
            if (values.isEmpty()) {
                null
            } else {
                buildMap {
                    put("date", group.startTime.toLocalDate().toString())
                    putAll(values)
                    put("origins", group.result.dataOrigins.map { it.packageName }.sorted())
                }
            }
        }
    }

    private fun openSetup(): Boolean {
        val candidates = when (sdkStatus()) {
            "available" -> listOf(
                Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS),
                HealthConnectClient.getHealthConnectManageDataIntent(activity),
            )
            "unsupported" -> emptyList()
            else -> listOf(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PROVIDER_PACKAGE&url=$ONBOARDING_URL"))
                    .setPackage("com.android.vending")
                    .putExtra("overlay", true)
                    .putExtra("callerId", activity.packageName),
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$PROVIDER_PACKAGE"),
                ),
            )
        }
        return candidates.any { intent ->
            try {
                activity.startActivity(intent)
                true
            } catch (_: ActivityNotFoundException) {
                false
            } catch (_: SecurityException) {
                false
            }
        }
    }

    private fun MethodCall.dateArgument(name: String): LocalDate {
        val raw = argument<String>(name)
            ?: throw ChannelException("invalidArgs", "Missing argument '$name'")
        return try {
            LocalDate.parse(raw)
        } catch (_: DateTimeParseException) {
            throw ChannelException("invalidArgs", "Argument '$name' is not a yyyy-MM-dd date: $raw")
        }
    }

    private companion object {
        const val CHANNEL = "calorie_snap/health_connect"
        const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"
        const val ONBOARDING_URL = "healthconnect%3A%2F%2Fonboarding"
    }
}
