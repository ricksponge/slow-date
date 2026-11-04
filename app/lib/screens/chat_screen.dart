import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/countdown.dart';
import '../widgets/date_proposal_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Json? _m;
  String? _error;
  List<String> _photoUrls = [];
  String _photoKey = '';
  late final Stream<List<Json>> _messages;
  final List<StreamSubscription<void>> _subs = [];
  Timer? _debounce;
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages = Api.messages(widget.matchId);
    _subs.add(Api.matchChanges(widget.matchId).listen((_) => _scheduleReload(), onError: (_) {}));
    _subs.add(Api.proposalChanges(widget.matchId).listen((_) => _scheduleReload(), onError: (_) {}));
    _reload();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _reload() async {
    try {
      final m = await Api.match(widget.matchId);
      final paths = (m['photos'] as List).cast<String>();
      final key = paths.join('|');
      if (key != _photoKey) {
        _photoKey = key;
        _photoUrls = await Api.photoUrls(paths);
      }
      if (mounted) setState(() {
        _m = m;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  String get _status => _m?['status'] as String? ?? '';
  String get _otherName => (_m?['other'] as Map?)?['first_name'] as String? ?? '';

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await Api.sendMessage(widget.matchId, text);
      _input.clear();
      if (_status == MatchStatus.waiting) _reload();
    } catch (e) {
      _snack(errorText(e));
      _reload();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _proposeDate() async {
    final days = (_m?['date_max_ahead_days'] as num?)?.toInt() ?? 7;
    final sent = await showDateProposalSheet(context, matchId: widget.matchId, maxDays: days);
    if (sent == true) {
      _snack('Proposition envoyée à $_otherName.');
      _reload();
    }
  }

  Future<void> _respond(String proposalId, bool accept) async {
    try {
      await Api.respondDate(proposalId, accept);
      _snack(accept ? 'Rendez-vous confirmé !' : 'Proposition déclinée. Proposez un autre moment ?');
    } catch (e) {
      _snack(errorText(e));
    }
    _reload();
  }

  Future<void> _unmatch() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mettre fin à l\'échange ?'),
        content: Text('La conversation avec $_otherName sera fermée définitivement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mettre fin')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.unmatch(widget.matchId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack(errorText(e));
    }
  }

  Future<void> _report() async {
    const reasons = ['Comportement inapproprié', 'Harcèlement', 'Faux profil', 'Arnaque', 'Autre'];
    String reason = reasons.first;
    final details = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Signaler $_otherName'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(labelText: 'Motif'),
                items: [for (final r in reasons) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setLocal(() => reason = v ?? reason),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: details,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Détails (facultatif)'),
              ),
              const SizedBox(height: 8),
              const Text('La personne sera bloquée et ne pourra plus vous voir.',
                  style: TextStyle(fontSize: 12, color: SlowColors.muted)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Signaler et bloquer')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.report((_m!['other'] as Map)['id'] as String, widget.matchId, reason, details.text);
      if (mounted) {
        Navigator.pop(context);
        _snack('Merci. $_otherName est bloqué·e.');
      }
    } catch (e) {
      _snack(errorText(e));
    }
  }

  void _showProfile() {
    final p = _m?['other_profile'] as Map?;
    if (p == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: SlowColors.paper,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(24),
            children: [
              Text('${p['first_name']}, ${p['age']}', style: t.headlineMedium),
              Text(p['commune'] as String, style: t.bodySmall),
              if (_photoUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final u in _photoUrls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(u)),
                  ),
              ],
              if ((p['bio'] as String).isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(p['bio'] as String, style: t.bodyLarge),
              ],
              for (final a in (p['answers'] as List).cast<Map>()) ...[
                const SizedBox(height: 18),
                Text(a['question'] as String, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(a['answer'] as String, style: t.bodyLarge),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final other = m?['other'] as Map?;
    final open = MatchStatus.isOpen(_status);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: other == null
            ? const Text('')
            : InkWell(
                onTap: _showProfile,
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: SlowColors.line,
                    backgroundImage: _photoUrls.isNotEmpty ? NetworkImage(_photoUrls.first) : null,
                    child: _photoUrls.isEmpty
                        ? const Icon(Icons.visibility_off_outlined, size: 16, color: SlowColors.muted)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${other['first_name']}, ${other['age']}', overflow: TextOverflow.ellipsis),
                      Text(other['commune'] as String,
                          style: const TextStyle(fontSize: 12, color: SlowColors.muted, fontFamily: null)),
                    ]),
                  ),
                ]),
              ),
        actions: [
          if (m != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'profile') {
                  _showProfile();
                } else if (v == 'unmatch') {
                  _unmatch();
                } else {
                  _report();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'profile', child: Text('Voir le profil')),
                if (open) const PopupMenuItem(value: 'unmatch', child: Text('Mettre fin à l\'échange')),
                const PopupMenuItem(value: 'report', child: Text('Signaler et bloquer')),
              ],
            ),
        ],
      ),
      body: m == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : Column(children: [
              _PhaseBanner(m: m, onDeadline: _reload),
              if (m['pending_proposal'] != null)
                _ProposalCard(
                  p: Json.from(m['pending_proposal'] as Map),
                  otherName: _otherName,
                  onAccept: (id) => _respond(id, true),
                  onDecline: (id) => _respond(id, false),
                  onCounter: _proposeDate,
                ),
              Expanded(child: _MessageList(stream: _messages, me: m['me'] as String)),
              if (open) _composer() else _closedFooter(),
            ]),
    );
  }

  Widget _composer() {
    final waiting = _status == MatchStatus.waiting;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: SlowColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (_status == MatchStatus.talking)
            IconButton(
              tooltip: 'Proposer un rendez-vous',
              onPressed: _proposeDate,
              icon: const Icon(Icons.event_available_outlined, color: SlowColors.terracotta),
            ),
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: waiting ? 'Écrivez le premier message…' : 'Votre message…',
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: SlowColors.line),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.arrow_upward),
          ),
        ]),
      ),
    );
  }

  Widget _closedFooter() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Cette conversation est terminée.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// Bandeau qui dit où on en est et combien de temps il reste.
class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.m, required this.onDeadline});
  final Json m;
  final VoidCallback onDeadline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final strong = t.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    final name = (m['other'] as Map)['first_name'];
    final status = m['status'] as String;

    late final Color color;
    late final IconData icon;
    final lines = <Widget>[];

    switch (status) {
      case MatchStatus.waiting:
        color = SlowColors.amber;
        icon = Icons.hourglass_top;
        lines.add(Text('C\'est réciproque ! L\'un de vous doit écrire en premier.', style: t.bodyMedium));
        lines.add(Countdown(
          target: parseTs(m['first_message_deadline'])!,
          prefix: 'Sans message, la rencontre s\'efface dans ',
          style: strong,
          onDone: onDeadline,
        ));
      case MatchStatus.talking:
        color = SlowColors.terracotta;
        icon = Icons.timer_outlined;
        final unlocked = m['photos_unlocked'] == true;
        final mine = (m['my_message_count'] as num).toInt();
        final theirs = (m['their_message_count'] as num).toInt();
        final need = (m['min_messages_each'] as num).toInt();
        final unlockAt = parseTs(m['photos_unlock_at'])!;
        if (unlocked) {
          lines.add(Text('Photos dévoilées — touchez le prénom en haut.', style: t.bodyMedium));
        } else if (unlockAt.isAfter(DateTime.now())) {
          lines.add(Countdown(target: unlockAt, prefix: 'Photos dans ', style: t.bodyMedium, onDone: onDeadline));
        }
        if (!unlocked && (mine < need || theirs < need)) {
          final parts = <String>[
            if (mine < need) 'vous : encore ${need - mine}',
            if (theirs < need) '$name : encore ${need - theirs}',
          ];
          lines.add(Text('Messages requis pour les photos (${parts.join(', ')})', style: t.bodySmall));
        }
        lines.add(Countdown(
          target: parseTs(m['date_deadline'])!,
          prefix: 'Rendez-vous à fixer dans ',
          suffix: ', sinon la conversation se ferme',
          style: strong,
          onDone: onDeadline,
        ));
      case MatchStatus.dateConfirmed:
        color = SlowColors.sage;
        icon = Icons.event_available;
        final d = m['confirmed_date'] as Map?;
        lines.add(Text('Rendez-vous confirmé', style: strong));
        if (d != null) {
          lines.add(Text(
            '${formatMeeting(parseTs(d['meeting_at'])!)} — ${d['place_name']}'
            '${d['place_address'] != null ? ', ${d['place_address']}' : ''}',
            style: t.bodyMedium,
          ));
        }
      default:
        color = SlowColors.muted;
        icon = Icons.lock_outline;
        lines.add(Text(
          m['ended_reason'] == 'no_first_message'
              ? 'Personne n\'a écrit dans les 48 heures : la rencontre s\'est effacée.'
              : m['ended_reason'] == 'no_date'
                  ? 'Aucun rendez-vous n\'a été fixé à temps : la conversation est close.'
                  : 'Cette conversation est terminée.',
          style: t.bodyMedium,
        ));
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 2), child: l)],
          ),
        ),
      ]),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.p,
    required this.otherName,
    required this.onAccept,
    required this.onDecline,
    required this.onCounter,
  });
  final Json p;
  final String otherName;
  final void Function(String id) onAccept;
  final void Function(String id) onDecline;
  final VoidCallback onCounter;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fromMe = p['from_me'] == true;
    final when = formatMeeting(parseTs(p['meeting_at'])!);
    final where = '${p['place_name']}${p['place_address'] != null ? ' — ${p['place_address']}' : ''}';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SlowColors.card,
        border: Border.all(color: SlowColors.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fromMe ? 'Votre proposition' : '$otherName propose un rendez-vous',
            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(when[0].toUpperCase() + when.substring(1), style: t.titleMedium),
        Text(where, style: t.bodyMedium),
        const SizedBox(height: 10),
        if (fromMe)
          Text('En attente de la réponse de $otherName.', style: t.bodySmall)
        else
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => onAccept(p['id'] as String),
              child: const Text('Accepter'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: onCounter,
              child: const Text('Autre proposition'),
            ),
            TextButton(onPressed: () => onDecline(p['id'] as String), child: const Text('Décliner')),
          ]),
      ]),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.stream, required this.me});
  final Stream<List<Json>> stream;
  final String me;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Json>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final msgs = snap.data!;
        if (msgs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Lisez son profil, rebondissez sur une réponse qui vous a parlé.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SlowColors.muted),
              ),
            ),
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final msg = msgs[msgs.length - 1 - i];
            final mine = msg['sender_id'] == me;
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: mine ? SlowColors.terracotta : SlowColors.card,
                  border: mine ? null : Border.all(color: SlowColors.line),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Text(msg['body'] as String,
                        style: TextStyle(color: mine ? Colors.white : SlowColors.ink, height: 1.35)),
                    const SizedBox(height: 3),
                    Text(
                      formatMessageTime(parseTs(msg['created_at'])!),
                      style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : SlowColors.muted),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
