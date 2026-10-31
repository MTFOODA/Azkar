import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/design/card_shape.dart';
import '../../../../core/design/theme_settings.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/typography/arabic_font_loader.dart';
import '../../../../core/typography/arabic_fonts.dart';
import '../../../../core/utils/app_exception.dart';
import '../../../../core/utils/hex_color.dart';
import '../../../../core/widgets/route_back_button.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/domain/card_style.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';
import '../../../content/widgets/content_card.dart';
import '../../content_management/presentation/card_style_editor.dart';
import '../../dashboard/presentation/admin_shell.dart';

/// Global palette/font/shape settings with live preview and contrast checks.
class AdminAppearancePage extends ConsumerStatefulWidget {
  const AdminAppearancePage({super.key, this.isPersonalPageAppearance = false});

  final bool isPersonalPageAppearance;

  @override
  ConsumerState<AdminAppearancePage> createState() =>
      _AdminAppearancePageState();
}

class _AdminAppearancePageState extends ConsumerState<AdminAppearancePage> {
  final Map<String, TextEditingController> _controllers = {};
  ThemeSettings? _settings;
  ThemeSettings? _originalSettings;
  bool _busy = false;
  String? _message;

  static const Map<String, String> _labels = <String, String>{
    'primaryColor': 'اللون الأساسي',
    'secondaryColor': 'اللون الثانوي (الذهبي)',
    'backgroundColor': 'لون خلفية الموقع',
    'surfaceColor': 'لون السطح',
    'defaultCardColor': 'لون البطاقة الافتراضي',
    'defaultTextColor': 'لون النص الافتراضي',
  };

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initialize(ThemeSettings settings) {
    _settings = settings;
    _originalSettings = settings;
    final values = <String, String>{
      'primaryColor': settings.primaryColor,
      'secondaryColor': settings.secondaryColor,
      'backgroundColor': settings.backgroundColor,
      'surfaceColor': settings.surfaceColor,
      'defaultCardColor': settings.defaultCardColor,
      'defaultTextColor': settings.defaultTextColor,
    };
    for (final entry in values.entries) {
      _controllers[entry.key] = TextEditingController(text: entry.value);
    }
  }

  ThemeSettings _readSettings() {
    final current = _settings!;
    return current.copyWith(
      primaryColor: _controllers['primaryColor']!.text.trim(),
      secondaryColor: _controllers['secondaryColor']!.text.trim(),
      backgroundColor: _controllers['backgroundColor']!.text.trim(),
      surfaceColor: _controllers['surfaceColor']!.text.trim(),
      defaultCardColor: _controllers['defaultCardColor']!.text.trim(),
      defaultTextColor: _controllers['defaultTextColor']!.text.trim(),
    );
  }

  void _changed() => setState(() => _settings = _readSettings());

  Future<void> _save() async {
    final settings = _readSettings();
    final errors = <String, String>{
      ...settings.validate(),
      ...settings.contrastProblems(),
    };
    if (errors.isNotEmpty) {
      setState(() => _message = errors.values.first);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ArabicFontLoader.ensure(settings.defaultFontId);
      await ref.read(themeSettingsProvider.notifier).update(settings);
      if (mounted) {
        setState(() {
          _settings = settings;
          _originalSettings = settings;
          _message = 'تم حفظ إعدادات المظهر وتطبيقها على الموقع.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final global = ref.watch(themeSettingsProvider);
    if (_settings == null) _initialize(global);
    final settings = _readSettings();
    final previewItem = ContentItem(
      id: 'appearance-preview',
      type: ContentType.azkar,
      title: 'معاينة الهوية',
      arabicText: 'سبحان الله وبحمده',
      description: 'هذه معاينة للنص والبطاقة بالإعدادات الحالية.',
      style: CardStyle.fromTheme(settings),
      isPublished: true,
    );
    return UnsavedChangesGuard(
      isDirty:
          _settings!.toMap().toString() !=
          _originalSettings!.toMap().toString(),
      fallbackLocation: widget.isPersonalPageAppearance
          ? '/dashboard'
          : '/admin/dashboard',
      child: SingleChildScrollView(
        child: AdminPageContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'المظهر والخطوط',
                subtitle: widget.isPersonalPageAppearance
                    ? 'تُطبق هذه الإعدادات على صفحتك فقط. يتم منع التباين غير المقروء.'
                    : 'تُطبق الإعدادات على المحتوى الجديد والهوية العامة. يتم منع التباين غير المقروء.',
              ),
              const SizedBox(height: AppPalette.spaceLg),
              LayoutBuilder(
                builder: (context, constraints) {
                  final form = _buildForm(settings);
                  final preview = AppearancePreview(item: previewItem);
                  if (constraints.maxWidth >= 1000) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: form),
                        const SizedBox(width: AppPalette.spaceXl),
                        Expanded(child: preview),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      form,
                      const SizedBox(height: AppPalette.spaceXl),
                      preview,
                    ],
                  );
                },
              ),
              if (_message != null) ...[
                const SizedBox(height: AppPalette.spaceMd),
                Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: AppPalette.spaceLg),
              Wrap(
                spacing: AppPalette.spaceMd,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ المظهر'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      for (final controller in _controllers.values) {
                        controller.dispose();
                      }
                      _controllers.clear();
                      _settings = null;
                    }),
                    child: const Text('إعادة تحميل الإعدادات'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in _labels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppPalette.spaceMd),
            child: ColorField(
              controller: _controllers[entry.key]!,
              label: '${entry.value} (#RRGGBB)',
              onChanged: (_) => _changed(),
              onSwatch: (color) {
                _controllers[entry.key]!.text = HexColor.format(color);
                _changed();
              },
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: settings.defaultFontId,
          decoration: const InputDecoration(labelText: 'الخط الافتراضي'),
          items: [
            for (final font in ArabicFonts.all)
              DropdownMenuItem(
                value: font.id,
                child: Text('${font.labelAr} — ${font.labelEn}'),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(
              () => _settings = _readSettings().copyWith(defaultFontId: value),
            );
          },
        ),
        const SizedBox(height: AppPalette.spaceMd),
        DropdownButtonFormField<CardShapeId>(
          initialValue: settings.defaultCardShape,
          decoration: const InputDecoration(labelText: 'شكل البطاقة الافتراضي'),
          items: [
            for (final shape in CardShapeId.values)
              DropdownMenuItem(value: shape, child: Text(shape.labelAr)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(
              () =>
                  _settings = _readSettings().copyWith(defaultCardShape: value),
            );
          },
        ),
      ],
    );
  }
}

class AppearancePreview extends StatelessWidget {
  const AppearancePreview({super.key, required this.item});

  final ContentItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('معاينة حية', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppPalette.spaceMd),
        ContentCard(item: item, preview: true),
      ],
    );
  }
}
