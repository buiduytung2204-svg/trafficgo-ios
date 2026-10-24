import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trafficgo/app/state.dart';
import 'package:trafficgo/features/onboarding/screens.dart';

void main() {
  testWidgets('Signup requires nickname; login does not show nickname', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [preferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: AccountScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Nickname'), findsOneWidget);
    await tester.ensureVisible(find.text('Tạo tài khoản'));
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pump();
    expect(find.text('Vui lòng nhập nickname từ 1 đến 100 ký tự.'), findsOneWidget);
    await tester.ensureVisible(find.text('Đã có tài khoản? Đăng nhập'));
    await tester.tap(find.text('Đã có tài khoản? Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Nickname'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
