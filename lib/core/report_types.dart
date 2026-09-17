import 'package:flutter/material.dart';

class ReportTypeInfo {
  final String code;
  final String label;
  final IconData icon;
  final Color color;

  const ReportTypeInfo({
    required this.code,
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Catalogo de tipos de reporte para la UI de Flutter. Debe reflejar los
/// `code` insertados en la tabla `report_types` (supabase/migrations/0001_init.sql,
/// generalizado en 0014_generalize_report_types.sql). Los labels son todos
/// universales -- ninguno menciona una autoridad especifica de un pais
/// (police_pnp/atu_checkpoint originalmente decian "PNP"/"ATU", especificos
/// de Peru, y se generalizaron para que la app tenga sentido en cualquier pais).
const reportTypes = <ReportTypeInfo>[
  ReportTypeInfo(
    code: 'police_pnp',
    label: 'Control policial',
    icon: Icons.local_police,
    color: Color(0xFF1D4ED8),
  ),
  ReportTypeInfo(
    code: 'atu_checkpoint',
    label: 'Fiscalizacion de transito',
    icon: Icons.badge,
    color: Color(0xFFF59E0B),
  ),
  ReportTypeInfo(
    code: 'accident',
    label: 'Accidente',
    icon: Icons.car_crash,
    color: Color(0xFFDC2626),
  ),
  ReportTypeInfo(
    code: 'traffic_jam',
    label: 'Trafico pesado',
    icon: Icons.traffic,
    color: Color(0xFFEA580C),
  ),
  ReportTypeInfo(
    code: 'hazard',
    label: 'Peligro en la via',
    icon: Icons.warning_amber,
    color: Color(0xFFCA8A04),
  ),
  ReportTypeInfo(
    code: 'road_closed',
    label: 'Via cerrada',
    icon: Icons.block,
    color: Color(0xFF64748B),
  ),
  ReportTypeInfo(
    code: 'comment',
    label: 'Comentario',
    icon: Icons.comment,
    color: Color(0xFF0EA5E9),
  ),
];

ReportTypeInfo reportTypeByCode(String code) =>
    reportTypes.firstWhere((r) => r.code == code, orElse: () => reportTypes.last);
