import '../../models/daily_activity.dart';

enum ActivitySyncAvailability {
  available,

  /// The platform has no such provider (e.g. Health Connect on Windows).
  unsupportedPlatform,

  /// The provider app/module is missing and can be installed.
  providerNotInstalled,

  /// The provider is present but too old.
  providerUpdateRequired,
}

enum ActivitySyncStatus {
  success,
  unsupportedPlatform,
  providerNotInstalled,
  providerUpdateRequired,
  permissionDenied,
  failed,
}

class ActivitySyncOutcome {
  const ActivitySyncOutcome({
    required this.status,
    this.importedDays = 0,
    this.syncedAt,
    this.message,
  });

  final ActivitySyncStatus status;

  /// Days of the requested range for which the provider returned any data.
  final int importedDays;
  final DateTime? syncedAt;

  /// Technical detail of a [ActivitySyncStatus.failed] outcome.
  final String? message;

  bool get isSuccess => status == ActivitySyncStatus.success;
}

/// Thrown by [ActivitySyncSource.fetchDays] when the provider call fails.
class ActivitySyncException implements Exception {
  const ActivitySyncException(this.message);

  final String message;

  @override
  String toString() => 'ActivitySyncException: $message';
}

/// A real on-device activity provider that can be read on user request.
abstract class ActivitySyncSource {
  ActivitySource get source;

  Future<ActivitySyncAvailability> checkAvailability();

  /// True when the minimum read permissions needed by the source are granted.
  /// Optional metrics must not cause repeated permission prompts.
  Future<bool> hasPermissions();

  /// Shows the provider's permission UI. Returns true when the permissions
  /// needed to read at least energy data were granted.
  Future<bool> requestPermissions();

  /// Per-day totals for local days in [startInclusive, endExclusive). Days
  /// without data are omitted; metrics the provider has no data or no
  /// permission for are left null. Throws [ActivitySyncException] on failure.
  Future<List<DailyActivity>> fetchDays(
    DateTime startInclusive,
    DateTime endExclusive,
  );

  /// Opens the provider's install/update page or its settings, when the
  /// platform has one. Returns false when nothing could be opened.
  Future<bool> openProviderSetup();
}
