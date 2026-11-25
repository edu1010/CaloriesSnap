# Goals, activity and wearable data

What the "Goals & activity" screen really does, where its numbers come from and
what it does not support.

## Summary

| Capability | Android | Windows |
| --- | --- | --- |
| Daily / weekly intake goals | yes | yes |
| Today and Monday–Sunday panels | yes | yes |
| Manual daily activity entry | yes | yes |
| CSV import | yes | yes |
| Health Connect synchronisation | yes (Android 9+) | no |
| Direct Xiaomi / Huawei / Strava account | no | no |
| Cloud sync or backup | no | no |

Everything is stored on the device, in `calorie_snap_activity.db` next to the
meals database (`calorie_snap.db`, whose schema is unchanged). Nothing is
uploaded, and nothing is written back to Health Connect.

## Goals

- A daily and a weekly **intake** goal, both optional, both positive kcal.
- They are independent: the weekly goal is not the daily goal × 7 and editing
  one never changes the other. Leaving a field empty clears that goal.
- The app does not suggest a target and does not estimate basal metabolism from
  age, weight or height. Type the numbers you got from wherever you trust.

## What the panels show

- **Consumed**: sum of the meals logged for the day / week.
- **Remaining**: goal minus consumed, shown only when the goal is set.
- **Active burned**: energy from activity only, as reported by the day's source.
- **Total burned**: active + resting expenditure, only when the source reports
  it. Many trackers share active calories only.
- **Net energy**: consumed minus total burned. It is shown only when total
  expenditure is known; active calories alone do not give an energy balance.
- **Steps, distance, exercise minutes**: when the source has them.

A missing value is shown as missing, not as zero. Weekly figures only add up the
days that have the value and say how many days that is ("data for 3 of 5
days"); weekly net energy is restricted to the days with known total
expenditure and is labelled as partial unless every elapsed day has it.

## One source per day

Each day uses a single activity record, chosen in this order:

1. Manual entry
2. Health Connect
3. CSV import

Sources are never added together, so a walk recorded by a watch and also typed
by hand is not counted twice. The choice is per record, not per field: a manual
entry with only steps hides that day's imported calories. Deleting the manual
entry brings the imported record back.

## Health Connect (Android)

Health Connect is Android's on-device health data store. CalorieSnap reads from
it with the official Jetpack client (`androidx.health.connect:connect-client`),
through a small native bridge (`HealthConnectChannel.kt`).

- **When**: only while the app is open and you tap **Synchronise**. There is no
  background sync.
- **What**: daily totals for the last 14 days of active calories, total
  calories, steps, distance and exercise-session duration. Read permissions
  only (`READ_ACTIVE_CALORIES_BURNED`, `READ_TOTAL_CALORIES_BURNED`,
  `READ_STEPS`, `READ_DISTANCE`, `READ_EXERCISE`).
- **How**: Health Connect's own daily aggregation is used, which removes
  overlaps between apps (phone and watch counting the same steps) according to
  the app priority you set inside Health Connect.
- **Permissions**: asked on the first sync. At least one of the two calorie
  permissions is needed; the other types are optional and simply stay empty if
  declined. A re-sync replaces the Health Connect records of those 14 days.
- **Availability**:
  - Android 14+: part of the system.
  - Android 9–13: needs the *Health Connect* app from Google Play; the screen
    offers to open its store page when it is missing or outdated.
  - Android 8: not supported by Health Connect.

Limits worth knowing:

- Health Connect only hands over data from up to 30 days before the permission
  was first granted.
- Total calories are whatever the writing apps stored. If a day's total comes
  back lower than its active calories, it was written for part of the day only
  and CalorieSnap treats the total as unknown.
- If Android stops showing the permission dialog (after repeated denials),
  grant access from Health Connect's own settings.

### Getting Xiaomi, Huawei and Strava data in

CalorieSnap never signs in to these services. Their data shows up only if the
app on your phone shares it with Health Connect:

| App | What to do |
| --- | --- |
| Mi Fitness (Xiaomi) | Profile → Third-party data → Health Connect; allow it to write activity data. Availability depends on the app and device. |
| Strava | You → Settings → Manage Apps and Devices → Health Connect. Strava shares time, distance and calories from GPS activities; these are not an all-day expenditure measurement. |
| Huawei Health | There is no direct Huawei connection in CalorieSnap. Use a compatible bridge that writes Huawei data to Health Connect, or convert an export to the CSV schema below. Bridge availability depends on region, permissions and provider support. |

Menu names can change between app versions. Then open Health Connect → *App permissions* and check that the app
may write and CalorieSnap may read.

Official setup references: [Xiaomi Mi Fitness sharing](https://www.mi.com/pk/support/faq/details/KA-728033/),
[Strava and Health Connect](https://support.strava.com/en-us/articles/15401554-health-connect-and-strava),
[Android Health Connect setup](https://developer.android.com/health-and-fitness/health-connect/get-started).

### Why there is no direct Huawei or Strava login

Direct account integration requires a vendor-registered application and user
authorization. Strava's OAuth exchange requires a client secret, which must
remain on a backend rather than be embedded in the app. Huawei Health Kit also
requires vendor setup and permission scopes for the chosen integration. This
project has no registered provider configuration or token-exchange server, so
direct account login is not implemented. Xiaomi data is read through Health
Connect; the app does not use a private Mi Fitness API.

References: [Strava authentication](https://developers.strava.com/docs/authentication/),
[Huawei Health Kit](https://developer.huawei.com/consumer/en/hms/huaweihealth/).

## Manual entry

Available everywhere and offline. Active kcal, total kcal, steps, distance and
exercise minutes are all optional, but at least one is required. Fill in total
kcal only if your device reports total expenditure. A manual entry can be
edited or deleted from the same screen.

## CSV import

For data exported or converted from another service. The vendors' own export
formats are not parsed; convert them to this schema first.

```csv
date,active_kcal,total_kcal,steps,distance_km,active_minutes
2026-10-05,420,2350,9120,6.8,45
2026-10-06,310,,7400,5.1,
```

- UTF-8 (BOM allowed), `,` or `;` as delimiter, quoted fields allowed.
- A header row is required. Column names are case-insensitive and may come in
  any order. `date` plus at least one metric column must be present; unknown
  columns are ignored.
- `date`: `yyyy-MM-dd`, a real date, not in the future.
- `active_kcal`, `total_kcal`: 0–30000, active not above total.
- `steps`: whole number, 0–300000. `distance_km`: 0–1000.
  `active_minutes`: whole number, 0–1440.
- Plain numbers with a decimal point (a decimal comma is accepted only with the
  `;` delimiter). No units, signs or thousands separators.
- An empty cell means "not reported".
- Rows that fail validation are listed with their line number and skipped; the
  valid rows are still imported after you confirm. If a date appears twice, the
  first valid row wins.
- Importing a date again replaces that date's CSV record. CSV has the lowest
  priority, so days with manual or Health Connect data keep showing those.

## Code map

- Models: `lib/models/calorie_goals.dart`, `daily_activity.dart`,
  `energy_summary.dart`
- Storage: `lib/data/repositories/activity_repository.dart`
- Logic: `lib/services/activity/` (dashboard service, sync coordinator, CSV
  importer, Health Connect source)
- Native: `android/app/src/main/kotlin/com/example/calorie_snap/`
- UI: `lib/features/activity/`
