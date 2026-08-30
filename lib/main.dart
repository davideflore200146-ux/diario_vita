import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// Sostituisci con l'indirizzo del tuo Worker Cloudflare
const String kAiEndpoint = 'https://diario-vita-ai.davideflore200146.workers.dev';

Future<String?> askAI(String prompt) async {
  try {
    final response = await http.post(
      Uri.parse(kAiEndpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': prompt}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['text'] as String?;
    }
    return null;
  } catch (e) {
    return null;
  }
}

void main() {
  runApp(const DiarioVitaApp());
}

class DiarioVitaApp extends StatelessWidget {
  const DiarioVitaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeReplay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF141210),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8A24D),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Georgia',
      ),
      home: const EpisodioScreen(),
    );
  }
}

// ---------- Modello dati ----------

class Entry {
  final int id;
  final String tag;
  final String text;
  final String time;

  Entry({required this.id, required this.tag, required this.text, required this.time});

  Map<String, dynamic> toJson() => {'id': id, 'tag': tag, 'text': text, 'time': time};

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
        id: json['id'],
        tag: json['tag'],
        text: json['text'],
        time: json['time'],
      );
}

class DayData {
  List<Entry> entries;
  int? mood10;
  Map<String, String> stats;
  String narrative;
  String episodeLabel;
  String momento;
  String ricordare;

  DayData({
    List<Entry>? entries,
    this.mood10,
    Map<String, String>? stats,
    this.narrative = '',
    this.episodeLabel = '',
    this.momento = '',
    this.ricordare = '',
  })  : entries = entries ?? [],
        stats = stats ?? {'luogo': '', 'musica': '', 'gaming': '', 'allenamento': ''};

  Map<String, dynamic> toJson() => {
        'entries': entries.map((e) => e.toJson()).toList(),
        'mood10': mood10,
        'stats': stats,
        'narrative': narrative,
        'episodeLabel': episodeLabel,
        'momento': momento,
        'ricordare': ricordare,
      };

  factory DayData.fromJson(Map<String, dynamic> json) => DayData(
        entries: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => Entry.fromJson(e as Map<String, dynamic>))
            .toList(),
        mood10: json['mood10'],
        stats: Map<String, String>.from(json['stats'] ?? {}),
        narrative: json['narrative'] ?? '',
        episodeLabel: json['episodeLabel'] ?? '',
        momento: json['momento'] ?? '',
        ricordare: json['ricordare'] ?? '',
      );
}

const List<Map<String, String>> tags = [
  {'id': 'luogo', 'label': 'Luogo', 'icon': '📍'},
  {'id': 'musica', 'label': 'Musica', 'icon': '🎵'},
  {'id': 'persona', 'label': 'Persona', 'icon': '👥'},
  {'id': 'momento', 'label': 'Momento', 'icon': '⭐'},
  {'id': 'foto', 'label': 'Foto', 'icon': '📸'},
];

String todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String timeNow() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

String moodEmoji(int? score) {
  if (score == null) return '•';
  if (score >= 9) return '✨';
  if (score >= 7) return '☀️';
  if (score >= 5) return '🙂';
  if (score >= 3) return '🌧️';
  return '🌙';
}

String moodLabel(int? score) {
  if (score == null) return 'Non registrato';
  if (score >= 9) return 'Splendida';
  if (score >= 7) return 'Tranquilla';
  if (score >= 5) return 'Così così';
  if (score >= 3) return 'Pesante';
  return 'Molto giù';
}

// ---------- Schermata principale ----------

class EpisodioScreen extends StatefulWidget {
  const EpisodioScreen({super.key});

  @override
  State<EpisodioScreen> createState() => _EpisodioScreenState();
}

class _EpisodioScreenState extends State<EpisodioScreen> {
  DayData day = DayData();
  bool loading = true;
  int? episodeNum;
  final String key = todayKey();
  final TextEditingController draftController = TextEditingController();
  String draftTag = tags[0]['id']!;
  bool narrLoading = false;
  bool narrError = false;
  final TextEditingController askController = TextEditingController();
  String askAnswer = '';
  bool askLoading = false;
  bool askError = false;

  static const amber = Color(0xFFE8A24D);
  static const teal = Color(0xFF4F7A78);
  static const ivory = Color(0xFFF2ECE1);
  static const ivoryDim = Color(0xFFA89D8C);
  static const bgCard = Color(0xFF1C1A17);
  static const line = Color(0xFF3A352C);

  @override
  void initState() {
    super.initState();
    _loadDay();
  }

  Future<void> _loadDay() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('day:$key');
    if (raw != null) {
      day = DayData.fromJson(jsonDecode(raw));
    }
    final allKeys = prefs.getKeys().where((k) => k.startsWith('day:')).toList();
    setState(() {
      episodeNum = allKeys.contains('day:$key') ? allKeys.length : allKeys.length + 1;
      loading = false;
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('day:$key', jsonEncode(day.toJson()));
  }

  void _addEntry() {
    final text = draftController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      day.entries.add(Entry(id: DateTime.now().millisecondsSinceEpoch, tag: draftTag, text: text, time: timeNow()));
      draftController.clear();
    });
    _persist();
    Navigator.of(context).pop();
  }

  void _removeEntry(int id) {
    setState(() {
      day.entries.removeWhere((e) => e.id == id);
    });
    _persist();
  }

  void _updateMood(double value) {
    setState(() {
      day.mood10 = value.round();
    });
    _persist();
  }

  void _updateStat(String field, String value) {
    day.stats[field] = value;
    _persist();
  }

  Future<void> _generateNarrative() async {
    if (day.entries.isEmpty || narrLoading) return;
    setState(() {
      narrLoading = true;
      narrError = false;
    });
    final sceneList = day.entries
        .map((e) => '- [${e.time}] (${tags.firstWhere((t) => t['id'] == e.tag)['label']}) ${e.text}')
        .join('\n');
    final statLines = [
      if (day.stats['luogo']?.isNotEmpty == true) 'Luogo: ${day.stats['luogo']}',
      if (day.stats['musica']?.isNotEmpty == true) 'Musica ascoltata: ${day.stats['musica']} min',
      if (day.stats['gaming']?.isNotEmpty == true) 'Gaming: ${day.stats['gaming']} min',
      if (day.stats['allenamento']?.isNotEmpty == true) 'Allenamento: ${day.stats['allenamento']} min',
    ].join('\n');
    final prompt =
        'Analizza la giornata di una persona e restituisci SOLO un oggetto JSON valido (nessun testo prima o dopo, '
        'nessun blocco markdown), con questa forma esatta:\n'
        '{"label": "...", "narrative": "...", "momento": "...", "ricordare": "..."}\n\n'
        '- "label": una breve etichetta con un\'emoji meteo/atmosfera davanti, tipo "☀️ Giornata tranquilla" o "🌧️ Giornata pesante" (max 4 parole dopo l\'emoji)\n'
        '- "narrative": 2-3 frasi in prosa, tono caldo e naturale, come il riassunto di una puntata di una serie tratta dalla vita reale\n'
        '- "momento": UNA frase che racconta il momento saliente della giornata\n'
        '- "ricordare": UNA frase breve su una cosa da ricordare di questa giornata\n\n'
        'Non inventare dettagli non presenti nei dati. Scrivi tutto in italiano.\n\n'
        'Umore della giornata: ${day.mood10 != null ? '${day.mood10}/10 (${moodLabel(day.mood10)})' : 'non specificato'}\n'
        '${statLines.isNotEmpty ? '\nStatistiche:\n$statLines' : ''}\n\n'
        'Scene:\n${sceneList.isNotEmpty ? sceneList : '(nessuna scena aggiunta, basati solo su umore e statistiche)'}';

    final result = await askAI(prompt);
    bool ok = false;
    if (result != null && result.isNotEmpty) {
      try {
        final start = result.indexOf('{');
        final end = result.lastIndexOf('}');
        if (start != -1 && end != -1 && end > start) {
          final jsonStr = result.substring(start, end + 1);
          final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
          day.episodeLabel = parsed['label'] ?? '';
          day.narrative = parsed['narrative'] ?? '';
          day.momento = parsed['momento'] ?? '';
          day.ricordare = parsed['ricordare'] ?? '';
          ok = day.narrative.isNotEmpty;
        }
      } catch (e) {
        ok = false;
      }
    }
    setState(() {
      narrLoading = false;
      narrError = !ok;
    });
    if (ok) _persist();
  }

  Future<void> _askHistory() async {
    final question = askController.text.trim();
    if (question.isEmpty || askLoading) return;
    setState(() {
      askLoading = true;
      askError = false;
      askAnswer = '';
    });
    final prefs = await SharedPreferences.getInstance();
    final dayKeys = prefs.getKeys().where((k) => k.startsWith('day:')).toList()..sort();
    final buffer = StringBuffer();
    for (final k in dayKeys) {
      final raw = prefs.getString(k);
      if (raw == null) continue;
      final d = DayData.fromJson(jsonDecode(raw));
      final date = k.replaceFirst('day:', '');
      buffer.writeln('### $date');
      if (d.mood10 != null) buffer.writeln('Mood: ${d.mood10}/10');
      if (d.stats['luogo']?.isNotEmpty == true) buffer.writeln('Luogo: ${d.stats['luogo']}');
      if (d.stats['musica']?.isNotEmpty == true) buffer.writeln('Musica: ${d.stats['musica']} min');
      if (d.stats['gaming']?.isNotEmpty == true) buffer.writeln('Gaming: ${d.stats['gaming']} min');
      if (d.stats['allenamento']?.isNotEmpty == true) buffer.writeln('Allenamento: ${d.stats['allenamento']} min');
      for (final e in d.entries) {
        buffer.writeln('- (${e.tag}) ${e.text}');
      }
      if (d.narrative.isNotEmpty) buffer.writeln('Racconto: ${d.narrative}');
      buffer.writeln();
    }
    final prompt =
        'Sei l\'assistente personale di un diario di vita automatico. Qui sotto trovi la cronologia delle giornate '
        'registrate dall\'utente. Rispondi alla domanda dell\'utente basandoti SOLO su questi dati. Se i dati non '
        'bastano per rispondere con certezza, dillo onestamente invece di inventare. Rispondi in italiano, in modo '
        'colloquiale e diretto.\n\nCRONOLOGIA:\n${buffer.toString()}\n\nDOMANDA: $question';

    final result = await askAI(prompt);
    setState(() {
      askLoading = false;
      if (result != null && result.isNotEmpty) {
        askAnswer = result;
      } else {
        askError = true;
      }
    });
  }

  String get episodeTitle {
    if (day.entries.isEmpty) return 'Un episodio ancora da scrivere';
    final counts = <String, int>{};
    for (final e in day.entries) {
      counts[e.tag] = (counts[e.tag] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    const themeWords = {
      'luogo': 'in movimento',
      'musica': 'a ritmo',
      'persona': 'in compagnia',
      'momento': 'di svolta',
      'foto': 'da ricordare',
    };
    final n = day.entries.length;
    return '${moodLabel(day.mood10)}, ${n == 1 ? 'un momento' : '$n momenti'} ${themeWords[top]}';
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nuova scena', style: TextStyle(fontSize: 17, color: ivory)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: tags.map((t) {
                    final selected = draftTag == t['id'];
                    return ChoiceChip(
                      label: Text('${t['icon']} ${t['label']}'),
                      selected: selected,
                      onSelected: (_) => setSheetState(() => draftTag = t['id']!),
                      selectedColor: amber.withOpacity(0.2),
                      labelStyle: TextStyle(color: selected ? amber : ivoryDim, fontSize: 12.5),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: selected ? amber : line),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: draftController,
                  maxLines: 2,
                  style: const TextStyle(color: ivory),
                  decoration: InputDecoration(
                    hintText: 'Cosa è successo?',
                    hintStyle: const TextStyle(color: ivoryDim),
                    filled: true,
                    fillColor: const Color(0xFF141210),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Annulla'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: amber, foregroundColor: const Color(0xFF141210)),
                        onPressed: _addEntry,
                        child: const Text('Aggiungi alla scena'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: amber,
        foregroundColor: const Color(0xFF141210),
        onPressed: _showAddSheet,
        child: const Icon(Icons.add, size: 28),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 30, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  'Episodio $episodeNum',
                  style: const TextStyle(fontSize: 11, letterSpacing: 2, color: Color(0xFF8A6531)),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  episodeTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: ivory),
                ),
              ),
              const SizedBox(height: 24),

              // Mood
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('MOOD', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: ivoryDim)),
                        Text(
                          day.mood10 != null
                              ? '${moodEmoji(day.mood10)} ${day.mood10}/10 · ${moodLabel(day.mood10)}'
                              : 'tocca per registrare',
                          style: const TextStyle(fontSize: 13, color: amber),
                        ),
                      ],
                    ),
                    Slider(
                      value: (day.mood10 ?? 5).toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      activeColor: amber,
                      onChanged: _updateMood,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Statistiche rapide
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: line)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('STATISTICHE DI OGGI', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: ivoryDim)),
                    const SizedBox(height: 10),
                    _statField('📍', 'luogo', 'es. Ollastra → Oristano', isNumber: false),
                    _statField('🎵', 'musica', 'Minuti di musica'),
                    _statField('🎮', 'gaming', 'Minuti di gaming'),
                    _statField('🏋️', 'allenamento', 'Minuti di allenamento'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Racconto IA
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✦ RACCONTO DELL\'EPISODIO', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: teal)),
                    const SizedBox(height: 10),
                    if (day.narrative.isEmpty)
                      Text(
                        day.entries.isEmpty
                            ? 'Aggiungi almeno una scena per generare il racconto della giornata.'
                            : 'Lascia che l\'IA intrecci le tue scene in un piccolo racconto.',
                        style: const TextStyle(fontSize: 13, color: ivoryDim),
                      )
                    else ...[
                      if (day.episodeLabel.isNotEmpty)
                        Text(day.episodeLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: amber)),
                      if (day.episodeLabel.isNotEmpty) const SizedBox(height: 10),
                      Text(day.narrative, style: const TextStyle(fontSize: 15, height: 1.5, color: ivory)),
                      if (day.momento.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text('MOMENTO DELLA GIORNATA', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: ivoryDim)),
                        const SizedBox(height: 4),
                        Text('"${day.momento}"', style: const TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: ivory)),
                      ],
                      if (day.ricordare.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('UNA COSA DA RICORDARE', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: ivoryDim)),
                        const SizedBox(height: 4),
                        Text('"${day.ricordare}"', style: const TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: ivory)),
                      ],
                    ],
                    if (narrError)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Non sono riuscito a generare il racconto. Riprova.', style: TextStyle(fontSize: 12, color: Color(0xFFD98A6F))),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: day.entries.isEmpty || narrLoading ? null : _generateNarrative,
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: teal)),
                      child: Text(narrLoading ? 'Scrivo…' : (day.narrative.isNotEmpty ? 'Rigenera racconto' : 'Genera racconto')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Timeline
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SCENE DELLA GIORNATA', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: ivoryDim)),
                  Text('${day.entries.length}', style: const TextStyle(color: Color(0xFF8A6531))),
                ],
              ),
              const SizedBox(height: 12),
              if (day.entries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: line)),
                  child: const Center(
                    child: Text(
                      'Nessuna scena ancora.\nTocca "+" per aggiungere il primo momento.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ivoryDim, fontSize: 13.5),
                    ),
                  ),
                )
              else
                ...day.entries.reversed.map((e) {
                  final tagInfo = tags.firstWhere((t) => t['id'] == e.tag);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: bgCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${tagInfo['icon']} ${tagInfo['label']} · ${e.time}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF8A6531))),
                            GestureDetector(
                              onTap: () => _removeEntry(e.id),
                              child: const Icon(Icons.close, size: 14, color: ivoryDim),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(e.text, style: const TextStyle(fontSize: 14.5, color: ivory)),
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 24),

              // Chiedi al tuo diario
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🧠 CHIEDI AL TUO DIARIO', style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: teal)),
                    const SizedBox(height: 4),
                    const Text(
                      'L\'IA cerca nella tua cronologia salvata e ti risponde.',
                      style: TextStyle(fontSize: 12.5, color: ivoryDim),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: askController,
                            style: const TextStyle(color: ivory, fontSize: 13.5),
                            decoration: InputDecoration(
                              hintText: 'es. "Qual è il mio momento più bello?"',
                              hintStyle: const TextStyle(color: ivoryDim, fontSize: 13),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              filled: true,
                              fillColor: const Color(0xFF141210),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: line)),
                            ),
                            onSubmitted: (_) => _askHistory(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: teal, foregroundColor: ivory),
                          onPressed: askLoading ? null : _askHistory,
                          child: Text(askLoading ? '…' : 'Chiedi'),
                        ),
                      ],
                    ),
                    if (askError)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text('Non sono riuscito a rispondere. Riprova.', style: TextStyle(fontSize: 12, color: Color(0xFFD98A6F))),
                      ),
                    if (askAnswer.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(askAnswer, style: const TextStyle(fontSize: 14.5, height: 1.5, color: ivory)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statField(String icon, String field, String placeholder, {bool isNumber = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text(icon, style: const TextStyle(fontSize: 15))),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: day.stats[field]),
              keyboardType: isNumber ? TextInputType.number : TextInputType.text,
              style: const TextStyle(color: ivory, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: const TextStyle(color: ivoryDim, fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: const Color(0xFF141210),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: line)),
              ),
              onSubmitted: (v) => _updateStat(field, v),
              onEditingComplete: () {},
            ),
          ),
        ],
      ),
    );
  }
}