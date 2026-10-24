// Isolated typography proof. Does not register or select this font in the app.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const sentence =
    'Trường Đại học CMC — Nguyễn Thị Thúy: xuất phát lúc 06:55, đến nơi đúng giờ.';
const sentenceNfd =
    'Trường Đại học CMC — Nguyễn Thị Thúy: xuất phát lúc 06:55, đến nơi đúng giờ.';
const marks = """ă â đ ê ô ơ ư · Ă Â Đ Ê Ô Ơ Ư
ắ ằ ẳ ẵ ặ · ấ ầ ẩ ẫ ậ · ớ ờ ở ỡ ợ
ứ ừ ử ữ ự · ế ề ể ễ ệ · ỳ ý ỷ ỹ ỵ""";

void main() {
  testWidgets('Local Jakarta 700 and 800 Vietnamese proof at iPhone viewport', (
    t,
  ) async {
    const base = String.fromEnvironment('JAKARTA_PROOF_DIR');
    for (final name in ['Bold', 'ExtraBold']) {
      final bytes = File(
        '$base'
        'PlusJakartaSans-$name.ttf',
      ).readAsBytesSync();
      await (FontLoader(
        'Proof$name',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await t.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    final metrics = <String, dynamic>{};
    for (final variant in [
      ('light', false, sentence),
      ('dark', true, sentence),
      ('nfd-light', false, sentenceNfd),
    ]) {
      final dark = variant.$2;
      final proof = variant.$3;
      final ink = dark ? const Color(0xfff5f6f2) : const Color(0xff171c24);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: dark
                  ? const Color(0xff14171b)
                  : const Color(0xfff5f6f2),
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Plus Jakarta Sans',
                      style: TextStyle(
                        fontFamily: 'ProofBold',
                        fontSize: 22,
                        color: ink,
                      ),
                    ),
                    Text(
                      'Flutter render · 393 × 852 · không phải iPhone thật',
                      style: TextStyle(
                        fontFamily: 'ProofBold',
                        fontSize: 12,
                        color: ink,
                      ),
                    ),
                    for (final name in ['Bold', 'ExtraBold']) ...[
                      const SizedBox(height: 20),
                      Text(
                        name == 'Bold' ? 'BOLD 700' : 'EXTRABOLD 800',
                        style: TextStyle(
                          fontFamily: 'ProofBold',
                          fontSize: 12,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xffc6f36b),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          proof,
                          style: TextStyle(
                            fontFamily: 'Proof$name',
                            fontSize: 24,
                            height: 1.35,
                            color: const Color(0xff171c24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        marks,
                        style: TextStyle(
                          fontFamily: 'Proof$name',
                          fontSize: 16,
                          height: 1.55,
                          color: ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await render.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$base'
          'comparison-${variant.$1}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      for (final name in ['Bold', 'ExtraBold']) {
        final p = TextPainter(
          text: TextSpan(
            text: proof,
            style: TextStyle(
              fontFamily: 'Proof$name',
              fontSize: 24,
              height: 1.35,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 321);
        metrics['${variant.$1}-$name'] = {
          'width': p.width,
          'height': p.height,
          'lines': p.computeLineMetrics().length,
          'has_missing_font_fallback_config': false,
        };
        p.dispose();
      }
    }
    File(
      '$base'
      'render-metrics.json',
    ).writeAsStringSync(jsonEncode(metrics));
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  }, skip: !const bool.fromEnvironment('JAKARTA_PROOF'));
}
