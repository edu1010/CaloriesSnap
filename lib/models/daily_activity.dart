/// Where a day's activity record came from.
///
/// Declared in priority order: when a day has records from several sources,
/// the first one in this list is the only one used. Sources are never summed,
/// so the same walk reported by a watch and typed by hand is not counted twice.
enum ActivitySource {
  manual('manual'),
  healthConnect('health_connect'),
  csvImport('csv_import');

  const ActivitySource(this.storageKey);

  /// Stable identifier persisted in the database.
  final String storageKey;

  static ActivitySource? fromStorageKey(String? key) {
    for (final source in values) {
      if (source.storageKey == key) {
        return source;
      }
    }
    return null;
  }
}

/// One source's activity totals for one local calendar day.
///
/// Every metric is nullable: null means "this source did not report it", which
/// is different from a reported zero.
class DailyActivity {
  const DailyActivity({
    required this.date,
    required this.source,
    required this.updatedAt,
    this.activeKcal,
    this.totalKcal,
    this.steps,
    this.distanceMeters,
    this.activeMinutes,
    this.origin,
  });

  /// Local midnight of the day the totals belong to.
  final DateTime date;
  final ActivitySource source;
  final DateTime updatedAt;

  /// Energy burned through activity only (excludes resting metabolism).
  final double? activeKcal;

  /// Total energy expenditure (active + resting), only when the source
  /// reported it. Never estimated by this app.
  final double? totalKcal;
  final int? steps;
  final double? distanceMeters;

  /// Minutes of recorded exercise sessions.
  final int? activeMinutes;

  /// Free-form provenance: the apps that wrote the data into Health Connect
  /// (comma separated package names) or the imported CSV file name.
  final String? origin;

  bool get hasAnyMetric =>
      activeKcal != null ||
      totalKcal != null ||
      steps != null ||
      distanceMeters != null ||
      activeMinutes != null;

  /// Null when the record is acceptable, otherwise the offending field name.
  String? get invalidField {
    bool bad(num? v, num max) => v != null && (!v.isFinite || v < 0 || v > max);
    if (bad(activeKcal, 30000)) return 'activeKcal';
    if (bad(totalKcal, 30000)) return 'totalKcal';
    if (bad(steps, 300000)) return 'steps';
    if (bad(distanceMeters, 1000000)) return 'distanceMeters';
    if (bad(activeMinutes, 1440)) return 'activeMinutes';
    if (activeKcal != null && totalKcal != null && activeKcal! > totalKcal!) {
      return 'activeKcal';
    }
    return null;
  }
}

/// Persisted result of the last synchronisation attempt for a source.
class ActivitySyncState {
  const ActivitySyncState({
    required this.source,
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastError,
    this.lastImportedDays,
  });

  final ActivitySource source;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;

  /// Short machine-readable reason of the last failed attempt (an
  /// `ActivitySyncStatus` name), null when the last attempt succeeded.
  final String? lastError;
  final int? lastImportedDays;
}
