import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Create (`/projects/new`, [project] null) or edit (`/projects/edit`,
/// [project] from `extra`) form.
///
/// The active limit comes from [projectsListProvider]; when the page is
/// opened directly (no list page below) the form loads it itself. Until it
/// has loaded, "Aktif" and Kaydet are disabled; a load error shows
/// "Tekrar dene" and keeps the typed values.
class ProjectEditScreen extends ConsumerStatefulWidget {
  const ProjectEditScreen({super.key, this.project});

  final Project? project;

  static const String createTitle = 'Yeni proje';
  static const String editTitle = 'Projeyi düzenle';
  static const String titleLabel = 'Başlık';
  static const String descriptionLabel = 'Açıklama (isteğe bağlı)';
  static const String statusLabel = 'Durum';
  static const String startDateLabel = 'Başlangıç tarihi';
  static const String targetDateLabel = 'Hedef tarih';
  static const String noDateText = 'Seçilmedi';
  static const String clearDateTooltip = 'Tarihi temizle';
  static const String saveText = 'Kaydet';
  static const String retryText = 'Tekrar dene';
  static const String activeUnavailableText =
      'Aktif proje sınırı dolu. Aktif seçmek için önce bir projeyi beklemeye ya da ileriye al.';

  /// Bounds of both dates (same as the backend).
  static final DateTime minDate = DateTime(2000, 1, 1);
  static final DateTime maxDate = DateTime(2100, 12, 31);

  /// Clamps [day] (date part only) into [minDate]..[maxDate].
  static DateTime clampDate(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(minDate)) return minDate;
    if (d.isAfter(maxDate)) return maxDate;
    return d;
  }

  static String formatDate(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  @override
  ConsumerState<ProjectEditScreen> createState() => ProjectEditScreenState();
}

class ProjectEditScreenState extends ConsumerState<ProjectEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;

  /// Chosen status. Null on create until the user picks one or saves: the
  /// default then follows the limits ([defaultNewProjectStatus]).
  ProjectStatus? _status;
  DateTime? _startDate;
  DateTime? _targetDate;
  bool _titleTouched = false;
  bool _saving = false;

  Project? get _original => widget.project;
  bool get _isEdit => _original != null;

  DateTime? get startDate => _startDate;
  DateTime? get targetDate => _targetDate;

  @override
  void initState() {
    super.initState();
    final p = _original;
    _title = TextEditingController(text: p?.title ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _status = p?.status;
    _startDate = p?.startDate;
    _targetDate = p?.targetDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void setStartDate(DateTime? day) =>
      setState(() => _startDate = day == null ? null : ProjectEditScreen.clampDate(day));

  void setTargetDate(DateTime? day) =>
      setState(() => _targetDate = day == null ? null : ProjectEditScreen.clampDate(day));

  ProjectStatus? _effectiveStatus(ProjectLimits? limits) =>
      _status ?? (limits == null ? null : defaultNewProjectStatus(limits));

  bool _activeAllowed(ProjectLimits? limits) =>
      limits != null && canChooseActive(limits, editing: _original);

  ProjectChanges _changes(ProjectStatus status) => computeProjectChanges(
    _original!,
    title: _title.text,
    description: _description.text,
    status: status,
    startDate: _startDate,
    targetDate: _targetDate,
  );

  bool _canSave(ProjectLimits? limits) {
    if (_saving || limits == null) return false;
    final status = _effectiveStatus(limits);
    if (status == null) return false;
    if (status == ProjectStatus.active && !_activeAllowed(limits)) return false;
    if (!isProjectFormValid(
      title: _title.text,
      description: _description.text,
      startDate: _startDate,
      targetDate: _targetDate,
    )) {
      return false;
    }
    if (_isEdit && _changes(status).isEmpty) return false; // nothing changed: no request
    return true;
  }

  Future<void> _pickDate({required bool target}) async {
    final current = target ? _targetDate : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? ProjectEditScreen.clampDate(ref.read(todayProvider)),
      firstDate: ProjectEditScreen.minDate,
      lastDate: ProjectEditScreen.maxDate,
    );
    if (!mounted || picked == null) return;
    target ? setTargetDate(picked) : setStartDate(picked);
  }

  Future<void> _save(ProjectLimits limits) async {
    if (!_canSave(limits)) return;
    final status = _effectiveStatus(limits)!;
    setState(() {
      _status = status; // the submitted status is kept if the server refuses it
      _saving = true;
    });
    final notifier = ref.read(projectsListProvider.notifier);

    final Either<Failure, Object?> result;
    if (_isEdit) {
      result = await notifier.updateProject(_original!.id, _changes(status));
    } else {
      result = await notifier.createProject(
        ProjectDraft(
          title: _title.text,
          description: _description.text,
          status: status,
          startDate: _startDate,
          targetDate: _targetDate,
        ),
      );
    }
    if (!mounted) return; // page closed while the request ran

    result.fold(
      (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
        );
      },
      (_) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRouter.projectsPath);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = ref.watch(projectsListProvider);
    final limits = value.valueOrNull?.limits;
    final status = _effectiveStatus(limits);
    final activeAllowed = _activeAllowed(limits);
    final titleError = _titleTouched ? validateProjectTitle(_title.text) : null;
    final datesError = validateProjectDates(_startDate, _targetDate);
    final canSave = _canSave(limits);

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(fallbackRoute: AppRouter.projectsPath),
        title: Text(
          _isEdit ? ProjectEditScreen.editTitle : ProjectEditScreen.createTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('project-title'),
                controller: _title,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: ProjectEditScreen.titleLabel,
                  errorText: titleError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() => _titleTouched = true),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('project-description'),
                controller: _description,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: ProjectEditScreen.descriptionLabel,
                  errorText: validateProjectDescription(_description.text),
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              _statusField(theme, value, limits, status, activeAllowed),
              const SizedBox(height: 24),
              _DateField(
                fieldKey: 'project-start-date',
                label: ProjectEditScreen.startDateLabel,
                date: _startDate,
                enabled: !_saving,
                onPick: () => _pickDate(target: false),
                onClear: () => setStartDate(null),
              ),
              const SizedBox(height: 16),
              _DateField(
                fieldKey: 'project-target-date',
                label: ProjectEditScreen.targetDateLabel,
                date: _targetDate,
                errorText: datesError,
                enabled: !_saving,
                onPick: () => _pickDate(target: true),
                onClear: () => setTargetDate(null),
              ),
            ],
          ),
        ),
      ),
      // Kaydet stays outside the scroll view: always reachable, lifted above
      // the keyboard, and a floating snackbar is laid out above it instead
      // of covering it.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: FilledButton(
            key: const ValueKey('project-save'),
            onPressed: canSave ? () => _save(limits!) : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text(ProjectEditScreen.saveText),
          ),
        ),
      ),
    );
  }

  Widget _statusField(
    ThemeData theme,
    AsyncValue<ProjectsOverview> value,
    ProjectLimits? limits,
    ProjectStatus? status,
    bool activeAllowed,
  ) {
    final children = <Widget>[
      DropdownMenu<ProjectStatus>(
        // Rebuilt when the default status appears so the field shows it.
        key: ValueKey('project-status-${status?.apiValue}'),
        initialSelection: status,
        enabled: !_saving && limits != null,
        requestFocusOnTap: false,
        expandedInsets: EdgeInsets.zero,
        label: const Text(ProjectEditScreen.statusLabel),
        dropdownMenuEntries: [
          for (final MapEntry(key: s, value: label) in projectStatusLabels.entries)
            DropdownMenuEntry(
              value: s,
              label: label,
              enabled: s != ProjectStatus.active || activeAllowed,
            ),
        ],
        onSelected: (s) {
          if (s != null) setState(() => _status = s);
        },
      ),
    ];

    if (limits == null && value.hasError) {
      children.addAll([
        const SizedBox(height: 8),
        Text(
          userMessage(value.error!),
          key: const ValueKey('project-limits-error'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            key: const ValueKey('project-limits-retry'),
            onPressed: () => ref.invalidate(projectsListProvider),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text(ProjectEditScreen.retryText),
          ),
        ),
      ]);
    } else if (limits == null) {
      children.addAll(const [
        SizedBox(height: 8),
        LinearProgressIndicator(key: ValueKey('project-limits-loading')),
      ]);
    } else if (!activeAllowed && status != ProjectStatus.active) {
      // Separate text below the field (never inside it), so it can wrap.
      children.addAll([
        const SizedBox(height: 8),
        Text(
          ProjectEditScreen.activeUnavailableText,
          key: const ValueKey('project-active-unavailable'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// A date that may be empty: tap to pick (48 high), × to clear (48x48).
class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.label,
    required this.date,
    required this.enabled,
    required this.onPick,
    required this.onClear,
    this.errorText,
  });

  final String fieldKey;
  final String label;
  final DateTime? date;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final d = date;
    return InkWell(
      key: ValueKey('$fieldKey-button'),
      onTap: enabled ? onPick : null,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InputDecorator(
          key: ValueKey(fieldKey),
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            errorMaxLines: 3,
            enabled: enabled,
            suffixIcon: d == null
                ? const Icon(Icons.calendar_today)
                : IconButton(
                    key: ValueKey('$fieldKey-clear'),
                    icon: const Icon(Icons.close),
                    tooltip: ProjectEditScreen.clearDateTooltip,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: enabled ? onClear : null,
                  ),
          ),
          child: Text(
            d == null ? ProjectEditScreen.noDateText : ProjectEditScreen.formatDate(d),
            key: ValueKey('$fieldKey-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Shown when `/projects/edit` is opened without a [Project] as `extra`
/// (deep link, notification, wrong type). No silent fallback to create.
class ProjectEditUnavailablePage extends StatelessWidget {
  const ProjectEditUnavailablePage({super.key});

  static const String message = 'Bu sayfa doğrudan açılamaz.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
