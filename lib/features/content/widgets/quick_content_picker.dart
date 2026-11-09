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
  final _loader = QuickContentLibrary.load();
  String _search = '';
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
                  final items = snapshot.data!
                      .where(
                        (item) =>
                            item.type == widget.type &&
                            (_search.isEmpty ||
                                ArabicTextUtils.comparisonKey(item.searchText)
                                    .contains(_search)),
                      )
                      .toList();
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'لا توجد نتائج. جرّب كلمة أخرى أو أضف نصك بنفسك.',
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    itemCount: items.length,
                    separatorBuilder: (_, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        title: Text(item.title),
                        subtitle: Text(item.source, maxLines: 2),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
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
