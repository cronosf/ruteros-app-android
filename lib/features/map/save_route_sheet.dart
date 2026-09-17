import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../../core/env.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

typedef SaveRouteResult = ({String nombre, String? direccionExacta, double lat, double lng});

/// Usado tanto para "Guardar ruta" (pin manual) como para "Guardar trayecto"
/// (grabado manejando) -- mismos campos que el editor de saved_routes_screen.dart:
/// nombre, "Ubicacion / Coordenadas" (buscable, por si el pin/GPS no cayo
/// exacto) y "Direccion exacta" (numero de casa/local, que la busqueda no
/// siempre trae). Ambos se precargan con la direccion ya geocodificada del
/// punto, asi el usuario solo tiene que revisarla o agregarle el numero.
Future<SaveRouteResult?> showSaveRouteSheet(
  BuildContext context, {
  required String title,
  required LatLng initialPoint,
  String? initialAddress,
}) {
  return showModalBottomSheet<SaveRouteResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SaveRouteForm(title: title, initialPoint: initialPoint, initialAddress: initialAddress),
  );
}

class _SaveRouteForm extends StatefulWidget {
  final String title;
  final LatLng initialPoint;
  final String? initialAddress;

  const _SaveRouteForm({required this.title, required this.initialPoint, this.initialAddress});

  @override
  State<_SaveRouteForm> createState() => _SaveRouteFormState();
}

class _SaveRouteFormState extends State<_SaveRouteForm> {
  final _nombreCtrl = TextEditingController();
  late final TextEditingController _ubicacionCtrl;
  late final TextEditingController _direccionExactaCtrl;
  late double _lat;
  late double _lng;

  Timer? _searchDebounce;
  List<GeoSuggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _lat = widget.initialPoint.latitude;
    _lng = widget.initialPoint.longitude;
    _ubicacionCtrl = TextEditingController(text: widget.initialAddress ?? '');
    // Arranca igual que la ubicacion geocodificada -- el usuario solo tiene
    // que agregarle el numero de casa/local encima.
    _direccionExactaCtrl = TextEditingController(text: widget.initialAddress ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _ubicacionCtrl.dispose();
    _direccionExactaCtrl.dispose();
    _searchDebounce?.cancel();
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
      _ubicacionCtrl.text = s.placeName;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  void _submit() {
    if (_nombreCtrl.text.trim().isEmpty) return;
    Navigator.of(context).pop((
      nombre: _nombreCtrl.text.trim(),
      direccionExacta: _direccionExactaCtrl.text.trim().isEmpty ? null : _direccionExactaCtrl.text.trim(),
      lat: _lat,
      lng: _lng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // viewInsets.bottom cubre el teclado; padding.bottom cubre la barra de
      // gestos del sistema.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.fondoOscuro,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _nombreCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre (ej. Casa - Trabajo)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ubicacionCtrl,
                onChanged: _onAddressChanged,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Ubicacion / Coordenadas',
                  helperText: 'Busca y elegi otra direccion si esta no es la correcta',
                  helperMaxLines: 2,
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
              TextField(
                controller: _direccionExactaCtrl,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Direccion exacta',
                  helperText: 'Agregale el numero de casa/local: la busqueda no siempre lo trae',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
