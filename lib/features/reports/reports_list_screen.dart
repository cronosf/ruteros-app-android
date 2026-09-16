import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models.dart';
import '../../core/report_types.dart';
import '../../core/theme.dart';
import '../map/report_sheet.dart';

const _limaLat = -12.0464;
const _limaLng = -77.0428;
const _searchRadiusMeters = 8000.0;

class ReportsListScreen extends StatefulWidget {
  const ReportsListScreen({super.key});

  @override
  State<ReportsListScreen> createState() => _ReportsListScreenState();
}

class _ReportsListScreenState extends State<ReportsListScreen> {
  final _supabase = Supabase.instance.client;
  List<ReportItem> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
                            'No hay reportes activos cerca de tu ubicacion.',
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
                        return Card(
                          child: ListTile(
                            leading: Icon(info.icon, color: info.color),
                            title: Text(info.label),
                            subtitle: r.comment != null ? Text(r.comment!) : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.thumb_up, size: 18, color: AppColors.verde),
                                  onPressed: () => _vote(r.id, 'confirm'),
                                ),
                                Text('${r.confirmations}'),
                                IconButton(
                                  icon: const Icon(Icons.thumb_down, size: 18, color: Colors.redAccent),
                                  onPressed: () => _vote(r.id, 'deny'),
                                ),
                                Text('${r.denials}'),
                              ],
                            ),
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
