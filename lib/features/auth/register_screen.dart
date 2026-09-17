import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/peru_data.dart';
import '../settings/terms_screen.dart';
import 'auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();

  final _nombres = TextEditingController();
  final _apellidos = TextEditingController();
  final _usuario = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _direccion = TextEditingController();
  final _provincia = TextEditingController();
  final _distrito = TextEditingController();
  final _departamentoLibre = TextEditingController();
  String _pais = 'PE';
  String _departamento = 'Lima';
  bool _acceptedTerms = false;

  bool _loading = false;
  String? _error;

  Timer? _usuarioDebounce;
  bool? _usuarioAvailable; // null = sin chequear todavia
  bool _checkingUsuario = false;

  Timer? _emailDebounce;
  bool? _emailAvailable;
  bool _checkingEmail = false;

  @override
  void dispose() {
    _usuarioDebounce?.cancel();
    _emailDebounce?.cancel();
    _departamentoLibre.dispose();
    super.dispose();
  }

  void _onUsuarioChanged(String value) {
    _usuarioDebounce?.cancel();
    setState(() => _usuarioAvailable = null);
    final usuario = value.trim();
    if (usuario.length < 4 || usuario.length > 12) return;
    _usuarioDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _checkingUsuario = true);
      final available = await _auth.isUsernameAvailable(usuario);
      if (!mounted) return;
      setState(() {
        _usuarioAvailable = available;
        _checkingUsuario = false;
      });
    });
  }

  void _onEmailChanged(String value) {
    _emailDebounce?.cancel();
    setState(() => _emailAvailable = null);
    final email = value.trim();
    if (!email.contains('@')) return;
    _emailDebounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _checkingEmail = true);
      final available = await _auth.isEmailAvailable(email);
      if (!mounted) return;
      setState(() {
        _emailAvailable = available;
        _checkingEmail = false;
      });
    });
  }

  Widget? _availabilitySuffix(bool checking, bool? available) {
    if (checking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (available == null) return null;
    return Icon(
      available ? Icons.check_circle : Icons.cancel,
      color: available ? Colors.green : Colors.redAccent,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_usuarioAvailable == false) {
      setState(() => _error = 'Ese usuario ya esta en uso.');
      return;
    }
    if (_emailAvailable == false) {
      setState(() => _error = 'Ese correo ya tiene una cuenta.');
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _error = 'Debes aceptar los terminos y condiciones para continuar.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        nombres: _nombres.text.trim(),
        apellidos: _apellidos.text.trim(),
        usuario: _usuario.text.trim(),
        telefono: _telefono.text.trim(),
        direccion: _direccion.text.trim(),
        pais: _pais,
        departamento: _pais == 'PE' ? _departamento : _departamentoLibre.text.trim(),
        provincia: _provincia.text.trim(),
        distrito: _distrito.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nombres,
                  decoration: const InputDecoration(labelText: 'Nombres'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _apellidos,
                  decoration: const InputDecoration(labelText: 'Apellidos'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _usuario,
                  onChanged: _onUsuarioChanged,
                  maxLength: 12,
                  decoration: InputDecoration(
                    labelText: 'Usuario',
                    helperText: 'Se usa para que tus amigos te agreguen y para iniciar sesion',
                    suffixIcon: _availabilitySuffix(_checkingUsuario, _usuarioAvailable),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 4) return 'Minimo 4 caracteres';
                    if (v.trim().length > 12) return 'Maximo 12 caracteres';
                    if (_usuarioAvailable == false) return 'Ya esta en uso';
                    return null;
                  },
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: _onEmailChanged,
                  decoration: InputDecoration(
                    labelText: 'Correo',
                    suffixIcon: _availabilitySuffix(_checkingEmail, _emailAvailable),
                  ),
                  validator: (v) {
                    if (v == null || !v.contains('@')) return 'Correo invalido';
                    if (_emailAvailable == false) return 'Ya tiene una cuenta';
                    return null;
                  },
                ),
                TextFormField(
                  controller: _telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefono'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contrasena'),
                  validator: (v) => (v == null || v.length < 6) ? 'Minimo 6 caracteres' : null,
                ),
                TextFormField(
                  controller: _direccion,
                  decoration: const InputDecoration(labelText: 'Direccion'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _pais,
                  decoration: const InputDecoration(labelText: 'Pais'),
                  items: paises
                      .map((p) => DropdownMenuItem(value: p.code, child: Text(p.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _pais = v ?? _pais),
                ),
                // El dropdown fijo de departamentos solo tiene sentido para Peru;
                // para cualquier otro pais "departamento" ni siquiera es el
                // termino correcto (estado, provincia, etc.), asi que se deja
                // como texto libre.
                if (_pais == 'PE')
                  DropdownButtonFormField<String>(
                    initialValue: _departamento,
                    decoration: const InputDecoration(labelText: 'Departamento'),
                    items: peruDepartamentos
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) => setState(() => _departamento = v ?? _departamento),
                  )
                else
                  TextFormField(
                    controller: _departamentoLibre,
                    decoration: const InputDecoration(labelText: 'Departamento / Estado / Region'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                  ),
                TextFormField(
                  controller: _provincia,
                  decoration: const InputDecoration(labelText: 'Provincia'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _distrito,
                  decoration: const InputDecoration(labelText: 'Distrito'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
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
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Crear cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
