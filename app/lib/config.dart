/// Configuration Supabase.
///
/// La clé « publishable » est faite pour être embarquée dans l'app : la
/// sécurité repose sur la RLS et les fonctions SQL. Ne mettez JAMAIS la clé
/// secrète (sb_secret_…) ici.
///
/// On peut surcharger au build :
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pshxbltlhwsjfjbnoyzj.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_hOSsCDCYTN3_gBchqNBYrg_VLre6msB',
  );
}
