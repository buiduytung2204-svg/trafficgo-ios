import '../core/design/components.dart';
import '../core/design/traffic_theme.dart';
import 'home_shell.dart';
import '../features/onboarding/accounts.dart';
import '../features/onboarding/screens.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/map/map_screen.dart';
import '../features/settings/screens.dart';
import '../features/departure/screens.dart';
import '../features/departure/models.dart';
import '../core/models.dart';
import 'state.dart';

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeGate()),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(path: '/saved', builder: (context, state) => const SavedScreen()),
    GoRoute(
      path: '/schedules',
      builder: (context, state) => const SchedulesScreen(),
    ),
    GoRoute(
      path: '/departure-notifications',
      builder: (context, state) => const DepartureNotificationsScreen(),
    ),
    GoRoute(
      path: '/schedule-edit',
      builder: (context, state) =>
          ScheduleEditor(schedule: state.extra as CommuteSchedule?),
    ),
    GoRoute(
      path: '/commute-route',
      builder: (context, state) {
        final data = state.extra as Map<String, dynamic>?;
        return MapScreen(
          autoStartNavigation: data?['start_navigation'] == true,
          plannedTrip: data?['trip'] as SavedTrip?,
          plannedVehicle: data?['vehicle'] as String?,
          journeyId: data?['journey_id'] as String?,
          direction: data?['direction'] as String?,
          occurrenceId: data?['occurrence_id'] as String?,
        );
      },
    ),
  ],
);

class TrafficGoApp extends ConsumerWidget {
  const TrafficGoApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stateProvider);
    return MaterialApp.router(
      title: 'TrafficGo',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: TrafficTokens.material(Brightness.light),
      darkTheme: TrafficTokens.material(Brightness.dark),
      themeMode: state.theme,
      builder: (context, child) => TrafficDesignScope(child: child!),
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
      final account = ref.watch(accountProvider);
      if (account.id != null) {
        return FutureBuilder(
          future: account.ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!account.complete) return const PersonalSetupScreen();
            return DepartureNotificationBridge(
              child: TrafficHomeShell(key: ValueKey('account:${account.id}')),
            );
          },
        );
      }
      if (state.onboarded) {
        return const DepartureNotificationBridge(
          child: TrafficHomeShell(key: ValueKey('guest')),
        );
      }
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
                        color: Color(0xff20252b),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Hà Nội,\nđi nhẹ nhàng hơn.',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Tìm địa điểm, so sánh tuyến đường và quản lý hành trình hằng ngày.',
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'TrafficGo chỉ xin vị trí khi bạn dùng định vị hoặc bắt đầu hành trình. Không theo dõi nền và không lưu lịch sử GPS.',
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: TrafficPrimaryButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AccountScreen(),
                            ),
                          ),
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
