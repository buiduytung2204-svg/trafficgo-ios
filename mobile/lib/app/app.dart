import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/map/map_screen.dart';
import '../features/settings/screens.dart';
import 'state.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeGate()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(path: '/saved', builder: (context, state) => const SavedScreen()),
  ],
);

class TrafficGoApp extends ConsumerWidget {
  const TrafficGoApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stateProvider);
    ThemeData theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff007c78),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff6f8fa)
          : const Color(0xff11191f),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
    );
    return MaterialApp.router(
      title: 'TrafficGo',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: state.theme,
      routerConfig: router,
    );
  }
}

class HomeGate extends ConsumerStatefulWidget {
  const HomeGate({super.key});
  @override
  ConsumerState<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends ConsumerState<HomeGate> {
  late final Future<void> startup;
  @override
  void initState() {
    super.initState();
    startup = ref.read(stateProvider).loadToken();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: startup,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore, size: 64),
                Text('TrafficGo'),
                CircularProgressIndicator(),
              ],
            ),
          ),
        );
      }
      if (snapshot.hasError) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Không đọc được bộ nhớ bảo mật. Bạn có thể mở cài đặt để thử lưu lại token.',
                  ),
                  TextButton(
                    onPressed: () => context.push('/settings'),
                    child: const Text('Mở cài đặt'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final state = ref.watch(stateProvider);
      if (state.onboarded) return const MapScreen();
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.explore_rounded,
                        size: 90,
                        color: Color(0xff007c78),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Hà Nội,\nđi nhẹ nhàng hơn.',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Khám phá bản đồ, so sánh tuyến ô tô và theo dõi giao thông từ TomTom.',
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'TrafficGo chỉ xin vị trí khi bạn dùng định vị hoặc bắt đầu hành trình. Không theo dõi nền và không lưu lịch sử GPS.',
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: state.completeOnboarding,
                          child: const Text('Bắt đầu khám phá'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
