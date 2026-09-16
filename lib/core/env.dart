/// Credenciales de Supabase inyectadas en build time via --dart-define.
///
/// Ejemplo:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=tu-anon-key \
///     --dart-define=GOOGLE_WEB_CLIENT_ID=tu-client-id.apps.googleusercontent.com
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Client ID de tipo "Web application" en Google Cloud Console, requerido por
  /// google_sign_in para obtener el idToken que se le pasa a Supabase Auth
  /// (signInWithIdToken necesita el audience del client "web", no el de Android).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Cuenta gratis en cloud.maptiler.com, sin tarjeta. Se usa solo para el
  /// buscador de direcciones del mapa (geocoding), no para las tiles (esas son
  /// de Google Maps SDK, ya incluido gratis en la app Android).
  static const maptilerKey = String.fromEnvironment('MAPTILER_KEY');
}
