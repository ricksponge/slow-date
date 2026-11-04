import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// Ouvre une feuille de recherche et renvoie {code, nom} ou null.
Future<Json?> pickCommune(BuildContext context) {
  return showModalBottomSheet<Json>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SlowColors.paper,
    builder: (_) => const _CommuneSearch(),
  );
}

class _CommuneSearch extends StatefulWidget {
  const _CommuneSearch();

  @override
  State<_CommuneSearch> createState() => _CommuneSearchState();
}

class _CommuneSearchState extends State<_CommuneSearch> {
  Timer? _debounce;
  List<Json> _results = [];
  bool _loading = false;
  String _q = '';

  void _onChanged(String q) {
    _q = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _loading = true);
      try {
        final r = await Api.searchCommunes(q);
        if (mounted && q == _q) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = []);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nom de commune ou code postal',
                ),
                onChanged: _onChanged,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Vous ne verrez que les personnes de votre commune et des communes limitrophes.',
                style: TextStyle(color: SlowColors.muted, fontSize: 13),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final c = _results[i];
                  final cps = (c['codes_postaux'] as List?)?.join(', ') ?? '';
                  return ListTile(
                    title: Text(c['nom'] as String),
                    subtitle: Text(cps.isEmpty ? 'Dép. ${c['departement']}' : cps),
                    onTap: () => Navigator.pop(context, {'code': c['code'], 'nom': c['nom']}),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
