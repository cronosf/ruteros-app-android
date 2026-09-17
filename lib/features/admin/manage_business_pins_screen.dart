import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/env.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

const _radiusOptions = [1000.0, 2000.0, 3000.0, 5000.0, 10000.0];

class ManageBusinessPinsScreen extends StatefulWidget {
  const ManageBusinessPinsScreen({super.key});

  @override
  State<ManageBusinessPinsScreen> createState() => _ManageBusinessPinsScreenState();
}

class _ManageBusinessPinsScreenState extends State<ManageBusinessPinsScreen> {
  final _supabase = Supabase.instance.client;
  List<SponsoredPinAdmin> _pins = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _supabase.rpc('list_sponsored_pins_admin');
    if (!mounted) return;
    setState(() {
      _pins = (data as List).map((e) => SponsoredPinAdmin.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _openForm({SponsoredPinAdmin? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BusinessPinForm(existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(SponsoredPinAdmin pin) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar pin'),
        content: Text('Se va a eliminar el pin de "${pin.businessName}". Esta accion no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true) return;
    await _supabase.from('sponsored_pins').delete().eq('id', pin.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestionar negocios')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _pins.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Todavia no hay pines de negocios creados.',
                            style: TextStyle(color: AppColors.grisUI),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _pins.length,
                      itemBuilder: (context, i) {
                        final p = _pins[i];
                        final expired = p.endsAt.isBefore(DateTime.now());
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.star,
                              color: p.status == 'active' && !expired ? Colors.amber : AppColors.grisUI,
                            ),
                            title: Text(p.businessName),
                            subtitle: Text(
                              '${p.category} · ${(p.radiusM / 1000).toStringAsFixed(0)}km · '
                              '${p.status == 'active' ? (expired ? 'Vencido' : 'Activo') : 'Pausado'}\n'
                              '${_fmtDate(p.startsAt)} - ${_fmtDate(p.endsAt)}',
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _openForm(existing: p),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () => _delete(p),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add_business),
      ),
    );
  }
}

String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

class _BusinessPinForm extends StatefulWidget {
  final SponsoredPinAdmin? existing;

  const _BusinessPinForm({this.existing});

  @override
  State<_BusinessPinForm> createState() => _BusinessPinFormState();
}

class _BusinessPinFormState extends State<_BusinessPinForm> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nombre = TextEditingController();
  final _categoria = TextEditingController();
  final _descripcion = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _direccionExactaCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  double _radius = 2000;
  DateTime _startsAt = DateTime.now();
  DateTime _endsAt = DateTime.now().add(const Duration(days: 30));
  String _status = 'active';

  Timer? _searchDebounce;
  List<GeoSuggestion> _suggestions = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nombre.text = e.businessName;
      _categoria.text = e.category;
      _descripcion.text = e.description ?? '';
      _lat = e.lat;
      _lng = e.lng;
      _direccionCtrl.text = 'Ubicacion ya guardada (${e.lat.toStringAsFixed(4)}, ${e.lng.toStringAsFixed(4)})';
      _direccionExactaCtrl.text = e.direccionExacta ?? '';
      _radius = e.radiusM;
      _startsAt = e.startsAt;
      _endsAt = e.endsAt;
      _status = e.status;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _direccionExactaCtrl.dispose();
    super.dispose();
  }

  void _onAddressChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    if (Env.maptilerKey.isEmpty) return;
    try {
      final uri = Uri.parse(
        'https://api.maptiler.com/geocoding/${Uri.encodeComponent(query)}.json'
        '?key=${Env.maptilerKey}&language=es&limit=5',
      );
      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _suggestions = features.map((f) {
          final coords = f['geometry']['coordinates'] as List;
          return GeoSuggestion(
            placeName: f['place_name'] as String,
            lat: (coords[1] as num).toDouble(),
            lng: (coords[0] as num).toDouble(),
          );
        }).toList();
      });
    } catch (_) {
      // sin sugerencias si falla la red
    }
  }

  void _selectSuggestion(GeoSuggestion s) {
    setState(() {
      _lat = s.lat;
      _lng = s.lng;
      _direccionCtrl.text = s.placeName;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startsAt : _endsAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Busca y selecciona una direccion de la lista.');
      return;
    }
    if (!_endsAt.isAfter(_startsAt)) {
      setState(() => _error = 'La fecha de fin debe ser posterior a la de inicio.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = {
        'business_name': _nombre.text.trim(),
        'category': _categoria.text.trim(),
        'description': _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
        'direccion_exacta': _direccionExactaCtrl.text.trim().isEmpty ? null : _direccionExactaCtrl.text.trim(),
        'geom': 'POINT($_lng $_lat)',
        'radius_m': _radius,
        'starts_at': _startsAt.toIso8601String(),
        'ends_at': _endsAt.toIso8601String(),
        'status': _status,
      };
      if (widget.existing != null) {
        await _supabase.from('sponsored_pins').update(payload).eq('id', widget.existing!.id);
      } else {
        final userId = _supabase.auth.currentUser?.id;
        await _supabase.from('sponsored_pins').insert({...payload, 'created_by': userId});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.fondoOscuro,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existing == null ? 'Nuevo negocio patrocinado' : 'Editar negocio',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(labelText: 'Nombre del negocio'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoria (ej. Grifo, Taller, Restaurante)'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _descripcion,
                  decoration: const InputDecoration(labelText: 'Oferta / descripcion (opcional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _direccionCtrl,
                  onChanged: _onAddressChanged,
                  decoration: const InputDecoration(
                    labelText: 'Ubicacion / Coordenadas',
                    helperText: 'Busca y elegi una direccion de la lista',
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111C30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place, size: 18),
                          title: Text(s.placeName, style: const TextStyle(fontSize: 13)),
                          onTap: () => _selectSuggestion(s),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _direccionExactaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Direccion exacta',
                    helperText: 'Numero de local, referencia, etc (la busqueda no siempre lo trae)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<double>(
                  initialValue: _radius,
                  decoration: const InputDecoration(labelText: 'Radio de visibilidad'),
                  items: _radiusOptions
                      .map((r) => DropdownMenuItem(value: r, child: Text('${(r / 1000).toStringAsFixed(0)} km')))
                      .toList(),
                  onChanged: (v) => setState(() => _radius = v ?? _radius),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: true),
                        child: Text('Desde: ${_fmtDate(_startsAt)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text('Hasta: ${_fmtDate(_endsAt)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                  subtitle: const Text('Si esta pausado no aparece en el mapa de nadie'),
                  value: _status == 'active',
                  onChanged: (v) => setState(() => _status = v ? 'active' : 'paused'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.existing == null ? 'Crear pin' : 'Guardar cambios'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
