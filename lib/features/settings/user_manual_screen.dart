import 'package:flutter/material.dart';
import '../../core/theme.dart';

class _ManualSection {
  final IconData icon;
  final String title;
  final String body;

  const _ManualSection({required this.icon, required this.title, required this.body});
}

const _sections = <_ManualSection>[
  _ManualSection(
    icon: Icons.touch_app,
    title: 'Tap simple (toque corto)',
    body:
        'Se usa para interactuar con lo que ya esta en el mapa: tocar un reporte '
        'muestra su detalle y los botones de voto, tocar un amigo muestra que esta '
        'compartiendo ubicacion, y tocar una estrella dorada muestra la info de un '
        'negocio patrocinado.',
  ),
  _ManualSection(
    icon: Icons.push_pin,
    title: 'Mantener presionado (tap largo)',
    body:
        'Se usa para colocar un pin en cualquier punto del mapa. Ese pin queda listo '
        'para armar una ruta hacia ahi, guardarla como favorita, o crear un reporte '
        'en ese lugar exacto (los reportes solo se pueden crear hasta 10km de tu '
        'ubicacion real; el ruteo no tiene ese limite).',
  ),
  _ManualSection(
    icon: Icons.add_location_alt,
    title: 'Como crear un reporte',
    body:
        '1. Mantene presionado el punto del mapa donde queres reportar (o dejalo sin '
        'tocar para reportar en tu ubicacion actual).\n'
        '2. Toca el boton azul "Reportar".\n'
        '3. Elegi el tipo (control policial, fiscalizacion de transito, accidente, trafico, '
        'peligro en la via, o via cerrada) y agrega un comentario opcional.\n'
        'Los reportes son siempre anonimos: nadie ve tu nombre, usuario ni correo.',
  ),
  _ManualSection(
    icon: Icons.directions,
    title: 'Como iniciar una ruta',
    body:
        'Busca una direccion en el buscador de arriba, o mantene presionado el '
        'destino directo en el mapa, y toca "Iniciar ruta". La app calcula hasta 3 '
        'rutas y elige la mas recomendada segun el trafico reportado. Mientras '
        'navegas, una voz guiada te avisa cuando hay que girar, igual que Waze.',
  ),
  _ManualSection(
    icon: Icons.alt_route,
    title: 'Como elegir entre rutas alternativas',
    body:
        'Cuando hay mas de una ruta disponible, aparecen chips debajo del mapa con '
        'la duracion de cada una. Toca un chip, o toca directamente la linea gris de '
        'otra ruta en el mapa, para cambiarte a esa alternativa.',
  ),
  _ManualSection(
    icon: Icons.bookmark_add,
    title: 'Como guardar una ruta preferida',
    body:
        'Con un pin colocado en el mapa, toca "Guardar ruta hasta este punto" y '
        'ponele un nombre (ej. "Casa - Trabajo"). Despues la encontras en '
        'Perfil > Mis rutas, para volver a abrirla cuando quieras sin buscarla de nuevo.',
  ),
  _ManualSection(
    icon: Icons.edit,
    title: 'Como cambiar tus preferencias de perfil',
    body:
        'Ve a Perfil > Editar perfil para actualizar tu nombre, apellido, telefono, '
        'direccion, departamento, provincia o distrito. El correo y el usuario no se '
        'pueden cambiar desde ahi.',
  ),
  _ManualSection(
    icon: Icons.list_alt,
    title: 'Como revisar tus reportes hechos',
    body:
        'Ve a Perfil > Mis reportes para ver solo los reportes que vos creaste, '
        'separados de "Reportes activos" (que muestra los de todos los usuarios '
        'dentro de 10km).',
  ),
  _ManualSection(
    icon: Icons.star,
    title: 'Destacar tu negocio en el mapa',
    body:
        'Si tenes un local o comercio y queres que aparezca destacado (con una '
        'estrella dorada, visible para cualquier conductor cerca), escribinos a '
        'cronosfvr@gmail.com para coordinar la publicacion.',
  ),
];

class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual de usuario')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = _sections[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(s.icon, color: AppColors.verde),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(s.body, style: const TextStyle(height: 1.4)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
