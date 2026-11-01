import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/widgets/adaptive_layout.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/domain/content_type.dart';
import '../../content_management/providers/admin_providers.dart';
import 'admin_dashboard_widgets.dart';
import 'admin_shell.dart';

/// Content-only dashboard overview. No fabricated visitor analytics are shown.
class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminDashboardProvider);
    return data.when(
      loading: () => const LoadingView(),
      error: (error, stackTrace) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(adminDashboardProvider),
      ),
      data: (overview) => SingleChildScrollView(
        child: AdminPageContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'نظرة عامة',
                subtitle:
                    'إحصاءات المحتوى المنشور والمسودات فقط، بدون تتبع الزوار.',
                trailing: FilledButton.icon(
                  onPressed: () => context.go('/admin/content/azkar/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة محتوى'),
                ),
              ),
              const SizedBox(height: AppPalette.spaceLg),
              Wrap(
                spacing: AppPalette.spaceMd,
                runSpacing: AppPalette.spaceMd,
                children: [
                  SummaryCard(
                    label: 'المحتوى المنشور',
                    value: overview.published,
                    color: AppPalette.success,
                  ),
                  SummaryCard(
                    label: 'المسودات',
                    value: overview.drafts,
                    color: AppPalette.warning,
                  ),
                  SummaryCard(
                    label: 'إجمالي السجلات',
                    value: overview.published + overview.drafts,
                  ),
                ],
              ),
              const SizedBox(height: AppPalette.spaceXl),
              Text(
                'المحتوى حسب النوع',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppPalette.spaceMd),
              AdaptiveCardGrid(
                minCardWidth: 220,
                children: [
                  for (final type in ContentType.values)
                    TypeCountCard(type: type, counts: overview.counts[type]),
                ],
              ),
              const SizedBox(height: AppPalette.spaceXl),
              Text(
                'أحدث المحتوى',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppPalette.spaceMd),
              if (overview.recent.isEmpty)
                const EmptyView(title: 'لا يوجد محتوى بعد')
              else
                Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      for (final item in overview.recent)
                        RecentTile(item: item),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
