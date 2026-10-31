import 'package:flutter/material.dart';

import 'sharing_service.dart';

/// Shows a short Arabic confirmation after copy/share actions.
void showShareFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// The prominent homepage share-website action.
class ShareWebsiteButton extends StatelessWidget {
  const ShareWebsiteButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'مشاركة',
        onPressed: () => _shareWebsite(context),
        color: Theme.of(context).colorScheme.primary,
        icon: const Icon(Icons.share_outlined),
      );
    }
    return FilledButton.icon(
      onPressed: () => _shareWebsite(context),
      icon: const Icon(Icons.ios_share_outlined),
      label: const Text('شارك الموقع'),
    );
  }

  Future<void> _shareWebsite(BuildContext context) => showShareSheet(
    context,
    text: SharingService.websiteText,
    link: SharingService.websiteLink(),
  );
}

/// Copy/share controls used by textual content cards.
class ContentShareActions extends StatelessWidget {
  const ContentShareActions({
    super.key,
    required this.text,
    required this.link,
    this.onOpen,
  });

  final String text;
  final String link;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await SharingService.copyText('$text\n$link');
            if (context.mounted) {
              showShareFeedback(
                context,
                ok ? 'تم نسخ المحتوى' : 'تعذّر النسخ، حاول مرة أخرى',
              );
            }
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('نسخ'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => showShareSheet(context, text: text, link: link),
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('مشاركة'),
        ),
        if (onOpen != null)
          IconButton(
            onPressed: onOpen,
            tooltip: 'فتح الرابط',
            icon: const Icon(Icons.open_in_new_outlined),
          ),
      ],
    );
  }
}

/// A small, keyboard-accessible share sheet with deterministic destinations.
Future<void> showShareSheet(
  BuildContext context, {
  required String text,
  required String link,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'شارك الأجر مع من تحب',
                style: Theme.of(sheetContext).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              for (final target in ShareTarget.values)
                ListTile(
                  leading: Icon(_iconFor(target)),
                  title: Text(target.labelAr),
                  onTap: () async {
                    final ok = await SharingService.share(
                      target,
                      text: text,
                      link: link,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                      showShareFeedback(
                        sheetContext,
                        target == ShareTarget.copy
                            ? (ok ? 'تم نسخ الرابط' : 'تعذّر النسخ')
                            : (ok
                                  ? 'تم فتح ${target.labelAr}'
                                  : 'تعذّر فتح التطبيق'),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

IconData _iconFor(ShareTarget target) => switch (target) {
  ShareTarget.system => Icons.ios_share_outlined,
  ShareTarget.whatsapp => Icons.chat_outlined,
  ShareTarget.telegram => Icons.send_outlined,
  ShareTarget.facebook => Icons.facebook_outlined,
  ShareTarget.copy => Icons.link_outlined,
};
