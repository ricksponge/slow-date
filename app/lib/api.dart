import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get sb => Supabase.instance.client;

typedef Json = Map<String, dynamic>;

/// Message d'erreur lisible (les fonctions SQL renvoient déjà du français).
String errorText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  if (e is StorageException) return e.message;
  return 'Une erreur est survenue. Réessayez.';
}

DateTime? parseTs(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// Statuts d'un match (miroir de l'enum SQL match_status).
class MatchStatus {
  static const waiting = 'waiting';
  static const talking = 'talking';
  static const dateConfirmed = 'date_confirmed';
  static const expired = 'expired';
  static const closed = 'closed';

  static bool isOpen(String s) => s == waiting || s == talking || s == dateConfirmed;
}

class Api {
  // ---------------- Authentification (lien ou code par e-mail) ----------------
  /// Le lien du mail ramène sur l'app web (session récupérée depuis l'URL).
  /// Si le modèle d'e-mail contient {{ .Token }} (SMTP perso), le code marche aussi.
  static Future<void> sendCode(String email) => sb.auth.signInWithOtp(
        email: email.trim(),
        shouldCreateUser: true,
        emailRedirectTo: kIsWeb ? Uri.base.origin : 'fr.slowdate://login-callback',
      );

  static Future<void> verifyCode(String email, String code) =>
      sb.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email);

  static String? get myId => sb.auth.currentUser?.id;

  // ---------------- Profil ----------------
  static Future<Json> myProfile() async => Json.from(await sb.rpc('get_my_profile') as Map);

  static Future<List<Json>> questions() async {
    final rows = await sb.from('questions').select('id, text, position').order('position');
    return rows.map((r) => Json.from(r)).toList();
  }

  static Future<List<Json>> searchCommunes(String q) async {
    if (q.trim().length < 2) return [];
    final rows = await sb.rpc('search_communes', params: {'p_query': q.trim(), 'p_limit': 12}) as List;
    return rows.map((r) => Json.from(r as Map)).toList();
  }

  static Future<void> saveProfile({
    required String firstName,
    required DateTime birthdate,
    required String gender,
    required List<String> seeking,
    required int ageMin,
    required int ageMax,
    required String communeCode,
    required String bio,
  }) async {
    await sb.from('profiles').upsert({
      'id': myId,
      'first_name': firstName.trim(),
      'birthdate': birthdate.toIso8601String().substring(0, 10),
      'gender': gender,
      'seeking': seeking,
      'age_min': ageMin,
      'age_max': ageMax,
      'commune_code': communeCode,
      'bio': bio.trim(),
    });
  }

  static Future<void> setVisible(bool visible) =>
      sb.from('profiles').update({'is_visible': visible}).eq('id', myId!);

  static Future<void> saveAnswer(int questionId, String answer) async {
    final text = answer.trim();
    if (text.isEmpty) {
      await sb.from('answers').delete().eq('user_id', myId!).eq('question_id', questionId);
    } else {
      await sb.from('answers').upsert({
        'user_id': myId,
        'question_id': questionId,
        'answer': text,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  static Future<void> uploadPhoto(Uint8List bytes, String mimeType, int position) async {
    final ext = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = '$myId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await sb.storage.from('photos').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: ext == 'jpg' ? 'image/jpeg' : mimeType),
        );
    await sb.from('profile_photos').insert({'user_id': myId, 'storage_path': path, 'position': position});
  }

  static Future<void> deletePhoto(String id, String path) async {
    await sb.from('profile_photos').delete().eq('id', id);
    await sb.storage.from('photos').remove([path]);
  }

  /// URLs signées (1 h). Le Storage refuse si les photos ne sont pas encore dévoilées.
  static Future<List<String>> photoUrls(List<String> paths) async {
    if (paths.isEmpty) return [];
    final signed = await sb.storage.from('photos').createSignedUrls(paths, 3600);
    return signed.map((s) => s.signedUrl).toList();
  }

  // ---------------- Découvrir ----------------
  static Future<Json> discovery() async =>
      Json.from(await sb.rpc('get_discovery', params: {'p_limit': 10}) as Map);

  static Future<Json> decide(String targetId, bool like) async =>
      Json.from(await sb.rpc('decide', params: {'p_target': targetId, 'p_like': like}) as Map);

  // ---------------- Rencontres ----------------
  static Future<List<Json>> myMatches() async {
    final rows = await sb.rpc('get_my_matches') as List;
    return rows.map((r) => Json.from(r as Map)).toList();
  }

  static Future<Json> match(String id) async =>
      Json.from(await sb.rpc('get_match', params: {'p_match_id': id}) as Map);

  static Stream<List<Json>> messages(String matchId) => sb
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('match_id', matchId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map((r) => Json.from(r)).toList());

  /// Émet à chaque changement du match (statut, photos…) pour recharger l'écran.
  static Stream<void> matchChanges(String matchId) =>
      sb.from('matches').stream(primaryKey: ['id']).eq('id', matchId).map((_) {});

  static Stream<void> proposalChanges(String matchId) =>
      sb.from('date_proposals').stream(primaryKey: ['id']).eq('match_id', matchId).map((_) {});

  static Future<void> sendMessage(String matchId, String body) =>
      sb.rpc('send_message', params: {'p_match_id': matchId, 'p_body': body});

  static Future<Json> meetingPoint(String matchId) async =>
      Json.from(await sb.rpc('suggest_meeting_point', params: {'p_match_id': matchId}) as Map);

  static Future<void> proposeDate(String matchId, String place, String? address, DateTime at) =>
      sb.rpc('propose_date', params: {
        'p_match_id': matchId,
        'p_place_name': place,
        'p_place_address': address,
        'p_meeting_at': at.toUtc().toIso8601String(),
      });

  static Future<void> respondDate(String proposalId, bool accept) =>
      sb.rpc('respond_date', params: {'p_proposal_id': proposalId, 'p_accept': accept});

  static Future<void> unmatch(String matchId) => sb.rpc('unmatch', params: {'p_match_id': matchId});

  static Future<void> report(String userId, String? matchId, String reason, String details) =>
      sb.rpc('report_user', params: {
        'p_user': userId,
        'p_match_id': matchId,
        'p_reason': reason,
        'p_details': details,
      });

  // ---------------- Compte ----------------
  static Future<void> signOut() => sb.auth.signOut();

  static Future<void> deleteAccount() async {
    final me = await myProfile();
    final paths = (me['photos'] as List).map((p) => (p as Map)['storage_path'] as String).toList();
    if (paths.isNotEmpty) await sb.storage.from('photos').remove(paths);
    await sb.rpc('delete_my_account');
    await sb.auth.signOut();
  }
}
