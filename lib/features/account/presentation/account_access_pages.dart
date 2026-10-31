import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/azkar_brand.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/route_back_button.dart';

class AccountLoginPage extends ConsumerStatefulWidget {
  const AccountLoginPage({super.key});

  @override
  ConsumerState<AccountLoginPage> createState() => _AccountLoginPageState();
}

String? _passwordError(String? value) {
  final password = value ?? '';
  if (password.length < 8) return 'استخدم 8 أحرف على الأقل.';
  if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
      !RegExp(r'\d').hasMatch(password)) {
    return 'يجب أن تحتوي كلمة المرور على حرف واحد ورقم واحد على الأقل.';
  }
  return null;
}

class _AccountLoginPageState extends ConsumerState<AccountLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final destination = ref.read(isDemoBackendProvider)
          ? await _signInDemoAdministrator()
          : await _signInSupabaseUser();
      if (mounted) context.go(destination);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _signInDemoAdministrator() async {
    await ref
        .read(adminSessionProvider.notifier)
        .signInDemo(email: _email.text, password: _password.text);
    return '/admin/dashboard';
  }

  Future<String> _signInSupabaseUser() async {
    await ref
        .read(accountSessionProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
    final administrator = await ref
        .read(adminSessionProvider.notifier)
        .refreshCurrentUser()
        .catchError((_) => null);
    return administrator == null ? '/dashboard' : '/admin/dashboard';
  }

  @override
  Widget build(BuildContext context) => _AccountAuthFrame(
    title: 'تسجيل الدخول',
    subtitle: 'أدر صفحتك الشخصية ومحتواها.',
    children: [
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
              validator: _emailError,
            ),
            const SizedBox(height: AppPalette.spaceMd),
            TextFormField(
              controller: _password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'كلمة المرور'),
              validator: (value) =>
                  (value ?? '').isEmpty ? 'أدخل كلمة المرور.' : null,
              onFieldSubmitted: (_) => _busy ? null : _signIn(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppPalette.spaceMd),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppPalette.spaceMd),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('تسجيل الدخول'),
            ),
            TextButton(
              onPressed: () => context.go('/reset-password'),
              child: const Text('نسيت كلمة المرور؟'),
            ),
            TextButton(
              onPressed: () => context.go('/register'),
              child: const Text('ليس لديك حساب؟ إنشاء حساب جديد'),
            ),
            if (ref.watch(isDemoBackendProvider))
              const Padding(
                padding: EdgeInsets.only(top: AppPalette.spaceSm),
                child: Text(
                  'وضع العرض المحلي مخصص لحساب المشرف التجريبي فقط. '
                  'تسجيل المستخدمين يتطلب إعداد Supabase والتحقق من قاعدة البيانات.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class AccountRegistrationPage extends ConsumerStatefulWidget {
  const AccountRegistrationPage({super.key});

  @override
  ConsumerState<AccountRegistrationPage> createState() =>
      _AccountRegistrationPageState();
}

class _AccountRegistrationPageState
    extends ConsumerState<AccountRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();
  bool _busy = false;
  bool _complete = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final authenticated = await ref
          .read(accountSessionProvider.notifier)
          .register(
            displayName: _displayName.text.trim(),
            email: _email.text,
            password: _password.text,
          );
      if (!mounted) return;
      if (authenticated) {
        context.go('/dashboard');
      } else {
        setState(() {
          _complete = true;
          _message =
              'تم إنشاء الحساب. راجع بريدك لتأكيده، ثم سجّل الدخول. '
              'إذا لم تظهر صفحتك بعد الدخول، أعد المحاولة أو تواصل مع الدعم.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registrationEnabled = ref.watch(isRegistrationEnabledProvider);
    final unavailableMessage = ref.watch(
      registrationUnavailableMessageProvider,
    );
    return _AccountAuthFrame(
      title: 'إنشاء حساب جديد',
      subtitle: 'أنشئ حسابًا وصفحة شخصية قابلة للمشاركة.',
      children: [
        if (!registrationEnabled)
          _RegistrationUnavailableNotice(
            message: unavailableMessage ?? 'التسجيل غير متاح حاليًا.',
          )
        else if (_complete)
          Column(
            children: [
              const Icon(Icons.mark_email_read_outlined, size: 44),
              const SizedBox(height: AppPalette.spaceMd),
              Text(_message ?? '', textAlign: TextAlign.center),
              const SizedBox(height: AppPalette.spaceMd),
              FilledButton(
                onPressed: () => context.go('/login'),
                child: const Text('الانتقال لتسجيل الدخول'),
              ),
            ],
          )
        else
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _displayName,
                  maxLength: 160,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                  validator: (value) {
                    final name = value?.trim() ?? '';
                    if (name.isEmpty) return 'أدخل اسمك.';
                    if (name.length > 160) {
                      return 'يجب ألا يتجاوز الاسم 160 حرفًا.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppPalette.spaceMd),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.newUsername],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                  ),
                  validator: _emailError,
                ),
                const SizedBox(height: AppPalette.spaceMd),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور (8 أحرف، وحرف ورقم على الأقل)',
                  ),
                  validator: _passwordError,
                ),
                const SizedBox(height: AppPalette.spaceMd),
                TextFormField(
                  controller: _passwordConfirmation,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور',
                  ),
                  validator: (value) => value != _password.text
                      ? 'كلمتا المرور غير متطابقتين.'
                      : null,
                  onFieldSubmitted: (_) => _busy ? null : _register(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppPalette.spaceMd),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppPalette.spaceLg),
                FilledButton(
                  onPressed: _busy ? null : _register,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('إنشاء الحساب'),
                ),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('لديك حساب بالفعل؟ تسجيل الدخول'),
                ),
                const Text(
                  'سيُنشئ النظام صفحة واحدة مرتبطة بهذا الحساب. لا تصبح مشرفًا عامًا.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class PasswordResetPage extends ConsumerStatefulWidget {
  const PasswordResetPage({super.key});

  @override
  ConsumerState<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends ConsumerState<PasswordResetPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final error = _emailError(_email.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(accountSessionProvider.notifier)
          .sendPasswordReset(_email.text);
      if (mounted) {
        setState(() {
          _message = 'إذا كان البريد مسجلًا، ستصلك رسالة لاستعادة كلمة المرور.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updatePassword() async {
    final passwordError = _passwordError(_password.text);
    if (passwordError != null) {
      setState(() => _error = passwordError);
      return;
    }
    if (_password.text != _confirmation.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(accountSessionProvider.notifier)
          .updatePassword(_password.text);
      if (mounted) {
        final administrator = await ref
            .read(adminSessionProvider.notifier)
            .refreshCurrentUser();
        if (mounted) {
          context.go(administrator == null ? '/dashboard' : '/admin/dashboard');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(accountSessionProvider);
    final demo = ref.watch(isDemoBackendProvider);
    return _AccountAuthFrame(
      title: user == null ? 'استعادة كلمة المرور' : 'تعيين كلمة مرور جديدة',
      subtitle: user == null
          ? 'أرسل رابط الاستعادة إلى بريدك الإلكتروني.'
          : 'اختر كلمة مرور جديدة لحسابك.',
      children: [
        if (demo)
          const _SupabaseRequiredNotice()
        else if (user == null) ...[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
          ),
          if (_message != null) ...[
            const SizedBox(height: AppPalette.spaceMd),
            Text(_message!, textAlign: TextAlign.center),
          ],
        ] else ...[
          TextField(
            controller: _password,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'كلمة المرور الجديدة (8 أحرف، وحرف ورقم على الأقل)',
            ),
          ),
          const SizedBox(height: AppPalette.spaceMd),
          TextField(
            controller: _confirmation,
            obscureText: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppPalette.spaceMd),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (!demo) ...[
          const SizedBox(height: AppPalette.spaceLg),
          FilledButton(
            onPressed: _busy
                ? null
                : (user == null ? _sendReset : _updatePassword),
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    user == null ? 'إرسال رابط الاستعادة' : 'حفظ كلمة المرور',
                  ),
          ),
        ],
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('العودة لتسجيل الدخول'),
        ),
      ],
    );
  }
}

class _AccountAuthFrame extends StatelessWidget {
  const _AccountAuthFrame({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 0,
      titleSpacing: 0,
      title: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  const AzkarBrandLockup(),
                  const Spacer(),
                  const RouteBackButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppPalette.spaceLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppPalette.spaceXl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: AppPalette.spaceSm),
                  Text(subtitle),
                  const SizedBox(height: AppPalette.spaceLg),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SupabaseRequiredNotice extends StatelessWidget {
  const _SupabaseRequiredNotice();

  @override
  Widget build(BuildContext context) => const Text(
    'إنشاء الحسابات الشخصية غير متاح في وضع العرض المحلي. '
    'اربط التطبيق بمشروع Supabase لتفعيله.',
    textAlign: TextAlign.center,
  );
}

class _RegistrationUnavailableNotice extends StatelessWidget {
  const _RegistrationUnavailableNotice({required this.message});

  final String message;
  @override
  Widget build(BuildContext context) =>
      Text(message, textAlign: TextAlign.center);
}

String? _emailError(String? value) {
  final email = value?.trim() ?? '';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'أدخل بريدًا إلكترونيًا صحيحًا.';
  }
  return null;
}
