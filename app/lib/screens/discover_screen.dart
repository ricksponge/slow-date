import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'chat_screen.dart';

/// Un profil à la fois, uniquement du texte.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, required this.onOpenMatches});
  final VoidCallback onOpenMatches;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  Json? _data;
  List<Json> _profiles = [];
  bool _loading = true;
  bool _deciding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await Api.discovery();
      setState(() {
        _data = d;
        _profiles = (d['profiles'] as List).map((p) => Json.from(p as Map)).toList();
      });
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(bool like) async {
    final p = _profiles.first;
    setState(() => _deciding = true);
    try {
      final res = await Api.decide(p['id'] as String, like);
      if (!mounted) return;
      setState(() => _profiles.removeAt(0));
      if (res['matched'] == true) {
        await _showMatch(p, res['match_id'] as String);
        await _load();
      } else if (like) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Si ${p['first_name']} a aussi envie d\'échanger, vous serez prévenu·e.'),
        ));
        if (_profiles.isEmpty) await _load();
      } else if (_profiles.isEmpty) {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
      await _load();
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  Future<void> _showMatch(Json p, String matchId) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('C\'est réciproque'),
        content: Text(
          'Vous et ${p['first_name']} avez envie d\'échanger.\n\n'
          'Vous avez 48 heures pour écrire le premier message. Sans message, la rencontre s\'efface.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Plus tard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Écrire maintenant')),
        ],
      ),
    );
    if (open == true && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(matchId: matchId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final likes = (_data?['likes_left'] as num?)?.toInt();
    final slots = (_data?['slots_left'] as num?)?.toInt();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Découvrir'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Empty(title: 'Oups', text: _error!, action: ('Réessayer', _load))
              : _buildBody(t, likes, slots),
    );
  }

  Widget _buildBody(TextTheme t, int? likes, int? slots) {
    switch (_data?['status']) {
      case 'paused':
        return const _Empty(
          title: 'Profil en pause',
          text: 'Réactivez votre profil dans l\'onglet Profil pour découvrir d\'autres personnes.',
        );
      case 'no_slot':
        return _Empty(
          title: 'Vos conversations d\'abord',
          text: 'Vous avez déjà le maximum de conversations en cours. Allez au bout — '
              'un rendez-vous ou un au revoir — avant d\'en ouvrir de nouvelles.',
          action: ('Voir mes rencontres', widget.onOpenMatches),
        );
      case 'no_likes_left':
        return const _Empty(
          title: 'À demain',
          text: 'Vous avez utilisé toutes vos envies d\'échanger aujourd\'hui. Prenez le temps.',
        );
      case 'incomplete':
        return const _Empty(title: 'Profil incomplet', text: 'Complétez votre profil dans l\'onglet Profil.');
    }

    if (_profiles.isEmpty) {
      return _Empty(
        title: 'Personne de nouveau pour l\'instant',
        text: 'Vous avez vu tout le monde près de chez vous. De nouvelles personnes arrivent chaque jour.',
        action: ('Actualiser', _load),
      );
    }

    final p = _profiles.first;
    final answers = (p['answers'] as List).cast<Map>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            _Pill(icon: Icons.favorite_border, text: '$likes aujourd\'hui'),
            const SizedBox(width: 8),
            _Pill(icon: Icons.forum_outlined, text: '$slots place${(slots ?? 0) > 1 ? 's' : ''} de conversation'),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Text('${p['first_name']}, ${p['age']}', style: t.headlineMedium),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.place_outlined, size: 16, color: SlowColors.muted),
                const SizedBox(width: 4),
                Text(p['commune'] as String, style: t.bodySmall),
              ]),
              if ((p['bio'] as String).trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(p['bio'] as String, style: t.bodyLarge),
              ],
              const SizedBox(height: 20),
              for (final a in answers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a['question'] as String,
                            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(a['answer'] as String, style: t.bodyLarge),
                      ]),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.visibility_off_outlined, size: 16, color: SlowColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Les photos se dévoilent après 24 h de discussion.', style: t.bodySmall),
                ),
              ]),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _deciding ? null : () => _decide(false),
                  child: const Text('Passer'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _deciding || (likes ?? 0) == 0 ? null : () => _decide(true),
                  child: const Text('J\'aimerais échanger'),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: SlowColors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: SlowColors.muted),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12, color: SlowColors.muted)),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.text, this.action});
  final String title;
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(text, style: t.bodyLarge?.copyWith(color: SlowColors.muted), textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 24),
            FilledButton(onPressed: action!.$2, child: Text(action!.$1)),
          ],
        ]),
      ),
    );
  }
}
