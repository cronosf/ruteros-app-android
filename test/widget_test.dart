// Smoke test: sin sesion de Supabase, la app debe mostrar la pantalla de login.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ruteros/features/auth/login_screen.dart';

void main() {
  setUpAll(() async {
    // LoginScreen crea un AuthService que llama a Supabase.instance; en los
    // tests de widget no hay backend real ni plugins nativos, asi que se
    // mockea shared_preferences (usado por supabase_flutter para persistir sesion).
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-key');
  });

  testWidgets('Muestra el formulario de login', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Ruteros'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
  });
}
