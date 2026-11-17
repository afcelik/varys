// Session end (expiry or deliberate logout) invalidates every user-data
// provider: after the next login routines, daily plan and task list are
// fetched again and no old data or old error state is shown.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';
import 'package:varys/features/auth/domain/auth_state.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _token = 'old.jwt.token';
const _newToken = 'new.jwt.token';
final _day = DateTime(2026, 11, 16);
const _failure = ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<RoutineDayItem> routines;
  late List<Task> tasks;
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late ProviderContainer container;
  late AuthNotifier auth;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
    routines = (jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final planJson = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
        as Map<String, dynamic>;
    tasks = (planJson['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': _token});
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();

    // Session 1: old user data; routines fail (old error state).
    when(() => planRepo.getPlan(any()))
        .thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: [tasks.first])));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([tasks.first]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Left(_failure));

    container = ProviderContainer(overrides: [
      todayProvider.overrideWith(_FixedToday.new),
      dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
      taskRepositoryProvider.overrideWith((ref) async => taskRepo),
      routineRepositoryProvider.overrideWith((ref) async => routineRepo),
    ]);
    auth = container.read(authNotifierProvider.notifier);
    await _flush();
    expect(container.read(authNotifierProvider), const TypeMatcher<AuthAuthenticated>());

    // Keep the autoDispose providers alive, as an open Home screen would.
    container.listen(dailyPlanProvider, (_, _) {});
    container.listen(taskListNotifierProvider, (_, _) {});
    container.listen(routinesForDayProvider(_day), (_, _) {});
    await _flush();

    expect(container.read(dailyPlanProvider).requireValue.tasks, [tasks.first]);
    expect(container.read(taskListNotifierProvider).requireValue.tasks.requireValue,
        [tasks.first]);
    expect(container.read(routinesForDayProvider(_day)).hasError, isTrue);
  });

  tearDown(() => container.dispose());

  /// Session 2 data, then "login" (same final steps as login()).
  Future<void> loginWithNewData() async {
    when(() => planRepo.getPlan(any()))
        .thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: tasks)));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
    await auth.updateToken(_newToken);
    await _flush();
  }

  void expectFreshData() {
    expect(container.read(dailyPlanProvider).requireValue.tasks, tasks);
    expect(container.read(taskListNotifierProvider).requireValue.tasks.requireValue, tasks);
    final routineValue = container.read(routinesForDayProvider(_day));
    expect(routineValue.hasError, isFalse, reason: 'old error state must be gone');
    expect(routineValue.requireValue, routines);

    verify(() => planRepo.getPlan(_day)).called(2);
    verify(() => taskRepo.getTasksByFilter(TaskFilter.all)).called(2);
    verify(() => routineRepo.getRoutinesForDay(_day)).called(2);
  }

  test('session expiry invalidates routines, daily plan and tasks; re-login reloads them',
      () async {
    final expired = await auth.handleSessionExpired(container, requestToken: _token);
    expect(expired, isTrue);
    final state = container.read(authNotifierProvider);
    expect((state as AuthUnauthenticated).sessionExpired, isTrue);

    await loginWithNewData();
    expectFreshData();
  });

  test('deliberate logout invalidates the same providers; re-login reloads them', () async {
    await auth.logout(container.invalidate);
    final state = container.read(authNotifierProvider);
    expect((state as AuthUnauthenticated).sessionExpired, isFalse);

    await loginWithNewData();
    expectFreshData();
  });

  test('invalidateUserData lists exactly the user-data providers; infra is separate', () {
    final userData = <ProviderOrFamily>[];
    AuthNotifier.invalidateUserData(userData.add);
    expect(userData.toSet(), {
      routinesForDayProvider,
      routineRepositoryProvider,
      dailyPlanProvider,
      dailyPlanRepositoryProvider,
      taskListNotifierProvider,
      taskRepositoryProvider,
    });
    expect(userData, hasLength(6));

    final infra = <ProviderOrFamily>[];
    AuthNotifier.invalidateSessionInfra(infra.add);
    expect(infra.toSet().intersection(userData.toSet()), isEmpty);
  });

  test('without the invalidation list nothing reloads (guards the test itself)', () async {
    // Token change alone does not rebuild overridden repositories, so only
    // invalidateUserData can trigger the reload checked above.
    await loginWithNewData();
    expect(container.read(routinesForDayProvider(_day)).hasError, isTrue);
    expect(container.read(dailyPlanProvider).requireValue.tasks, [tasks.first]);
  });
}
