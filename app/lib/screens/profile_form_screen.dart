import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../theme.dart';
import '../util/format.dart';
import '../widgets/commune_picker.dart';

/// Création (onboarding) et modification du profil.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, required this.initial, required this.onboarding, this.onSaved});

  /// Résultat de get_my_profile.
  final Json initial;
  final bool onboarding;
  final VoidCallback? onSaved;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _PendingPhoto {
  _PendingPhoto(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _firstName = TextEditingController();
  final _bio = TextEditingController();
  DateTime? _birthdate;
  bool _birthdateLocked = false;
  String? _gender;
  final Set<String> _seeking = {};
  RangeValues _ages = const RangeValues(25, 45);
  Json? _commune;

  List<Json> _questions = [];
  final Map<int, TextEditingController> _answers = {};
  final Map<int, String> _initialAnswers = {};

  List<Json> _photos = []; // {id, storage_path, url}
  final List<_PendingPhoto> _pending = [];
  final Set<String> _removed = {};

  late final Json _rules;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  int get _minAnswers => (_rules['min_answers'] as num?)?.toInt() ?? 3;
  int get _minPhotos => (_rules['min_photos'] as num?)?.toInt() ?? 1;
  int get _minAge => (_rules['min_age'] as num?)?.toInt() ?? 18;

  int get _answerCount => _answers.values.where((c) => c.text.trim().length >= 2).length;
  int get _photoCount => _photos.where((p) => !_removed.contains(p['id'])).length + _pending.length;

  @override
  void initState() {
    super.initState();
    _rules = Json.from((widget.initial['rules'] as Map?) ?? {});
    final p = widget.initial['profile'] as Map?;
    if (p != null) {
      _firstName.text = p['first_name'] as String;
      _bio.text = (p['bio'] as String?) ?? '';
      _birthdate = DateTime.parse(p['birthdate'] as String);
      _birthdateLocked = true;
      _gender = p['gender'] as String;
      _seeking.addAll((p['seeking'] as List).cast<String>());
      _ages = RangeValues(
        (p['age_min'] as num).clamp(18, 99).toDouble(),
        (p['age_max'] as num).clamp(18, 99).toDouble(),
      );
      _commune = {'code': p['commune_code'], 'nom': p['commune_nom']};
    }
    for (final a in (widget.initial['answers'] as List? ?? [])) {
      _initialAnswers[(a['question_id'] as num).toInt()] = a['answer'] as String;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final qs = await Api.questions();
      final photos = (widget.initial['photos'] as List? ?? []).map((e) => Json.from(e as Map)).toList();
      final urls = await Api.photoUrls(photos.map((p) => p['storage_path'] as String).toList());
      for (var i = 0; i < photos.length && i < urls.length; i++) {
        photos[i]['url'] = urls[i];
      }
      setState(() {
        _questions = qs;
        for (final q in qs) {
          final id = (q['id'] as num).toInt();
          _answers[id] = TextEditingController(text: _initialAnswers[id] ?? '')..addListener(() => setState(() {}));
        }
        _photos = photos;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final latest = DateTime(now.year - _minAge, now.month, now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 100),
      lastDate: latest,
      initialEntryMode: DatePickerEntryMode.input,
      helpText: 'Date de naissance',
    );
    if (d != null) setState(() => _birthdate = d);
  }

  Future<void> _addPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _pending.add(_PendingPhoto(bytes, file.mimeType ?? 'image/jpeg')));
  }

  String? _validate() {
    if (_firstName.text.trim().isEmpty) return 'Indiquez votre prénom.';
    if (_birthdate == null) return 'Indiquez votre date de naissance.';
    if (_gender == null) return 'Indiquez votre genre.';
    if (_seeking.isEmpty) return 'Indiquez qui vous souhaitez rencontrer.';
    if (_commune == null) return 'Choisissez votre commune.';
    if (_answerCount < _minAnswers) return 'Répondez à au moins $_minAnswers questions.';
    if (_photoCount < _minPhotos) return 'Ajoutez au moins $_minPhotos photo(s). Elles restent cachées au début.';
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.saveProfile(
        firstName: _firstName.text,
        birthdate: _birthdate!,
        gender: _gender!,
        seeking: _seeking.toList(),
        ageMin: _ages.start.round(),
        ageMax: _ages.end.round(),
        communeCode: _commune!['code'] as String,
        bio: _bio.text,
      );
      for (final entry in _answers.entries) {
        final now = entry.value.text.trim();
        if (now != (_initialAnswers[entry.key] ?? '')) {
          await Api.saveAnswer(entry.key, now.length >= 2 ? now : '');
          _initialAnswers[entry.key] = now;
        }
      }
      for (final p in _photos.where((p) => _removed.contains(p['id']))) {
        await Api.deletePhoto(p['id'] as String, p['storage_path'] as String);
      }
      var position = _photos.length;
      for (final p in List.of(_pending)) {
        await Api.uploadPhoto(p.bytes, p.mime, position++);
        _pending.remove(p);
      }
      if (!mounted) return;
      if (widget.onboarding) {
        widget.onSaved?.call();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _bio.dispose();
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Votre profil' : 'Modifier mon profil'),
        actions: [
          if (widget.onboarding)
            TextButton(onPressed: Api.signOut, child: const Text('Déconnexion')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                if (widget.onboarding)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      'Ici, on se découvre d\'abord par les mots. Vos photos ne seront visibles '
                      'qu\'après 24 heures de discussion avec quelqu\'un.',
                      style: t.bodyLarge?.copyWith(color: SlowColors.muted),
                    ),
                  ),
                _Section('L\'essentiel'),
                TextField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: 'Prénom', counterText: ''),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _birthdateLocked ? null : _pickBirthdate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Date de naissance',
                      helperText: _birthdateLocked ? 'Non modifiable' : null,
                    ),
                    child: Text(_birthdate == null
                        ? 'Choisir'
                        : DateFormat('d MMMM y', 'fr_FR').format(_birthdate!)),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final c = await pickCommune(context);
                    if (c != null) setState(() => _commune = c);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Ma commune', suffixIcon: Icon(Icons.place_outlined)),
                    child: Text(_commune?['nom'] as String? ?? 'Choisir'),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Je suis', style: t.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: genderLabels.entries
                      .map((e) => ChoiceChip(
                            label: Text(e.value),
                            selected: _gender == e.key,
                            onSelected: (_) => setState(() => _gender = e.key),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                Text('Je souhaite rencontrer', style: t.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: seekingLabels.entries
                      .map((e) => FilterChip(
                            label: Text(e.value),
                            selected: _seeking.contains(e.key),
                            onSelected: (v) => setState(() => v ? _seeking.add(e.key) : _seeking.remove(e.key)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                Text('Âge : ${_ages.start.round()} – ${_ages.end.round()} ans', style: t.titleMedium),
                RangeSlider(
                  values: _ages,
                  min: _minAge.toDouble(),
                  max: 99,
                  divisions: 99 - _minAge,
                  onChanged: (v) => setState(() => _ages = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bio,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Quelques mots sur vous',
                    alignLabelWithHint: true,
                  ),
                ),
                _Section('Questions de fond',
                    subtitle: 'Répondez à au moins $_minAnswers. C\'est ce que les autres liront en premier '
                        '($_answerCount/$_minAnswers).'),
                for (final q in _questions) ...[
                  Text(q['text'] as String, style: t.titleMedium),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _answers[(q['id'] as num).toInt()],
                    maxLines: null,
                    minLines: 2,
                    maxLength: 1000,
                    decoration: const InputDecoration(hintText: 'Votre réponse (facultatif)', counterText: ''),
                  ),
                  const SizedBox(height: 16),
                ],
                _Section('Photos',
                    subtitle: 'Cachées au début : elles se dévoilent après 24 h de vraie discussion. '
                        'Au moins $_minPhotos.'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final p in _photos.where((p) => !_removed.contains(p['id'])))
                      _PhotoTile(
                        image: p['url'] != null ? NetworkImage(p['url'] as String) : null,
                        onRemove: () => setState(() => _removed.add(p['id'] as String)),
                      ),
                    for (final p in _pending)
                      _PhotoTile(image: MemoryImage(p.bytes), onRemove: () => setState(() => _pending.remove(p))),
                    if (_photoCount < 6)
                      InkWell(
                        onTap: _addPhoto,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 96,
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(color: SlowColors.line, width: 1.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.add_a_photo_outlined, color: SlowColors.muted),
                        ),
                      ),
                  ],
                ),
              ],
            ),
      bottomSheet: _loading
          ? null
          : Container(
              color: SlowColors.paper,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: const TextStyle(color: SlowColors.terracotta)),
                      ),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(widget.onboarding ? 'C\'est parti' : 'Enregistrer'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: t.bodySmall),
        ],
      ]),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.image, required this.onRemove});
  final ImageProvider? image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 96,
          height: 120,
          color: SlowColors.line,
          child: image == null ? null : Image(image: image!, fit: BoxFit.cover),
        ),
      ),
      Positioned(
        top: 4,
        right: 4,
        child: InkWell(
          onTap: onRemove,
          child: const CircleAvatar(
            radius: 13,
            backgroundColor: Colors.black54,
            child: Icon(Icons.close, size: 16, color: Colors.white),
          ),
        ),
      ),
    ]);
  }
}
