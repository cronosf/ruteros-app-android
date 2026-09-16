import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/root_shell.dart';
import 'login_screen.dart';

/// Muestra el shell principal (bottom nav) si hay sesion activa, o el login si no.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
        return session != null ? const RootShell() : const LoginScreen();
      },
    );
  }
}
