import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Handles a direct/deep-link route with no earlier page, while leaving normal
/// navigator pops and Android/iOS back gestures to Flutter.
class AppBackNavigation extends StatelessWidget {
  const AppBackNavigation({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => BackButtonListener(
    onBackButtonPressed: () async {
      final router = GoRouter.of(context);
      if (router.canPop()) return false;
      final location = router.routeInformationProvider.value.uri.path;
      if (location == '/' || location == '/onboarding') return false;
      // A shared memorial is a public entry point. Let the platform leave the
      // app/browser page rather than redirecting its visitor to an account home.
      if (RegExp(r'^/m/[^/]+/?$').hasMatch(location)) return false;
      if (!await confirmUnsavedChanges(context)) return true;
      router.go(routeBackFallback(location));
      return true;
    },
    child: child,
  );
}

class RouteBackButton extends StatelessWidget {
  const RouteBackButton({super.key, this.fallbackLocation, this.iconSize});

  final String? fallbackLocation;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final location =
        GoRouter.maybeOf(context)?.routeInformationProvider.value.uri.path ??
        '/';
    return IconButton(
      key: const ValueKey('route-back-button'),
      tooltip: 'رجوع',
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: () => navigateBack(
        context,
        fallbackLocation: fallbackLocation ?? routeBackFallback(location),
      ),
      icon: Icon(
        Icons.arrow_back,
        size: iconSize,
        textDirection: TextDirection.ltr,
      ),
    );
  }
}

Future<void> navigateBack(
  BuildContext context, {
  required String fallbackLocation,
}) async {
  final didHandle = await Navigator.of(context).maybePop();
  if (!didHandle && context.mounted) {
    GoRouter.maybeOf(context)?.go(fallbackLocation);
  }
}

String routeBackFallback(String location) {
  if (location.startsWith('/m/')) {
    final segments = location.split('/');
    return segments.length > 3 ? '/${segments.take(3).skip(1).join('/')}' : '/';
  }
  if (location.startsWith('/c/')) {
    final segments = location.split('/');
    final type = segments.length > 2 ? segments[2] : null;
    const routes = <String, String>{
      'azkar': '/azkar',
      'quran': '/quran',
      'hadith': '/hadith',
      'dua': '/dua',
      'tasbeeh': '/tasbeeh',
      'youtube': '/videos',
      'dedication': '/dedications',
    };
    return routes[type] ?? '/';
  }
  if (location.startsWith('/dashboard/pages/')) {
    final segments = location.split('/');
    if (segments.length >= 4) {
      final pagePath = '/dashboard/pages/${segments[3]}';
      if (segments.length == 4) return '/dashboard';
      if (segments.length > 6 && segments[4] == 'content') {
        return '$pagePath/content/${segments[5]}';
      }
      return pagePath;
    }
  }
  if (location == '/register' || location == '/reset-password') return '/login';
  if (location.startsWith('/admin/content/')) {
    final segments = location.split('/');
    return segments.length > 3
        ? '/admin/content/${segments[3]}'
        : '/admin/dashboard';
  }
  if (location.startsWith('/admin/')) return '/admin/dashboard';
  if (location.startsWith('/dashboard/')) return '/dashboard';
  if (location.startsWith('/worship/')) return '/worship';
  if (location == '/login') return '/';
  return '/';
}

class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.isDirty,
    required this.fallbackLocation,
    required this.child,
  });

  final bool isDirty;
  final String fallbackLocation;
  final Widget child;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _allowPop = false;
  bool _confirming = false;

  Future<bool> confirmNavigation() async {
    if (!mounted || !widget.isDirty) return true;
    if (_confirming) return false;
    _confirming = true;
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مغادرة الصفحة؟'),
        content: const Text('لديك تغييرات غير محفوظة. هل تريد تجاهلها؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('متابعة التعديل'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تجاهل التغييرات'),
          ),
        ],
      ),
    );
    _confirming = false;
    return shouldDiscard == true && mounted;
  }

  Future<void> _confirmPop() async {
    if (!await confirmNavigation() || !mounted) return;
    if (GoRouter.of(context).canPop()) {
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      context.go(widget.fallbackLocation);
    }
  }

  @override
  void initState() {
    super.initState();
    _activeUnsavedGuards.add(this);
  }

  @override
  void dispose() {
    _activeUnsavedGuards.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !widget.isDirty || _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && widget.isDirty && !_allowPop) {
        _confirmPop();
      }
    },
    child: widget.child,
  );
}

final List<_UnsavedChangesGuardState> _activeUnsavedGuards = [];

Future<bool> confirmUnsavedChanges(BuildContext context) async {
  for (final guard in _activeUnsavedGuards.reversed) {
    if (!guard.mounted) continue;
    return guard.confirmNavigation();
  }
  return true;
}

Future<void> navigateToLocation(
  BuildContext context,
  String location, {
  bool closeDrawer = false,
}) async {
  if (!await confirmUnsavedChanges(context) || !context.mounted) return;
  if (closeDrawer) Scaffold.maybeOf(context)?.closeDrawer();
  if (context.mounted) {
    if (location == '/') {
      context.go(location);
    } else if (GoRouterState.of(context).uri.toString() != location) {
      context.push(location);
    }
  }
}
