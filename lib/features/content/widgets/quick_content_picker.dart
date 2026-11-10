import 'package:flutter/material.dart';

import '../../../core/utils/arabic_text_utils.dart';
import '../data/quick_content_library.dart';
import '../domain/content_type.dart';

class QuickContentPicker extends StatefulWidget {
  const QuickContentPicker({super.key, required this.type});
  final ContentType type;
  @override
  State<QuickContentPicker> createState() => _QuickContentPickerState();
}

class _QuickContentPickerState extends State<QuickContentPicker> {
  late Future<List<QuickContentPreset>> _loader;
  String _search = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    _loader = QuickContentLibrary.forType(widget.type);
  }

  @override
  void didUpdateWidget(covariant QuickContentPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _loader = QuickContentLibrary.forType(widget.type);
      _search = '';
      _category = null;
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.45,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'اختيارات سريعة — ${widget.type.pluralLabelAr}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey('quick-content-search-${widget.type.id}'),
              decoration: const InputDecoration(
                labelText: 'ابحث عن نص أو عنوان',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(
                () => _search = ArabicTextUtils.comparisonKey(value),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<QuickContentPreset>>(
                key: ValueKey(widget.type),
                future: _loader,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'تعذّر تحميل الاختيارات. يمكنك كتابة المحتوى بنفسك.',
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final categories =
                      snapshot.data!
                          .expand((item) => item.categories)
                          .toSet()
                          .toList()
                        ..sort();
                  final items = snapshot.data!
                      .where(
                        (item) =>
                            item.type == widget.type &&
                            (_category == null ||
                                item.categories.contains(_category)) &&
                            (_search.isEmpty ||
                                item.normalizedSearchText.contains(_search)),
                      )
                      .toList();
                  final list = items.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد نتائج. جرّب كلمة أخرى أو أضف نصك بنفسك.',
                          ),
                        )
                      : ListView.separated(
                          controller: controller,
                          itemCount: items.length,
                          separatorBuilder: (_, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ListTile(
                              key: ValueKey(
                                'quick-preset-${item.type.id}-${item.id}',
                              ),
                              title: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(item.source, maxLines: 2),
                              trailing: const Icon(Icons.add_circle_outline),
                              onTap: () => Navigator.pop(context, item),
                            );
                          },
                        );
                  return Column(
                    children: [
                      if (categories.length > 1) ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'quick-content-category-${widget.type.id}',
                          ),
                          initialValue: _category ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'الباب'),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('كل الأبواب'),
                            ),
                            for (final category in categories)
                              DropdownMenuItem(
                                value: category,
                                child: Text(
                                  category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _category = value == '' ? null : value,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          '${items.length} اختيار متاح',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(child: list),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
