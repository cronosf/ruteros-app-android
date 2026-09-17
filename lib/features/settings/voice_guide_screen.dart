import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../core/theme.dart';
import '../../core/voice_guide_service.dart';

class VoiceGuideScreen extends StatefulWidget {
  const VoiceGuideScreen({super.key});

  @override
  State<VoiceGuideScreen> createState() => _VoiceGuideScreenState();
}

class _VoiceGuideScreenState extends State<VoiceGuideScreen> {
  final _tts = FlutterTts();
  List<String> _locales = [];
  String? _selected; // null = automatico
  bool _loading = true;
  String? _testingLocale;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _tts.getLanguages;
      final locales = (raw as List).cast<String>().toSet().toList()..sort();
      final saved = await VoiceGuideService.getSavedLocale();
      if (!mounted) return;
      setState(() {
        _locales = locales;
        _selected = (saved != null && locales.contains(saved)) ? saved : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String? locale) async {
    setState(() => _selected = locale);
    await VoiceGuideService.setSavedLocale(locale);
  }

  String _testPhraseFor(String locale) {
    if (locale.startsWith('en')) return 'Hello, this is a voice guide test.';
    if (locale.startsWith('pt')) return 'Ola, este e um teste da voz guiada.';
    if (locale.startsWith('fr')) return "Bonjour, ceci est un test de la voix guidee.";
    if (locale.startsWith('it')) return 'Ciao, questo e un test della guida vocale.';
    if (locale.startsWith('de')) return 'Hallo, dies ist ein Test der Sprachfuhrung.';
    return 'Hola, esta es una prueba de la guia de voz. Gire a la derecha en 300 metros.';
  }

  Future<void> _preview(String locale) async {
    setState(() => _testingLocale = locale);
    await _tts.setLanguage(locale);
    await _tts.speak(_testPhraseFor(locale));
    if (mounted) setState(() => _testingLocale = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guia de voz')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              children: [
                const Text(
                  'Elegi con que voz/idioma queres que te hable la guia mientras manejas. '
                  'Se usa donde sea que estes, sin importar el pais.',
                  style: TextStyle(color: AppColors.grisUI),
                ),
                const SizedBox(height: 16),
                Card(
                  child: RadioListTile<String?>(
                    value: null,
                    groupValue: _selected,
                    onChanged: (_) => _select(null),
                    title: const Text('Automatico'),
                    subtitle: const Text('Usa la voz en espanol que tenga tu telefono'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_locales.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No se pudo leer la lista de voces instaladas en tu telefono.',
                      style: TextStyle(color: AppColors.grisUI),
                    ),
                  )
                else
                  ..._locales.map(
                    (locale) => Card(
                      child: RadioListTile<String?>(
                        value: locale,
                        groupValue: _selected,
                        onChanged: (_) => _select(locale),
                        title: Text(voiceGuideLabelFor(locale)),
                        secondary: IconButton(
                          icon: _testingLocale == locale
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.volume_up, color: AppColors.verde),
                          tooltip: 'Probar esta voz',
                          onPressed: _testingLocale == null ? () => _preview(locale) : null,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Si no encontras la voz que buscas, tu telefono puede tener mas para '
                  'descargar en Ajustes > Sistema > Idiomas > Sintesis de voz.',
                  style: TextStyle(color: AppColors.grisUI, fontSize: 12),
                ),
              ],
            ),
    );
  }
}
