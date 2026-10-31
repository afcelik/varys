import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/theme/app_theme.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
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
  String _originalText = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.plan.sayNoText ?? '');
    _originalText = widget.plan.sayNoText ?? '';
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

  void _saveIfChanged() {
    final currentText = _controller.text.trim();
    if (currentText != _originalText) {
      _originalText = currentText;
      // Send empty string as null to clear
      final textToSend = currentText.isEmpty ? null : currentText;
      ref.read(dailyPlanProvider.notifier).updatePlan(sayNoText: textToSend);
    }
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
                Text(
                  'Bugün "Hayır" Diyeceğim Şey',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.amberHighlight,
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