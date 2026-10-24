import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/core/design/traffic_theme.dart';
import 'package:trafficgo/core/design/sheets.dart';
import 'package:trafficgo/features/departure/controller.dart';
import 'package:trafficgo/features/departure/day_exception.dart';
import 'package:trafficgo/features/departure/models.dart';

import 'departure_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const path = String.fromEnvironment('QA_FONT_PATH');
    if (path.isNotEmpty) {
      final bytes = await File(path).readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  for (final dark in [false, true]) {
    testWidgets(
      'Exception modal: ${dark ? 'dark 320px 200% text' : 'light 390px'}',
      (tester) async {
        tester.view.physicalSize = Size(dark ? 320 : 390, 694);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final dio = Dio();
        final c = DepartureController(dio, prefs);
        await c.ready;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              preferencesProvider.overrideWithValue(prefs),
              departureProvider.overrideWith((ref) => c),
            ],
            child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('vi'),
                supportedLocales: const [Locale('vi')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: TrafficTokens.material(
                  dark ? Brightness.dark : Brightness.light,
                ),
                builder: (context, child) => TrafficDesignScope(
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(dark ? 2 : 1)),
                    child: child!,
                  ),
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showTrafficSheet(
                        context,
                        title: 'Ngoại lệ lịch lặp',
                        builder: (_) => DayExceptionEditor(
                          schedule: CommuteSchedule(
                            Map<String, dynamic>.from(
                              (fixture.overview()['schedules'] as List).first,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Mở ngoại lệ'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Mở ngoại lệ'));
        await tester.pumpAndSettle();
        expect(find.text('Ngoại lệ lịch lặp'), findsOneWidget);
        await tester.ensureVisible(find.text('Nghỉ / bỏ qua ngày này'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/reports/schedule-actions-qa/${dark ? 'dark-large' : 'light-normal'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
        if (!c.disposed) c.dispose();
        dio.close();
      },
    );
  }
}
