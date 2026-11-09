import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/azkar_brand.dart';
import '../../../core/widgets/adaptive_layout.dart';
import '../data/bismillah_loader.dart';
import '../domain/memorial_link_parser.dart';

/// The general homepage keeps the AZKAR identity without memorial content.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    child: PageContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHero(),
          SizedBox(height: AppPalette.spaceLg),
          OpenMemorialPageCard(),
          SizedBox(height: AppPalette.spaceXl),
        ],
      ),
    ),
  );
}

/// Lets app users open a published memorial page by pasting its link or slug.
class OpenMemorialPageCard extends StatefulWidget {
  const OpenMemorialPageCard({super.key});

  @override
  State<OpenMemorialPageCard> createState() => _OpenMemorialPageCardState();
}

class _OpenMemorialPageCardState extends State<OpenMemorialPageCard> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final slug = parseMemorialSlug(_controller.text);
    if (slug == null) {
      setState(() => _error = 'أدخل رابط الصفحة أو اسمها المختصر بشكل صحيح.');
      return;
    }
    setState(() => _error = null);
    context.push('/m/$slug');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppPalette.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'فتح صفحة صدقة جارية',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppPalette.spaceSm),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              textDirection: TextDirection.ltr,
              onSubmitted: (_) => _open(),
              decoration: InputDecoration(
                labelText: 'رابط الصفحة أو اسمها المختصر',
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppPalette.spaceSm),
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.open_in_new),
              label: const Text('فتح الصفحة'),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeHero extends StatelessWidget {
  const HomeHero({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: AppPalette.spaceLg),
        const AzkarBrandLockup(markSize: 88),
        const SizedBox(height: AppPalette.spaceSm),
        Text(
          'أذكار • أدعية • قرآن • أحاديث',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppPalette.spaceXl),
        FutureBuilder<String>(
          future: BismillahLoader.load(),
          builder: (context, snapshot) {
            final bismillah = snapshot.data ?? '';
            return Column(
              children: [
                if (bismillah.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppPalette.spaceMd),
                    child: Text(
                      bismillah,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        height: 2,
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                Text(
                  'صدقة جارية نسأل الله قبولها',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
