import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/azkar_brand.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      title: 'مرحبًا بك في أذكار',
      description:
          'مساحة للذكر والعبادة والصدقة الجارية؛ تجمع ما يعينك على الخير '
          'ويقرّبك ممن تحب.',
      icon: Icons.auto_awesome_outlined,
    ),
    _OnboardingSlide(
      title: 'صدقة جارية لمن نحب',
      description:
          'أنشئ صفحات تذكارية لمن تحب، واجمع فيها ما ينفعهم من خير، '
          'ثم شاركها مع العائلة والأصدقاء.',
      icon: Icons.volunteer_activism_outlined,
    ),
    _OnboardingSlide(
      title: 'القرآن والأذكار',
      description:
          'تصفّح آيات قرآنية وأحاديث وأدعية وأذكاراً منشورة، '
          'واستعن بها على دوام الصلة بالله.',
      icon: Icons.menu_book_outlined,
    ),
    _OnboardingSlide(
      title: 'سبّح واذكر الله',
      description:
          'استخدم عدّادات تسبيح مستقلة ومحفوظة على جهازك، '
          'من دون خلطها بعدّادات صفحات التذكار.',
      icon: Icons.fingerprint,
    ),
    _OnboardingSlide(
      title: 'صلاتك في وقتها',
      description:
          'تابع مواقيت الصلاة حسب موقعك الحالي وتوقيته، وسجّل ما أتممت من الصلوات '
          'على هذا الجهاز.',
      icon: Icons.mosque_outlined,
    ),
    _OnboardingSlide(
      title: 'ذكّر نفسك بالخير',
      description:
          'اختر أذكار الصباح والمساء، والتذكيرات المخصصة، وتسبيح ما بعد '
          'الصلاة، وتذكير سورة الكهف يوم الجمعة.',
      icon: Icons.notifications_active_outlined,
    ),
    _OnboardingSlide(
      title: 'ابدأ رحلتك مع أذكار',
      description:
          'أنشئ حساباً لإدارة صفحاتك وإعداداتك، أو سجّل الدخول، '
          'أو تابع استكشاف المحتوى العام.',
      icon: Icons.celebration_outlined,
      isFinal: true,
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({String destination = '/'}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(onboardingCompletionStoreProvider).markCompleted();
      if (mounted) context.go(destination);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Saving onboarding completion failed',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
  }

  Future<void> _next() async {
    if (_index == _slides.length - 1) {
      await _finish();
      return;
    }
    final nextIndex = _index + 1;
    setState(() => _index = nextIndex);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(nextIndex);
    } else {
      await _controller.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _previous() async {
    if (_index == 0) return;
    final previousIndex = _index - 1;
    setState(() => _index = previousIndex);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(previousIndex);
    } else {
      await _controller.animateToPage(
        previousIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slide = _slides[_index];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.all(AppPalette.spaceMd),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        IconButton(
                          tooltip: 'رجوع',
                          onPressed: _busy
                              ? null
                              : () => _index == 0 ? _finish() : _previous(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        if (constraints.maxWidth < 400)
                          const AzkarBrandMark(size: 38)
                        else
                          const AzkarBrandLockup(markSize: 38),
                        const Spacer(),
                        if (!slide.isFinal)
                          TextButton(
                            onPressed: _busy ? null : () => _finish(),
                            child: const Text('تخطي'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  Semantics(
                    label: 'الخطوة ${_index + 1} من ${_slides.length}',
                    child: LinearProgressIndicator(
                      value: (_index + 1) / _slides.length,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _slides.length,
                      onPageChanged: (index) => setState(() => _index = index),
                      itemBuilder: (context, index) {
                        final item = _slides[index];
                        return _SlideContent(slide: item);
                      },
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  if (slide.isFinal)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final actions = <Widget>[
                          if (_index > 0)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _previous,
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('السابق'),
                            ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _finish(destination: '/login'),
                            child: const Text('تسجيل الدخول'),
                          ),
                          FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _finish(destination: '/register'),
                            child: const Text('إنشاء حساب'),
                          ),
                          TextButton(
                            onPressed: _busy ? null : () => _finish(),
                            child: const Text('استكشاف المحتوى'),
                          ),
                        ];
                        if (constraints.maxWidth < 600) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final action in actions)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppPalette.spaceXs,
                                  ),
                                  child: action,
                                ),
                            ],
                          );
                        }
                        return Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppPalette.spaceSm,
                          runSpacing: AppPalette.spaceSm,
                          children: actions,
                        );
                      },
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final actions = <Widget>[
                          if (_index > 0)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _previous,
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('السابق'),
                            ),
                          FilledButton.icon(
                            onPressed: _busy ? null : _next,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('التالي'),
                          ),
                        ];
                        if (constraints.maxWidth < 400) {
                          return Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: AppPalette.spaceSm,
                            runSpacing: AppPalette.spaceSm,
                            children: actions,
                          );
                        }
                        return Row(
                          children: [
                            if (_index > 0) actions.first,
                            const Spacer(),
                            actions.last,
                          ],
                        );
                      },
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: AppPalette.spaceSm),
                  Text(
                    'يمكنك إعادة فتح التعريف من إعدادات العبادة.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.title,
    required this.description,
    required this.icon,
    this.isFinal = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool isFinal;
}

class _SlideContent extends StatelessWidget {
  const _SlideContent({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppPalette.spaceLg,
        vertical: AppPalette.spaceMd,
      ),
      child: Center(
        child: Card(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Padding(
              padding: const EdgeInsets.all(AppPalette.spaceXl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.7,
                        ),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      slide.icon,
                      size: 52,
                      color: theme.colorScheme.primary,
                      semanticLabel: slide.title,
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceXl),
                  Text(
                    slide.title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  Text(
                    slide.description,
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.8),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
