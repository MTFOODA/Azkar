import 'package:flutter/material.dart';

import '../design/app_palette.dart';

/// Responsive breakpoints used by the public site and the dashboard.
class AppBreakpoints {
  const AppBreakpoints._();

  static const double mobile = 600;
  static const double tablet = 1024;
  static const double desktop = 1440;

  static int columnsFor(double width) {
    if (width < mobile) return 1;
    if (width < tablet) return 2;
    if (width < desktop) return 2;
    return 3;
  }
}

/// A masonry-like, height-flexible card grid.
///
/// `Wrap` is used instead of a fixed-height `GridView` so every card can grow
/// with its Arabic text. A card with `span == 2` takes two columns on wide
/// screens and automatically falls back to one column on mobile.
class AdaptiveCardGrid extends StatelessWidget {
  const AdaptiveCardGrid({
    super.key,
    required this.children,
    this.spacing = AppPalette.spaceLg,
    this.runSpacing = AppPalette.spaceLg,
    this.maxWidth = AppPalette.maxContentWidth,
    this.minCardWidth = 280,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final double maxWidth;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width < minCardWidth * 1.5
                ? 1
                : AppBreakpoints.columnsFor(width);
            final cardWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: runSpacing,
              children: [
                for (final child in children)
                  SizedBox(
                    width: _widthFor(child, cardWidth, columns, spacing),
                    child: child,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _widthFor(
    Widget child,
    double cardWidth,
    int columns,
    double spacing,
  ) {
    if (columns == 1) return cardWidth;
    int span;
    if (child is GridSpan) {
      span = child.span;
    } else {
      span = 1;
    }
    if (span <= 1) return cardWidth;
    final effective = span.clamp(1, columns);
    return cardWidth * effective + spacing * (effective - 1);
  }
}

/// Marks a child as spanning multiple columns in [AdaptiveCardGrid].
class GridSpan extends StatelessWidget {
  const GridSpan({super.key, required this.span, required this.child});

  final int span;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A centered, readable page container with safe mobile margins.
class PageContent extends StatelessWidget {
  const PageContent({
    super.key,
    required this.child,
    this.maxWidth = AppPalette.maxContentWidth,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(
                horizontal: AppPalette.spaceMd,
                vertical: AppPalette.spaceLg,
              ),
          child: child,
        ),
      ),
    );
  }
}
