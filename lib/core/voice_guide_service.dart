import 'package:shared_preferences/shared_preferences.dart';

const _voiceGuideLocaleKey = 'voice_guide_locale';

/// Nombres legibles para los codigos de locale del motor de TTS mas comunes
/// -- si no esta mapeado, se muestra el codigo tal cual (ej. "pt-BR").
const Map<String, String> voiceGuideLocaleLabels = {
  'es-ES': 'Espanol (Espana)',
  'es-US': 'Espanol (Estados Unidos / neutro)',
  'es-MX': 'Espanol (Mexico)',
  'es-AR': 'Espanol (Argentina)',
  'es-CO': 'Espanol (Colombia)',
  'es-CL': 'Espanol (Chile)',
  'es-PE': 'Espanol (Peru)',
  'es-VE': 'Espanol (Venezuela)',
  'en-US': 'Ingles (Estados Unidos)',
  'en-GB': 'Ingles (Reino Unido)',
  'en-AU': 'Ingles (Australia)',
  'en-IN': 'Ingles (India)',
  'pt-BR': 'Portugues (Brasil)',
  'pt-PT': 'Portugues (Portugal)',
  'fr-FR': 'Frances (Francia)',
  'it-IT': 'Italiano (Italia)',
  'de-DE': 'Aleman (Alemania)',
};

String voiceGuideLabelFor(String locale) => voiceGuideLocaleLabels[locale] ?? locale;

/// Guarda que voz/idioma eligio el usuario para la guia por voz del modo de
/// ruteo (ver map_screen.dart _initTts) -- persiste sin importar en que pais
/// este despues, en vez de que la app siga adivinando segun el telefono cada
/// vez. `null` = automatico (comportamiento anterior: prueba es-ES, es-US,
/// es-MX, es en ese orden segun lo que tenga instalado el telefono).
class VoiceGuideService {
  static Future<String?> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_voiceGuideLocaleKey);
  }

  static Future<void> setSavedLocale(String? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_voiceGuideLocaleKey);
    } else {
      await prefs.setString(_voiceGuideLocaleKey, locale);
    }
  }
}
