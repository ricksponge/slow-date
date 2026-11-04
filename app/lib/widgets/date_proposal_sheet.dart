import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../theme.dart';
import '../util/format.dart';

/// Feuille « Proposer un rendez-vous ». Renvoie true si la proposition est partie.
Future<bool?> showDateProposalSheet(BuildContext context, {required String matchId, required int maxDays}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SlowColors.paper,
    builder: (_) => _DateProposalSheet(matchId: matchId, maxDays: maxDays),
  );
}

class _DateProposalSheet extends StatefulWidget {
  const _DateProposalSheet({required this.matchId, required this.maxDays});
  final String matchId;
  final int maxDays;

  @override
  State<_DateProposalSheet> createState() => _DateProposalSheetState();
}

class _DateProposalSheetState extends State<_DateProposalSheet> {
  final _place = TextEditingController();
  final _address = TextEditingController();
  Json? _midpoint;
  DateTime? _day;
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.meetingPoint(widget.matchId).then((m) {
      if (mounted) setState(() => _midpoint = m);
    }).catchError((_) {});
  }

  DateTime? get _when =>
      _day == null ? null : DateTime(_day!.year, _day!.month, _day!.day, _time.hour, _time.minute);

  Future<void> _searchNearby() async {
    final m = _midpoint;
    if (m == null) return;
    final query = Uri.encodeComponent('café ${m['commune']}');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(Duration(days: widget.maxDays)),
      helpText: 'Jour du rendez-vous',
    );
    if (d != null) setState(() => _day = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time, helpText: 'Heure du rendez-vous');
    if (t != null) setState(() => _time = t);
  }

  Future<void> _send() async {
    final when = _when;
    if (_place.text.trim().length < 2) {
      setState(() => _error = 'Indiquez le lieu.');
      return;
    }
    if (when == null) {
      setState(() => _error = 'Choisissez le jour.');
      return;
    }
    if (when.isBefore(DateTime.now().add(const Duration(hours: 1)))) {
      setState(() => _error = 'Le rendez-vous doit être dans au moins une heure.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Api.proposeDate(widget.matchId, _place.text, _address.text, when);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = _midpoint;
    final when = _when;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Proposer un rendez-vous', style: t.headlineSmall),
          const SizedBox(height: 16),
          if (m != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.near_me_outlined, size: 18, color: SlowColors.sage),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m['same_commune'] == true
                            ? 'Vous habitez la même commune : ${m['commune']}'
                            : 'À mi-chemin entre ${m['from']} et ${m['to']} : ${m['commune']}',
                        style: t.titleMedium,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _searchNearby,
                    icon: const Icon(Icons.local_cafe_outlined),
                    label: Text('Chercher un café à ${m['commune']}'),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _place,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Lieu (café, parc, expo…)', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Adresse (facultatif)', counterText: ''),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.event_outlined),
                label: Text(_day == null ? 'Jour' : '${_day!.day}/${_day!.month}'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(_time.format(context)),
              ),
            ),
          ]),
          if (when != null) ...[
            const SizedBox(height: 8),
            Text('Le ${formatMeeting(when)}', style: t.bodySmall, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 12),
          Text(
            'Pour un premier rendez-vous, choisissez un lieu public et prévenez un·e proche.',
            style: t.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: SlowColors.terracotta)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Envoyer la proposition'),
          ),
        ]),
      ),
    );
  }
}
