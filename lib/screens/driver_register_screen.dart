import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

import '../main.dart';
import '../widgets/bus_ui.dart';
import 'solicitud_revision_screen.dart';

class PantallaRegistroConductor extends StatefulWidget {
  const PantallaRegistroConductor({super.key, this.reenviar = false});

  /// `true` cuando el conductor llega desde una solicitud rechazada: el
  /// formulario se precarga con su ficha y conserva los adjuntos que ya estaban
  /// en el servidor, para que solo corrija lo que el administrador señaló.
  final bool reenviar;

  @override
  State<PantallaRegistroConductor> createState() =>
      _PantallaRegistroConductorState();
}

class _PantallaRegistroConductorState extends State<PantallaRegistroConductor> {
  /// Títulos de los tiles de adjuntos. Los tres primeros son obligatorios y
  /// sus títulos son la clave de [_pendientesDeAdjuntar], así que no se
  /// escriben como literales sueltos en las dos páginas.
  static const String _kDocSelfie = 'Foto Selfie (Verificación)';
  static const String _kDocCedula = 'Foto de la Cédula';
  static const String _kDocLicencia = 'Licencia de Conducción';
  static const String _kDocSoat = 'SOAT Vigente';
  static const String _kDocTecnomecanica = 'Revisión Tecnomecánica';

  /// "a", "a y b", "a, b y c": une la lista para los mensajes de SnackBar.
  static String _enumerar(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }

  /// El formulario se parte en dos páginas (0 = datos personales y selfie,
  /// 1 = vehículo y documentos legales). Cada página tiene su propio
  /// `FormState` para poder validar solo lo que se ve, pero ambas permanecen
  /// montadas en un `IndexedStack`: así los campos conservan su texto y su
  /// error al cambiar de página.
  ///
  /// La validación final vuelve a pasar por la página 1 (aunque ya se haya
  /// pasado) porque el usuario puede volver atrás, dejarla inválida e
  /// regresar aquí por otro camino.
  int _paginaActual = 0;
  final _formKeyPagina1 = GlobalKey<FormState>();
  final _formKeyPagina2 = GlobalKey<FormState>();

  final _nombreController = TextEditingController();
  final _apellidoController = TextEditingController();
  final _numDocController = TextEditingController();
  String _tipoDocumento = 'Cédula de Ciudadanía';

  final _placaController = TextEditingController();
  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _anioController = TextEditingController();
  final _telefonoController = TextEditingController();

  /// Archivo elegido por tile, indexado por el título del documento. Se guarda
  /// el `PlatformFile` completo, no solo el nombre, porque al enviar hay que
  /// subir el binario a Storage; el nombre de cada tile sale de aquí.
  final Map<String, PlatformFile> _archivos = <String, PlatformFile>{};

  /// Adjuntos que ya están en `solicitudes/{uid}/adjuntos` y en la ficha.
  /// Indexados por título del tile: `{name, slug, isPdf}`. Al reenviar una
  /// solicitud rechazada no hay que volver a subirlos; solo se reemplazan los
  /// que el conductor elija de nuevo.
  final Map<String, Map<String, dynamic>> _documentosPrevios =
      <String, Map<String, dynamic>>{};

  String? _nombreDoc(String titulo) {
    final PlatformFile? nuevo = _archivos[titulo];
    if (nuevo != null) return nuevo.name;
    return _documentosPrevios[titulo]?['name']?.toString();
  }

  String? get _nombreSelfie => _nombreDoc(_kDocSelfie);
  String? get _nombreCedula => _nombreDoc(_kDocCedula);
  String? get _nombreLicencia => _nombreDoc(_kDocLicencia);
  String? get _nombreSoat => _nombreDoc(_kDocSoat);
  String? get _nombreTecnomecanica => _nombreDoc(_kDocTecnomecanica);

  /// Títulos de los adjuntos obligatorios que faltaron en el último intento
  /// de envío. Se usan como clave (el título es único por tile) y se quitan
  /// del conjunto al adjuntar el archivo. Permite resaltar en rojo el
  /// documento exacto que falta en vez de un mensaje genérico.
  final Set<String> _pendientesDeAdjuntar = <String>{};

  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    if (widget.reenviar) _precargarSolicitud();
  }

  /// Rellena el formulario con la ficha que ya existe y recuerda los adjuntos
  /// del servidor. Sin esto, corregir una solicitud rechazada obligaba a
  /// escribir todo de nuevo y a volver a subir los cinco documentos.
  Future<void> _precargarSolicitud() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      if (!doc.exists || !mounted) return;
      final Map<String, dynamic> datos =
          (doc.data() as Map<String, dynamic>?) ?? <String, dynamic>{};

      final String completo =
          (datos['fullName'] ?? '').toString().trim();
      final List<String> partes = completo
          .split(RegExp(r'\s+'))
          .where((String p) => p.isNotEmpty)
          .toList();
      String nombre = '';
      String apellido = '';
      if (partes.length == 1) {
        nombre = partes.first;
      } else if (partes.length >= 2) {
        // La ficha guarda un solo `fullName`; se reparte por la mitad para no
        // dejar el apellido vacío (2 palabras -> 1/1, 4 -> 2/2).
        final int corte = (partes.length / 2).ceil();
        nombre = partes.sublist(0, corte).join(' ');
        apellido = partes.sublist(corte).join(' ');
      }

      final String tipo = (datos['docType'] ?? '').toString();
      final Map<String, dynamic> documentos =
          datos['documents'] is Map<String, dynamic>
              ? datos['documents'] as Map<String, dynamic>
              : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _nombreController.text = nombre;
        _apellidoController.text = apellido;
        _numDocController.text = (datos['docNumber'] ?? '').toString();
        _telefonoController.text = (datos['phone'] ?? '').toString();
        _placaController.text = (datos['busPlate'] ?? '').toString();
        _marcaController.text = (datos['busBrand'] ?? '').toString();
        _modeloController.text = (datos['busModel'] ?? '').toString();
        _anioController.text = (datos['busYear'] ?? '').toString();
        if (tipo == 'Cédula de Ciudadanía' ||
            tipo == 'Cédula de Extranjería' ||
            tipo == 'Pasaporte') {
          _tipoDocumento = tipo;
        }
        _documentosPrevios
          ..clear()
          ..addAll(<String, Map<String, dynamic>>{
            for (final MapEntry<String, dynamic> entrada
                in documentos.entries)
              if (entrada.value is Map)
                entrada.key: Map<String, dynamic>.from(
                  entrada.value as Map,
                ),
          });
      });
    } catch (e) {
      debugPrint('Registro conductor: no se pudo precargar la ficha: $e');
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _apellidoController.dispose();
    _numDocController.dispose();
    _placaController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _telefonoController.dispose();
    super.dispose();
  }

  /// Pide acceso a las fotos para poder leer las que el conductor adjunta.
  ///
  /// Importante: esto **no** decide si se puede abrir el selector. El selector
  /// de archivos de Android (SAF) no necesita ningún permiso, porque el sistema
  /// es quien elige el archivo. Por eso un permiso denegado solo avisa y deja
  /// seguir: bloquear aquí dejaba al conductor sin poder adjuntar nada por
  /// haber dicho "no" a algo que de verdad no necesitaba.
  ///
  /// `Permission.camera` no se pide a propósito: la cámara se abre de forma
  /// delegada desde el selector, sin permiso. Y declararla en el manifiesto la
  /// volvería obligatoria.
  Future<bool> _solicitarPermisosDispositivo() async {
    if (!kIsWeb &&
        (Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS)) {
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.photos,
      ].request();

      final PermissionStatus estado =
          statuses[Permission.photos] ?? PermissionStatus.denied;

      if (!estado.isGranted && !estado.isLimited && mounted) {
        // Denegado para siempre: volver a pedir no hace nada, hay que ir a
        // Ajustes. Merece la pena decirlo, o el conductor lo intenta mil veces.
        final bool abrirAjustes = estado.isPermanentlyDenied;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              abrirAjustes
                  ? 'Acceso a fotos bloqueado. Actívalo en Ajustes del sistema; '
                        'mientras tanto puedes elegir el archivo igual.'
                  : 'Sin acceso a fotos. Puedes elegir el archivo desde el '
                        'selector de todas formas.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 5),
            action: abrirAjustes
                ? SnackBarAction(
                    label: 'Ajustes',
                    textColor: Colors.white,
                    onPressed: openAppSettings,
                  )
                : null,
          ),
        );
      }
    }
    return true;
  }

  /// Abre el selector de archivos. [tituloDocumento] es la clave del tile que
  /// se está llenando: al guardar el archivo se quita de
  /// [_pendientesDeAdjuntar] para que deje de mostrarse en rojo.
  ///
  /// `withData: true` es deliberado: deja los bytes en memoria para poder
  /// subirlos a Storage al enviar, en lugar de releerlos del disco. Así el
  /// código funciona igual en web (donde no hay ruta de archivo) y en Android,
  /// sin importar `dart:io`.
  Future<void> _seleccionarArchivo(
    ValueChanged<PlatformFile> onArchivoSeleccionado, {
    required String tituloDocumento,
  }) async {
    bool tienePermiso = await _solicitarPermisosDispositivo();
    if (!tienePermiso || !mounted) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );

      if (result != null && mounted) {
        final PlatformFile archivo = result.files.single;
        if (archivo.bytes == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo leer el archivo. Elígelo de nuevo.'),
              backgroundColor: AppColors.danger,
            ),
          );
          return;
        }
        onArchivoSeleccionado(archivo);
        setState(() => _pendientesDeAdjuntar.remove(tituloDocumento));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Archivo adjuntado: ${archivo.name}'),
              backgroundColor: AppColors.ink,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error al seleccionar archivo: $e');
      }
    }
  }

  /// Cambia de página y cierra el teclado. No hay `setState` si la página
  /// pedida ya es la visible, para no reconstruir los campos sin motivo.
  void _irAPagina(int pagina) {
    FocusScope.of(context).unfocus();
    if (_paginaActual == pagina) return;
    setState(() => _paginaActual = pagina);
  }

  /// Avanza a la página 2 solo si la página 1 quedó válida; si no, los campos
  /// con error se quedan a la vista y el `Form` los marca en rojo.
  void _continuar() {
    if (_formKeyPagina1.currentState?.validate() ?? false) {
      _irAPagina(1);
    }
  }

  /// Escribe la solicitud en `usuarios/{uid}` con `role: 'driver'` e
  /// `isApproved: false`, que es exactamente lo que filtra la cola del panel
  /// administrativo. Las reglas de `firestore.rules` permiten crear el
  /// documento solo si es el propio usuario, con uno de los dos roles válidos y
  /// sin auto-aprobarse.
  Future<void> _enviarRegistro() async {
    // Vuelve a validar la página 1: el usuario pudo regresarla, limpiarla e
    // incompleta, así que no basta con la validación del botón Continuar.
    final bool pagina1Valida = _formKeyPagina1.currentState?.validate() ?? true;
    final bool pagina2Valida =
        _formKeyPagina2.currentState?.validate() ?? false;

    if (!pagina1Valida || !pagina2Valida) {
      if (!pagina1Valida) _irAPagina(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pagina1Valida
                ? 'Revisa los datos del vehículo y los documentos.'
                : 'Revisa los datos personales antes de enviar.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // Adjuntos obligatorios: se resaltan en rojo los que falten y se lleva al
    // usuario a la página donde están, no siempre a la primera.
    final List<String> faltantes = <String>[
      if (_nombreSelfie == null) _kDocSelfie,
      if (_nombreCedula == null) _kDocCedula,
      if (_nombreLicencia == null) _kDocLicencia,
    ];

    if (faltantes.isNotEmpty) {
      setState(() {
        _pendientesDeAdjuntar
          ..clear()
          ..addAll(faltantes);
      });
      if (_nombreSelfie == null) _irAPagina(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Adjunta ${_enumerar(faltantes)} para enviar el registro.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _enviando = true);

    // Sin sesión no hay uid, y `usuarios/{uid}` es la única clave que usa el
    // panel administrativo para aprobar al conductor.
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión para enviar tu registro.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    try {
      // Primero los binarios: si algún adjunto no se guarda, la solicitud no
      // se escribe y el conductor puede reintentar sin dejar una ficha que
      // apunte a fotos inexistentes.
      final Map<String, dynamic> adjuntos = await _guardarAdjuntos(user.uid);

      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set(<
        String,
        dynamic
      >{
        'uid': user.uid,
        'email': user.email,
        'fullName':
            '${_nombreController.text.trim()} ${_apellidoController.text.trim()}',
        'docType': _tipoDocumento,
        'docNumber': _numDocController.text.trim(),
        'phone': _telefonoController.text.trim(),
        'busPlate': _placaController.text.trim().toUpperCase(),
        'busBrand': _marcaController.text.trim(),
        'busModel': _modeloController.text.trim(),
        'busYear': _anioController.text.trim(),
        'documents': adjuntos,
        'role': 'driver',
        'isApproved': false,
        // El reenvío deja la solicitud otra vez en la cola de pendientes y
        // borra el motivo del rechazo anterior. `createdAt` solo se escribe en
        // el alta: con `merge` a `true`, omitirlo en un reenvío conserva la
        // fecha original.
        'estadoSolicitud': 'pendiente',
        'motivoRechazo': FieldValue.delete(),
        if (!widget.reenviar) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _enviando = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const PantallaSolicitudRevision(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'auth/network-request-failed'
                ? 'Sin conexión. Revisa tu internet e inténtalo otra vez.'
                : 'Tu sesión venció. Cierra sesión e ingrésala de nuevo.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeDeErrorDeFirestore(e)),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo enviar el registro. Inténtalo otra vez.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// Guarda cada adjunto como su propio documento en
  /// `solicitudes/{uid}/{slug}` y devuelve el mapa que se guarda en la ficha
  /// del conductor: `{título del tile: {name, slug}}`. El panel administrativo
  /// lee esos documentos para mostrar las fotos.
  ///
  /// Un documento por archivo y no uno solo con todo, porque Firestore admite
  /// 1 MiB por documento: una foto de celular sin comprimir pesa 3 o 4 MiB, así
  /// que hay que reducirla antes ([_comprimir]).
  Future<Map<String, dynamic>> _guardarAdjuntos(String uid) async {
    // Se parte de los adjuntos que ya están en el servidor: al reenviar una
    // solicitud rechazada, los documentos que el conductor no reemplace siguen
    // enlazados y no tiene que volver a subirlos.
    final Map<String, dynamic> resultado = <String, dynamic>{
      for (final MapEntry<String, Map<String, dynamic>> previo
          in _documentosPrevios.entries)
        previo.key: previo.value,
    };
    final CollectionReference<Map<String, dynamic>> coleccion =
        FirebaseFirestore.instance
            .collection('solicitudes')
            .doc(uid)
            .collection('adjuntos');

    for (final MapEntry<String, PlatformFile> entrada in _archivos.entries) {
      final Uint8List? original = entrada.value.bytes;
      if (original == null) {
        throw FirebaseException(
          plugin: 'firestore',
          code: 'unknown',
          message: 'No se pudo leer ${entrada.value.name}.',
        );
      }

      final bool esPdf = _extensionDe(entrada.value.name) == 'pdf';
      // Un PDF no se puede recomprimir como imagen, así que se guarda tal cual
      // si cabe; si no, el error dice cuál es el problema.
      final Uint8List bytes = esPdf ? original : await _comprimir(original);

      if (bytes.length > _kMaxBytesPorDocumento) {
        throw FirebaseException(
          plugin: 'firestore',
          code: 'document-too-large',
          message:
              '${entrada.value.name} pesa ${(bytes.length / 1024).round()} KB.',
        );
      }

      final String slug = _slugDe(entrada.key);
      await coleccion.doc(slug).set(<String, dynamic>{
        'name': entrada.value.name,
        'isPdf': esPdf,
        'size': bytes.length,
        // `Blob` y no el `Uint8List` pelado: es la representación que espera
        // Firestore para un campo de bytes. Un `Uint8List` es un `Iterable` de
        // enteros, así que en web el encoder lo guardaría como un array JSON de
        // números (unas 150 mil entradas por foto) y al leerlo volvería un
        // `JSArray` que no se puede pintar. Con `Blob` se guarda como bytes de
        // verdad y vuelve como `Blob`, igual en web y en Android.
        'data': Blob(bytes),
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      resultado[entrada.key] = <String, dynamic>{
        'name': entrada.value.name,
        'slug': slug,
        'isPdf': esPdf,
      };
    }

    return resultado;
  }

  /// Reduce la imagen hasta que pese menos de [_kMaxBytesPorDocumento]. Una
  /// foto de 4000 px de un celular baja a unos 150 KB con 1280 px y calidad 75,
  /// que es más que suficiente para que el admin identifique al conductor y el
  /// documento.
  ///
  /// Va en [compute] para no congelar la interfaz mientras se procesa: en web no
  /// hay isolate y se ejecuta en el hilo principal, pero el trabajo es el mismo.
  Future<Uint8List> _comprimir(Uint8List original) async {
    return compute(_reducirImagen, original);
  }

  /// Límite duro de Firestore: 1 MiB por documento, redondeado hacia abajo para
  /// no quedar justo en el borde y comerse un rechazo del servidor.
  static const int _kMaxBytesPorDocumento = 900 * 1024;
  static const int _kLadoMaximo = 1280;
  static const int _kCalidadJpeg = 75;

  /// Se ejecuta en el isolate de [compute], así que solo puede usar tipos
  /// simples: recibe y devuelve `Uint8List`.
  static Uint8List _reducirImagen(Uint8List original) {
    final img.Image? imagen = img.decodeImage(original);
    if (imagen == null) {
      throw FirebaseException(
        plugin: 'firestore',
        code: 'unknown',
        message: 'El archivo no es una imagen válida.',
      );
    }

    // Se reduce por el lado más largo: una foto vertical de celular viene en
    // 3:4 o 9:16 y no interesa mantener la proporción, solo que se lea.
    img.Image salida = imagen;
    final int ladoMayor = imagen.width > imagen.height
        ? imagen.width
        : imagen.height;
    if (ladoMayor > _kLadoMaximo) {
      if (imagen.width >= imagen.height) {
        salida = img.copyResize(
          imagen,
          width: _kLadoMaximo,
          interpolation: img.Interpolation.average,
        );
      } else {
        salida = img.copyResize(
          imagen,
          height: _kLadoMaximo,
          interpolation: img.Interpolation.average,
        );
      }
    }

    final Uint8List jpeg = img.encodeJpg(salida, quality: _kCalidadJpeg);
    // JPEG siempre sale más chico que el original decodificado, pero por si
    // acaso se devuelve el que cumple.
    return jpeg.length < original.length ? jpeg : original;
  }

  /// "Foto de la Cédula" → `cedula`. Los títulos de los tiles son la clave del
  /// mapa, pero tienen acentos, espacios y paréntesis: el id del documento
  /// tiene que ser limpio.
  String _slugDe(String titulo) {
    switch (titulo) {
      case _kDocSelfie:
        return 'selfie';
      case _kDocCedula:
        return 'cedula';
      case _kDocLicencia:
        return 'licencia';
      case _kDocSoat:
        return 'soat';
      case _kDocTecnomecanica:
        return 'tecnomecanica';
      default:
        return 'documento';
    }
  }

  String _extensionDe(String nombreArchivo) {
    final int punto = nombreArchivo.lastIndexOf('.');
    if (punto < 0 || punto == nombreArchivo.length - 1) return 'bin';
    return nombreArchivo.substring(punto + 1).toLowerCase();
  }

  /// `FirebaseException` es la clase padre de `FirebaseAuthException` y también
  /// de los errores de Firestore, así que estos mensajes llegan también los de
  /// autenticación: cada código se traduce a algo accionable.
  String _mensajeDeErrorDeFirestore(FirebaseException e) {
    switch (e.code) {
      case 'document-too-large':
        return '${e.message} supera el máximo de 900 KB. '
            'Vuelve a tomar la foto más cerca del documento o comprímela.';
      case 'permission-denied':
        return 'Tu cuenta no tiene permisos para enviar esta solicitud. '
            'Si ya te habías registrado antes, no puedes crear un segundo perfil '
            'con el mismo correo.';
      case 'unavailable':
        return 'No pudimos guardar los documentos. Revisa tu internet.';
      case 'failed-precondition':
        return 'Firestore respondió con un error de configuración del proyecto. '
            'Revisa las reglas y el índice compuesto.';
      default:
        return 'No se pudo enviar el registro (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildEncabezado(context),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Column(
                        children: [
                          _buildIndicadorPasos(),
                          // `IndexedStack` en vez de un `switch`: las dos
                          // páginas quedan montadas y cada una conserva su
                          // `FormState`, el texto escrito y el error mostrado al
                          // volver atrás.
                          Expanded(
                            child: IndexedStack(
                              index: _paginaActual,
                              children: [
                                Form(
                                  key: _formKeyPagina1,
                                  child: ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      0,
                                      0,
                                      20,
                                    ),
                                    children: _buildContenidoPagina1(),
                                  ),
                                ),
                                Form(
                                  key: _formKeyPagina2,
                                  child: ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      0,
                                      0,
                                      20,
                                    ),
                                    children: _buildContenidoPagina2(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Encabezado amarillo. En la página 2 la flecha vuelve a la página 1 en vez
  /// de salir del formulario: al haber solo dos pasos, atrás dentro del flujo
  /// es lo que se espera.
  Widget _buildEncabezado(BuildContext context) {
    return BusHeader(
      title: 'Registro de Conductor',
      subtitle: _paginaActual == 0
          ? 'Paso 1 de 2 · Datos personales y selfie'
          : 'Paso 2 de 2 · Vehículo y documentos',
      titleSize: 21,
      fullBleed: true,
      leading: BusIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => _paginaActual == 1
            ? _irAPagina(0)
            : Navigator.of(context).maybePop(),
      ),
      trailing: const BusIconBadge(
        icon: Icons.badge_rounded,
        size: 46,
        color: Colors.white,
      ),
    );
  }

  /// Indicador de progreso: dos fichas separadas por una flecha; la del paso
  /// actual va resaltada en amarillo y la otra atenuada.
  Widget _buildIndicadorPasos() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: _buildFichaPaso(
              Icons.looks_one,
              'Datos personales y selfie',
              0,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.keyboard_arrow_right,
              color: AppColors.textMuted,
              size: 24,
            ),
          ),
          Expanded(
            child: _buildFichaPaso(Icons.looks_two, 'Vehículo y documentos', 1),
          ),
        ],
      ),
    );
  }

  Widget _buildFichaPaso(IconData icono, String titulo, int indice) {
    final bool activo = _paginaActual == indice;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: activo ? 1 : 0.75,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: activo ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: activo
              ? const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icono,
              color: activo ? AppColors.primary : AppColors.textMuted,
              size: 20,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                  height: 1.15,
                  color: activo ? Colors.white : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Página 1: datos personales y verificación biométrica, dentro de la
  /// tarjeta blanca de la maqueta.
  List<Widget> _buildContenidoPagina1() {
    return [
      _buildTarjeta([
        _buildEncabezadoSeccion('1. Datos Personales'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nombreController,
          decoration: _decoracionCampo('Nombres Completos', Icons.person),
          validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _apellidoController,
          decoration: _decoracionCampo(
            'Apellidos Completos',
            Icons.person_sharp,
          ),
          validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _tipoDocumento,
          // `isExpanded` recorta con puntos suspensivos el valor seleccionado
          // ("Cédula de Ciudadanía" desborda la caja en pantallas de 360 dp).
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.ink,
          ),
          decoration: _decoracionCampo('Selecciona un Documento', Icons.badge),
          style: _estiloTextoCampo,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(16),
          items: const [
            DropdownMenuItem(
              value: 'Cédula de Ciudadanía',
              child: Text('Cédula de Ciudadanía'),
            ),
            DropdownMenuItem(
              value: 'Cédula de Extranjería',
              child: Text('Cédula de Extranjería'),
            ),
            DropdownMenuItem(value: 'Pasaporte', child: Text('Pasaporte')),
          ],
          onChanged: (val) => setState(() => _tipoDocumento = val!),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _numDocController,
          keyboardType: TextInputType.number,
          decoration: _decoracionCampo('Número de Documento', Icons.numbers),
          validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _telefonoController,
          keyboardType: TextInputType.phone,
          decoration: _decoracionCampo('Teléfono de contacto', Icons.phone),
          // El panel lo muestra como único dato de contacto del conductor, así
          // que se exige un número. Se cuentan dígitos para no exigir un
          // formato: en Colombia escriben "+57 300 123 4567", "3001234567",
          // etc., y rechazar el formato deja conductor sin poder registrarse.
          validator: (v) {
            final digitos = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
            if (digitos.isEmpty) return 'Campo requerido';
            if (digitos.length < 7) return 'Número muy corto';
            return null;
          },
        ),
        const SizedBox(height: 22),

        _buildEncabezadoSeccion('2. Verificación Biométrica'),
        const SizedBox(height: 12),
        _buildDocumentTile(
          _kDocSelfie,
          _nombreSelfie,
          () => _seleccionarArchivo(
            (archivo) => _archivos[_kDocSelfie] = archivo,
            tituloDocumento: _kDocSelfie,
          ),
          icono: Icons.camera_alt,
          requerido: true,
        ),
      ]),
    ];
  }

  /// Página 2: datos del vehículo y documentos legales, con la misma tarjeta
  /// blanca que la página 1.
  List<Widget> _buildContenidoPagina2() {
    return [
      _buildTarjeta([
        BusInfoBox(
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.ink,
          child: Text(
            'Confirma los datos del vehículo y adjunta los documentos legales '
            'originales.',
            style: GoogleFonts.poppins(
              color: AppColors.textStrong,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 18),

        _buildEncabezadoSeccion('3. Datos del Vehículo'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _placaController,
          textCapitalization: TextCapitalization.characters,
          decoration: _decoracionCampo(
            'Placa (Ej: ABC123)',
            Icons.directions_bus,
          ),
          validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _marcaController,
                decoration: _decoracionCampo('Marca', Icons.car_rental),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _modeloController,
                decoration: _decoracionCampo('Modelo', Icons.model_training),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _anioController,
          keyboardType: TextInputType.number,
          decoration: _decoracionCampo(
            'Año del Vehículo',
            Icons.calendar_today,
          ),
          validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
        ),
        const SizedBox(height: 22),

        _buildEncabezadoSeccion('4. Documentos Legales'),
        const SizedBox(height: 12),
        _buildDocumentTile(
          _kDocCedula,
          _nombreCedula,
          () => _seleccionarArchivo(
            (archivo) => _archivos[_kDocCedula] = archivo,
            tituloDocumento: _kDocCedula,
          ),
          icono: Icons.badge,
          requerido: true,
        ),
        const SizedBox(height: 10),
        _buildDocumentTile(
          _kDocLicencia,
          _nombreLicencia,
          () => _seleccionarArchivo(
            (archivo) => _archivos[_kDocLicencia] = archivo,
            tituloDocumento: _kDocLicencia,
          ),
          icono: Icons.card_membership,
          requerido: true,
        ),
        const SizedBox(height: 10),
        _buildDocumentTile(
          _kDocSoat,
          _nombreSoat,
          () => _seleccionarArchivo(
            (archivo) => _archivos[_kDocSoat] = archivo,
            tituloDocumento: _kDocSoat,
          ),
          icono: Icons.shield,
        ),
        const SizedBox(height: 10),
        _buildDocumentTile(
          _kDocTecnomecanica,
          _nombreTecnomecanica,
          () => _seleccionarArchivo(
            (archivo) => _archivos[_kDocTecnomecanica] = archivo,
            tituloDocumento: _kDocTecnomecanica,
          ),
          icono: Icons.fact_check,
        ),
      ]),
    ];
  }

  /// Tarjeta blanca: envuelve el contenido de la página y sus dos botones.
  Widget _buildTarjeta(List<Widget> contenido) {
    return BusCard(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...contenido, const SizedBox(height: 20), _buildBotones()],
      ),
    );
  }

  /// Encabezado numerado de cada apartado (1. Datos Personales, 2. ...), con la
  /// barra amarilla que usan el resto de formularios.
  Widget _buildEncabezadoSeccion(String texto) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
        ),
      ],
    );
  }

  /// Par de botones. La acción principal (Continuar / Enviar a Aprobación) va
  /// en negro con icono amarillo; la secundaria (Cancelar / Volver) en blanco
  /// con borde, para que no se confundan. En la página 2 "Enviar a Aprobación"
  /// es el envío definitivo.
  Widget _buildBotones() {
    final bool ultima = _paginaActual == 1;
    return Row(
      children: [
        Expanded(
          child: _buildBotonSecundario(
            ultima ? 'Volver' : 'Cancelar',
            ultima
                ? () => _irAPagina(0)
                : () => Navigator.of(context).maybePop(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: BusPrimaryButton(
            label: ultima ? 'Enviar a Aprobación' : 'Continuar',
            icon: ultima ? Icons.send_rounded : Icons.arrow_forward_rounded,
            loading: _enviando,
            onPressed: ultima ? _enviarRegistro : _continuar,
          ),
        ),
      ],
    );
  }

  /// Botón blanco con borde para la acción de salida del paso.
  Widget _buildBotonSecundario(String texto, VoidCallback onPressed) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textStrong,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: onPressed,
        // `FittedBox` en vez de confiar en el ancho del texto: "Volver" y
        // "Cancelar" se reducen un punto en pantallas de 360 dp en lugar de
        // salirse del botón.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            texto,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textStrong,
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _estiloTextoCampo =>
      GoogleFonts.poppins(fontSize: 13, color: AppColors.textStrong);

  /// Barra de campo: fondo amarillo pálido, borde suave que se vuelve negro al
  /// enfocar, e icono a la izquierda. La etiqueta es el `hint`.
  InputDecoration _decoracionCampo(String etiqueta, IconData icono) {
    return InputDecoration(
      hintText: etiqueta,
      hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
      prefixIcon: Icon(icono, color: AppColors.ink, size: 22),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 22),
      filled: true,
      fillColor: AppColors.formField,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      errorStyle: TextStyle(fontSize: 11, color: AppColors.danger),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.ink, width: 1.6),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: AppColors.danger, width: 1.6),
      ),
    );
  }

  /// Barra de documento: misma barra gris que los campos, con el icono del
  /// documento a la izquierda y el botón de adjuntar a la derecha. [requerido]
  /// lo marca en rojo cuando el último intento de envío lo dejó pendiente, para
  /// que el usuario sepa cuál adjuntar en vez de recibir un error genérico.
  Widget _buildDocumentTile(
    String title,
    String? nombreArchivoSeleccionado,
    VoidCallback onTap, {
    required IconData icono,
    bool requerido = false,
  }) {
    final bool cargado = nombreArchivoSeleccionado != null;
    final bool falta = requerido && _pendientesDeAdjuntar.contains(title);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: falta ? AppColors.danger : AppColors.border,
          width: falta ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: BusIconBadge(
          icon: icono,
          size: 40,
          color: cargado
              ? AppColors.success
              : (falta ? AppColors.danger : Colors.white),
          iconColor: cargado || falta ? Colors.white : AppColors.ink,
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textStrong,
          ),
        ),
        subtitle: Text(
          cargado
              ? 'Archivo: $nombreArchivoSeleccionado'
              : (falta
                    ? 'Obligatorio: adjúntalo para enviar'
                    : 'Pendiente por adjuntar'),
          style: GoogleFonts.poppins(
            color: cargado
                ? AppColors.success
                : (falta ? AppColors.danger : AppColors.textMuted),
            fontSize: 11,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          cargado ? Icons.check_circle_rounded : Icons.upload_rounded,
          color: cargado
              ? AppColors.success
              : (falta ? AppColors.danger : AppColors.ink),
          size: 22,
        ),
      ),
    );
  }
}
