import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models.dart';
import '../../core/report_types.dart';
import '../../core/theme.dart';
import '../map/report_sheet.dart';

const _limaLat = -12.0464;
const _limaLng = -77.0428;
const _searchRadiusMeters = 10000.0; // 10km

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  final _supabase = Supabase.instance.client;
  List<ReportItem> _reports = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    // Sin esto la lista solo se cargaba una vez al abrir la app: como las
    // pestanas quedan montadas a la vez (IndexedStack en RootShell), un
    // reporte nuevo creado desde el Mapa nunca aparecia aca sin pull-to-refresh.
    _channel = _supabase
        .channel('public:ruteros-reports-list')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    double lat = _limaLat;
    double lng = _limaLng;
    try {
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 5));
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      // Sin permiso o timeout: se usa el centro de Lima como respaldo.
    }

    // "Reportes activos" = todos los reportes de cualquier usuario dentro de
    // 10km (no solo los mios) -- los propios se revisan aparte en Perfil ->
    // Mis reportes, para no confundir ambas listas.
    final data = await _supabase.rpc('nearby_reports', params: {
      'lat': lat,
      'lng': lng,
      'radius_m': _searchRadiusMeters,
    });
    if (!mounted) return;
    setState(() {
      _reports = (data as List).map((e) => ReportItem.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _vote(String reportId, String vote) async {
    await _supabase.rpc('vote_report', params: {'p_report_id': reportId, 'p_vote': vote});
    _load();
  }

  // Los reportes son anonimos (no se guarda ni se muestra quien reporto):
  // el modal solo tiene el tipo, el comentario opcional y los votos.
  Future<void> _showDetail(ReportItem r) async {
    final info = reportTypeByCode(r.typeCode);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(info.icon, color: info.color),
            const SizedBox(width: 8),
            Expanded(child: Text(info.label)),
          ],
        ),
        content: Text(r.comment ?? 'Sin comentario adicional.'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _vote(r.id, 'deny');
            },
            icon: const Icon(Icons.thumb_down, color: Colors.redAccent, size: 18),
            label: const Text('Ya no esta'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _vote(r.id, 'confirm');
            },
            icon: const Icon(Icons.thumb_up, size: 18),
            label: const Text('Sigue ahi'),
          ),
        ],
      ),
    );
  }

  Future<void> _createReport() async {
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 5));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener tu ubicacion actual.')),
      );
      return;
    }
    if (!mounted) return;
    await showReportSheet(context, (typeCode, comment) async {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('reports').insert({
        'user_id': userId,
        'type_code': typeCode,
        'geom': 'POINT(${pos!.longitude} ${pos.latitude})',
        'comment': comment,
      });
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes activos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _reports.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No hay reportes activos a menos de 10km de tu ubicacion.',
                            style: TextStyle(color: AppColors.grisUI),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _reports.length,
                      itemBuilder: (context, i) {
                        final r = _reports[i];
                        final info = reportTypeByCode(r.typeCode);
                        // Solo tipo + votos en la fila -- el comentario (si lo
                        // hay) queda en el modal, para que la lista no se vea
                        // desprolija con textos largos de distinto tamano.
                        return Card(
                          child: ListTile(
                            leading: Icon(info.icon, color: info.color),
                            title: Text(info.label),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.thumb_up, size: 16, color: AppColors.verde),
                                const SizedBox(width: 4),
                                Text('${r.confirmations}'),
                                const SizedBox(width: 12),
                                const Icon(Icons.thumb_down, size: 16, color: Colors.redAccent),
                                const SizedBox(width: 4),
                                Text('${r.denials}'),
                              ],
                            ),
                            onTap: () => _showDetail(r),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createReport,
        child: const Icon(Icons.add_location_alt),
      ),
    );
  }
}
