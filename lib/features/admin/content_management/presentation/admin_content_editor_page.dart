import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/utils/app_exception.dart';
import '../../../../core/widgets/route_back_button.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/domain/card_style.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';
import '../../../content/domain/content_validation.dart';
import '../../../content/data/content_homepage_lifecycle.dart';
import '../../../content/widgets/content_card.dart';
import '../../../content/data/quick_content_library.dart';
import '../../../content/widgets/quick_content_picker.dart';
import '../../../quran/domain/quran_dataset.dart';
import '../../dashboard/presentation/admin_shell.dart';
import '../providers/admin_providers.dart';
import 'card_style_editor.dart';

/// Create/edit screen with draft/publish workflow and a live public-renderer
/// preview. The same screen handles all seven content types.
class AdminContentEditorPage extends ConsumerStatefulWidget {
  const AdminContentEditorPage({
    super.key,
    required this.type,
    this.itemId,
    this.basePath = '/admin',
  });

  final ContentType type;
  final String? itemId;
  final String basePath;

  bool get isNew => itemId == null || itemId == 'new';

  @override
  ConsumerState<AdminContentEditorPage> createState() =>
      _AdminContentEditorPageState();
}

class _AdminContentEditorPageState
    extends ConsumerState<AdminContentEditorPage> {
  late Future<ContentItem> _loader;
  final Map<String, TextEditingController> _controllers = {};
  ContentItem? _base;
  late ContentItem _draft;
  bool _ready = false;
  bool _busy = false;
  bool _applyingPreset = false;
  bool _hasEdits = false;
  bool _mobilePreview = false;
  Map<String, String> _errors = {};
  List<String> _warnings = [];
  QuranValidationResult? _quranResult;
  List<QuranSurahMeta> _surahs = [];
  bool _surahIndexLoading = false;
  String? _surahIndexError;
  int? _surahNumber;
  HadithAuthenticity _authenticity = HadithAuthenticity.unverified;
  DedicationRecipient _recipient = DedicationRecipient.male;

  static const List<String> _textKeys = <String>[
    'title',
    'arabicText',
    'description',
    'source',
    'translation',
    'narrator',
    'hadithNumber',
    'explanation',
    'surahName',
    'ayahFrom',
    'ayahTo',
    'videoUrl',
    'personName',
    'dedicationMessage',
  ];

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<ContentItem> _load() async {
    if (widget.isNew) {
      final theme = ref.read(themeSettingsProvider);
      return ContentItem(
        id: '',
        type: widget.type,
        surahNumber: widget.type == ContentType.quran ? 1 : null,
        ayahFrom: widget.type == ContentType.quran ? 1 : null,
        ayahTo: widget.type == ContentType.quran ? 1 : null,
        style: CardStyle.fromTheme(
          theme,
          hint: widget.type == ContentType.dedication
              ? ContentShapeHint.secondary
              : ContentShapeHint.primary,
        ),
      );
    }
    final item = await ref
        .read(contentRepositoryProvider)
        .fetchById(widget.type, widget.itemId!);
    if (item == null) throw const NotFoundException();
    return item;
  }

  void _initialize(ContentItem item) {
    _base = item;
    _draft = item;
    _hasEdits = false;
    _surahNumber = item.surahNumber;
    _authenticity = item.authenticity;
    _recipient = item.recipient;
    for (final key in _textKeys) {
      final controller = TextEditingController(text: _initialText(key, item));
      controller.addListener(_onTextChanged);
      _controllers[key] = controller;
    }
    if (widget.type == ContentType.quran) {
      _surahIndexLoading = true;
      unawaited(_loadSurahIndex());
    }
    setState(() => _ready = true);
  }

  Future<void> _loadSurahIndex() async {
    try {
      final surahs = await ref
          .read(quranDatasetRepositoryProvider)
          .surahIndex();
      if (!mounted) return;
      setState(() {
        _surahs = surahs;
        _surahIndexError = null;
        _surahIndexLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _surahIndexError = friendlyMessage(error);
        _surahIndexLoading = false;
      });
    }
  }

  String _initialText(String key, ContentItem item) => switch (key) {
    'title' => item.title,
    'arabicText' => item.arabicText,
    'description' => item.description ?? '',
    'source' => item.source ?? '',
    'translation' => item.translation ?? '',
    'narrator' => item.narrator ?? '',
    'hadithNumber' => item.hadithNumber ?? '',
    'explanation' => item.explanation ?? '',
    'surahName' => item.surahName ?? '',
    'ayahFrom' => item.ayahFrom?.toString() ?? '',
    'ayahTo' => item.ayahTo?.toString() ?? '',
    'videoUrl' => item.videoUrl ?? '',
    'personName' => item.personName ?? '',
    'dedicationMessage' => item.dedicationMessage ?? '',
    _ => '',
  };

  TextEditingController _c(String key) => _controllers[key]!;

  String _text(String key) => _c(key).text;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    if (!_ready || _applyingPreset) return;
    setState(() {
      _hasEdits = true;
      _quranResult = null;
      _draft = _buildDraft();
    });
  }

  ContentItem _buildDraft() {
    final base = _base!;
    final from = int.tryParse(_text('ayahFrom').trim());
    final to = int.tryParse(_text('ayahTo').trim()) ?? from;
    var item = base.copyWith(
      title: _text('title'),
      arabicText: _text('arabicText'),
      description: _text('description'),
      source: _text('source'),
      translation: _text('translation'),
      narrator: _text('narrator'),
      hadithNumber: _text('hadithNumber'),
      explanation: _text('explanation'),
      surahNumber: _surahNumber,
      surahName: _text('surahName'),
      ayahFrom: from,
      ayahTo: to,
      videoUrl: _text('videoUrl'),
      videoId: _text('videoUrl').trim().isEmpty
          ? null
          : Uri.tryParse(_text('videoUrl'))?.queryParameters['v'],
      authenticity: _authenticity,
      recipient: _recipient,
      personName: _text('personName'),
      dedicationMessage: _text('dedicationMessage'),
      clearValidation: true,
      style: _draft.style,
    );
    final result = _quranResult;
    if (widget.type == ContentType.quran && result != null && result.isValid) {
      item = item.copyWith(
        validationHash: result.fingerprint,
        datasetVersion: result.datasetVersion,
      );
    }
    return item;
  }

  void _updateStyle(CardStyle style) {
    setState(() {
      _hasEdits = true;
      _draft = _draft.copyWith(style: style);
    });
  }

  Future<void> _choosePreset() async {
    final type = widget.type;
    final preset = await showModalBottomSheet<QuickContentPreset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => QuickContentPicker(type: type),
    );
    if (preset == null ||
        !mounted ||
        widget.type != type ||
        preset.type != type) {
      return;
    }
    if (_hasEdits) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('استبدال النص الحالي؟'),
          content: Text(
            'سيتم ملء الحقول باختيار «${preset.title}». يمكنك تعديله قبل الحفظ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('استخدام الاختيار'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted || widget.type != type) return;
    }
    setState(() => _busy = true);
    try {
      final dataset = type == ContentType.quran
          ? await ref.read(quranDatasetRepositoryProvider).dataset()
          : null;
      if (!mounted || widget.type != type) return;
      final item = preset.createDraft(dataset: dataset);
      if (!mounted) return;
      _applyingPreset = true;
      _surahNumber = item.surahNumber;
      _authenticity = item.authenticity;
      for (final key in _textKeys) {
        _c(key).text = _initialText(key, item);
      }
      _applyingPreset = false;
      setState(() {
        _hasEdits = true;
        _errors = {};
        _quranResult = dataset?.validateRange(
          surahNumber: item.surahNumber!,
          from: item.ayahFrom!,
          to: item.ayahTo!,
          text: item.arabicText,
        );
        _draft = _buildDraft();
      });
    } catch (error) {
      _applyingPreset = false;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _verifyQuran() async {
    final item = _buildDraft();
    final result = await ref
        .read(quranDatasetRepositoryProvider)
        .validate(
          surahNumber: item.surahNumber ?? 0,
          from: item.ayahFrom ?? 0,
          to: item.ayahTo ?? item.ayahFrom ?? 0,
          text: item.arabicText,
        );
    if (!mounted) return result.isValid;
    setState(() {
      _quranResult = result;
      _draft = _buildDraft();
    });
    if (!result.isValid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.messageAr)));
    }
    return result.isValid;
  }

  Future<void> _insertVerifiedQuranText() async {
    final from = int.tryParse(_text('ayahFrom').trim()) ?? 1;
    final to = int.tryParse(_text('ayahTo').trim()) ?? from;
    try {
      final dataset = await ref.read(quranDatasetRepositoryProvider).dataset();
      final text = dataset.rangeText(_surahNumber ?? 1, from, to);
      if (text == null || text.isEmpty) {
        if (mounted) {
          setState(() => _hasEdits = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('نطاق الآيات غير صالح لهذه السورة.')),
          );
        }
        return;
      }
      _c('arabicText').text = text;
      final surah = dataset.surah(_surahNumber ?? 1);
      if (surah != null) _c('surahName').text = surah.name;
      await _verifyQuran();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
  }

  Future<void> _save(bool publish) async {
    if (_busy) return;
    if (publish && widget.type == ContentType.quran) {
      final valid = await _verifyQuran();
      if (!mounted || !valid) return;
    }
    final item = _buildDraft().copyWith(isPublished: publish);
    final validation = ContentValidation.validate(
      item,
      forPublication: publish,
    );
    if (!validation.isValid) {
      setState(() {
        _errors = validation.fieldErrors;
        _warnings = validation.warnings;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validation.fieldErrors.values.first)),
      );
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
      _warnings = validation.warnings;
    });
    try {
      if (widget.isNew) {
        await ref.read(contentHomepageLifecycleProvider).saveNew(item);
      } else {
        await ref.read(contentRepositoryProvider).save(item);
      }
      invalidateContentViews(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(publish ? 'تم نشر المحتوى' : 'تم حفظ المسودة'),
          ),
        );
        context.go('${widget.basePath}/content/${widget.type.id}');
      }
    } catch (error) {
      if (error is ContentHomepageLinkException) {
        invalidateContentViews(ref);
        _base = error.savedItem;
        _draft = error.savedItem;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _error(String key) => _errors[key];

  Widget _field(
    String key,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    TextDirection? direction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppPalette.spaceMd),
      child: TextField(
        controller: _c(key),
        maxLines: maxLines,
        keyboardType: keyboardType,
        textDirection: direction,
        decoration: InputDecoration(
          labelText: label,
          errorText: _error(key),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ContentItem>(
      future: _loader,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(
            error: snapshot.error,
            onRetry: () =>
                context.go('${widget.basePath}/content/${widget.type.id}'),
          );
        }
        if (!snapshot.hasData) return const LoadingView();
        if (!_ready) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_ready) _initialize(snapshot.data!);
          });
          return const LoadingView();
        }
        return _buildEditor(context);
      },
    );
  }

  Widget _buildEditor(BuildContext context) {
    final form = _buildForm(context);
    final preview = _buildPreview(context);
    return UnsavedChangesGuard(
      isDirty: _hasEdits,
      fallbackLocation: '${widget.basePath}/content/${widget.type.id}',
      child: SingleChildScrollView(
        child: AdminPageContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: widget.isNew
                    ? 'إنشاء ${widget.type.labelAr}'
                    : 'تعديل ${widget.type.labelAr}',
                subtitle: 'المعاينة تستخدم نفس مكوّن العرض في الموقع العام.',
                trailing: TextButton(
                  onPressed: () => navigateBack(
                    context,
                    fallbackLocation:
                        '${widget.basePath}/content/${widget.type.id}',
                  ),
                  child: const Text('إلغاء'),
                ),
              ),
              const SizedBox(height: AppPalette.spaceLg),
              if (_errors.isNotEmpty)
                _ValidationMessages(errors: _errors, warnings: _warnings),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 1000) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: form),
                        const SizedBox(width: AppPalette.spaceXl),
                        Expanded(flex: 4, child: preview),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      form,
                      const SizedBox(height: AppPalette.spaceXl),
                      preview,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'معاينة حية',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('سطح المكتب'),
                  icon: Icon(Icons.desktop_windows_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('جوال'),
                  icon: Icon(Icons.phone_android_outlined),
                ),
              ],
              selected: {_mobilePreview},
              onSelectionChanged: (value) =>
                  setState(() => _mobilePreview = value.first),
            ),
          ],
        ),
        const SizedBox(height: AppPalette.spaceMd),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _mobilePreview ? 360 : 620),
            child: ContentCard(item: _draft, preview: true),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('المحتوى', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppPalette.spaceMd),
        if (QuickContentLibrary.supports(widget.type)) ...[
          OutlinedButton.icon(
            key: const ValueKey('quick-content-picker'),
            onPressed: _busy ? null : _choosePreset,
            icon: const Icon(Icons.library_add_outlined),
            label: const Text('اختيار سريع من المكتبة'),
          ),
          const SizedBox(height: 8),
          const Text(
            'اختَر نصاً جاهزاً بمصدره أو اكتب محتوى جديداً في الحقول أدناه.',
          ),
          const SizedBox(height: AppPalette.spaceMd),
        ],
        if (widget.type != ContentType.tasbeeh &&
            widget.type != ContentType.youtube)
          _field('title', 'العنوان (اختياري)'),
        if (widget.type == ContentType.quran) _quranFields(),
        if (widget.type == ContentType.hadith) _hadithFields(),
        if (widget.type == ContentType.youtube) _youtubeFields(),
        if (widget.type == ContentType.dedication) _dedicationFields(),
        if (widget.type == ContentType.azkar ||
            widget.type == ContentType.dua) ...[
          _field(
            'arabicText',
            'النص العربي',
            maxLines: 6,
            direction: TextDirection.rtl,
          ),
          _field('description', 'وصف مختصر (اختياري)', maxLines: 3),
          _field('source', 'المصدر (اختياري)'),
        ],
        if (widget.type == ContentType.tasbeeh)
          _field(
            'arabicText',
            'نص التسبيح',
            maxLines: 3,
            direction: TextDirection.rtl,
          ),
        const Divider(height: AppPalette.spaceXl),
        CardStyleEditor(style: _draft.style, onChanged: _updateStyle),
        const SizedBox(height: AppPalette.spaceLg),
        Wrap(
          spacing: AppPalette.spaceMd,
          runSpacing: AppPalette.spaceMd,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _save(false),
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ كمسودة'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _save(true),
              icon: const Icon(Icons.publish_outlined),
              label: const Text('نشر'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quranFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_surahIndexLoading)
          const LinearProgressIndicator()
        else if (_surahIndexError != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  _surahIndexError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: _loadSurahIndex,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          )
        else
          DropdownButtonFormField<int>(
            key: ValueKey(_surahNumber),
            initialValue: _surahNumber,
            decoration: const InputDecoration(labelText: 'السورة'),
            items: [
              for (final surah in _surahs)
                DropdownMenuItem(
                  value: surah.number,
                  child: Text(surah.labelAr),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _hasEdits = true;
                _surahNumber = value;
                final selected = _surahs.where(
                  (surah) => surah.number == value,
                );
                if (selected.isNotEmpty) {
                  _c('surahName').text = selected.first.name;
                }
                _quranResult = null;
                _draft = _buildDraft();
              });
            },
          ),
        const SizedBox(height: AppPalette.spaceMd),
        Row(
          children: [
            Expanded(
              child: _field(
                'ayahFrom',
                'من الآية',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppPalette.spaceMd),
            Expanded(
              child: _field(
                'ayahTo',
                'إلى الآية',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        _field('surahName', 'اسم السورة'),
        _field(
          'arabicText',
          'نص الآية/الآيات',
          maxLines: 7,
          direction: TextDirection.rtl,
        ),
        Wrap(
          spacing: AppPalette.spaceSm,
          runSpacing: AppPalette.spaceSm,
          children: [
            OutlinedButton.icon(
              onPressed: _insertVerifiedQuranText,
              icon: const Icon(Icons.verified_outlined),
              label: const Text('إدراج النص المعتمد'),
            ),
            TextButton.icon(
              onPressed: _verifyQuran,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('التحقق من النص'),
            ),
          ],
        ),
        if (_quranResult != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppPalette.spaceSm),
            child: Text(
              _quranResult!.messageAr,
              style: TextStyle(
                color: _quranResult!.isValid
                    ? AppPalette.success
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        _field(
          'translation',
          'ترجمة موثوقة (اختياري)',
          maxLines: 3,
          direction: TextDirection.ltr,
        ),
      ],
    );
  }

  Widget _hadithFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          'arabicText',
          'نص الحديث',
          maxLines: 7,
          direction: TextDirection.rtl,
        ),
        _field('narrator', 'الراوي'),
        _field('source', 'الكتاب / المجموعة'),
        _field('hadithNumber', 'رقم الحديث أو المرجع'),
        Padding(
          padding: const EdgeInsets.only(bottom: AppPalette.spaceMd),
          child: DropdownButtonFormField<HadithAuthenticity>(
            initialValue: _authenticity,
            decoration: const InputDecoration(labelText: 'درجة الحديث'),
            items: [
              for (final value in HadithAuthenticity.values)
                DropdownMenuItem(value: value, child: Text(value.labelAr)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _hasEdits = true;
                _authenticity = value;
                _draft = _buildDraft();
              });
            },
          ),
        ),
        _field('explanation', 'شرح مختصر (اختياري)', maxLines: 4),
      ],
    );
  }

  Widget _youtubeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field('title', 'عنوان الفيديو (اختياري)'),
        _field(
          'videoUrl',
          'رابط يوتيوب أو Shorts',
          direction: TextDirection.ltr,
        ),
        _field('description', 'وصف (اختياري)', maxLines: 3),
      ],
    );
  }

  Widget _dedicationFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field('personName', 'اسم الشخص / الأشخاص'),
        Padding(
          padding: const EdgeInsets.only(bottom: AppPalette.spaceMd),
          child: DropdownButtonFormField<DedicationRecipient>(
            initialValue: _recipient,
            decoration: const InputDecoration(labelText: 'صيغة الإهداء'),
            items: [
              for (final value in DedicationRecipient.values)
                DropdownMenuItem(value: value, child: Text(value.labelAr)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _hasEdits = true;
                _recipient = value;
                _draft = _buildDraft();
              });
            },
          ),
        ),
        _field('dedicationMessage', 'رسالة الإهداء', maxLines: 2),
        _field(
          'arabicText',
          'الدعاء',
          maxLines: 5,
          direction: TextDirection.rtl,
        ),
      ],
    );
  }
}

class _ValidationMessages extends StatelessWidget {
  const _ValidationMessages({required this.errors, required this.warnings});

  final Map<String, String> errors;
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppPalette.spaceLg),
      padding: const EdgeInsets.all(AppPalette.spaceMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppPalette.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in errors.values)
            Text(
              '• $message',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          for (final warning in warnings)
            Text('• $warning', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
