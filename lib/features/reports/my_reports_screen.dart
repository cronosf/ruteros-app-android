import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models.dart';
import '../../core/report_types.dart';
import '../../core/theme.dart';

/// A diferencia de "Reportes activos" (todos los reportes a 10km, de
/// cualquiera), esta pantalla es solo la lista de reportes que YO cree --
/// para diferenciar claramente cual lista es cual.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  final _supabase = Supabase.instance.client;
  List<ReportItem> _reports = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _supabase
        .channel('public:ruteros-my-reports')
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
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final data = await _supabase
        .from('reports')
        .select('id, type_code, comment, confirmations, denials, status, created_at, geom')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    if (!mounted) return;
    setState(() {
      _reports = (data as List).map((row) {
        final map = row as Map<String, dynamic>;
        return ReportItem(
          id: map['id'] as String,
          typeCode: map['type_code'] as String,
          lat: 0,
          lng: 0,
          comment: map['comment'] as String?,
          confirmations: map['confirmations'] as int? ?? 0,
          denials: map['denials'] as int? ?? 0,
          createdAt: DateTime.parse(map['created_at'] as String),
        );
      }).toList();
      _loading = false;
    });
  }

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
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis reportes')),
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
                            'Todavia no creaste ningun reporte.',
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
    );
  }
}
