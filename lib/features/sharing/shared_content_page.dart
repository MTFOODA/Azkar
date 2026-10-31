import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_palette.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/state_views.dart';
import '../content/domain/content_type.dart';
import '../content/providers/content_providers.dart';
import '../content/widgets/content_card.dart';

/// A stable public deep link for one shared content record.
class SharedContentPage extends ConsumerWidget {
  const SharedContentPage({super.key, required this.type, required this.id});

  final ContentType type;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItem = ref.watch(sharedContentProvider((type: type, id: id)));
    return SingleChildScrollView(
      child: PageContent(
        maxWidth: AppPalette.maxReadingWidth,
        child: asyncItem.when(
          loading: () => const LoadingView(),
          error: (error, stackTrace) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(
              sharedContentProvider((type: type, id: id)),
            ),
          ),
          data: (item) {
            if (item == null) {
              return const EmptyView(
                title: 'لم يتم العثور على هذا المحتوى',
                message: 'ربما حُذف أو أُلغي نشره. يمكنك العودة إلى الصفحة الرئيسية.',
                icon: Icons.search_off_outlined,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: item.type.labelAr),
                const SizedBox(height: AppPalette.spaceLg),
                ContentCard(item: item),
              ],
            );
          },
        ),
      ),
    );
  }
}
