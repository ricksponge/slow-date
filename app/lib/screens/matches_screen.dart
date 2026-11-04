import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/countdown.dart';
import 'chat_screen.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> with WidgetsBindingObserver {
  List<Json>? _matches;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await Api.myMatches();
      if (mounted) setState(() {
        _matches = m;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _open(Json m) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(matchId: m['id'] as String)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = _matches;
    final open = list?.where((m) => MatchStatus.isOpen(m['status'] as String)).toList() ?? [];
    final ended = list?.where((m) => !MatchStatus.isOpen(m['status'] as String)).toList() ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Rencontres')),
      body: list == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (open.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                      child: Text(
                        'Aucune conversation en cours.\nQuand l\'envie d\'échanger est réciproque, elle apparaît ici.',
                        textAlign: TextAlign.center,
                        style: t.bodyLarge?.copyWith(color: SlowColors.muted),
                      ),
                    ),
                  for (final m in open) _MatchTile(m: m, onTap: () => _open(m), onDeadline: _load),
                  if (ended.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
                      child: Text('Terminées', style: t.titleMedium?.copyWith(color: SlowColors.muted)),
                    ),
                    for (final m in ended) _MatchTile(m: m, onTap: () => _open(m)),
                  ],
                ],
              ),
            ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.m, required this.onTap, this.onDeadline});
  final Json m;
  final VoidCallback onTap;
  final VoidCallback? onDeadline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final other = m['other'] as Map;
    final status = m['status'] as String;
    final last = m['last_message'] as Map?;
    final ended = !MatchStatus.isOpen(status);

    Widget statusLine;
    Color accent;
    switch (status) {
      case MatchStatus.waiting:
        accent = SlowColors.amber;
        statusLine = Countdown(
          target: parseTs(m['first_message_deadline'])!,
          prefix: 'Premier message à écrire · ',
          style: t.bodySmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
          onDone: onDeadline,
        );
      case MatchStatus.talking:
        accent = SlowColors.terracotta;
        statusLine = Countdown(
          target: parseTs(m['date_deadline'])!,
          prefix: 'Rendez-vous à fixer · ',
          style: t.bodySmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
          onDone: onDeadline,
        );
      case MatchStatus.dateConfirmed:
        accent = SlowColors.sage;
        final d = m['confirmed_date'] as Map?;
        statusLine = Text(
          d == null ? 'Rendez-vous confirmé' : 'RDV ${formatMeeting(parseTs(d['meeting_at'])!)} · ${d['place_name']}',
          style: t.bodySmall?.copyWith(color: accent, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      default:
        accent = SlowColors.muted;
        statusLine = Text(
          m['ended_reason'] == 'no_first_message' ? 'Effacée : personne n\'a écrit' : 'Close : pas de rendez-vous fixé',
          style: t.bodySmall,
        );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: ended ? SlowColors.line : accent.withValues(alpha: 0.15),
                child: Text(
                  (other['first_name'] as String).characters.first.toUpperCase(),
                  style: TextStyle(fontSize: 20, color: ended ? SlowColors.muted : accent, fontFamily: 'serif'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${other['first_name']}, ${other['age']} · ${other['commune']}',
                      style: t.titleMedium?.copyWith(color: ended ? SlowColors.muted : null)),
                  const SizedBox(height: 2),
                  if (last != null)
                    Text(
                      '${last['from_me'] == true ? 'Vous : ' : ''}${last['body']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(color: SlowColors.muted),
                    ),
                  const SizedBox(height: 4),
                  statusLine,
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
