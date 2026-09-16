import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/env.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;
  Session? get currentSession => _supabase.auth.currentSession;

  Future<void> signIn({required String email, required String password}) {
    return _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String nombres,
    required String apellidos,
    required String telefono,
    required String direccion,
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
    await _supabase.from('profiles').update({
      'telefono': telefono,
      'direccion': direccion,
      'pais': 'PE',
      'departamento': departamento,
      'provincia': provincia,
      'distrito': distrito,
    }).eq('id', userId);
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
