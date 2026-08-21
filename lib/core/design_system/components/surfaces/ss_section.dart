import 'package:flutter/material.dart';

import '../../foundations/ss_spacing.dart';

/// A title and content composition that deliberately adds no card layer.
final class SsSection extends StatelessWidget {
  const SsSection({
    super.key,
    required this.title,
    required this.child,
    this.spacing = SsSpacing.space2,
  });

  final String title;
  final Widget child;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(height: spacing),
        child,
      ],
    );
  }
}
