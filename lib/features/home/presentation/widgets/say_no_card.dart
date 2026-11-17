import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/theme/app_theme.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';

/// "What will I say no to today?" card - amber styled editable text field
class SayNoCard extends ConsumerStatefulWidget {
  const SayNoCard({super.key, required this.plan});

  final DailyPlan plan;

  @override
  ConsumerState<SayNoCard> createState() => _SayNoCardState();
}

class _SayNoCardState extends ConsumerState<SayNoCard> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  /// Last successfully saved value, normalized: null, "" and whitespace-only
  /// are all treated as the same empty value ("").
  String _originalText = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.plan.sayNoText ?? '');
    _originalText = (widget.plan.sayNoText ?? '').trim();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _saveIfChanged();
    }
  }

  /// Saves when the text differs from the last SUCCESSFULLY saved value.
  /// On failure the typed text stays in the field and the next focus loss retries.
  Future<void> _saveIfChanged() async {
    final currentText = _controller.text.trim();
    if (_isSaving || currentText == _originalText) return;

    _isSaving = true;
    // Empty (or whitespace-only) clears the field with explicit null, never ""
    final notifier = ref.read(dailyPlanProvider.notifier);
    final result = currentText.isEmpty
        ? await notifier.clearSayNoText()
        : await notifier.updatePlan(sayNoText: PlanField.set(currentText));
    _isSaving = false;
    if (!mounted) return;

    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
      ),
      (_) {
        _originalText = currentText;
        // Cleared: drop leftover whitespace so the hint shows
        if (currentText.isEmpty) _controller.clear();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: AppTheme.amberCardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.amberBorder,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.block_outlined,
                  size: 20,
                  color: AppTheme.amberHighlight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bugün "Hayır" Diyeceğim Şey',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.amberHighlight,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 1,
              decoration: InputDecoration(
                hintText: 'Örn: Sosyal medya, gereksiz toplantılar...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.amberHighlight.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppTheme.amberHighlight,
              ),
              onSubmitted: (_) => _saveIfChanged(),
              onEditingComplete: _saveIfChanged,
            ),
          ],
        ),
      ),
    );
  }
}