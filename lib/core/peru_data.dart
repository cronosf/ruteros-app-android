const peruDepartamentos = [
  'Amazonas', 'Ancash', 'Apurimac', 'Arequipa', 'Ayacucho', 'Cajamarca',
  'Callao', 'Cusco', 'Huancavelica', 'Huanuco', 'Ica', 'Junin',
  'La Libertad', 'Lambayeque', 'Lima', 'Loreto', 'Madre de Dios',
  'Moquegua', 'Pasco', 'Piura', 'Puno', 'San Martin', 'Tacna',
  'Tumbes', 'Ucayali',
];

class PaisOption {
  final String code;
  final String label;

  const PaisOption(this.code, this.label);
}

/// Ruteros arranco enfocado en Peru (por eso el dropdown fijo de
/// departamentos arriba), pero cualquiera puede instalar la app fuera de
/// Peru -- este catalogo deja elegir el pais real en el registro/perfil en
/// vez de forzar 'PE' siempre. Cuando el pais no es Peru, el campo
/// "departamento" pasa a texto libre (ver register_screen.dart /
/// edit_profile_screen.dart) porque "departamento" ni siquiera es el
/// termino correcto en la mayoria de estos paises (estado, provincia, etc).
const paises = <PaisOption>[
  PaisOption('PE', 'Peru'),
  PaisOption('AR', 'Argentina'),
  PaisOption('BO', 'Bolivia'),
  PaisOption('BR', 'Brasil'),
  PaisOption('CL', 'Chile'),
  PaisOption('CO', 'Colombia'),
  PaisOption('CR', 'Costa Rica'),
  PaisOption('CU', 'Cuba'),
  PaisOption('DO', 'Republica Dominicana'),
  PaisOption('EC', 'Ecuador'),
  PaisOption('SV', 'El Salvador'),
  PaisOption('ES', 'Espana'),
  PaisOption('GT', 'Guatemala'),
  PaisOption('HN', 'Honduras'),
  PaisOption('MX', 'Mexico'),
  PaisOption('NI', 'Nicaragua'),
  PaisOption('PA', 'Panama'),
  PaisOption('PY', 'Paraguay'),
  PaisOption('US', 'Estados Unidos'),
  PaisOption('UY', 'Uruguay'),
  PaisOption('VE', 'Venezuela'),
];
