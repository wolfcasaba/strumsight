import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../data/auth_repository.dart';
import '../providers/auth_providers.dart';

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

  String _errorText(AppLocalizations l10n, Object error) {
    final kind = error is AuthException ? error.kind : AuthErrorKind.unknown;
    switch (kind) {
      case AuthErrorKind.invalidCredentials:
        return l10n.authErrorInvalidCredentials;
      case AuthErrorKind.emailTaken:
        return l10n.authErrorEmailTaken;
      case AuthErrorKind.network:
        return l10n.authErrorNetwork;
      case AuthErrorKind.unknown:
        return l10n.authErrorUnknown;
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccount)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
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
                  const SizedBox(height: 28),
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
                      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(value);
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
                    onFieldSubmitted: (_) => loading ? null : _submit(),
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
                    Text(
                      _errorText(l10n, auth.error!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(_isSignUp
                            ? l10n.authSignUpAction
                            : l10n.authSignInAction),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(_isSignUp
                        ? l10n.authToggleToSignIn
                        : l10n.authToggleToSignUp),
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
