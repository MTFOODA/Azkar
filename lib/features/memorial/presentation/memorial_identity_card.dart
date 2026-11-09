import 'package:flutter/material.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/widgets/asymmetric_card.dart';
import '../../content/widgets/content_style.dart';
import '../domain/memorial_page.dart';

/// The same dedication presentation on the homepage and the memorial itself.
class MemorialIdentityCard extends StatelessWidget {
  const MemorialIdentityCard({super.key, required this.page});

  final MemorialPage page;

  String get _name => page.displayDeceasedName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = page.dedicationMessage?.trim() ?? '';
    return AsymmetricCard(
      backgroundColor: theme.colorScheme.surface,
      decorationColor: theme.colorScheme.primary,
      showDecoration: true,
      borderColor: theme.colorScheme.outlineVariant,
      showBorder: true,
      semanticLabel: 'إهداء $_name',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArabicText(
            _name,
            style: theme.textTheme.headlineMedium!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppPalette.spaceMd),
          ArabicText(
            message.isEmpty ? 'رسالة الإهداء لم تُضف بعد.' : message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge!,
          ),
        ],
      ),
    );
  }
}
