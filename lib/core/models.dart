class GeoSuggestion {
  final String placeName;
  final double lat;
  final double lng;

  GeoSuggestion({required this.placeName, required this.lat, required this.lng});
}

class Profile {
  final String id;
  final String nombres;
  final String apellidos;
  final String? usuario;
  final String? telefono;
  final String email;
  final String? direccion;
  final String pais;
  final String? departamento;
  final String? provincia;
  final String? distrito;
  final String role;

  bool get isAdmin => role == 'admin';

  Profile({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.email,
    required this.pais,
    this.usuario,
    this.telefono,
    this.direccion,
    this.departamento,
    this.provincia,
    this.distrito,
    this.role = 'user',
  });

  /// Iniciales estilo Google (primera letra del nombre + primera del
  /// apellido) para el avatar -- nunca se usa la foto de Google, ni acá ni
  /// para cuentas registradas a mano, para que todos los avatares se vean
  /// consistentes.
  String get initials {
    final n = nombres.trim();
    final a = apellidos.trim();
    final first = n.isNotEmpty ? n[0] : '';
    final last = a.isNotEmpty ? a[0] : '';
    final result = '$first$last'.toUpperCase();
    return result.isEmpty ? '?' : result;
  }

  String get displayName => (usuario != null && usuario!.isNotEmpty) ? '@$usuario' : '$nombres $apellidos';

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        nombres: json['nombres'] as String? ?? '',
        apellidos: json['apellidos'] as String? ?? '',
        usuario: json['usuario'] as String?,
        telefono: json['telefono'] as String?,
        email: json['email'] as String,
        direccion: json['direccion'] as String?,
        pais: json['pais'] as String? ?? 'PE',
        departamento: json['departamento'] as String?,
        provincia: json['provincia'] as String?,
        distrito: json['distrito'] as String?,
        role: json['role'] as String? ?? 'user',
      );
}

class NearbyUser {
  final String userId;
  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  final DateTime updatedAt;

  NearbyUser({
    required this.userId,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    this.heading,
    this.speed,
  });

  factory NearbyUser.fromJson(Map<String, dynamic> json) => NearbyUser(
        userId: json['user_id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        speed: (json['speed'] as num?)?.toDouble(),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class FriendUser {
  final String id;
  final String nombres;
  final String apellidos;
  final String? usuario;

  FriendUser({required this.id, required this.nombres, required this.apellidos, this.usuario});

  /// Se muestra el "usuario" en vez del nombre completo (asi no se expone el
  /// nombre real de nadie mas alla de lo que la persona elija como usuario).
  /// Las cuentas viejas sin usuario todavia caen al nombre completo.
  String get displayName => (usuario != null && usuario!.isNotEmpty) ? '@$usuario' : '$nombres $apellidos';

  factory FriendUser.fromJson(Map<String, dynamic> json) => FriendUser(
        id: json['id'] as String,
        nombres: json['nombres'] as String? ?? '',
        apellidos: json['apellidos'] as String? ?? '',
        usuario: json['usuario'] as String?,
      );
}

class FriendRequest {
  final String userId;
  final String nombres;
  final String apellidos;
  final String? usuario;
  final DateTime createdAt;

  FriendRequest({
    required this.userId,
    required this.nombres,
    required this.apellidos,
    required this.createdAt,
    this.usuario,
  });

  String get displayName => (usuario != null && usuario!.isNotEmpty) ? '@$usuario' : '$nombres $apellidos';

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        userId: json['user_id'] as String,
        nombres: json['nombres'] as String? ?? '',
        apellidos: json['apellidos'] as String? ?? '',
        usuario: json['usuario'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class FriendLocation {
  final String userId;
  final String nombres;
  final String? usuario;
  final double lat;
  final double lng;
  final DateTime updatedAt;

  FriendLocation({
    required this.userId,
    required this.nombres,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    this.usuario,
  });

  String get displayName => (usuario != null && usuario!.isNotEmpty) ? '@$usuario' : nombres;

  factory FriendLocation.fromJson(Map<String, dynamic> json) => FriendLocation(
        userId: json['user_id'] as String,
        nombres: json['nombres'] as String? ?? '',
        usuario: json['usuario'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class SavedRoute {
  final String id;
  final String nombre;
  final double origenLat;
  final double origenLng;
  final double destinoLat;
  final double destinoLng;
  final double? distanceMeters;
  final int? durationSeconds;
  final bool recorded;
  final String? direccionExacta;

  SavedRoute({
    required this.id,
    required this.nombre,
    required this.origenLat,
    required this.origenLng,
    required this.destinoLat,
    required this.destinoLng,
    this.distanceMeters,
    this.durationSeconds,
    this.recorded = false,
    this.direccionExacta,
  });

  String? get distanceLabel {
    final d = distanceMeters;
    if (d == null) return null;
    return d >= 1000 ? '${(d / 1000).toStringAsFixed(1)} km' : '${d.round()} m';
  }

  String? get durationLabel {
    final s = durationSeconds;
    if (s == null) return null;
    final minutes = (s / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return '${hours}h ${rest}min';
  }

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        origenLat: (json['origen_lat'] as num).toDouble(),
        origenLng: (json['origen_lng'] as num).toDouble(),
        destinoLat: (json['destino_lat'] as num).toDouble(),
        destinoLng: (json['destino_lng'] as num).toDouble(),
        distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        recorded: json['recorded'] as bool? ?? false,
        direccionExacta: json['direccion_exacta'] as String?,
      );
}

class ReportItem {
  final String id;
  final String typeCode;
  final double lat;
  final double lng;
  final String? comment;
  final int confirmations;
  final int denials;
  final DateTime createdAt;

  ReportItem({
    required this.id,
    required this.typeCode,
    required this.lat,
    required this.lng,
    required this.confirmations,
    required this.denials,
    required this.createdAt,
    this.comment,
  });

  factory ReportItem.fromJson(Map<String, dynamic> json) => ReportItem(
        id: json['id'] as String,
        typeCode: json['type_code'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        comment: json['comment'] as String?,
        confirmations: json['confirmations'] as int? ?? 0,
        denials: json['denials'] as int? ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Pin de negocio patrocinado (ver migracion 0012): a diferencia de
/// ReportItem, no lo crea un conductor -- lo administra un admin desde
/// ManageBusinessPinsScreen, y se ve en el mapa de cualquiera dentro del
/// radio que ese negocio compro.
class SponsoredPin {
  final String id;
  final String businessName;
  final String category;
  final String? description;
  final double lat;
  final double lng;
  final String? logoUrl;

  SponsoredPin({
    required this.id,
    required this.businessName,
    required this.category,
    required this.lat,
    required this.lng,
    this.description,
    this.logoUrl,
  });

  factory SponsoredPin.fromJson(Map<String, dynamic> json) => SponsoredPin(
        id: json['id'] as String,
        businessName: json['business_name'] as String,
        category: json['category'] as String,
        description: json['description'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        logoUrl: json['logo_url'] as String?,
      );
}

/// Fila completa (incluye estado/fechas/radio) para la pantalla de gestion
/// del admin -- nearby_sponsored_pins (arriba) no expone esos campos porque
/// un conductor comun no los necesita.
class SponsoredPinAdmin {
  final String id;
  final String businessName;
  final String category;
  final String? description;
  final String? direccionExacta;
  final double lat;
  final double lng;
  final double radiusM;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;

  SponsoredPinAdmin({
    required this.id,
    required this.businessName,
    required this.category,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.description,
    this.direccionExacta,
  });

  factory SponsoredPinAdmin.fromJson(Map<String, dynamic> json) => SponsoredPinAdmin(
        id: json['id'] as String,
        businessName: json['business_name'] as String,
        category: json['category'] as String,
        description: json['description'] as String?,
        direccionExacta: json['direccion_exacta'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        radiusM: (json['radius_m'] as num).toDouble(),
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        status: json['status'] as String,
      );
}
