import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        if (!_email.text.contains('@')) throw const FormatException();
        await Api.sendCode(_email.text);
        setState(() => _codeSent = true);
      });

  Future<void> _verify() => _run(() => Api.verifyCode(_email.text, _code.text));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Slow Date', style: t.headlineMedium?.copyWith(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(
                    'Moins de profils, plus de rencontres.\nPrès de chez vous, en vrai, en 48 heures.',
                    style: t.bodyLarge?.copyWith(color: SlowColors.muted),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _email,
                    enabled: !_codeSent,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Adresse e-mail'),
                    onSubmitted: (_) => _send(),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: SlowColors.sage.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'E-mail envoyé. Ouvrez-le sur cet appareil et touchez le lien : '
                        'vous serez connecté·e automatiquement.\n\n'
                        'Si l\'e-mail contient un code à la place, saisissez-le ci-dessous.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 8,
                      decoration: const InputDecoration(
                        labelText: 'Code (facultatif)',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _verify(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error == 'Une erreur est survenue. Réessayez.' && !_codeSent
                          ? 'Adresse e-mail invalide.'
                          : _error!,
                      style: const TextStyle(color: SlowColors.terracotta),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : (_codeSent ? _verify : _send),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_codeSent ? 'Valider le code' : 'Recevoir le lien de connexion'),
                  ),
                  if (_codeSent)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _code.clear();
                              }),
                      child: const Text('Changer d\'adresse'),
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
