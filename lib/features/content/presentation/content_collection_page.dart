import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/widgets/adaptive_layout.dart';
import '../../../core/widgets/state_views.dart';
import '../../content/domain/content_type.dart';
import '../../content/providers/content_providers.dart';
import '../../content/widgets/content_card.dart';

/// Generic public collection page for all seven content kinds.
class ContentCollectionPage extends ConsumerWidget {
  const ContentCollectionPage({super.key, required this.type});

  final ContentType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(publishedContentProvider(type));
    return PublicPageFrame(
      title: type.pluralLabelAr,
      child: asyncItems.when(
        loading: () => const LoadingView(),
        error: (error, stackTrace) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(publishedContentProvider(type)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyView(
              title: 'لا يوجد محتوى منشور بعد',
              message: _emptyMessage(type),
              icon: type.icon,
            );
          }
          return PageContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (type == ContentType.tasbeeh)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppPalette.spaceLg),
                    child: LocalCounterNotice(),
                  ),
                AdaptiveCardGrid(
                  children: [
                    for (final item in items)
                      ContentCard(key: ValueKey(item.cardKey), item: item),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _emptyMessage(ContentType type) {
    if (type == ContentType.quran) {
      return 'تُنشر الآيات بعد اختيارها والتحقق منها مقابل النسخة المعتمدة من المصحف.';
    }
    if (type == ContentType.hadith) {
      return 'تُنشر الأحاديث مع بيانات مصدرها، وتظهر الأحاديث غير المصنّفة بوسم المراجعة.';
    }
    return 'سيظهر المحتوى هنا بعد أن ينشره المشرف من لوحة التحكم.';
  }
}

/// Explains the visitor-local nature of Tasbeeh counters.
class LocalCounterNotice extends StatelessWidget {
  const LocalCounterNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppPalette.spaceMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppPalette.radiusSm),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'عدّاداتك محفوظة على هذا الجهاز/المتصفح فقط، ولا تُرسل إلى الخادم. '
              'قد تتأثر بالتصفح الخاص أو حذف بيانات المتصفح أو تغيير الجهاز.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared public page title wrapper (the actual scaffold is supplied by the
/// public shell so the app bar and drawer stay consistent across routes).
class PublicPageFrame extends StatelessWidget {
  const PublicPageFrame({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageContent(
            maxWidth: AppPalette.maxContentWidth,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: SectionHeader(title: title),
          ),
          child,
        ],
      ),
    );
  }
}
