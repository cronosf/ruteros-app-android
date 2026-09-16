import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/peru_data.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nombres = TextEditingController();
  final _apellidos = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final _provincia = TextEditingController();
  final _distrito = TextEditingController();
  String _departamento = 'Lima';
  String _email = '';

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final data = await _supabase.from('profiles').select().eq('id', userId).maybeSingle();
    if (!mounted) return;
    if (data != null) {
      _nombres.text = data['nombres'] as String? ?? '';
      _apellidos.text = data['apellidos'] as String? ?? '';
      _telefono.text = data['telefono'] as String? ?? '';
      _direccion.text = data['direccion'] as String? ?? '';
      _provincia.text = data['provincia'] as String? ?? '';
      _distrito.text = data['distrito'] as String? ?? '';
      _email = data['email'] as String? ?? '';
      final dep = data['departamento'] as String?;
      if (dep != null && peruDepartamentos.contains(dep)) _departamento = dep;
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _supabase.from('profiles').update({
        'nombres': _nombres.text.trim(),
        'apellidos': _apellidos.text.trim(),
        'telefono': _telefono.text.trim(),
        'direccion': _direccion.text.trim(),
        'departamento': _departamento,
        'provincia': _provincia.text.trim(),
        'distrito': _distrito.text.trim(),
      }).eq('id', userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil actualizado.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      initialValue: _email,
                      enabled: false,
                      decoration: const InputDecoration(labelText: 'Correo (no editable)'),
                    ),
                    const SizedBox(height: 12),
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
                      controller: _telefono,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Telefono'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
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
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Guardar cambios'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
