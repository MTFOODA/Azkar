import 'package:flutter/material.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/design/card_shape.dart';
import '../../../../core/typography/arabic_font_loader.dart';
import '../../../../core/typography/arabic_fonts.dart';
import '../../../../core/utils/hex_color.dart';
import '../../../content/domain/card_style.dart';

/// Appearance controls shared by every admin content editor.
class CardStyleEditor extends StatefulWidget {
  const CardStyleEditor({
    super.key,
    required this.style,
    required this.onChanged,
  });

  final CardStyle style;
  final ValueChanged<CardStyle> onChanged;

  @override
  State<CardStyleEditor> createState() => _CardStyleEditorState();
}

class _CardStyleEditorState extends State<CardStyleEditor> {
  late final TextEditingController _textColorController;
  late final TextEditingController _backgroundController;

  @override
  void initState() {
    super.initState();
    _textColorController = TextEditingController(text: widget.style.textColor);
    _backgroundController = TextEditingController(
      text: widget.style.backgroundColor,
    );
  }

  @override
  void didUpdateWidget(covariant CardStyleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style.textColor != widget.style.textColor &&
        _textColorController.text != widget.style.textColor) {
      _textColorController.text = widget.style.textColor;
    }
    if (oldWidget.style.backgroundColor != widget.style.backgroundColor &&
        _backgroundController.text != widget.style.backgroundColor) {
      _backgroundController.text = widget.style.backgroundColor;
    }
  }

  @override
  void dispose() {
    _textColorController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  void _change(CardStyle value) => widget.onChanged(value);

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('مظهر البطاقة', style: theme.textTheme.titleLarge),
        const SizedBox(height: AppPalette.spaceMd),
        DropdownButtonFormField<String>(
          initialValue: style.fontFamily,
          decoration: const InputDecoration(labelText: 'الخط العربي'),
          items: [
            for (final font in ArabicFonts.all)
              DropdownMenuItem(
                value: font.id,
                child: Text('${font.labelAr} — ${font.labelEn}'),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            ArabicFontLoader.ensure(value);
            _change(style.copyWith(fontFamily: value));
          },
        ),
        const SizedBox(height: AppPalette.spaceMd),
        SliderField(
          label: 'حجم الخط',
          value: style.fontSize,
          min: CardStyle.minFontSize,
          max: CardStyle.maxFontSize,
          divisions: 58,
          onChanged: (value) => _change(style.copyWith(fontSize: value)),
        ),
        DropdownButtonFormField<int>(
          initialValue: style.fontWeight,
          decoration: const InputDecoration(labelText: 'وزن الخط'),
          items: [
            for (final weight in <int>[300, 400, 500, 600, 700, 800, 900])
              DropdownMenuItem(value: weight, child: Text('$weight')),
          ],
          onChanged: (value) {
            if (value != null) _change(style.copyWith(fontWeight: value));
          },
        ),
        SliderField(
          label: 'ارتفاع السطر',
          value: style.lineHeight,
          min: CardStyle.minLineHeight,
          max: CardStyle.maxLineHeight,
          divisions: 18,
          onChanged: (value) => _change(style.copyWith(lineHeight: value)),
        ),
        const SizedBox(height: AppPalette.spaceSm),
        DropdownButtonFormField<CardShapeId>(
          initialValue: style.shape,
          decoration: const InputDecoration(labelText: 'شكل البطاقة'),
          items: [
            for (final shape in CardShapeId.values)
              DropdownMenuItem(value: shape, child: Text(shape.labelAr)),
          ],
          onChanged: (value) {
            if (value != null) _change(style.copyWith(shape: value));
          },
        ),
        const SizedBox(height: AppPalette.spaceMd),
        DropdownButtonFormField<TextAlign>(
          initialValue: style.textAlignment,
          decoration: const InputDecoration(labelText: 'محاذاة النص'),
          items: const [
            DropdownMenuItem(value: TextAlign.center, child: Text('وسط')),
            DropdownMenuItem(
              value: TextAlign.start,
              child: Text('بداية السطر'),
            ),
            DropdownMenuItem(value: TextAlign.end, child: Text('نهاية السطر')),
            DropdownMenuItem(value: TextAlign.justify, child: Text('ضبط')),
          ],
          onChanged: (value) {
            if (value != null) _change(style.copyWith(textAlignment: value));
          },
        ),
        const SizedBox(height: AppPalette.spaceMd),
        ColorField(
          controller: _textColorController,
          label: 'لون النص (#RRGGBB)',
          onChanged: (value) => _change(style.copyWith(textColor: value)),
          onSwatch: (color) {
            _textColorController.text = HexColor.format(color);
            _change(style.copyWith(textColor: HexColor.format(color)));
          },
        ),
        const SizedBox(height: AppPalette.spaceMd),
        ColorField(
          controller: _backgroundController,
          label: 'لون خلفية البطاقة (#RRGGBB)',
          onChanged: (value) => _change(style.copyWith(backgroundColor: value)),
          onSwatch: (color) {
            _backgroundController.text = HexColor.format(color);
            _change(style.copyWith(backgroundColor: HexColor.format(color)));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تدرّج لوني خفيف'),
          value: style.gradientEnabled,
          onChanged: (value) => _change(style.copyWith(gradientEnabled: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('زخرفة هندسية إسلامية'),
          value: style.decorationEnabled,
          onChanged: (value) =>
              _change(style.copyWith(decorationEnabled: value)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('إطار حول البطاقة'),
          value: style.borderEnabled,
          onChanged: (value) => _change(style.copyWith(borderEnabled: value)),
        ),
      ],
    );
  }
}

class SliderField extends StatelessWidget {
  const SliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(value < 5 ? 1 : 0)}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class ColorField extends StatelessWidget {
  const ColorField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    required this.onSwatch,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final ValueChanged<Color> onSwatch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(labelText: label),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in <Color>[
              AppPalette.lightPrimary,
              AppPalette.lightSecondary,
              AppPalette.lightText,
              AppPalette.lightSurface,
              AppPalette.lightBackground,
              AppPalette.darkSurface,
              AppPalette.darkText,
            ])
              InkWell(
                onTap: () => onSwatch(color),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
