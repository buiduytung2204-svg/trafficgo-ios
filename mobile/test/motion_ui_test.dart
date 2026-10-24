import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:trafficgo/core/design/components.dart';
import 'package:trafficgo/core/design/traffic_theme.dart';
import 'package:trafficgo/core/design/sheets.dart';
import 'package:trafficgo/features/journeys/store.dart';
import 'package:trafficgo/features/journeys/expense_chart.dart';

final captureBoundary = GlobalKey();
var captureFrame = 0;
Future<void> captureMotion(WidgetTester t) async {
  if (!const bool.fromEnvironment('CAPTURE_MOTION')) return;
  await t.runAsync(() async {
    final render =
        captureBoundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'build/reports/motion-frames/${(captureFrame++).toString().padLeft(3, '0')}.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget shell(Widget child, {bool reduced = false}) => RepaintBoundary(
  key: captureBoundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: TrafficTokens.material(Brightness.light),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Center(child: child),
      ),
    ),
  ),
);

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
  testWidgets(
    'Async button starts immediately, keeps dimensions and blocks duplicate activation',
    (t) async {
      final done = Completer<void>();
      var calls = 0;
      await t.pumpWidget(
        shell(
          TrafficPrimaryButton(
            onPressed: () {
              calls++;
              return done.future;
            },
            child: const Text('Lưu lịch nhắc'),
          ),
        ),
      );
      final button = find.byType(TrafficPrimaryButton);
      final size = t.getSize(button);
      await captureMotion(t);
      final touch = await t.startGesture(t.getCenter(button));
      await t.pump(const Duration(milliseconds: 90));
      await captureMotion(t);
      await touch.up();
      expect(calls, 1);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(t.getSize(button), size);
      await t.pump(const Duration(milliseconds: 140));
      await captureMotion(t);
      await t.tap(button);
      await t.pump();
      expect(calls, 1);
      done.complete();
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(t.getSize(button), size);
      await captureMotion(t);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
  testWidgets('Button success is shown only after the real Future completes', (
    t,
  ) async {
    final done = Completer<void>();
    await t.pumpWidget(
      shell(
        TrafficPrimaryButton(
          successFeedback: true,
          onPressed: () => done.future,
          child: const Text('Lưu'),
        ),
      ),
    );
    await t.tap(find.byType(TrafficPrimaryButton));
    await t.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    done.complete();
    await t.pump();
    await t.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await captureMotion(t);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('Failure never shows success and remains retryable', (t) async {
    var calls = 0;
    await t.pumpWidget(
      shell(
        TrafficPrimaryButton(
          successFeedback: true,
          onPressed: () async {
            calls++;
            throw StateError('test');
          },
          child: const Text('Ghi chi phí'),
        ),
      ),
    );
    await t.tap(find.byType(TrafficPrimaryButton));
    await t.pump();
    await t.pump();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    await captureMotion(t);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    await t.tap(find.byType(TrafficPrimaryButton));
    await t.pump();
    expect(calls, 2);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('Touch press scales and releases; disabled button does not run', (
    t,
  ) async {
    await t.pumpWidget(
      shell(
        TrafficPrimaryButton(onPressed: () {}, child: const Text('Bắt đầu')),
      ),
    );
    final gesture = await t.startGesture(
      t.getCenter(find.byType(TrafficPrimaryButton)),
    );
    await t.pump(const Duration(milliseconds: 80));
    expect(
      t.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale,
      .975,
    );
    await gesture.up();
    await t.pumpAndSettle();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, 1);
    await t.pumpWidget(
      shell(const TrafficPrimaryButton(child: Text('Không thể lưu'))),
    );
    await t.tap(find.byType(TrafficPrimaryButton));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      t.getSize(find.byType(TrafficPrimaryButton)).height,
      greaterThanOrEqualTo(48),
    );
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('Reduced motion is static and loading stays understandable', (
    t,
  ) async {
    await t.pumpWidget(
      shell(
        const TrafficEntrance(
          child: TrafficPrimaryButton(
            phase: TrafficButtonPhase.loading,
            child: Text('Đang lưu'),
          ),
        ),
        reduced: true,
      ),
    );
    await t.pump();
    expect(t.widget<Animate>(find.byType(Animate)).controller!.value, 1);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      t.widget<AnimatedScale>(find.byType(AnimatedScale).first).duration,
      Duration.zero,
    );
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('Content updates do not replay entrance animation', (t) async {
    late StateSetter update;
    var value = 0;
    await t.pumpWidget(
      shell(
        StatefulBuilder(
          builder: (_, set) {
            update = set;
            return TrafficEntrance(child: Text('ETA $value'));
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    final controller = t.widget<Animate>(find.byType(Animate)).controller!;
    expect(controller.value, 1);
    update(() => value++);
    await t.pump();
    expect(
      t.widget<Animate>(find.byType(Animate)).controller,
      same(controller),
    );
    expect(controller.value, 1);
    expect(find.text('ETA 1'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('Vehicle toggle works with touch and arrow keys', (t) async {
    var vehicle = 'car';
    await t.pumpWidget(
      shell(
        StatefulBuilder(
          builder: (_, set) => SizedBox(
            width: 300,
            child: TrafficToggle<String>(
              value: vehicle,
              values: const ['car', 'motorcycle'],
              label: (v) => v == 'car' ? 'Ô tô' : 'Xe máy',
              icon: (v) =>
                  v == 'car' ? Icons.directions_car : Icons.two_wheeler,
              onChanged: (v) => set(() => vehicle = v),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Xe máy'));
    await t.pumpAndSettle();
    expect(vehicle, 'motorcycle');
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(vehicle, 'car');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  testWidgets('7/30 day chart uses actual data and reuses unchanged plot', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = JourneyStore(prefs);
    final today = DateTime(2026, 10, 24);
    await store.saveExpense(
      const Expense(
        id: 'today',
        category: 'fuel',
        date: '2026-10-24',
        amount: 50000,
      ),
    );
    await store.saveExpense(
      const Expense(
        id: 'older',
        category: 'other',
        date: '2026-10-05',
        amount: 100000,
      ),
    );
    late StateSetter update;
    await t.pumpWidget(
      shell(
        SingleChildScrollView(
          child: StatefulBuilder(
            builder: (_, set) {
              update = set;
              return ExpensePeriodChart(store: store, today: today);
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final plot = t.widget<BarChart>(find.byType(BarChart));
    expect(
      plot.data.barGroups.fold<double>(
        0,
        (sum, g) => sum + g.barRods.first.toY,
      ),
      50,
    );
    update(() {});
    await t.pump();
    expect(t.widget<BarChart>(find.byType(BarChart)), same(plot));
    await t.ensureVisible(find.text('30 ngày'));
    await t.pumpAndSettle();
    await t.tap(find.text('30 ngày'));
    await t.pumpAndSettle();
    final next = t.widget<BarChart>(find.byType(BarChart));
    expect(next.data.barGroups, hasLength(30));
    expect(
      next.data.barGroups.fold<double>(
        0,
        (sum, g) => sum + g.barRods.first.toY,
      ),
      150,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    store.dispose();
  });
  testWidgets('Keyboard activation stays accessible and cannot double-submit', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final done = Completer<void>();
    var calls = 0;
    await t.pumpWidget(
      shell(
        TrafficPrimaryButton(
          onPressed: () {
            calls++;
            return done.future;
          },
          child: const Text('Lưu lịch nhắc'),
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(calls, 1);
    expect(
      find.bySemanticsLabel(RegExp('Đang xử lý Lưu lịch nhắc')),
      findsWidgets,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(calls, 1);
    done.complete();
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
    semantics.dispose();
  });
  testWidgets('Reduced motion removes modal route movement', (t) async {
    Duration? duration;
    await t.pumpWidget(
      shell(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showTrafficSheet(
              context,
              title: 'Kiểm tra modal',
              builder: (c) {
                duration = ModalRoute.of(c)!.transitionDuration;
                return const Text('Nội dung');
              },
            ),
            child: const Text('Mở modal'),
          ),
        ),
        reduced: true,
      ),
    );
    await t.tap(find.text('Mở modal'));
    await t.pumpAndSettle();
    expect(duration, Duration.zero);
    expect(find.text('Nội dung'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
}
