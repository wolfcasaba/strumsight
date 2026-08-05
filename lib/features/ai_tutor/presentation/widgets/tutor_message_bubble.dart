/// Tutor Chat message bubble (E04-R18 §5.1).
///
/// Renders one [TutorMessage] by iterating its content blocks. Each
/// block type has its own renderer; an unknown block is rendered as a
/// non-executable, monospaced, JSON-escaped panel — the renderer
/// NEVER parses the payload as HTML or runs any script.
///
/// The bubble is `const`-friendly: it never reaches into providers.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../domain/models/tutor_content_block.dart';
import '../../domain/models/tutor_message.dart';

/// Renders one tutor (or user) message.
class TutorMessageBubble extends StatelessWidget {
  const TutorMessageBubble({super.key, required this.message});

  final TutorMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == TutorMessageRole.user;
    final alignment = isUser
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    final color = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final block in message.blocks)
                  _BlockView(block: block, color: textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.color});

  final TutorContentBlock block;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Bind `block` to a local so `is`-checks promote the type. Field
    // promotion is intentionally conservative in Dart; this is the
    // documented workaround.
    final TutorContentBlock b = block;
    final theme = Theme.of(context);
    final bodySmall = theme.textTheme.bodySmall?.copyWith(color: color);
    final bodyMedium = theme.textTheme.bodyMedium?.copyWith(color: color);
    final titleMedium = theme.textTheme.titleMedium?.copyWith(
      color: color,
      fontWeight: FontWeight.w700,
    );

    if (b is TutorTextBlock) {
      return _Text(text: b.text, color: color);
    }
    if (b is TutorHeadingBlock) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(b.text, style: titleMedium),
      );
    }
    if (b is TutorBulletListBlock) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final item in b.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _Text(text: '• $item', color: color),
              ),
          ],
        ),
      );
    }
    if (b is TutorMetricBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '${b.label}: ${b.value}${b.unit != null ? ' ${b.unit}' : ''}',
          style: bodyMedium?.copyWith(
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      );
    }
    if (b is TutorEvidenceBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '[evidence:${b.evidenceId}] ${b.summary}',
          style: bodySmall,
        ),
      );
    }
    if (b is TutorSourceBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('${b.title} (${b.reference})', style: bodySmall),
      );
    }
    if (b is TutorActionBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '[action:${b.actionId.value}] ${b.label}',
          style: bodySmall,
        ),
      );
    }
    if (b is TutorPracticePlanBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('[plan:${b.planId}] ${b.title}', style: bodySmall),
      );
    }
    if (b is TutorWarningBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('⚠ ${b.message}', style: bodySmall),
      );
    }
    if (b is TutorErrorBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('⨯ ${b.message}', style: bodySmall),
      );
    }
    if (b is TutorUnknownContentBlock) {
      return _UnknownBlock(block: b, color: color);
    }
    return const SizedBox.shrink();
  }
}

class _Text extends StatelessWidget {
  const _Text({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
      ),
    );
  }
}

/// Renders an unknown block as a non-executable, monospaced JSON
/// panel. The raw payload is escaped and displayed verbatim — never
/// parsed as HTML, never executed.
class _UnknownBlock extends StatelessWidget {
  const _UnknownBlock({required this.block, required this.color});

  final TutorUnknownContentBlock block;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(block.rawJson);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          '[unknown:${block.originalType}]\n$pretty',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
