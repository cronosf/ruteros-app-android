import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/env.dart';

const _rememberSessionKey = 'remember_session';

class AuthService {
  final _supabase = Supabase.instance.client;

  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;
  Session? get currentSession => _supabase.auth.currentSession;

  /// Supabase persiste la sesion en disco por defecto (asi deberia ser: no
  /// hay que volver a iniciar sesion cada vez que se abre la app). Esta
  /// bandera es lo que controla el checkbox "Recordar sesion" del login: si
  /// se desmarca, se guarda como false y en el proximo arranque en frio
  /// (ver main.dart) se cierra la sesion antes de que la UI la detecte,
  /// simulando una sesion que no se recuerda.
  static Future<void> setRememberSession(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberSessionKey, value);
  }

  static Future<bool> getRememberSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberSessionKey) ?? true;
  }

  /// Acepta el correo o el "usuario" (username) como identificador -- si no
  /// tiene "@" se asume usuario y primero se resuelve el correo real via la
  /// RPC get_email_by_username, porque Supabase Auth siempre pide un correo.
  Future<void> signIn({required String identifier, required String password}) async {
    var email = identifier.trim();
    if (!email.contains('@')) {
      final resolved = await _supabase.rpc('get_email_by_username', params: {'p_usuario': email});
      if (resolved == null) {
        throw Exception('No existe una cuenta con ese usuario.');
      }
      email = resolved as String;
    }
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String nombres,
    required String apellidos,
    required String usuario,
    required String telefono,
    required String direccion,
    required String pais,
    required String departamento,
    required String provincia,
    required String distrito,
  }) async {
    final res = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'nombres': nombres, 'apellidos': apellidos},
    );
    final userId = res.user?.id;
    if (userId == null) return;

    // El trigger handle_new_user ya creo la fila en profiles; completamos el resto.
    // register_screen.dart exige aceptar los terminos antes de llamar a este
    // metodo, por eso se guarda incondicionalmente aca.
    await _supabase.from('profiles').update({
      'usuario': usuario,
      'telefono': telefono,
      'direccion': direccion,
      'pais': pais,
      'departamento': departamento,
      'provincia': provincia,
      'distrito': distrito,
      'terms_accepted_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  Future<bool> isUsernameAvailable(String usuario) async {
    final res = await _supabase.rpc('is_username_available', params: {'p_usuario': usuario});
    return res as bool;
  }

  Future<bool> isEmailAvailable(String email) async {
    final res = await _supabase.rpc('is_email_available', params: {'p_email': email});
    return res as bool;
  }

  /// Google Sign-In nativo en Android: pide el idToken al SDK de Google y se lo
  /// pasa a Supabase, que valida el token y crea/recupera la sesion. Esto evita
  /// el flujo de redireccion por navegador que usa la web.
  Future<void> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      serverClientId: Env.googleWebClientId.isNotEmpty ? Env.googleWebClientId : null,
    );
    // Sin este signOut, el SDK de Google reusa en silencio la ultima cuenta
    // autenticada en el dispositivo y nunca muestra el selector de cuentas.
    await googleSignIn.signOut();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return; // usuario cancelo

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw Exception('Google no devolvio idToken. Revisa GOOGLE_WEB_CLIENT_ID.');
    }

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
  }

  Future<void> signOut() => _supabase.auth.signOut();
}
