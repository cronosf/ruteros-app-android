import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  final String version;
  final String apkUrl;
  final String? notes;

  AppUpdateInfo({required this.version, required this.apkUrl, this.notes});

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        version: json['version'] as String,
        apkUrl: json['apkUrl'] as String,
        notes: json['notes'] as String?,
      );
}

/// Ruteros no esta en Play Store (se distribuye el .apk directo), asi que no
/// hay actualizacion automatica del sistema -- esto la reemplaza con un
/// chequeo propio: al abrir la app se consulta un JSON chiquito hosteado
/// junto al dashboard web en Render (sin costo extra, ya esta desplegado ahi)
/// con la ultima version y el link de descarga (el .apk en si vive en GitHub
/// Releases del repo ruteros-app-android, no en el propio Render, para no
/// inflar ningun repo con binarios de ~90MB en cada release).
class UpdateService {
  static const _versionUrl = 'https://ruteros-web.onrender.com/version.json';

  /// Compara "1.2.10" vs "1.2.9" numero por numero (no como texto, si no
  /// "1.2.10" quedaria "menor" que "1.2.9" al comparar caracter por caracter).
  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final l = local.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (var i = 0; i < r.length || i < l.length; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  /// Devuelve la info de la nueva version si hay una mas nueva que la
  /// instalada, o null si ya estas al dia o el chequeo fallo (sin internet,
  /// Render dormido, etc. -- nunca bloquea el arranque de la app por eso).
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final res = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final info = AppUpdateInfo.fromJson(data);
      final localVersion = (await PackageInfo.fromPlatform()).version;
      return _isNewer(info.version, localVersion) ? info : null;
    } catch (_) {
      return null;
    }
  }
}
