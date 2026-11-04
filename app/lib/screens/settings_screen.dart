import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'profile_form_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onProfileChanged});
  final VoidCallback onProfileChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Json? _me;
  List<String> _photoUrls = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await Api.myProfile();
      final paths = (me['photos'] as List).map((p) => (p as Map)['storage_path'] as String).toList();
      final urls = await Api.photoUrls(paths);
      if (mounted) setState(() {
        _me = me;
        _photoUrls = urls;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProfileFormScreen(initial: _me!, onboarding: false)),
    );
    if (changed == true) {
      await _load();
      if (_me?['complete'] != true) widget.onProfileChanged();
    }
  }

  Future<void> _toggleVisible(bool v) async {
    try {
      await Api.setVisible(v);
      await _load();
    } catch (e) {
      _snack(errorText(e));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer mon compte ?'),
        content: const Text('Profil, photos, conversations : tout sera effacé définitivement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SlowColors.terracotta),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteAccount();
    } catch (e) {
      _snack(errorText(e));
    }
  }

  void _snack(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final me = _me;
    final p = me?['profile'] as Map?;
    final rules = me?['rules'] as Map?;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: me == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (p != null) ...[
                    Text('${p['first_name']}, ${p['age']}', style: t.headlineMedium),
                    Text(p['commune_nom'] as String, style: t.bodySmall),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 130,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photoUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(_photoUrls[i], width: 100, height: 130, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  OutlinedButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier mon profil'),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: SwitchListTile(
                      value: p?['is_visible'] == true,
                      onChanged: _toggleVisible,
                      title: const Text('Profil visible'),
                      subtitle: const Text('En pause, personne ne vous découvre ; vos conversations continuent.'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Les règles du jeu', style: t.titleLarge),
                  const SizedBox(height: 12),
                  if (rules != null) ..._rules(rules, t),
                  const SizedBox(height: 32),
                  TextButton(onPressed: Api.signOut, child: const Text('Se déconnecter')),
                  TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(foregroundColor: SlowColors.terracotta),
                    child: const Text('Supprimer mon compte'),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _rules(Map r, TextTheme t) {
    String n(String k) => (r[k] as num).toStringAsFixed(0);
    final items = [
      (Icons.place_outlined, 'Uniquement votre commune et les communes limitrophes.'),
      (Icons.visibility_off_outlined, 'D\'abord les mots : bio et réponses, sans photo.'),
      (Icons.hourglass_top, 'Quand c\'est réciproque : ${n('first_message_hours')} h pour écrire le premier message.'),
      (Icons.photo_outlined,
          'Photos dévoilées après ${n('photo_unlock_hours')} h de discussion (${n('min_messages_each')} messages chacun au moins).'),
      (Icons.event_available_outlined,
          'Un rendez-vous accepté dans les ${n('date_deadline_hours')} h, sinon la conversation se ferme.'),
      (Icons.forum_outlined,
          '${n('max_active_matches')} conversations en cours maximum, ${n('daily_likes')} envies d\'échanger par jour.'),
    ];
    return [
      for (final (icon, text) in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: SlowColors.terracotta),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: t.bodyMedium)),
          ]),
        ),
    ];
  }
}
