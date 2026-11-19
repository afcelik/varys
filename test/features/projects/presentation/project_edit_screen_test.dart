import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/presentation/project_edit_screen.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_project_repository.dart';

final _day = DateTime(2026, 11, 19);
const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);
const _invalid = ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

typedef _ProjectResult = Either<Failure, Project>;

void main() {
  late FakeProjectRepository repo;
  late GoRouter router;

  setUpAll(() async => initializeDateFormatting('tr_TR', null));

  setUp(() => repo = FakeProjectRepository());

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// [initial] is where the app starts. Default: the list page, so the form
  /// is pushed on top of it (the normal flow).
  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = AppRouter.projectsPath,
    Size size = const Size(600, 1400),
    bool settle = true,
  }) async {
    setSize(tester, size);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.projectsPath, builder: (_, _) => const ProjectsScreen()),
        GoRoute(path: AppRouter.projectsNewPath, builder: (_, _) => const ProjectEditScreen()),
        GoRoute(
          path: AppRouter.projectsEditPath,
          builder: (_, state) => ProjectEditScreen(project: state.extra! as Project),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        projectRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> openCreate(WidgetTester tester, {Size size = const Size(600, 1400)}) async {
    await pumpApp(tester, size: size);
    router.push(AppRouter.projectsNewPath);
    await tester.pumpAndSettle();
    expect(find.text(ProjectEditScreen.createTitle), findsOneWidget);
  }

  Future<void> openEdit(WidgetTester tester, Project project) async {
    await pumpApp(tester);
    router.push(AppRouter.projectsEditPath, extra: project);
    await tester.pumpAndSettle();
    expect(find.text(ProjectEditScreen.editTitle), findsOneWidget);
  }

  Project fixture(int id) => repo.server.firstWhere((p) => p.id == id);

  final titleField = find.byKey(const ValueKey('project-title'));
  final descriptionField = find.byKey(const ValueKey('project-description'));
  final saveButton = find.byKey(const ValueKey('project-save'));
  final statusMenu = find.byType(DropdownMenu<ProjectStatus>);
  final reason = find.byKey(const ValueKey('project-active-unavailable'));
  final targetDateField = find.byKey(const ValueKey('project-target-date'));

  String fieldText(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
      .controller
      .text;
  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;
  ProjectEditScreenState formState(WidgetTester tester) =>
      tester.state<ProjectEditScreenState>(find.byType(ProjectEditScreen));
  DropdownMenu<ProjectStatus> dropdown(WidgetTester tester) =>
      tester.widget<DropdownMenu<ProjectStatus>>(statusMenu);
  bool activeEnabled(WidgetTester tester) => dropdown(
    tester,
  ).dropdownMenuEntries.firstWhere((e) => e.value == ProjectStatus.active).enabled;
  ProjectStatus? shownStatus(WidgetTester tester) => dropdown(tester).initialSelection;
  String dateText(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey('$key-text'))).data!;
  Finder snack(String text) =>
      find.descendant(of: find.byType(SnackBar), matching: find.text(text));

  Future<void> selectStatus(WidgetTester tester, String label) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(statusMenu);
    await tester.tap(statusMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, label).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
  }

  group('validation', () {
    testWidgets('title: required after editing; 255 ok, 256 too long; Kaydet follows', (
      tester,
    ) async {
      await openCreate(tester);
      expect(saveEnabled(tester), isFalse, reason: 'empty title');
      expect(find.text(projectTitleRequiredMessage), findsNothing, reason: 'not touched yet');

      await tester.enterText(titleField, '   ');
      await tester.pump();
      expect(find.text(projectTitleRequiredMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(titleField, '🚀' * 255);
      await tester.pump();
      expect(find.text(projectTitleTooLongMessage), findsNothing, reason: 'emoji count as one');
      expect(saveEnabled(tester), isTrue);

      await tester.enterText(titleField, 'a' * 256);
      await tester.pump();
      expect(find.text(projectTitleTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('description over 2000 characters: error and Kaydet disabled', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'P');
      await tester.enterText(descriptionField, 'x' * 2001);
      await tester.pump();
      expect(find.text(projectDescriptionTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(descriptionField, 'x' * 2000);
      await tester.pump();
      expect(find.text(projectDescriptionTooLongMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('target before start: error under the target date, Kaydet disabled; same '
        'day fixes it', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'P');
      formState(tester).setStartDate(DateTime(2026, 12, 10));
      formState(tester).setTargetDate(DateTime(2026, 12, 9));
      await tester.pump();

      expect(
        find.descendant(of: targetDateField, matching: find.text(projectDatesOrderMessage)),
        findsOneWidget,
      );
      expect(saveEnabled(tester), isFalse);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      expect(repo.createBodies, isEmpty);

      formState(tester).setTargetDate(DateTime(2026, 12, 10));
      await tester.pump();
      expect(find.text(projectDatesOrderMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('server 422 (passed client checks): generic text, form stays with values', (
      tester,
    ) async {
      repo.onCreate = (_) async => const Left(_invalid);
      await openCreate(tester);
      await tester.enterText(titleField, 'Tarih hatası');
      await tester.enterText(descriptionField, 'Not');
      formState(tester).setStartDate(DateTime(2026, 12, 1));
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ProjectEditScreen), findsOneWidget);
      expect(snack('Gönderilen veriler geçersiz.'), findsOneWidget);
      expect(find.textContaining('target_date'), findsNothing);
      expect(fieldText(tester, titleField), 'Tarih hatası');
      expect(fieldText(tester, descriptionField), 'Not');
      expect(formState(tester).startDate, DateTime(2026, 12, 1));
      expect(saveEnabled(tester), isTrue);
    });
  });

  group('dates', () {
    testWidgets('picker: 2000-01-01..2100-12-31, starts on today when empty; Turkish İptal '
        'keeps the form', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'P');
      expect(dateText(tester, 'project-start-date'), ProjectEditScreen.noDateText);

      await tester.tap(find.byKey(const ValueKey('project-start-date-button')));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2000, 1, 1));
      expect(picker.lastDate, DateTime(2100, 12, 31));
      expect(picker.initialDate, _day);
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(fieldText(tester, titleField), 'P');
      expect(dateText(tester, 'project-start-date'), ProjectEditScreen.noDateText);
    });

    testWidgets('picked dates are sent as YYYY-MM-DD; dates are clamped to the bounds', (
      tester,
    ) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'P');
      formState(tester).setStartDate(DateTime(1999, 1, 1));
      formState(tester).setTargetDate(DateTime(2027, 1, 5, 22, 30));
      await tester.pumpAndSettle();
      expect(dateText(tester, 'project-start-date'), '01.01.2000');
      expect(dateText(tester, 'project-target-date'), '05.01.2027');

      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.createBodies.single['start_date'], '2000-01-01');
      expect(repo.createBodies.single['target_date'], '2027-01-05');
    });

    testWidgets('edit: × clears a date; the PATCH sends it as explicit null', (tester) async {
      await openEdit(tester, fixture(1));
      expect(dateText(tester, 'project-target-date'), '20.11.2026');
      final clear = find.byKey(const ValueKey('project-target-date-clear'));
      final size = tester.getSize(clear);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(dateText(tester, 'project-target-date'), ProjectEditScreen.noDateText);
      expect(formState(tester).targetDate, isNull);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(repo.updateCalls.single.$1, 1);
      expect(repo.updateCalls.single.$2, {'target_date': null});
      expect(find.byType(ProjectEditScreen), findsNothing, reason: 'popped');
    });
  });

  group('status and the active limit', () {
    testWidgets('create with a free slot: default Aktif, option enabled, no reason text', (
      tester,
    ) async {
      await openCreate(tester);
      expect(shownStatus(tester), ProjectStatus.active);
      expect(activeEnabled(tester), isTrue);
      expect(reason, findsNothing);
    });

    testWidgets('create with the limit full: default Beklemede, Aktif disabled, reason shown '
        'below the field', (tester) async {
      repo.maxActive = 2;
      await openCreate(tester);
      expect(shownStatus(tester), ProjectStatus.onHold);
      expect(activeEnabled(tester), isFalse);
      expect(reason, findsOneWidget);
      expect(find.text(ProjectEditScreen.activeUnavailableText), findsOneWidget);
      expect(
        find.descendant(of: statusMenu, matching: reason),
        findsNothing,
        reason: 'not inside the dropdown',
      );
      expect(
        tester.getTopLeft(reason).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(statusMenu).dy),
      );

      // The real menu: tapping the disabled Aktif changes nothing.
      await tester.tap(statusMenu);
      await tester.pumpAndSettle();
      final activeItem = find.widgetWithText(MenuItemButton, 'Aktif').last;
      expect(tester.widget<MenuItemButton>(activeItem).onPressed, isNull);
      await tester.tap(activeItem, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(shownStatus(tester), ProjectStatus.onHold);

      await tester.enterText(titleField, 'P');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.createBodies.single['status'], 'on_hold');
    });

    testWidgets('chosen status is sent', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'P');
      await selectStatus(tester, 'İleride');
      expect(shownStatus(tester), ProjectStatus.someday);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.createBodies.single['status'], 'someday');
    });

    testWidgets('edit an active project with the limit full: Aktif stays enabled, no reason, '
        'saving works', (tester) async {
      repo.limitsOverride = const ProjectLimits(maxActive: 3, activeCount: 3);
      await openEdit(tester, fixture(1));
      expect(shownStatus(tester), ProjectStatus.active);
      expect(activeEnabled(tester), isTrue);
      expect(reason, findsNothing);

      await tester.enterText(titleField, 'Ev taşıma 2');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls.single.$2, {'title': 'Ev taşıma 2'});
    });

    testWidgets('edit a non-active project with the limit full: Aktif disabled with reason', (
      tester,
    ) async {
      repo.limitsOverride = const ProjectLimits(maxActive: 3, activeCount: 3);
      await openEdit(tester, fixture(3));
      expect(shownStatus(tester), ProjectStatus.onHold);
      expect(activeEnabled(tester), isFalse);
      expect(reason, findsOneWidget);
    });

    testWidgets('edit a non-active project with a free slot: Aktif enabled, no reason, '
        'activating sends the status', (tester) async {
      await openEdit(tester, fixture(4));
      expect(activeEnabled(tester), isTrue);
      expect(reason, findsNothing);
      await selectStatus(tester, 'Aktif');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls.single.$2, {'status': 'active'});
    });

    testWidgets('stale count (2/3 locally, server full): 409 keeps the form and values, shows '
        'the limit text; after the refresh Aktif is disabled', (tester) async {
      await openCreate(tester);
      expect(shownStatus(tester), ProjectStatus.active);
      // Another client filled the last slot.
      repo.server = [
        for (final p in repo.server) p.id == 3 ? p.copyWith(status: ProjectStatus.active) : p,
      ];
      await tester.enterText(titleField, 'Fazla');
      await tester.enterText(descriptionField, 'Açıklama');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(repo.createBodies.single['status'], 'active');
      expect(find.byType(ProjectEditScreen), findsOneWidget);
      expect(snack(ActiveProjectLimitFailure.message), findsOneWidget);
      expect(find.textContaining('active_project_limit_reached'), findsNothing);
      expect(fieldText(tester, titleField), 'Fazla');
      expect(fieldText(tester, descriptionField), 'Açıklama');
      expect(shownStatus(tester), ProjectStatus.active, reason: 'submitted value kept');
      expect(activeEnabled(tester), isFalse, reason: 'server limits now 3/3');
      expect(saveEnabled(tester), isFalse, reason: 'Aktif no longer allowed');
      expect(reason, findsNothing, reason: 'hidden while Aktif is selected');

      await selectStatus(tester, 'Beklemede');
      expect(reason, findsOneWidget);
      expect(saveEnabled(tester), isTrue);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.createBodies.last['status'], 'on_hold');
      expect(find.byType(ProjectEditScreen), findsNothing);
    });
  });

  group('saving', () {
    testWidgets('create sends the trimmed values, pops back, the list shows the project', (
      tester,
    ) async {
      await openCreate(tester);
      await tester.enterText(titleField, '  Bahçe  ');
      await tester.enterText(descriptionField, '  ');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(repo.createBodies.single, {
        'title': 'Bahçe',
        'description': null,
        'status': 'active',
        'start_date': null,
        'target_date': null,
      });
      expect(find.byType(ProjectEditScreen), findsNothing);
      expect(find.byType(ProjectsScreen), findsOneWidget);
      expect(find.text('Bahçe'), findsOneWidget);
      expect(find.text('Aktif 3/3'), findsOneWidget);
    });

    testWidgets('Kaydet disabled while the request runs; double tap sends one request', (
      tester,
    ) async {
      final pending = Completer<_ProjectResult>();
      repo.onCreate = (_) => pending.future;
      await openCreate(tester);
      await tester.enterText(titleField, 'P');
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();

      pending.complete(Right(createdProjectFixture().copyWith(id: 50, title: 'P')));
      await tester.pumpAndSettle();
      expect(repo.createBodies, hasLength(1));
    });

    testWidgets('server error: form open, values kept, snackbar, Kaydet re-enabled', (
      tester,
    ) async {
      repo.onUpdate = (_, _) async => const Left(_serverError);
      await openEdit(tester, fixture(1));
      await tester.enterText(titleField, 'Yeni ad');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ProjectEditScreen), findsOneWidget);
      expect(snack(userMessage(_serverError)), findsOneWidget);
      expect(fieldText(tester, titleField), 'Yeni ad');
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('edit prefilled; no change: Kaydet disabled and nothing is sent', (tester) async {
      await openEdit(tester, fixture(1));
      expect(fieldText(tester, titleField), 'Ev taşıma');
      expect(fieldText(tester, descriptionField), 'Yeni eve geçiş işleri');
      expect(dateText(tester, 'project-start-date'), '01.11.2026');
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(titleField, ' Ev taşıma ');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isFalse, reason: 'only whitespace differs');
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.updateCalls, isEmpty);
      expect(find.byType(ProjectEditScreen), findsOneWidget);
    });

    testWidgets('emptied description is sent as clear (null)', (tester) async {
      await openEdit(tester, fixture(1));
      await tester.enterText(descriptionField, '');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls.single.$2, {'description': null});
    });

    testWidgets('404 on save: form stays, "Kaynak bulunamadı."', (tester) async {
      await openEdit(tester, fixture(2));
      repo.server = repo.server.where((p) => p.id != 2).toList();
      await tester.enterText(titleField, 'X');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ProjectEditScreen), findsOneWidget);
      expect(snack('Kaynak bulunamadı.'), findsOneWidget);
    });
  });

  group('/projects/new opened directly (no list page below)', () {
    testWidgets('the form loads the limits itself: Aktif and Kaydet disabled until loaded', (
      tester,
    ) async {
      repo.listGate = Completer<void>();
      await pumpApp(tester, initial: AppRouter.projectsNewPath, settle: false);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ProjectsScreen), findsNothing);
      expect(find.byKey(const ValueKey('project-limits-loading')), findsOneWidget);
      expect(activeEnabled(tester), isFalse);
      expect(dropdown(tester).enabled, isFalse);
      await tester.enterText(titleField, 'P');
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      expect(repo.listCalls, 1, reason: 'requested by the form');

      repo.listGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-limits-loading')), findsNothing);
      expect(activeEnabled(tester), isTrue);
      expect(shownStatus(tester), ProjectStatus.active);
      expect(saveEnabled(tester), isTrue);
      expect(fieldText(tester, titleField), 'P');
    });

    testWidgets('load error: "Tekrar dene", values kept, Kaydet disabled; retry recovers', (
      tester,
    ) async {
      repo.listFailure = _serverError;
      await pumpApp(tester, initial: AppRouter.projectsNewPath);
      await tester.enterText(titleField, 'Bahçe');
      await tester.enterText(descriptionField, 'Not');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('project-limits-error')), findsOneWidget);
      expect(find.text(userMessage(_serverError)), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      final retry = find.byKey(const ValueKey('project-limits-retry'));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

      repo.listFailure = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-limits-error')), findsNothing);
      expect(fieldText(tester, titleField), 'Bahçe');
      expect(fieldText(tester, descriptionField), 'Not');
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('success with nothing to pop: goes to the projects page', (tester) async {
      await pumpApp(tester, initial: AppRouter.projectsNewPath);
      expect(router.canPop(), isFalse);
      await tester.enterText(titleField, 'Bahçe');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ProjectsScreen), findsOneWidget);
      expect(find.text('Bahçe'), findsOneWidget);
    });
  });

  group('keyboard open (narrow screen)', () {
    testWidgets('360px with a 300px keyboard: Kaydet above the keyboard and tappable; the '
        'error snackbar does not cover it', (tester) async {
      repo.onCreate = (_) async => const Left(_serverError);
      await openCreate(tester, size: const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(titleField, 'P');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(saveButton);
      expect(rect.bottom, lessThanOrEqualTo(640 - 300), reason: 'above the keyboard');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repo.createBodies, hasLength(1));
      final snackRect = tester.getRect(find.byType(SnackBar));
      final saveRect = tester.getRect(saveButton);
      expect(snackRect.bottom, lessThanOrEqualTo(saveRect.top), reason: 'snackbar above Kaydet');
      expect(saveEnabled(tester), isTrue);

      // Kaydet is still hit-testable while the snackbar shows.
      repo.onCreate = null;
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(repo.createBodies, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('page closed while saving (mounted checks)', () {
    testWidgets('list page below: close during the request, no exception, list updated', (
      tester,
    ) async {
      final pending = Completer<_ProjectResult>();
      repo.onCreate = (_) => pending.future;
      await openCreate(tester);
      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectEditScreen), findsNothing);
      expect(find.byType(ProjectsScreen), findsOneWidget);

      final created = createdProjectFixture().copyWith(id: 60, title: 'Koşu');
      repo.server = [...repo.server, created];
      pending.complete(Right(created));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ProjectsScreen), findsOneWidget, reason: 'no extra pop');
      expect(find.text('Koşu'), findsOneWidget, reason: 'list still updated');
      expect(repo.createBodies, hasLength(1));
    });

    testWidgets('/projects/new opened directly: close during the request, no exception', (
      tester,
    ) async {
      final pending = Completer<_ProjectResult>();
      repo.onCreate = (_) => pending.future;
      await pumpApp(tester, initial: AppRouter.projectsNewPath);
      expect(find.byType(ProjectsScreen), findsNothing);
      expect(router.canPop(), isFalse);
      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      router.go(AppRouter.homePath);
      await tester.pumpAndSettle();
      expect(find.byType(ProjectEditScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);

      pending.complete(Right(createdProjectFixture().copyWith(id: 61, title: 'Koşu')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget, reason: 'no navigation after close');
      expect(repo.createBodies, hasLength(1));
    });
  });
}
