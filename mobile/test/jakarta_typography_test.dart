import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trafficgo/core/design/traffic_theme.dart';

const nfc =
    "Đường Nguyễn Trãi\nHành trình của bạn\nĐiểm đến và thời gian dự kiến\nBảo dưỡng xe định kỳ\nQuãng đường di chuyển\nẮ Ằ Ẳ Ẵ Ặ\nẾ Ề Ể Ễ Ệ\nỚ Ờ Ở Ỡ Ợ\nỪ Ử Ữ Ự";
const nfd =
    "Đường Nguyễn Trãi\nHành trình của bạn\nĐiểm đến và thời gian dự kiến\nBảo dưỡng xe định kỳ\nQuãng đường di chuyển\nẮ Ằ Ẳ Ẵ Ặ\nẾ Ề Ể Ễ Ệ\nỚ Ờ Ở Ỡ Ợ\nỪ Ử Ữ Ự";
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final name in ['Medium', 'SemiBold', 'Bold']) {
      await (FontLoader(
            'PlusJakartaSans',
          )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$name.ttf')))
          .load();
    }
  });
  test('Material and Forui share local Jakarta weights and readable secondary text', () {
    for (final mode in Brightness.values) {
      final theme = TrafficTokens.material(mode);
      expect(theme.textTheme.bodyMedium!.fontFamily, 'PlusJakartaSans');
      expect(theme.textTheme.bodyMedium!.fontWeight, FontWeight.w500);
      expect(theme.textTheme.titleMedium!.fontWeight, FontWeight.w600);
      expect(theme.textTheme.headlineMedium!.fontWeight, FontWeight.w700);
      expect(
        TrafficTokens.forui(mode).typography.body.fontFamily,
        'PlusJakartaSans',
      );
      expect(
        TrafficTokens.forui(mode).typography.body.fontFamilyFallback,
        isEmpty,
      );
      final a = theme.colorScheme.onSurfaceVariant.computeLuminance();
      final b = theme.colorScheme.surface.computeLuminance();
      expect(
        ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
  for (final weight in [FontWeight.w500, FontWeight.w600, FontWeight.w700]) {
    testWidgets('Vietnamese NFC and NFD same pixels at weight ${weight.value}', (
      t,
    ) async {
      await t.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final key = GlobalKey();
      Future<Uint8List> render(String value, String suffix) async {
        await t.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                backgroundColor: const Color(0xfff5f6f2),
                body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: TrafficTokens.fontFamily,
                      fontWeight: weight,
                      fontSize: 22,
                      height: 1.65,
                      color: const Color(0xff171c24),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        late Uint8List pixels;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final path = File(
              'build/reports/jakarta-typography/weight-${weight.value}-$suffix.png',
            );
            await path.parent.create(recursive: true);
            await path.writeAsBytes(png!.buffer.asUint8List());
          }
          image.dispose();
        });
        return pixels;
      }

      final composed = await render(nfc, 'nfc');
      final decomposed = await render(nfd, 'nfd');
      expect(decomposed, orderedEquals(composed));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
  }
}
