import 'dart:async';

import 'package:flutter/foundation.dart'; // compute
import 'package:flutter/material.dart';
import 'package:kontaktbericht_swift_flutter/services/permissions_service.dart';
import 'package:native_audio/native_audio.dart';

import '../models/gespraechstyp_item.dart';
import '../services/audio_channel.dart';
import '../services/kontaktbericht_ffi.dart';
import '../widgets/section_header.dart';

class KontaktberichtFormPage extends StatefulWidget {
  const KontaktberichtFormPage({super.key});

  @override
  State<KontaktberichtFormPage> createState() => _KontaktberichtFormPageState();
}

class _KontaktberichtFormPageState extends State<KontaktberichtFormPage> {
  // Freitext (KI Input)
  final freeTextCtrl = TextEditingController(
    text: 'Gestern um 10 Uhr Telefonat mit Müller: möchte Angebot für 50 Lizenzen.',
  );

  // Rückfrage
  final followupCtrl = TextEditingController();

  // Manuell editierbarer Bericht (Form)
  final ansprechpartnerCtrl = TextEditingController();
  final inhaltCtrl = TextEditingController();

  DateTime dateTime = DateTime.now();

  // Gesprächstypen
  final List<GespraechstypItem> types = const [
    GespraechstypItem('messegespraech', 'Messegespräch'),
    GespraechstypItem('kundenbesuch', 'Kundenbesuch'),
    GespraechstypItem('email', 'E-Mail'),
    GespraechstypItem('chance', 'Chance'),
    GespraechstypItem('telefon', 'Telefon'),
  ];
  String selectedType = 'telefon';

  // State aus KI
  Map<String, dynamic>? lastResult;
  String? originalFreeText;
  bool isLoading = false;
  String? errorText;

  final audio = AudioChannel();
  StreamSubscription<Map<String, dynamic>>? audioSub;

  String activeMic = 'none';
  bool isSpeaking = false;
  bool isAuthorized = false;

  String? lastSpokenQuestion;

  void _onAudioEvent(Map<String, dynamic> e) {
    if (e['type'] != 'state') return;

    final mic = (e['target'] ?? 'none').toString();
    final text = (e['text'] ?? '').toString();
    final err = e['error'];

    if (!mounted) return;

    setState(() {
      isAuthorized = e['isAuthorized'] == true;
      activeMic = mic;
      isSpeaking = e['isSpeaking'] == true;

      if (err is String && err.trim().isNotEmpty) {
        errorText = err;
      }
    });

    // Textfelder erst NACH setState aktualisieren
    if (mic == 'freeText') {
      freeTextCtrl.text = text;
      freeTextCtrl.selection = TextSelection.collapsed(offset: text.length);
    } else if (mic == 'followup') {
      followupCtrl.text = text;
      followupCtrl.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  @override
  void initState() {
    super.initState();

    audioSub = audio.events().listen(_onAudioEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      //final ok = await ensureAudioPermissions();
      final ok = await NativeAudio.requestPermissions();
      if (!mounted) return;
      setState(() => isAuthorized = ok);

      if (ok) {
        NativeAudio.start();
      }
    });
  }


  String? get pendingQuestion {
    final q = lastResult?['pendingQuestion'];
    return (q is String && q.trim().isNotEmpty) ? q : null;
  }

  Map<String, dynamic>? get berichtMap {
    final b = lastResult?['bericht'];
    return (b is Map) ? b.cast<String, dynamic>() : null;
  }

  bool get canSave => berichtMap != null;

  @override
  void dispose() {
    audioSub?.cancel();
    freeTextCtrl.dispose();
    followupCtrl.dispose();
    ansprechpartnerCtrl.dispose();
    inhaltCtrl.dispose();
    NativeAudio.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  DateTime _parseDateTimeLoose(dynamic v) {
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d != null) return d;
    }
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    return DateTime.now();
  }

  void _applyBerichtToForm(Map<String, dynamic> bericht) {
    ansprechpartnerCtrl.text = (bericht['ansprechpartner'] ?? '').toString();
    inhaltCtrl.text = (bericht['inhalt'] ?? '').toString();

    final typ = (bericht['typ'] ?? '').toString();
    if (types.any((t) => t.value == typ)) {
      selectedType = typ;
    }

    // Swift DTO nutzt dateISO
    final dt = bericht['dateISO'] ?? bericht['date'] ?? bericht['datum'];
    dateTime = _parseDateTimeLoose(dt);
  }

  Map<String, dynamic> _formToBerichtDto() {
    final dto = <String, dynamic>{
      'ansprechpartner': ansprechpartnerCtrl.text.trim(),
      'typ': selectedType,
      'inhalt': inhaltCtrl.text.trim(),
      'dateISO': dateTime.toIso8601String(),
    };

    final existingId = berichtMap?['id'];
    if (existingId != null && existingId.toString().isNotEmpty) {
      dto['id'] = existingId.toString();
    }

    return dto;
  }

  void _setLoading(bool v) {
    if (!mounted) return;
    setState(() {
      isLoading = v;
      if (v) errorText = null;
    });
  }

  Future<void> _autoSpeakPendingQuestionIfNeeded() async {
    final q = pendingQuestion;
    if (q == null) return;

    if (lastSpokenQuestion == q) return;
    lastSpokenQuestion = q;

    try {
      await audio.speakPendingQuestionAuto(q, auto: true);
    } catch (_) {
      // optional: ignore
    }
  }

  // Actions
  Future<void> _extract() async {
    final txt = freeTextCtrl.text.trim();
    if (txt.isEmpty) return;

    _setLoading(true);
    try {
      final res = await compute(ffiExtract, txt);

      if (!mounted) return;
      setState(() {
        originalFreeText = txt;
        lastResult = res;

        final bericht = berichtMap;
        if (bericht != null) _applyBerichtToForm(bericht);
      });
      await _autoSpeakPendingQuestionIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() => errorText = e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _answerFollowup() async {
    final curBericht = berichtMap;
    if (curBericht == null || originalFreeText == null) return;

    final ans = followupCtrl.text.trim();
    if (ans.isEmpty) return;

    _setLoading(true);
    try {
      final payload = <String, dynamic>{
        'originalFreeText': originalFreeText!,
        'followupAnswer': ans,
        'currentBerichtDto': curBericht,
      };

      final res = await compute(ffiAnswer, payload);

      if (!mounted) return;
      setState(() {
        final newOrig = res['newOriginalFreeText'] as String?;
        originalFreeText = newOrig ?? originalFreeText;

        lastResult = (res['result'] as Map).cast<String, dynamic>();
        followupCtrl.clear();

        final bericht = berichtMap;
        if (bericht != null) _applyBerichtToForm(bericht);
      });
      await _autoSpeakPendingQuestionIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() => errorText = e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _save() async {
    final b = berichtMap;
    if (b == null) return;

    final dto = _formToBerichtDto();

    try {
      final ok = await compute(ffiSave, dto);
      if (!mounted) return;

      if (ok) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler beim Speichern')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Speichernnn\n$e')),
      );
    }
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: dateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;

    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(dateTime),
    );
    if (t == null) return;

    setState(() {
      dateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  void _resetAll() {
    setState(() {
      lastResult = null;
      originalFreeText = null;
      errorText = null;
      isLoading = false;

      lastSpokenQuestion = null;

      followupCtrl.clear();
      ansprechpartnerCtrl.clear();
      inhaltCtrl.clear();
      selectedType = 'telefon';
      dateTime = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontaktbericht'),
        actions: [
          IconButton(
            tooltip: 'Zurücksetzen',
            onPressed: isLoading ? null : _resetAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader(
            title: 'Freitext eingeben',
            subtitle: 'Optional – die KI kann dir beim Ausfüllen helfen.',
            icon: Icons.notes,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: freeTextCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Freitext',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Diktieren',
                        onPressed: (!isAuthorized || isLoading)
                            ? null
                            : () => audio.toggleFreeTextMic(),
                        icon: Icon(
                          activeMic == 'freeText'
                              ? Icons.mic
                              : Icons.mic_none,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isLoading ? null : _extract,
                          icon: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.auto_awesome),
                          label: const Text('Extrahieren (KI)'),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: TextStyle(color: cs.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (pendingQuestion != null) ...[
            const SectionHeader(
              title: 'Rückfrage',
              subtitle: 'Bitte ergänzen, damit der Bericht vollständig ist.',
              icon: Icons.help_outline,
            ),
            Card(
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pendingQuestion!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: followupCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Antwort eingeben …',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Antwort diktieren',
                          onPressed: (!isAuthorized || isLoading)
                              ? null
                              : () => audio.toggleFollowupMic(),
                          icon: Icon(
                            activeMic == 'followup'
                                ? Icons.mic
                                : Icons.mic_none,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Frage vorlesen',
                          onPressed: () async {
                            final q = pendingQuestion;
                            if (q == null) return;

                            if (isSpeaking) {
                              await audio.stopSpeak();
                            } else {
                              await audio.speak(q);
                            }
                          },
                          icon: Icon(isSpeaking ? Icons.stop : Icons.volume_up),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isLoading ? null : _answerFollowup,
                            icon: const Icon(Icons.send),
                            label: const Text('Antwort senden'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if ((lastResult?['pendingMissing'] is List) &&
                        (lastResult!['pendingMissing'] as List).isNotEmpty)
                      Text(
                        'Betroffene Felder: ${(lastResult!['pendingMissing'] as List).join(", ")}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          const SectionHeader(
            title: 'Kontaktbericht',
            subtitle: 'Du kannst die Felder jederzeit manuell anpassen.',
            icon: Icons.assignment_outlined,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: ansprechpartnerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ansprechpartner',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: isLoading ? null : _pickDateTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Datum & Uhrzeit',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              MaterialLocalizations.of(context).formatFullDate(dateTime) +
                                  ' • ' +
                                  TimeOfDay.fromDateTime(dateTime).format(context),
                            ),
                          ),
                          const Icon(Icons.calendar_month),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    items: types
                        .map((t) => DropdownMenuItem(
                              value: t.value,
                              child: Text(t.label),
                            ))
                        .toList(),
                    onChanged: isLoading
                        ? null
                        : (v) => setState(() => selectedType = v ?? selectedType),
                    decoration: const InputDecoration(
                      labelText: 'Gesprächstyp',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: inhaltCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Inhalt',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (canSave && !isLoading) ? _save : null,
                    icon: const Icon(Icons.save),
                    label: const Text('Speichern'),
                  ),
                  if (!canSave) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Tipp: Erst „Extrahieren (KI)“ ausführen oder Felder manuell füllen.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
