// Lightweight smoke test: verifies the app's localization wiring resolves
// without touching plugins or the database (those need a full device/host and
// would hang in a headless `flutter test` run).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calorie_snap/core/l10n/app_localizations.dart';

void main() {
  Widget wrap(Locale locale) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Text(AppLocalizations.of(context).today),
      ),
    );
  }

  testWidgets('localization resolves Spanish strings', (tester) async {
    await tester.pumpWidget(wrap(const Locale('es')));
    await tester.pumpAndSettle();
    expect(find.text('Hoy'), findsOneWidget);
  });

  testWidgets('localization resolves English strings', (tester) async {
    await tester.pumpWidget(wrap(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
  });
}
