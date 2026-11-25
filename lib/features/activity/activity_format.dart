import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/app_localizations.dart';
import '../../models/daily_activity.dart';

/// Locale-aware number and date formatting shared by the activity widgets.
class ActivityFormat {
  ActivityFormat._(this.localeTag);

  factory ActivityFormat.of(BuildContext context) {
    return ActivityFormat._(Localizations.localeOf(context).toLanguageTag());
  }

  /// Shown wherever a value is unknown, so it never reads as zero.
  static const missing = '—';

  final String localeTag;

  String whole(num value) {
    return NumberFormat.decimalPattern(localeTag).format(value.round());
  }

  String signedWhole(num value) {
    final rounded = value.round();
    if (rounded > 0) {
      return '+${whole(rounded)}';
    }
    if (rounded < 0) {
      return '−${whole(-rounded)}';
    }
    return whole(0);
  }

  String kilometres(double meters) {
    return NumberFormat('#,##0.0#', localeTag).format(meters / 1000);
  }

  String weekday(DateTime date) => DateFormat.E(localeTag).format(date);

  String dayMonth(DateTime date) => DateFormat.MMMd(localeTag).format(date);

  String fullDate(DateTime date) => DateFormat.yMMMEd(localeTag).format(date);

  String longDate(DateTime date) =>
      DateFormat.MMMMEEEEd(localeTag).format(date);

  String dateTime(DateTime value) {
    return DateFormat.yMMMd(localeTag).add_Hm().format(value);
  }
}

String activitySourceName(AppLocalizations l10n, ActivitySource source) {
  switch (source) {
    case ActivitySource.manual:
      return l10n.sourceManual;
    case ActivitySource.healthConnect:
      return l10n.sourceHealthConnect;
    case ActivitySource.csvImport:
      return l10n.sourceCsvImport;
  }
}
