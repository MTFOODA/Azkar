import 'package:flutter/material.dart';

import '../../../core/design/app_palette.dart';

class MemorialGenderSegmentedControl extends StatelessWidget {
  const MemorialGenderSegmentedControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedColor = theme.brightness == Brightness.dark
        ? colorScheme.primary
        : colorScheme.secondary;
    final selectedTextColor = theme.brightness == Brightness.dark
        ? colorScheme.onPrimary
        : colorScheme.onSecondary;
    final borderRadius = BorderRadius.circular(AppPalette.radiusMd);

    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outline),
          borderRadius: borderRadius,
        ),
        child: Row(
          children: [
            _GenderSegment(
              label: 'المرحوم',
              option: 'male',
              selected: value == 'male',
              selectedColor: selectedColor,
              selectedTextColor: selectedTextColor,
              onTap: onChanged,
            ),
            Container(width: 1, height: 48, color: colorScheme.outline),
            _GenderSegment(
              label: 'المرحومة',
              option: 'female',
              selected: value == 'female',
              selectedColor: selectedColor,
              selectedTextColor: selectedTextColor,
              onTap: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderSegment extends StatelessWidget {
  const _GenderSegment({
    required this.label,
    required this.option,
    required this.selected,
    required this.selectedColor,
    required this.selectedTextColor,
    required this.onTap,
  });

  final String label;
  final String option;
  final bool selected;
  final Color selectedColor;
  final Color selectedTextColor;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('memorial-gender-$option'),
        onTap: () => onTap(option),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          color: selected ? selectedColor : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppPalette.spaceSm),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? selectedTextColor
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    ),
  );
}
