import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/app_palette.dart';
import '../../../core/widgets/adaptive_layout.dart';
import '../../../core/widgets/asymmetric_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../home/domain/homepage_entry.dart';
import '../../sharing/share_widgets.dart';
import '../../tasbeeh/widgets/tasbeeh_card.dart';
import '../../youtube/widgets/youtube_card.dart';
import '../domain/content_item.dart';
import '../domain/content_type.dart';
import 'content_style.dart';

/// Dispatches a content record to the same renderer used by the public site and
/// by the admin live preview. There is deliberately no second preview design.
class ContentCard extends StatelessWidget {
  const ContentCard({
    super.key,
    required this.item,
    this.showActions = true,
    this.preview = false,
    this.onOpen,
    this.pageId,
    this.pageSlug,
  });

  final ContentItem item;
  final bool showActions;
  final bool preview;
  final VoidCallback? onOpen;
  final String? pageId;
  final String? pageSlug;

  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      ContentType.tasbeeh => TasbeehCard(
        item: item,
        pageId: pageId,
        preview: preview,
      ),
      ContentType.youtube => YoutubeCard(item: item, preview: preview),
      ContentType.dedication => DedicationCard(item: item, preview: preview),
      _ => TextContentCard(
        item: item,
        showActions: showActions,
        preview: preview,
        onOpen: onOpen,
        pageSlug: pageSlug,
      ),
    };
  }
}

/// Textual Azkar / Quran / Hadith / Dua card.
class TextContentCard extends StatelessWidget {
  const TextContentCard({
    super.key,
    required this.item,
    this.showActions = true,
    this.preview = false,
    this.onOpen,
    this.pageSlug,
  });

  final ContentItem item;
  final bool showActions;
  final bool preview;
  final VoidCallback? onOpen;
  final String? pageSlug;

  @override
  Widget build(BuildContext context) {
    final style = item.style;
    final background = style.backgroundColorValue;
    final gradient = style.gradientEnabled
        ? LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              background,
              Color.lerp(background, style.textColorValue, 0.06) ?? background,
            ],
          )
        : null;
    final title = item.displayTitle;
    final reference = item.referenceLine;

    return AsymmetricCard(
      shape: style.shape,
      backgroundColor: background,
      gradient: gradient,
      decorationColor: style.textColorValue,
      showDecoration: style.decorationEnabled,
      borderColor: style.textColorValue.withValues(alpha: 0.35),
      showBorder: style.borderEnabled,
      semanticLabel: title.isEmpty ? item.type.labelAr : title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            ArabicText(
              title,
              style: ContentStyleResolver.titleStyle(style),
              textAlign: style.textAlignment,
            ),
            const SizedBox(height: AppPalette.spaceMd),
          ],
          if (item.reviewBadge != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusBadge(
                label: item.reviewBadge!,
                color: AppPalette.warning,
                icon: Icons.fact_check_outlined,
              ),
            ),
            const SizedBox(height: AppPalette.spaceSm),
          ],
          ArabicText(
            item.arabicText,
            style: ContentStyleResolver.textStyle(style),
            textAlign: style.textAlignment,
          ),
          if (item.description != null &&
              item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: AppPalette.spaceMd),
            ArabicText(
              item.description!,
              style: ContentStyleResolver.metaStyle(style),
              textAlign: style.textAlignment,
            ),
          ],
          if (item.translation != null &&
              item.translation!.trim().isNotEmpty) ...[
            const SizedBox(height: AppPalette.spaceMd),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                item.translation!,
                style: ContentStyleResolver.metaStyle(style),
                textAlign: TextAlign.start,
              ),
            ),
          ],
          if (item.explanation != null &&
              item.explanation!.trim().isNotEmpty) ...[
            const SizedBox(height: AppPalette.spaceMd),
            ArabicText(
              item.explanation!,
              style: ContentStyleResolver.metaStyle(style),
              textAlign: TextAlign.start,
            ),
          ],
          if (reference.isNotEmpty) ...[
            const SizedBox(height: AppPalette.spaceLg),
            ArabicText(
              reference,
              style: ContentStyleResolver.metaStyle(style),
              textAlign: TextAlign.center,
            ),
          ],
          if (showActions && item.type.isTextual && !preview) ...[
            const SizedBox(height: AppPalette.spaceLg),
            ContentShareActions(
              text: item.shareText,
              link: pageSlug == null
                  ? AppConfig.contentLink(type: item.type.id, id: item.id)
                  : AppConfig.memorialPageLink(pageSlug!),
              onOpen: onOpen,
            ),
          ],
        ],
      ),
    );
  }
}

/// Dedication cards use the reversed asymmetric shape by default.
class DedicationCard extends StatelessWidget {
  const DedicationCard({super.key, required this.item, this.preview = false});

  final ContentItem item;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final style = item.style;
    final person = item.personName?.trim() ?? '';
    final message = item.dedicationMessage?.trim() ?? '';
    return AsymmetricCard(
      shape: style.shape,
      backgroundColor: style.backgroundColorValue,
      decorationColor: style.textColorValue,
      showDecoration: style.decorationEnabled,
      borderColor: style.textColorValue.withValues(alpha: 0.35),
      showBorder: style.borderEnabled,
      semanticLabel: 'صدقة جارية $person',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.isNotEmpty) ...[
            ArabicText(
              message,
              style: ContentStyleResolver.titleStyle(style),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppPalette.spaceMd),
          ],
          if (person.isNotEmpty) ...[
            ArabicText(
              '${item.recipient.defaultHonorific} / $person',
              style: ContentStyleResolver.textStyle(style),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppPalette.spaceMd),
          ],
          if (item.arabicText.trim().isNotEmpty)
            ArabicText(
              item.arabicText,
              style: ContentStyleResolver.textStyle(style),
              textAlign: style.textAlignment,
            ),
        ],
      ),
    );
  }
}

/// Convenience for a homepage card with an optional wide span.
Widget homeCardWidget(
  HomeCard card, {
  Key? key,
  String? pageId,
  String? pageSlug,
}) {
  final child = ContentCard(
    item: card.item,
    pageId: pageId,
    pageSlug: pageSlug,
  );
  if (card.span <= 1) {
    return KeyedSubtree(key: key, child: child);
  }
  return GridSpan(key: key, span: card.span, child: child);
}
