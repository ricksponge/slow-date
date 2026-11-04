import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'config.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_form_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  runApp(const SlowDateApp());
}

class SlowDateApp extends StatelessWidget {
  const SlowDateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slow Date',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/// Aiguillage : connexion → profil à compléter → application.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _sub;
  Future<Json>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn || s.event == AuthChangeEvent.signedOut) {
        setState(_load);
      }
    });
  }

  void _load() {
    _profile = sb.auth.currentSession == null ? null : Api.myProfile();
  }

  void _refresh() => setState(_load);

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (sb.auth.currentSession == null || _profile == null) return const AuthScreen();

    return FutureBuilder<Json>(
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(errorText(snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _refresh, child: const Text('Réessayer')),
                  TextButton(onPressed: Api.signOut, child: const Text('Se déconnecter')),
                ]),
              ),
            ),
          );
        }
        final data = snap.data!;
        if (data['complete'] != true) {
          return ProfileFormScreen(initial: data, onboarding: true, onSaved: _refresh);
        }
        return HomeScreen(onProfileChanged: _refresh);
      },
    );
  }
}
