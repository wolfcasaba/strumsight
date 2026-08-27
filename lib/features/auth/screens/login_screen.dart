import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../presentation/auth_failure_message.dart';
import '../providers/auth_providers.dart';
import '../theme/auth_theme_scope.dart';

/// Sign-in / create-account screen. Pushed from Settings; pops on success.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// "Continue without an account" (A1, ADR 0292 norm) always has to leave
  /// this screen — but it is reached two ways: PUSHED (from Settings, a real
  /// route to pop back to) and via a `go()` that REPLACED the stack (from the
  /// profile hub), which leaves nothing to pop (javító kör 1, F4). `maybePop`
  /// alone silently no-ops on the second path, stranding the user here; a
  /// `go()` fallback only fires when there genuinely was nothing to pop.
  Future<void> _continueWithoutAccount() async {
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      context.go(AppRoutes.profileHome);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final controller = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim();
    final password = _password.text;
    if (_isSignUp) {
      await controller.register(email, password);
    } else {
      await controller.login(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;

    // Pop back to Settings the moment a session exists.
    ref.listen(authControllerProvider, (_, next) {
      if (next.value != null && context.mounted) context.pop();
    });

    return AuthThemeScope(
      // A fresh `context` (a descendant of the scope above) is required for
      // `Theme.of(context).extension<SsColorScheme>()` to resolve — the
      // enclosing `context` is the WIDGET's OWN incoming context, an
      // ancestor of the scope, not a descendant of it.
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).extension<SsColorScheme>()!;
          return Scaffold(
            appBar: AppBar(title: Text(l10n.settingsAccount)),
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isSignUp ? l10n.authSignUpTitle : l10n.authSignInTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Montserrat',
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SsCard(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _email,
                                enabled: !loading,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: l10n.authEmail,
                                  prefixIcon: const Icon(Icons.mail_outline),
                                ),
                                validator: (v) {
                                  final value = (v ?? '').trim();
                                  final ok = RegExp(
                                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                  ).hasMatch(value);
                                  return ok ? null : l10n.authEmailInvalid;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _password,
                                enabled: !loading,
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) =>
                                    loading ? null : _submit(),
                                decoration: InputDecoration(
                                  labelText: l10n.authPassword,
                                  prefixIcon: const Icon(Icons.lock_outline),
                                ),
                                validator: (v) => (v ?? '').length >= 8
                                    ? null
                                    : l10n.authPasswordTooShort,
                              ),
                              if (auth.hasError) ...[
                                const SizedBox(height: 16),
                                // Only the stable, localised failure code ever
                                // reaches the UI (authFailureMessage) — no raw
                                // exception/transport text (A2).
                                Text(
                                  authFailureMessage(l10n, auth.error),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: colors.danger,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              SsButton(
                                label: _isSignUp
                                    ? l10n.authSignUpAction
                                    : l10n.authSignInAction,
                                loading: loading,
                                onPressed: loading ? null : _submit,
                              ),
                              const SizedBox(height: 8),
                              SsButton(
                                variant: SsButtonVariant.tertiary,
                                label: _isSignUp
                                    ? l10n.authToggleToSignIn
                                    : l10n.authToggleToSignUp,
                                onPressed: loading
                                    ? null
                                    : () => setState(
                                        () => _isSignUp = !_isSignUp,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Fiók opcionális (CLAUDE.md) — a bejelentkezésből MINDIG van
                      // explicit út "fiók nélkül tovább" (A1, ADR 0292 norma).
                      SsButton(
                        key: const Key('authContinueWithoutAccount'),
                        variant: SsButtonVariant.tertiary,
                        label: l10n.authContinueWithoutAccount,
                        onPressed: loading ? null : _continueWithoutAccount,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
