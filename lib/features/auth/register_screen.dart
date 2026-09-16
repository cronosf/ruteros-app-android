import 'package:flutter/material.dart';
import '../../core/peru_data.dart';
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
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _direccion = TextEditingController();
  final _provincia = TextEditingController();
  final _distrito = TextEditingController();
  String _departamento = 'Lima';

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
        telefono: _telefono.text.trim(),
        direccion: _direccion.text.trim(),
        departamento: _departamento,
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
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'Correo invalido' : null,
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
                  initialValue: _departamento,
                  decoration: const InputDecoration(labelText: 'Departamento'),
                  items: peruDepartamentos
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) => setState(() => _departamento = v ?? _departamento),
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
