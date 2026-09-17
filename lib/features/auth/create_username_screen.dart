import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settings/terms_screen.dart';
import 'auth_service.dart';

/// Pantalla de bloqueo total: se muestra en vez del mapa/app cuando la
/// cuenta (tipicamente una creada con Google Sign-In, que no pasa por el
/// formulario de registro) todavia no tiene "usuario" asignado. No se puede
/// cerrar ni saltear -- root_shell.dart la muestra en lugar del IndexedStack
/// hasta que el usuario se guarde con exito.
class CreateUsernameScreen extends StatefulWidget {
  final VoidCallback onCreated;

  const CreateUsernameScreen({super.key, required this.onCreated});

  @override
  State<CreateUsernameScreen> createState() => _CreateUsernameScreenState();
}

class _CreateUsernameScreenState extends State<CreateUsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _supabase = Supabase.instance.client;
  final _usuario = TextEditingController();

  Timer? _debounce;
  bool? _available; // null = sin chequear todavia
  bool _checking = false;
  bool _saving = false;
  bool _acceptedTerms = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _available = null);
    final usuario = value.trim();
    if (usuario.length < 4 || usuario.length > 12) return;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _checking = true);
      final available = await _auth.isUsernameAvailable(usuario);
      if (!mounted) return;
      setState(() {
        _available = available;
        _checking = false;
      });
    });
  }

  Widget? _suffix() {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_available == null) return null;
    return Icon(
      _available! ? Icons.check_circle : Icons.cancel,
      color: _available! ? Colors.green : Colors.redAccent,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_available == false) {
      setState(() => _error = 'Ese usuario ya esta en uso.');
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _error = 'Debes aceptar los terminos y condiciones para continuar.');
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Se vuelve a chequear disponibilidad justo antes de guardar (evita la
      // carrera de que alguien mas lo tome entre el ultimo chequeo y este submit).
      final stillAvailable = await _auth.isUsernameAvailable(_usuario.text.trim());
      if (!stillAvailable) {
        setState(() {
          _available = false;
          _error = 'Ese usuario ya esta en uso.';
        });
        return;
      }
      // Este es el momento de "creacion de cuenta" para el flujo de Google
      // (nunca paso por register_screen.dart), asi que tambien se registra
      // la aceptacion de terminos aca.
      await _supabase.from('profiles').update({
        'usuario': _usuario.text.trim(),
        'terms_accepted_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      widget.onCreated();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.person_pin_circle, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'Crea tu usuario',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Falta un ultimo paso antes de usar el mapa: elige un usuario. '
                      'Se usa para que tus amigos te agreguen y para iniciar sesion.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _usuario,
                      autofocus: true,
                      onChanged: _onChanged,
                      maxLength: 12,
                      decoration: InputDecoration(
                        labelText: 'Usuario',
                        border: const OutlineInputBorder(),
                        suffixIcon: _suffix(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length < 4) return 'Minimo 4 caracteres';
                        if (v.trim().length > 12) return 'Maximo 12 caracteres';
                        if (_available == false) return 'Ya esta en uso';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _acceptedTerms,
                      onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                      title: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Acepto los '),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const TermsScreen()),
                            ),
                            child: const Text(
                              'terminos y condiciones',
                              style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Guardar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
