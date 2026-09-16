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
  final String? telefono;
  final String email;
  final String? direccion;
  final String pais;
  final String? departamento;
  final String? provincia;
  final String? distrito;

  Profile({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.email,
    required this.pais,
    this.telefono,
    this.direccion,
    this.departamento,
    this.provincia,
    this.distrito,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        nombres: json['nombres'] as String? ?? '',
        apellidos: json['apellidos'] as String? ?? '',
        telefono: json['telefono'] as String?,
        email: json['email'] as String,
        direccion: json['direccion'] as String?,
        pais: json['pais'] as String? ?? 'PE',
        departamento: json['departamento'] as String?,
        provincia: json['provincia'] as String?,
        distrito: json['distrito'] as String?,
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

  FriendUser({required this.id, required this.nombres, required this.apellidos});

  factory FriendUser.fromJson(Map<String, dynamic> json) => FriendUser(
        id: json['id'] as String,
        nombres: json['nombres'] as String? ?? '',
        apellidos: json['apellidos'] as String? ?? '',
      );
}

class FriendRequest {
  final String userId;
  final String nombres;
  final String apellidos;
  final DateTime createdAt;

  FriendRequest({
    required this.userId,
    required this.nombres,
    required this.apellidos,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        userId: json['user_id'] as String,
        nombres: json['nombres'] as String? ?? '',
        apellidos: json['apellidos'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class FriendLocation {
  final String userId;
  final String nombres;
  final double lat;
  final double lng;
  final DateTime updatedAt;

  FriendLocation({
    required this.userId,
    required this.nombres,
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  factory FriendLocation.fromJson(Map<String, dynamic> json) => FriendLocation(
        userId: json['user_id'] as String,
        nombres: json['nombres'] as String? ?? '',
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

  SavedRoute({
    required this.id,
    required this.nombre,
    required this.origenLat,
    required this.origenLng,
    required this.destinoLat,
    required this.destinoLng,
  });

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        origenLat: (json['origen_lat'] as num).toDouble(),
        origenLng: (json['origen_lng'] as num).toDouble(),
        destinoLat: (json['destino_lat'] as num).toDouble(),
        destinoLng: (json['destino_lng'] as num).toDouble(),
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
