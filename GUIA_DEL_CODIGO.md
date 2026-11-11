# Guía del código de BusTrack (v1.0.0)

Este documento explica **dónde está cada cosa y por qué está ahí**, con la ruta y la línea exactas para poder abrir el archivo en el editor (`Ctrl+G` en VS Code) y responder preguntas concretas.

Está escrito contra el código actual, no contra la memoria del proyecto. Es el documento técnico de referencia del repositorio: si algo no coincide con él, manda la guía.

> **Nota sobre este repositorio público:** las credenciales no se versionan. `lib/firebase_options.dart` y `web/index.html` traen marcadores en lugar de los identificadores reales, `android/app/google-services.json` y `android/local.properties` no existen (hay plantillas `.example`) y la clave de Google Maps se inyecta desde `local.properties` vía `${mapsApiKey}`. El código de la app no cambia por eso: solo hay que configurar esos archivos para ejecutarla. Los pasos están en el `README.md`.

Convenciones:

- `archivo:línea` = línea del **código actual**.
- "Padre" es el rol `parent`; "conductor" es `driver`; "admin" es el correo de `AdminService.adminEmail`.
- La app **no es** un GPS que da instrucciones giro a giro. Es un tablero compartido: el teléfono del conductor publica su posición y la app dibuja el camino por carretera entre el bus y el siguiente objetivo.

---

## 0. Mapa rápido: "¿dónde está…?"

| Si preguntan por… | Abrir |
|---|---|
| El mapa que ve el **padre** | `lib/widgets/parent_map_view.dart:874` (`GoogleMap`) |
| El mapa que ve el **conductor** | `lib/screens/driver_ruta_screen.dart:1492` (`GoogleMap`) |
| La pantalla del mapa del padre completa | `lib/widgets/parent_map_view.dart:815` (`build`) |
| El panel del padre (4 pestañas) | `lib/parent_home_screen.dart:80` (`build`) y `:137` (`IndexedStack`) |
| El panel del conductor (4 pestañas) | `lib/screens/driver_ruta_screen.dart:1162` (`build`) |
| El arranque de la app / "sesión" | `lib/services/session_router.dart:97` (`PantallaDeArranque`) |
| El login | `lib/screens/login_screen.dart:20` |
| El registro de padre | `lib/parent_register_screen.dart:20` |
| El registro de conductor | `lib/screens/driver_register_screen.dart` (`_enviarRegistro` en `:314`) |
| La selección de rol | `lib/screens/role_selection_screen.dart:8` |
| La aprobación/rechazo de conductores | `lib/admin_home_screen.dart:180` y `:307`; `lib/admin_service.dart:14` y `:33` |
| El GPS del conductor | `lib/services/bus_location_service.dart:58` |
| La vinculación por código/QR | `lib/services/hijos_service.dart:118` y `:259` |
| Las reglas de Firestore | `firestore.rules` (todo comentado, bloque por bloque) |
| Los colores y el tema | `lib/main.dart:52` (`AppColors`) y `:139` (`_buildTheme`) |
| Los tests | `test/` (4 archivos, 17 tests) |
| La configuración Android | `android/app/src/main/AndroidManifest.xml` y `android/app/build.gradle.kts` |

---

## 1. Entrada de la app, tema y paleta

### `lib/main.dart`

| Línea | Qué hace |
|---|---|
| `:39` | `runApp(const BusTrackApp(inicio: PantallaDeArranque()))`. El `home` **no** es el login: es la pantalla que decide. |
| `:52` | `class AppColors`, la paleta "de fuente única" (aspiracional: algunas pantallas nuevas usan azules propios, ver §17). |
| `:117` | `BusTrackApp`, el `StatelessWidget` raíz. |
| `:128` | `MaterialApp`: título, tema, transiciones. |
| `:132` | `home: inicio ?? const SplashScreen()`. El `inicio` lo inyecta `main()`. |
| `:139` | `_buildTheme()`: `ColorScheme`, tipografía Poppins (`google_fonts`), `CardTheme`, botones, `SnackBar`, `Dialog`, `BottomSheet`, `Checkbox`, `Divider`. |
| `:293` | `_FadeSlidePageTransitionsBuilder`, la transición de páginas. |

**Por qué el `home` es `PantallaDeArranque` y no el login:** la sesión de Firebase se restaura de forma asíncrona. Si el `home` fuera el login, un usuario con sesión vería el formulario un instante antes de entrar a su panel, y eso se reportó como "la app me saca de la cuenta". El arranque muestra "Restaurando tu sesión…" mientras resuelve.

**Sobre `AppColors`:** está documentada como paleta única, pero no se aplica en todas partes. `main.dart` mismo usa `0xFFFFC107` hardcodeado en el `ThemeData`, y pantallas como el registro usan `Color(0xFF0D47A1)` / `Colors.blueAccent`. No es un bug: es deuda visual conocida.

---

## 2. Arranque y sesión

### 2.1 `lib/services/session_router.dart`

Es el archivo más importante para explicar "cómo sabe la app quién eres".

| Línea | Qué hace |
|---|---|
| `:29` | `DestinoDeSesion` = `{ pantalla, dejarLoginDebajo }`. |
| `:43` | `resolverDestinoDeSesion(User)` — **la única copia** de la lógica de enrutado. La usan el login y el arranque. |
| `:47` | Anota la sesión (`PreferenciasDeSesion.recordarSesion`) para distinguir "aquí nunca se inició sesión" de "había sesión y Firebase no la restauró". |
| `:49` | Si el correo es el admin → `AdminHomeScreen`. |
| `:53` | Lee `usuarios/{uid}` (red). |
| `:58` | Si no existe la ficha → `RoleSelectionScreen` con `dejarLoginDebajo: true` (se entra con `push` para que "atrás" funcione). |
| `:65` | `role` por defecto `'parent'`. |
| `:71` | **La puerta del conductor:** `role == 'driver' && isApproved != true` → `PantallaSolicitudRevision`. |
| `:72` | Le pasa `rechazo` y `motivoRechazo` para que la pantalla muestre el motivo si fue rechazado. |
| `:80` | `parent` → `ParentHomeScreen`; cualquier otro (conductor aprobado) → `PantallaRutaConductor`. |

### 2.2 La pantalla de arranque (`:97`)

| Línea | Qué hace |
|---|---|
| `:106` | `_destino` es un `Future<Widget>` que el `FutureBuilder` observa; se reasigna al reintentar. |
| `:114` | `_resolver()`: el flujo completo. |
| `:117` | Lee `sesionRecordada()`. Si hay correo anotado, se le da más margen a Firebase para restaurar. |
| `:120` | `_usuarioConSesion(esperarSesion: correoRecordado != null)`. |
| `:131` | Si no hay usuario y nunca hubo sesión → `SplashScreen` (bienvenida). |
| `:125` | Si había sesión y no se restauró → `_SesionNoRestaurada` (aviso con "Reintentar" e "Iniciar sesión"). |
| `:137` | `aplicarPoliticaDeArranque`: aquí **sí** se puede aplicar la casilla "Recordarme" desmarcada, porque ya se sabe que hay usuario. |
| `:142` | `_destinoDesdeCache`: primero la copia local, para no esperar a la red. |
| `:147` | Si no hay caché, `resolverDestinoDeSesion` (red). |
| `:155` | Si falla la red → `_SinConexion` (reintentar **sin** cerrar sesión), nunca la bienvenida. |
| `:200` | `_usuarioConSesion`: `currentUser` o la primera emisión **no nula** de `authStateChanges()`; espera 6 s si había sesión anotada, 1 s si no. El `.where((u) => u != null)` es lo que evita tomar el `null` inicial como "no hay sesión". |
| `:223` | `_destinoDesdeCache`: admin, luego `usuarios/{uid}` con `GetOptions(source: Source.cache)`. |
| `:239` | **La misma puerta de `isApproved`** en el camino del caché: si no, un conductor sin aprobar entraría por el atajo. |
| `:256` | `FutureBuilder`: mientras no esté `done` → `_RestaurandoSesion`. |
| `:262` | `_RestaurandoSesion` (definida en `:277`): bus amarillo + spinner + "Restaurando tu sesión…". |
| `:336` | `_SesionNoRestaurada`: "No pudimos restaurar tu sesión", con el correo y dos botones. |
| `:415` | `_SinConexion`: "Seguimos dentro de tu cuenta", con reintentar y cerrar sesión de verdad. |

**Idea para el profesor:** el arranque nunca "pierde" al usuario. Los tres estados posibles son: bienvenida (nunca hubo sesión), restaurando, o panel/aviso. Nunca el login con la sesión viva.

### 2.3 `lib/services/session_prefs.dart`

| Línea | Qué hace |
|---|---|
| `:31` | `PreferenciasDeSesion`, sobre `shared_preferences`. |
| `:34` | Clave `recordarme`. |
| `:35` | Clave `sesion_correo`. |
| `:40` | `recordarme()` (por defecto `true`). |
| `:51` | `guardarRecordarme(bool)`. |
| `:64` | `sesionRecordada()` → `String?` con el último correo. |
| `:76` | `recordarSesion(email)`. |
| `:88` | `olvidarSesion()`. |
| `:103` | `aplicarPoliticaDeArranque(user)`: si la casilla está desmarcada, cierra la sesión al arrancar. |

**Punto fino:** en Android/iOS Firebase Auth **siempre** persiste el token; no existe `setPersistence` nativo. La casilla no impide que Firebase guarde la sesión: lo que hace es cerrarla en el siguiente arranque. Por eso se aplica en `PantallaDeArranque` y no en `main()` (ahí `currentUser` todavía puede ser `null`).

`sesion_correo` no es una credencial: no hay token ni contraseña en disco. Solo sirve para no confundir "aquí nunca se inició sesión" con "había sesión y Firebase no la restauró".

---

## 3. Login y registro

### 3.1 Login — `lib/screens/login_screen.dart`

| Línea | Qué hace |
|---|---|
| `:20` | `_PantallaLoginPaisajeState`. |
| `:28` | `_recordarme = true`. |
| `:36` | `_cargarRecordarme()`: sincroniza la casilla con lo guardado. |
| `:44` | `_guardarRecordarme()`: guarda **antes** de iniciar sesión. |
| `:48` | `_handleLogin()`: valida, `signInWithEmailAndPassword`, maneja errores y llama a `_enrutar`. |
| `:87` | `_iniciarSesionConGoogle()`: delega en `GoogleAuth.iniciarSesion()`. |
| `:135` | `_enrutar(user)`: usa `resolverDestinoDeSesion` y entra con `pushReplacement` o `push` según `dejarLoginDebajo`. |
| `:225` | `GoogleButton`: el botón de Google es **blanco con borde**, distinto del botón principal. |

La flecha "Volver" del encabezado solo se dibuja si `Navigator.canPop()` es `true`: al arrancar y al cerrar sesión el login es la ruta raíz y la flecha no tendría a dónde ir.

### 3.2 Google — `lib/services/google_auth.dart`

| Línea | Qué hace |
|---|---|
| `:10` | `GoogleAuthError` (no es `FirebaseException`; quien llama debe usar `on GoogleAuthError`). |
| `:46` | `class GoogleAuth`. |
| `:68` | `_serverClientId`: el **Web OAuth client id**, no el de Android de `google-services.json`. En el repo público es un marcador que se pasa con `--dart-define=GOOGLE_WEB_CLIENT_ID=...`. |
| `:76` | `_inicializacion`: memoiza `initialize()` (el paquete lo pide una vez por proceso). |
| `:88` | `iniciarSesion()`: bifurca por `kIsWeb`. |
| `:95` | `cerrarSesion()`. |
| `:152` | `_enWeb()`: `signInWithPopup` (solo web). |

**Por qué existe este archivo:** `FirebaseAuth.signInWithPopup` es **solo web**; en Android/iOS/desktop el canal lanza `UnimplementedError`. En nativo se usa `google_sign_in` **7.x** con `CredentialManager`, que abre una Chrome Custom Tab. `signInWithRedirect` tampoco sirve: también es solo web.

**Requisito externo:** la SHA-1 de la keystore con la que se firma el APK debe estar registrada en Firebase. Si no, `google_sign_in` 7.x devuelve `clientConfigurationError` o `canceled`. Ningún cambio de código arregla eso.

### 3.3 Registro — `lib/register_screen.dart`

| Línea | Qué hace |
|---|---|
| `:25` | `_registrarUsuario()`: `createUserWithEmailAndPassword`. |
| `:48` | Al terminar, `_irASeleccionDeRol()`. |
| `:80` | `_registrarConGoogle()`. |
| `:93` | `_irASeleccionDeRol()`: `pushReplacement` a `RoleSelectionScreen` (el login ya estaba debajo). |
| `:106` | `_mostrarAviso()`: `clearSnackBars()` primero, para que un error viejo de Google no parezca el del registro por email. |
| `:211` | Botón "Registrarse" (primario). |
| `:220` | `_buildBoton(...)`: primario sólido vs. Google blanco con borde. **No unificar colores**: la maqueta los dibujó iguales y causó toques erráticos reportados como "el registro por email muestra un error de Google". |

### 3.4 Selección de rol — `lib/screens/role_selection_screen.dart`

| Línea | Qué hace |
|---|---|
| `:8` | `RoleSelectionScreen` (hay un duplicado muerto en `lib/role_selection_screen.dart`, ver §18). |
| `:32` | "Volver" con `maybePop()`: aquí sí es correcto, siempre hay login debajo. |
| `:54` | Tarjeta "Conductor" → `PantallaRegistroConductor`. |
| `:69` | Tarjeta "Padre" → `ParentRegisterScreen`. |
| `:99` | `_buildRoleCard`. |

### 3.5 Registro de padre — `lib/parent_register_screen.dart`

| Línea | Qué hace |
|---|---|
| `:20` | `ParentRegisterScreen`. |
| `:53` | `_escanearCodigo()`: abre `ScanQrScreen`. |
| `:62` | `_verificarCodigo()`: resuelve el código antes de guardar. |
| `:112` | `_guardarDatosPadre()`: escribe `usuarios/{uid}` y, si hay código, crea el primer hijo vinculado. |
| `:188` | Traduce errores con `_mensajeDeErrorDeFirestore`. |
| `:212` | `_mensajeDeErrorDeFirestore`: `permission-denied` → mensaje legible. |

**Cambio de diseño importante:** este formulario **ya no pide placa ni nombre del conductor**. Antes, un dato escrito a mano vinculaba al bus equivocado sin avisar. Ahora pide nombre/teléfono del padre, datos del hijo y un código **opcional**.

### 3.6 Registro de conductor — `lib/screens/driver_register_screen.dart`

| Línea | Qué hace |
|---|---|
| `:314` | `_enviarRegistro()`: revalida las dos páginas, exige los adjuntos y escribe `usuarios/{uid}` + `solicitudes/{uid}/adjuntos/{slug}`. |
| — | Soporta `reenviar: true`: precarga la ficha y conserva los adjuntos ya subidos. |
| — | Los adjuntos se reducen a 1280 px / JPEG q75 en `compute()` y se limitan a **900 KB** (`_kMaxBytesPorDocumento`), bajo el 1 MiB por documento de Firestore. |
| — | El teléfono se valida por **cantidad de dígitos** (`< 7` → "Número muy corto"), no por formato: en Colombia se escribe "+57 300 123 4567", "3001234567", etc. |

### 3.7 Solicitud en revisión — `lib/screens/solicitud_revision_screen.dart`

`:22` `PantallaSolicitudRevision`. Muestra:

- "Tu solicitud está en revisión" si `estadoSolicitud == 'pendiente'`.
- El **motivo del rechazo** si `estadoSolicitud == 'rechazado'`.
- "Corregir y reenviar" → `PantallaRegistroConductor(reenviar: true)`.
- "Cerrar sesión".

Es la pantalla a la que cae el conductor no aprobado, tanto al iniciar sesión como al arrancar con sesión guardada.

---

## 4. Panel del padre

### `lib/parent_home_screen.dart`

| Línea | Qué hace |
|---|---|
| `:44` | `ParentHomeScreen`. |
| `:54` | `_destinos`: los 4 destinos de `BusNavBar` (Ruta, Recorrido, Conductor, Mi Perfil). |
| `:72` | `_pestana = _kPestanaRuta`: abre en "Ruta". |
| `:80` | `build`: encabezado + selector de hijos + `IndexedStack` + `BusNavBar`. |
| `:83` | `BusNavBar` (compartida con el conductor). |
| `:115` | `StreamBuilder` sobre `_hijosDelPadre()`. |
| `:137` | **`IndexedStack`**: cambiar de pestaña no destruye las otras, así que no se cortan los `snapshots()` ni se pierde el scroll. |
| `:164` | `_perfilPadre()`: `StreamsDeDocumento.de('usuarios/$uid')`. |
| `:172` | `_hijosDelPadre()`: `StreamsDeDocumento.deConsulta('estudiantes/$uid', ...)`. |
| `:210` | `_buildSelectorHijos(...)`: selector horizontal **solo si hay más de un hijo**. |
| `:260` | `_buildRuta(...)`. |
| `:268` | `ParentMapView` con la **placa del hijo seleccionado**, no una del perfil. |
| `:281` | `_buildRecorrido(...)`. |
| `:285` | `RecorridoBusView` (el mismo widget que usa el conductor). |
| `:293` | `_buildVehiculo(...)`. |
| `:297` | `ParentVehiculoView` (datos del bus/conductor + llamar). |
| `:305` | `_buildSinHijos()`: estado cuando el padre no tiene ningún hijo. |
| `:346` | `_buildSinBus(hijo)`: "«nombre» no tiene bus vinculado". |
| `:388` | `_buildPestana(...)`: contenedor con scroll. |
| `:413` | `_buildEncabezado()`. |
| `:428` | `_cerrarSesion(context)`: cierra sesión y `pushAndRemoveUntil` al login. |
| `:456` | `_agregarHijo()`: abre `ChildFormScreen` en modo alta. |
| `:471` | `_editarHijo(hijo)` y `:620` `_abrirHijos(...)`. |
| `:495` | `_buildTarjetaPerfil(...)`: el perfil es **solo un menú** (mis datos, mis hijos, cambiar contraseña, acerca de, cerrar sesión); no incrusta datos. |
| `:610` | `_abrirDatos()`: `ParentDatosScreen`. |

**Multi-hijo:** un padre puede tener varios hijos y **cada uno puede ir en un bus distinto**. Por eso las tres vistas de bus reciben la **placa del hijo seleccionado**. El perfil no tiene placa.

**"Mis hijos" vuelve al panel** con el hijo tocado ya seleccionado y cambia a "Ruta".

---

## 5. El mapa del padre (la pregunta más probable)

### `lib/widgets/parent_map_view.dart` (1347 líneas)

| Línea | Qué hace |
|---|---|
| `:22` | `_kSegundosAviso = 10`: ventana para confirmar el aviso de llegada. |
| `:25` | `_PuntoRecogida` (id, punto, etiqueta). |
| `:53` | `ParentMapView`: recibe `streams`, `placa`, `studentId`, `childName`. |
| `:96` | `_ParentMapViewState`. |
| `:105` | `_destino` (colegio). |
| `:112` | `_miPunto`: el punto de recogida de **este** hijo. |
| `:120` | `_subidos`: ids de estudiantes ya recogidos. |
| `:134` | `_autoConfirmado`. |
| `:248` | `_cargarIconoBus()`: convierte el PNG del bus en un `BitmapDescriptor`. |
| `:253` | `_suscribirBus()`: escucha `buses/{placa}`. |
| `:262` | `_suscribirMiPunto()`: escucha `recogida/{studentId}` **aparte** de la lista del bus, para ver el marcador incluso antes de que el conductor inicie la ruta. |
| `:291` | `_alActualizarBus(...)`: lee posición, `enMovimiento`, `paradasPublicas`, `driverUid`. |
| `:384` | `_alActualizarRuta(...)`: lee `rutas/{driverUid}` → `destino`, `estadoParadas` (`llegoEn` / `subioEn`) y el legado `recogidos`. |
| `:460` | `_leerParadasPublicas(...)`: convierte `buses/{placa}.paradasPublicas` (`{id, lat, lng}`) en puntos. |
| `:487` | `_quizasSellarDriverUid(...)`: copia el `driverUid` del bus a `recogida/{studentId}`. Es la clave que las reglas comparan para que el conductor pueda leer mi punto. |
| `:510` | `_elegirMiPunto()`: abre `MapPickerScreen`. |
| `:571` | `_eliminarMiPunto()`. |
| `:628` | `_avisarLlegada()`: SnackBar "¡El bus llegó a tu paradero!" con acción "Confirmar" y 10 s de duración. |
| `:651` | `_quizasAutoConfirmar()`: si pasaron 10 s sin respuesta, confirma solo. |
| `:664` | `_confirmarLlegada()`: escribe `recogida/{studentId}.avisoVistoEn`. |
| `:702` | `_rutaActiva => _bus['enMovimiento'] == true`. Es el único dato que decide si el mapa está "en vivo". |
| `:704` | `_posicionBus()` / `:715` `_ultimaPosicionBus()`. |
| `:727` | `_programarCalculoRuta(...)`: debounce antes de pedir la ruta a OSRM. |
| `:761` | **`_rutaInteres()`**: qué tramo dibuja el padre. |
| `:766` | Antes de que su hijo suba: `bus → mi punto`. |
| `:773` | Después: `bus → siguiente parada pendiente más cercana`, y solo al final al colegio. |
| `:777` | `_calcularRuta()`: llama a `RouteService`. |
| `:815` | **`build`**: `Scaffold` con el mapa y el panel inferior. |
| `:873` | `_buildMapa()`. |
| `:874` | **`GoogleMap(...)`**: aquí está el mapa que ve el padre. |
| `:891` | `polylines`: una sola `Polyline` con id `ruta_padre`. |
| `:913` | **`_buildMarcadores()`**: bus + paradas + mi punto + colegio. |
| `:938` | Recorre `_recogidas`: verde si ya subió, azul si es mía, gris si es de otro. |
| `:1011` | `_buildChipSenal()`: "señal hace X s". |
| `:1088` | **`_buildPanelInferior()`**: la tarjeta blanca bajo el mapa. |
| `:1113` | `_buildSinPunto()`: invita a marcar el punto. |
| `:1148` | `_buildConPunto()`: estado del bus, distancia, "aún tiene N paradas", botón de confirmar. |
| `:1316` | **`_siguienteParada()`**: la parada pendiente más cercana. Es la que decide el texto y la que reutiliza `_rutaInteres`. |
| `:1335` | `_AvisoMapa` (estado vacío). |

**La regla que hay que explicar bien:** la línea del padre y la del conductor **tienen que dar el mismo trayecto**. Antes divergían: cuando el hijo del padre subía, la línea del padre saltaba al colegio mientras el bus seguía con los puntos de otros, y el texto decía "aún tiene N paradas pendientes". Hoy las dos calculan "la más cercana" con las mismas paradas y el mismo `estadoParadas`:

- Conductor: `lib/screens/driver_ruta_screen.dart:992` `_rutaOrdenada()`.
- Padre: `lib/widgets/parent_map_view.dart:761` `_rutaInteres()`.

**Datos que el padre NO puede leer:** el padre no lee `recogida` de otros hijos (esa colección tiene nombre y teléfono). Solo ve sus puntos anónimos publicados por el conductor en `buses/{placa}.paradasPublicas`.

---

## 6. Panel del conductor

### `lib/screens/driver_ruta_screen.dart` (1939 líneas)

| Línea | Qué hace |
|---|---|
| `:31` | `_kRadioLlegadaMetros = 120`: distancia a la que el botón de recogida se pinta verde. **No bloquea**: un GPS con retraso no puede dejar al conductor sin poder marcar. |
| `:34` | `ParadaRecogida`: id, punto, etiqueta, teléfono, `avisoVistoEn`, etc. |
| `:76` | `EstudianteBus`: la fila de la pestaña "Estudiantes". |
| `:122` | **`fusionarEstudiantes(...)`**: función pura (testeada) que mezcla `estudiantes` + `recogida` sin duplicados y filtrando por placa. |
| `:170` | `PantallaRutaConductor`. |
| `:184` | `_destinos`: Ruta, Recorrido, Estudiantes, Mi Perfil. |
| `:211` | `_destino` (colegio elegido). |
| `:224` | `_recogidas`: puntos del bus. |
| `:238` | `_estadoParadas`: `{ studentId: {llegoEn, subioEn} }`. |
| `:244` | `_esRutaActiva`. |
| `:274` | `_subRecogidas`, `:275` `_subEstudiantes`. |
| `:300` | `_cargarIconoBus()`. |
| `:307` | `_escucharPerfil()`: `usuarios/{uid}` para nombre y placa. |
| `:343` | `_escucharEstudiantes()`: `estudiantes where driverUid == uid`. |
| `:379` | `_estudiantesDelBus`: `fusionarEstudiantes(...)`. |
| `:385` | `_reengancharPlaca(uid, placa)`: si cambia la placa, se re-suscribe. |
| `:420` | `_alActualizarRutaDoc(...)`: `rutas/{uid}` → destino y `estadoParadas`. |
| `:469` | `_alActualizarBus(...)`. |
| `:525` | `_alActualizarRecogidas(...)`: filtra por placa en Dart (un conductor puede tener dos buses). |
| `:570` | **`_publicarParadasPublicas()`**: copia `{id, lat, lng}` a `buses/{placa}.paradasPublicas`. Es lo único que ve el padre de las paradas de otros hijos. Usa una firma para no reescribir si nada cambió. |
| `:609` | `_elegirDestino()`: abre `MapPickerScreen`. |
| `:678` | **`_iniciarRuta()`**: exige destino, escribe `buses/{placa}` (estado, `driverUid`, `rutaIniciada`), resetea `estadoParadas` y arranca el GPS. |
| `:759` | **`_finalizarRuta()`**: archiva el historial, limpia `lat`/`lng`/velocidad/`paradasPublicas` y **conserva `driverUid`** para que el padre siga sabiendo de quién es el bus. |
| `:820` | `_archivarRuta(uid)`: escribe `rutas/{uid}/historial/{registro}`. |
| `:871` | **`_marcarSubio(parada)`**: un solo toque cierra la parada, pone `subioEn` y avanza el tramo. Con rollback si falla. |
| `:924` | `_reanudarRutaSiEstabaActiva(uid, placa)`: si la app se reabre con la ruta en curso, la retoma. |
| `:954` | `_programarCalculoRuta(...)`. |
| `:992` | **`_rutaOrdenada()`**: bus → siguiente parada pendiente, o al colegio si ya no queda ninguna. |
| `:1005` | `_calcularRuta()`: pide la ruta a OSRM. |
| `:1043` | `_seguirConSiguiente()`: centra el tramo siguiente. |
| `:1078` | `_encuadrarRuta()`. |
| `:1105` | `_abrirCodigoBus()`: abre `DriverQrScreen`. |
| `:1123` | `_cerrarSesion()`. |
| `:1162` | **`build`**: `Scaffold` + `BusNavBar` + `IndexedStack` de las 4 pestañas. |
| `:1197` | `_buildEncabezado()`. |
| `:1221` | `_buildPestanaRuta()`: mapa + panel. |
| `:1233` | `_buildPestanaRecorrido()`: `RecorridoBusView` con `driverUidRespaldo`. |
| `:1252` | `_buildPestanaEstudiantes()`: lista fusionada. |
| `:1330` | `_buildFilaEstudiante(...)`: nombre + botón de llamada (deshabilitado si no hay teléfono). |
| `:1367` | `_llamarPadre(telefono)`. |
| `:1374` | `_buildPestanaPerfil()`: solo opciones. |
| `:1475` | `_abrirMisDatos()`. |
| `:1485` | `_buildMapa()`. |
| `:1492` | **`GoogleMap(...)`**: el mapa del conductor. |
| `:1512` | `polylines: _buildPolilineas()`. |
| `:1577` | `_buildChipCoordenadas()`. |
| `:1629` | **`_buildMarcadores()`**. |
| `:1652` | Marcadores de paradas. |
| `:1671` | Marcador del colegio. |
| `:1689` | **`_buildPolilineas()`**: la ruta calculada. |
| `:1701` | **`_buildPanelInferior()`**: panel del viaje. |
| `:1851` | `_buildResumenPendientes()`. |
| `:1866` | `_buildTodoRecogido()`. |
| `:1874` | `_buildSiguienteParada(...)`: "Siguiente parada: X · a N m" y "Ya recogí a X". |
| `:1925` | `_siguienteParada()`: la pendiente más cercana. |

**Las dos fuentes de la pestaña "Estudiantes":** `estudiantes where driverUid == uid` (el vínculo, manda) y `recogida where driverUid == uid` (aporta `parentPhone` y datos legados). Antes solo leía `recogida`, así que un hijo vinculado **sin punto de recogida era invisible** para el conductor: ni aparecía ni se podía llamar al padre. Hoy se fusionan por `studentId` y aparece "Sin punto de recogida" cuando falta el pin.

**El QR no reemplaza la placa:** `buses/{placa}` sigue teniendo el id = placa. El código es cómo el padre *descubre* su bus sin escribirlo.

---

## 7. GPS del conductor

### `lib/services/bus_location_service.dart`

| Línea | Qué hace |
|---|---|
| `:46` | `AvisoGps` (mensaje para la UI). |
| `:58` | `BusLocationService`. |
| `:69` | **`_intervaloPara(kmh)`**: `5 s` si `< 2 km/h`, `2 s` si `< 25`, `1 s` en carretera. |
| `:76` | `_periodoVigilante = 1 s`. |
| `:82` | `_silencioMaximo = 3 s`. |
| `:88` | `_ultimoEnvio`. |
| `:92` | `_ultimaActividad`. |
| `:141` | `distanceFilter: 0` para que mande `intervalDuration`. |
| `:180` | `iniciar(placa)`: permisos, posición inicial, stream y vigilante. |
| `:221` | `Timer.periodic` del vigilante. |
| `:229` | **`_sondear()`**: pide una posición si el stream lleva 3 s callado. Mide **recepción** (`_ultimaActividad`), no escritura: si midiera `_ultimoEnvio`, un bus detenido 5 s parecería desconectado. |
| `:266` | Throttle de escritura: `if (!forzar && ahora - _ultimoEnvio < _intervaloPara(kmh)) return;`. |
| `:303` | `detener(...)`. |

**Campos que escribe en `buses/{placa}`:** `lat`, `lng`, `ultimaLat`, `ultimaLng`, `rumbo`, `velocidad`, `precision`, `ultimaActualizacion`, `gpsOrigen` (`inicial` / `stream` / `sondeo`, solo diagnóstico).

**Idea para el profesor:** el stream de `Geolocator` entrega cada segundo, pero la escritura a Firestore se espacia según la velocidad. El marcador despierta en cuanto el bus arranca; lo que se ahorra son escrituras y batería con el bus parado.

### `lib/services/ubicacion_actual.dart`

Es la única puerta a la ubicación **fuera** del seguimiento del bus.

| Línea | Qué hace |
|---|---|
| `:36` | `UbicacionObtenida`. |
| `:71` | `UbicacionActual`. |
| — | `obtener()`: revisa GPS, **pide permiso** y busca posición (lo que dispara un botón del usuario). |
| — | `obtenerSiYaHayPermiso()`: consulta silenciosa para centrar el mapa al abrirlo. |
| — | `abrirAjustes` / `abrirAjustesDeUbicacion`. |

**Por qué existe:** `Geolocator.getCurrentPosition` **no pide permiso por sí solo**. En Android lanza `PermissionDeniedException` si no está concedido, y el selector de mapa nunca lo pedía: "Mi ubicación" mostraba siempre "No pudimos obtener tu ubicación actual", incluso con GPS encendido, porque el usuario nunca había visto el diálogo.

Si no hay fix en 15 s, se usa `getLastKnownPosition` y se avisa ("Usamos tu última ubicación conocida").

---

## 8. "Recorrido" e itinerario (padre y conductor)

### `lib/widgets/recorrido_bus_view.dart`

| Línea | Qué hace |
|---|---|
| `:12` | `_Parada` (id, etiqueta, recogido, esMia, hora). |
| `:49` | `RecorridoBusView`: el **mismo** widget para padre y conductor. |
| `:84` | `build`. |
| `:90` | `StreamBuilder` sobre `buses/{placa}`. |
| `:99` | `finalizada = estadoRuta == 'finalizada'`. |
| `:115` | `_buildEnVivo(...)`: destino y recogidos de `rutas/{driverUid}` + `buses/{placa}.paradasPublicas`. |
| `:139` | `_buildFinalizada(...)`: lee `rutas/{uid}/historial`. |
| `:154` | `.orderBy('finalizada', descending: true)`. |
| `:243` | `_buildCabecera(...)`. |
| `:288` | `_buildRutaYParadas(...)`. |
| `:361` | `_leerDestino(...)`. |
| `:401` | `_leerParadasPublicas(...)`. |
| `:425` | `_leerParadasHistorial(...)`. |

El padre pasa `studentId` para marcar "(tu punto)"; el conductor lo deja en `null` y pasa `driverUidRespaldo` con su uid, porque antes de iniciar la ruta `buses/{placa}` todavía no publica `driverUid` y sin respaldo no vería el destino planificado.

### `lib/widgets/itinerario_timeline.dart`

| Línea | Qué hace |
|---|---|
| `:11` | `ParadaItinerario`. |
| `:37` | `formatoHoraCorta(DateTime)`. |
| `:53` | `ItinerarioTimeline`. |

---

## 9. Hijos y vinculación (código / QR)

### 9.1 Modelo — `lib/models/hijo.dart`

| Línea | Qué hace |
|---|---|
| `:20` | `Hijo`. |
| `:34` | `id`: es la clave de `recogida/{id}` y de `rutas/{driverUid}.estadoParadas[id]`. |
| `:51` | `esLegado`. |
| `:53` | `tieneBus`. |
| `:56` | `desdeDoc(...)`. |
| `:66` | `desdeMapa(...)`. |
| `:88` | **`legado(parentUid, perfil)`**: sintetiza el hijo de las cuentas viejas con `id = parentUid`. Ese formato **no se migra**. |
| `:106` | `CodigoBus`. |
| `:119` | `desdeDoc(...)`: descarta códigos inactivos. |

### 9.2 Servicio — `lib/services/hijos_service.dart`

| Línea | Qué hace |
|---|---|
| `:20` | Alfabeto `ABCDEFGHJKMNPQRSTUVWXYZ23456789`: sin `0/O` ni `1/I/L`, porque el código se dicta por WhatsApp o de viva voz. |
| `:30` | `normalizarCodigo(texto)`: acepta `ABC234`, `?codigo=ABC234` y `.../vincular/ABC234`. |
| `:55` | `esCodigoValido` (4–12 alfanuméricos). |
| `:60` | `generarCodigo(largo: 6)`. |
| `:69` | `consultaHijos(parentUid)`: `where('parentUid', '==', uid)` **sin `orderBy`** (un solo campo no necesita índice; el orden se resuelve en Dart). |
| `:79` | `hijosDesdeSnapshot(...)`. |
| `:104` | **`listaCompleta(...)`**: legado primero + `estudiantes`, para que el panel y "Mis hijos" ordenen igual. |
| `:118` | `resolverCodigo(texto)` → `CodigoBus?` (null si no existe o está inactivo). |
| `:129` | `crearHijo(...)`: crea en `estudiantes`; si recibe `vinculacion`, nace ya asociado al bus. Devuelve el id. |
| `:160` | `actualizarHijo(...)`: si es legado, escribe en `usuarios/{uid}`; además **sincroniza `driverUid` en `recogida`** al vincular a otro bus. |
| `:230` | `eliminarHijo(...)`: borra el hijo y su `recogida`. La ruta activa no se toca (si ya lo habían recogido, el historial conserva la parada). |
| `:259` | `asegurarCodigoConductor({uid, placa, ...})`: busca por `driverUid` y filtra en Dart por placa + `activo`. Un conductor con dos buses tiene un código por cada uno. |
| `:302` | `regenerarCodigoConductor(...)`: marca el anterior `activo: false` en vez de borrarlo, para que un padre con el código viejo reciba "no existe o ya fue desactivado". |
| `:339` | `_crearCodigoUnico(...)`: hasta 8 intentos contra colisiones. |
| `:380` | `sincronizarTelefonoPadre(...)`: copia el `phone` del perfil a todos sus `recogida`, porque el conductor no puede leer `usuarios/{uid}`. |
| `:408` | `_sincronizarRecogida(...)`. |

### 9.3 Pantallas

| Pantalla | Archivo:línea | Qué hace |
|---|---|---|
| Alta/edición de hijo | `lib/screens/child_form_screen.dart:19` | Datos, código opcional, escanear, verificar, quitar vínculo y eliminar. `_guardar` en `:127`, `_escanear` en `:76`, `_verificarCodigo` en `:88`, `_eliminar` en `:221`. |
| Mis hijos | `lib/screens/parent_hijos_screen.dart:20` | Lista de hijos del padre; alta `:231`, edición `:242`. |
| QR del conductor | `lib/screens/driver_qr_screen.dart:18` | Genera y muestra el QR (`QrImageView` en `:261`); `_cargar` en `:43`, `_regenerar` en `:85`, `_copiar` en `:139`. |
| Escáner | `lib/screens/scan_qr_screen.dart:20` | `MobileScanner` en `:122`; `_alDetectar` en `:42`; errores de cámara en `:171`. |

**El QR lleva el código pelado** (`ABC234`), no un enlace. No hay Universal/App Links ni deep links. `normalizarCodigo` acepta enlaces por si algún día se comparte uno.

**Un hijo sin código queda creado sin bus** y se vincula después. `_buildSinBus` en el panel lo dice explícitamente.

---

## 10. Panel del administrador

### `lib/admin_service.dart`

| Línea | Qué hace |
|---|---|
| `:5` | `adminEmail = "danieljerez810@gmail.com"`. **Duplicado en `firestore.rules:12`**: si se cambia uno, se cambia el otro. |
| `:8` | `isAdmin(email)`. |
| `:14` | `aprobarConductor(uid)`: `isApproved: true`, `estadoSolicitud: 'aprobado'`, borra `motivoRechazo`, `revisadoEn`. |
| `:33` | `rechazarConductor(uid, motivo:)`: **no borra el documento**; guarda `estadoSolicitud: 'rechazado'` + `motivoRechazo`. |
| `:60` | `eliminarRuta(uid)`: vacía `rutas/{uid}/historial` y luego borra `rutas/{uid}` (borrar un doc no borra subcolecciones). |
| `:79` | `eliminarPuntoRecogida(parentUid)`: borra `recogida/{parentUid}` y los `recogida/{hijo.id}`. |

### `lib/admin_home_screen.dart`

| Línea | Qué hace |
|---|---|
| `:27` | `AdminHomeScreen` (es `StatefulWidget` para que el menú lateral recuerde la sección). |
| `:43` | `_seccion = SeccionAdmin.pendientes`. |
| `:46` | `build`. |
| `:55` | `AdminDrawer` con `actual` y `onSeleccionar`. |
| `:81` | `_buildBandaTitulo(...)` con el botón de cerrar sesión. |
| `:109` | `_cerrarSesion(...)`. |
| `:137` | `_buildEncabezadoSeccion()`. |
| `:180` | **`_buildListaSeccion()`**: switch de las tres consultas. |
| `:187` | Pendientes: `where('role', == 'driver').where('isApproved', == false)`. |
| `:201` | Aprobados: `where('role', == 'driver').where('isApproved', == true)`. |
| `:167` | "Usuarios totales": la colección completa, **sin `where`** (no necesita índice). |
| `:229` | `_buildLista(...)`. |
| `:307` | `_buildFichaConductor(...)`. |
| `:416` | `_mostrarDetalle(...)`: hoja de detalle. |
| `:505` | `_HijosDelPadre`: carga bajo demanda los hijos de un padre (`estudiantes` + legado). |
| `:664` | `_buildBotonEliminar(...)`. |
| `:688` | `_confirmarYEliminar(...)`. |
| `:743` | `_pedirMotivoRechazo(...)`: "Rechazar" **pide un motivo**. |
| `:824` | `_buildAdjuntos(...)`. |
| `:962` | **`_bytesDe(Object? valor)`**: normaliza los bytes de un adjunto (móvil devuelve `Uint8List`, web devuelve `Blob`). Úsalo en vez de castear. |
| `:1017` | `_abrirAdjunto(...)`. |

**Solo la cola de pendientes muestra Aprobar/Rechazar.** "Rechazar" pide motivo y no puede quedar a un toque en una lista que mezcla padres y conductores.

**Índice compuesto necesario:** `role` ASC + `isApproved` ASC. Está en `firestore.indexes.json` y sirve tanto para `true` como para `false`.

---

## 11. Esquema de Firestore (inferido del código)

| Colección / documento | Campos principales | Quién escribe |
|---|---|---|
| `usuarios/{uid}` | `uid`, `email`, `fullName`, `role`, `isApproved` (solo drivers), `createdAt`; conductor: `estadoSolicitud`, `motivoRechazo`, `docType`, `docNumber`, `phone`, `busPlate`, `busBrand`, `busModel`, `busYear`, `documents`; padre: `phone` y, solo cuentas viejas, `childName`, `childAge`, `schoolName`, `busPlate`, `driverName` | el propio usuario; el admin aprueba/rechaza |
| `estudiantes/{id}` | `parentUid`, `nombre`, `edad`, `colegio`, `createdAt`, `updatedAt`, `busPlate`, `driverUid`, `driverName`, `codigo` | el padre dueño |
| `codigos/{codigo}` | `busPlate`, `driverUid`, `conductor`, `activo`, `createdAt` | el conductor de esa placa |
| `recogida/{studentId}` | `busPlate`, `driverUid`, `parentUid`, `studentId`, `lat`, `lng`, `childName`, `parentName`, `parentPhone`, `avisoVistoEn?`, `updatedAt` | el padre dueño |
| `solicitudes/{uid}/adjuntos/{slug}` | `name`, `isPdf`, `size`, `uploadedAt`, `data` (**`Blob`**) | el conductor |
| `buses/{placa}` (id = placa) | `placa`, `driverUid`, `conductor`, `estadoRuta`, `enMovimiento`, `paradaActual`, `rutaIniciada`, `paradasPublicas` | el conductor |
| `rutas/{driverUid}` | `destino`, `paradas`, `estadoParadas`, `iniciada`, `finalizada` | el conductor |
| `rutas/{driverUid}/historial/{registro}` | `destino`, `paradas`, `finalizada` | el conductor |

**Detalles que suelen preguntar:**

- `estudiantes` se lista con `where('parentUid', '==', uid)` **sin `orderBy`**.
- El id de `estudiantes` es la clave de `recogida/{id}` y de `rutas/{driverUid}.estadoParadas[id]`.
- `recogida` se indexa por **id del hijo**, no por uid del padre. Los documentos viejos siguen funcionando porque el hijo legado usa el uid del padre como id.
- `buses/{placa}.driverUid` **no se borra al finalizar**: solo se limpian `lat`/`lng`, la velocidad y `paradasPublicas`, para que el padre siga sabiendo de quién es el bus.
- `rutas/{driverUid}` va por **uid del conductor**, no por placa: un conductor con dos placas tiene dos rutas.
- `rutas` y su `historial` no se heredan: las reglas tienen un bloque aparte para `historial`.
- `hora` **no se escribe al añadir una parada**: la pone el conductor al reportar llegada. Todos los lectores toleran que falte.

---

## 12. Reglas de Firestore (`firestore.rules`)

El archivo está comentado bloque por bloque. Resumen con líneas:

| Línea | Regla |
|---|---|
| `:10` | `esAdmin()`: `request.auth.token.email == 'danieljerez810@gmail.com'`. |
| `:15` | `esPropio(uid)`. |
| `:22` | `usuarios/{uid}`: `read` admin o dueño (`:23`); `create` propio y nunca auto-aprobándose (`:29`); `update` admin o dueño sin cambiar rol ni `isApproved` (`:44`); `delete` solo admin (`:49`). |
| `:61` | `solicitudes/{uid}/adjuntos/{slug}`: `read` solo admin (`:62`); `create/update` propio, con `name` y `data`, y `data < 1 MiB` (`:63`). |
| `:78` | `buses/{placa}`: `read` cualquier autenticado (`:79`); `create` con `driverUid == auth.uid` (`:80`); `update` con `driverUid` igual antes y después (`:82`); `delete` admin (`:86`). |
| `:97` | `rutas/{uid}`: `read` autenticados (`:98`); `write` admin o dueño (`:99`). |
| `:108` | `rutas/{uid}/historial/{registro}`: `read` autenticados (`:109`); `create` dueño/admin (`:110`); `update/delete` admin (`:111`). |
| `:122` | `codigoValido(codigo, placa)`: existe + `activo` + `busPlate` coincide. |
| `:140` | `esMiHijo(studentId)`: el propio uid (hijo legado) o un `estudiantes` con ese `parentUid`. |
| `:146` | `estudiantes/{id}`: `read` padre dueño, conductor vinculado o admin (`:158`); `create`/`update` del padre dueño con vinculación válida (`:163`, `:167`); `delete` del padre dueño (`:175`). |
| `:187` | `codigos/{codigo}`: `read` autenticados (`:188`); `create` propio y con el `busPlate` de la ficha del conductor (`:190`); `update` sin cambiar `driverUid` ni `busPlate` (`:197`); `delete` admin (`:203`). |
| `:228` | `recogida/{studentId}`: `read` padre dueño, conductor del bus o admin (`:229`); `create/update` con `parentUid == auth.uid` y `esMiHijo(studentId)` (`:234`); `delete` padre o admin (`:238`). |

**Las tres cosas que hay que saber explicar:**

1. **`estudiantes` y `recogida` se leen por campo directo, sin `get(...)` en el `read`.** La lista del padre es una consulta `where('parentUid', '==', uid)`; Firestore solo puede demostrar que todos los resultados cumplen la regla si el campo se compara directo. Un `get` con valor por defecto ahí deniega la colección entera.
2. **`buses` no está abierto a "cualquier autenticado" en escritura.** Si lo estuviera, un conductor podría secuestrar el bus de otro escribiendo su uid en la placa ajena, y el padre vería la ruta equivocada.
3. **`recogida` ya no lo lee cualquier autenticado.** Lleva nombre del hijo, nombre y teléfono del padre. Por eso el conductor publica la copia anónima en `buses/{placa}.paradasPublicas`.

**La aprobación del conductor NO vive en las reglas:** vive en `session_router.dart` (navegación). Las reglas no impiden que un conductor no aprobado escriba `buses`, `rutas` o `recogida`; cerrar eso obligaría a un `get(usuarios/$(uid)).isApproved` en cada `allow`. Es una decisión de producto, no un descuido.

**Las reglas se compilan, no se prueban.** Un deploy viejo es indistinguible de un bug de código. No hay suite de reglas en este repo.

---

## 13. Listeners de Firestore: `StreamsDeDocumento` y `CanalCompartido`

### `lib/services/document_stream.dart`

| Línea | Qué hace |
|---|---|
| `:24` | `StreamsDeDocumento`. |
| `:31` | `de(ruta)` → stream memoizado de `doc(ruta).snapshots()`. |
| `:44` | `deConsulta(clave, crear)` → stream memoizado de un `where(...).snapshots()`. La clave la pone quien llama porque una consulta no tiene ruta única. |
| `:55` | `olvidar(ruta)`: cierra y suelta el canal. **Hoy no lo llama nadie.** |

### `lib/services/canal_compartido.dart`

| Línea | Qué hace |
|---|---|
| `:18` | `CanalCompartido<T>`. |
| `:24` | `StreamController.broadcast` con `onListen` / `onCancel`. |
| `:30` | **`stream` es siempre el mismo objeto** y hace replay del último evento antes de reenviar los siguientes. |
| `:47` | `_abrir()`: una sola suscripción a la fuente. |
| `:57` | Los errores (p. ej. `permission-denied`) se reenvían; no se tragan. |
| `:65` | `_cerrar()` al quedarse sin oyentes. |
| `:71` | `descartar()`. |

**El problema que resuelven (explicación de 30 segundos):** `FirebaseFirestore.instance.doc(ruta).snapshots()` evaluado dentro de `build` devuelve un objeto **nuevo** en cada rebuild, y `StreamBuilder` decide si resuscribe comparando identidad. Resultado: cada `setState` abría otro listen target. En web llegaba a fallar con `FIRESTORE INTERNAL ASSERTION FAILED` en `WatchChangeAggregator`. El caché devuelve siempre la misma instancia.

**Por qué no basta el caché:** `Query.snapshots()` es un stream **broadcast**, y un broadcast no guarda el último evento para quien llega después. Sin replay, la segunda pantalla (el panel ya suscrito debajo) se quedaba en `ConnectionState.waiting` con el spinner girando para siempre. Pasaba con "Mis datos" del padre y del conductor.

**Invariantes que no se pueden romper:** el `stream` devuelto es siempre el mismo objeto, y el replay entrega el valor **antes** de reenviar los siguientes. `test/canal_compartido_test.dart` cubre las dos cosas.

---

## 14. Servicios de apoyo

| Archivo | Qué hace |
|---|---|
| `lib/services/route_service.dart:43` | `RouteService`: pide la ruta a **OSRM** y parsea GeoJSON `[lng,lat]` → `LatLng(lat,lng)`. `calcular` en `:52`, `parsear` en `:80` (estático y testeado). `RutaCalculada` en `:9`. |
| `lib/services/google_auth.dart` | Google Sign-In multiplataforma (ver §3.2). |
| `lib/services/session_prefs.dart` | "Recordarme" y `sesion_correo` (ver §2.3). |
| `lib/services/ubicacion_actual.dart` | Permiso y posición del usuario (ver §7). |
| `lib/services/phone_launcher.dart:9` | `PhoneLauncher.llamar`: normaliza a dígitos y `+` (`:13`) y abre `tel:` (`:20`). |
| `lib/services/hijos_service.dart` | Hijos, códigos y sincronización (ver §9.2). |
| `lib/services/bus_location_service.dart` | GPS del conductor (ver §7). |

**Nota sobre `RouteService`:** OSRM es un servicio público ajeno. Se envía un `User-Agent` de navegador (`:49`) porque el de `dart:io` puede recibir 403. Usa `debugPrint` y devuelve `null` si falla; la pantalla simplemente no dibuja polilínea.

**Nota sobre el buscador de lugares:** `lib/services/place_search.dart` y `lib/services/photon_place_search.dart` **ya no existen**. El conductor elige el colegio con `MapPickerScreen` (mapa), tocando el pin. No hay typeahead ni API de lugares en el proyecto.

---

## 15. Pantallas secundarias

| Pantalla | Archivo:línea | Qué hace |
|---|---|---|
| Bienvenida | `lib/screens/splash_screen.dart:14` | Logo, ilustración y los dos accesos. **No toca Firebase** (por eso el widget test puede renderizarla). |
| Selector de mapa | `lib/screens/map_picker_screen.dart:18` | Centro inicial (`:85`), "Mi ubicación" (`:111`), atajos a ajustes (`:134`), `GoogleMap` en `:184`. |
| Acerca de | `lib/screens/acerca_de_screen.dart:18` | Versión (`kBusTrackVersion` en `:14`), correo del admin copiable (`:155`), servicios usados. |
| Mis datos (padre) | `lib/screens/parent_datos_screen.dart:18` | Datos del padre en vivo. |
| Mis datos (conductor) | `lib/screens/driver_datos_screen.dart:17` | Datos del conductor en vivo. |
| Editar padre | `lib/screens/parent_edit_screen.dart:19` | Nombre y teléfono; `_guardar` en `:51` y `sincronizarTelefonoPadre`. |
| Cambiar contraseña | `lib/screens/change_password_screen.dart:15` | `_cambiar` en `:46`. |
| Vehículo (padre) | `lib/widgets/parent_vehiculo_view.dart:19` | Datos del bus/conductor; `_contactar` en `:211` (llama con `PhoneLauncher`). |

---

## 16. Widgets compartidos

| Widget | Archivo:línea | Qué hace |
|---|---|---|
| `BusNavBar` | `lib/widgets/bus_nav_bar.dart:25` | Barra de 4 destinos para padre y conductor. `BusNavDestino` en `:7`. |
| `BusHeader`, `BusPageHeader`, `BusCard`, `BusInfoBox`, `BusStatusPill`, `BusIconBadge`, `BusPrimaryButton`, `BusEmptyState`, `BusOpcion`, `BusSeccion`, `BusDato` | `lib/widgets/bus_ui.dart:35, 168, 242, 278, 429, 487, 520, 601, 656, 736, 808` | La familia visual de los paneles. |
| `GradientField` | `lib/widgets/gradient_field.dart:13` | El campo **compartido** de login/registro. Dueña de su controller/focus node. No escribas un `TextField` nuevo en esas pantallas. |
| `GoogleButton` | `lib/widgets/google_button.dart:36` | Blanco con borde; **no** debe parecerse al botón principal. |
| `BusMarker` | `lib/widgets/bus_marker.dart:17` | Icono/bitmap del bus. |
| `AdminDrawer` | `lib/widgets/admin_drawer.dart` | Menú lateral del admin (`SeccionAdmin`). |
| `ItinerarioTimeline` | `lib/widgets/itinerario_timeline.dart:53` | Lista de paradas con hora. |
| `RecorridoBusView` | `lib/widgets/recorrido_bus_view.dart:49` | Pestaña "Recorrido" (ver §8). |
| `ParentMapView` | `lib/widgets/parent_map_view.dart:53` | Mapa del padre (ver §5). |

**Reglas de diseño:** botones de 48 px de alto (touch target), tarjetas de rol de 88, etiquetas largas en `FittedBox(fit: BoxFit.scaleDown)`. Opacidad siempre con `withValues(alpha: ...)`, no `withOpacity`.

---

## 17. Tests (`test/`, 17 tests)

| Archivo | Tests | Qué cubre |
|---|---|---|
| `test/canal_compartido_test.dart` | 5 | Identidad estable del stream, replay al oyente tardío, reapertura al quedarse sin oyentes, reenvío de errores y `descartar()`. **Es el test de regresión del spinner infinito.** No necesita red ni Firebase. |
| `test/estudiantes_conductor_test.dart` | 6 | `fusionarEstudiantes` (`driver_ruta_screen.dart:122`): vinculado sin punto visible, teléfono desde `recogida`, hijo legado sin fila en `estudiantes`, sin duplicados, filtrado por placa. |
| `test/route_service_test.dart` | 4 | `RouteService.parsear` con payloads guardados: GeoJSON, distancia/duración, casos inválidos. Sin red. |
| `test/widget_test.dart` | 2 | `find.text('Iniciar sesión')` y `find.text('Registrarse')` en `BusTrackApp()`. |

**Detalle importante del widget test:** hace `pump` de `BusTrackApp()` directamente, saltándose `main()` y por tanto `Firebase.initializeApp`. No llames a Firebase desde un `build`/`initState` que le agregues a la pantalla de bienvenida/login: no hay mocks de Firebase en `dev_dependencies`.

**Nunca `pumpAndSettle` después de tocar "Continuar con Google"**: la llamada falla rápido bajo el arnés, el `finally` deja `_isLoading` en true un tick mientras entra el SnackBar y puede expirar. Usa `tester.pump(Duration)` explícito.

---

## 18. Configuración Android

### `android/app/src/main/AndroidManifest.xml`

| Línea | Permiso / declaración | Por qué |
|---|---|---|
| `:5` | `INTERNET` | Flutter solo lo declara en debug/profile: sin esto, la build de **release** no tendría red y Firestore fallaría en silencio. |
| `:26` | `READ_MEDIA_IMAGES` | Requerido desde Android 13 (API 33). |
| `:27` | `CAMERA` | `mobile_scanner` abre la cámara **desde la app**; sin `CAMERA`, Android niega sin diálogo y el escáner queda negro. |
| `:28` | `uses-feature camera required="false"` | Para no excluir equipos sin cámara: escribir el código a mano sigue siendo el fallback. |
| `:33` | `ACCESS_FINE_LOCATION` | GPS del conductor. |
| `:34` | `ACCESS_COARSE_LOCATION` | Permiso aproximado. |
| `:35` | `FOREGROUND_SERVICE` | Servicio de ubicación. |
| `:36` | `FOREGROUND_SERVICE_LOCATION` | Android 14+: seguir enviando posición con la pantalla bloqueada. |
| `:43` | `POST_NOTIFICATIONS` | Android 13+: sin la notificación del servicio, algunos fabricantes matan el proceso y el bus parece "congelado". |
| `:45` | `READ_EXTERNAL_STORAGE` con `maxSdkVersion="32"` | Solo teléfonos viejos; sin el tope, Play lo marca como over-request. |
| `:76` | `com.google.android.geo.API_KEY` con el valor `${mapsApiKey}`. La clave real la inyecta Gradle desde `android/local.properties` (`MAPS_API_KEY`), que no se versiona. Si se restringe en Google Cloud, debe incluir el paquete y la SHA-1. |
| `:90` | `<queries>` `PROCESS_TEXT` y `DIAL` (`tel:`) | Android 11+ exige declarar el esquema para abrir el marcador. |

**Un permiso que no está en el manifiesto no se puede conceder.** `Permission.X.request()` devuelve `denied` sin mostrar diálogo y el código parece roto sin razón visible.

### `android/app/build.gradle.kts`

| Línea | Qué hace |
|---|---|
| `:11` | `namespace = "com.practica.bus_track"`. |
| `:12` | `compileSdk = 36`. |
| `:22` | `applicationId = "com.practica.bus_track"`. |
| `:25` | `minSdk = flutter.minSdkVersion`. |
| `:26` | `targetSdk = 36`. |
| `:31` | `versionCode` / `:32` `versionName` desde `pubspec.yaml`. |
| `:39` | **`signingConfig = signingConfigs.getByName("debug")`**: el release se firma con la keystore de debug, así que cualquiera puede compilar sin keystore propia. Esa es la SHA-1 que hay que registrar en Firebase. |
| final | Bloque que lee `android/local.properties` y publica `MAPS_API_KEY` como `manifestPlaceholders["mapsApiKey"]`. Si la propiedad no está, el placeholder queda vacío y el mapa sale gris, pero el build termina. |

### Archivos de configuración que no se versionan

| Archivo | Plantilla en el repo | Qué lleva |
|---|---|---|
| `android/app/google-services.json` | `android/app/google-services.json.example` | Identificadores del proyecto de Firebase y la huella SHA-1 registrada. Lo genera `flutterfire configure`. |
| `android/local.properties` | `android/local.properties.example` | `sdk.dir`, `flutter.sdk` y `MAPS_API_KEY`. Lo genera Flutter a medias; la línea de Maps la pone el usuario. |
| `lib/firebase_options.dart` | el propio archivo, con marcadores | Se sobrescribe al correr `flutterfire configure`. |

### `pubspec.yaml`

| Línea | Qué hace |
|---|---|
| `:6` | `version: 1.0.0+1`. |
| `:9` | `sdk: ^3.13.3`. |
| `:14`–`:16` | `firebase_core`, `firebase_auth`, `cloud_firestore`. |
| `:22` | `google_sign_in: ^7.1.1`. |
| `:23` | `permission_handler`. |
| `:26` | `google_maps_flutter`. |
| `:27` | `geolocator`. |
| `:28` | `file_picker`. |
| `:30` | `google_fonts`. |
| `:32` | `image` (reducción de adjuntos en isolate). |
| — | `qr_flutter`, `mobile_scanner`, `url_launcher`, `shared_preferences`, `http`, `intl` y los assets declarados. |

**La versión de la app está en dos sitios que deben coincidir a ojo:** `pubspec.yaml:6` (`1.0.0+1`) y `lib/screens/acerca_de_screen.dart:14` (`kBusTrackVersion = '1.0.0'`). Es una constante local, sin `package_info_plus`.

---

## 19. Código muerto (no alcanzable desde `home:`)

Nada importa esto. No asumas que se renderiza ni lo edites esperando un efecto visible:

- `lib/role_selection_screen.dart` — **duplicado** de `lib/screens/role_selection_screen.dart`, mismo nombre de clase. Solo se importa el de `screens/`.
- `lib/screens/home_screen.dart` (`PantallaPrincipalBusTrack`) + `lib/widgets/landscape_painter.dart`.
- `lib/main_navigation_screen.dart` y, transitivamente, `history_screen.dart`, `alerts_screen.dart`, `profile_screen.dart`.
- `lib/widgets/bus_track_bottom_nav_bar.dart` — reemplazado por `bus_nav_bar.dart`.
- `lib/widgets/action_button.dart` (`ActionButton`) y `lib/settings_screen.dart`.

**Assets vacíos:** las carpetas `assets/audios`, `assets/jsons`, `assets/pdfs`, `assets/rive_animations` y `assets/videos` solo contienen un `.gitkeep`. Los assets reales son `assets/icon/app_icon.png` y `assets/images/Gemini_Generated_Image_cbhrgpcbhrgpcbhr.jpg` (fondo del login).

---

## 20. Preguntas típicas y respuesta corta

**"¿Dónde está el mapa que ve el padre?"**
`lib/widgets/parent_map_view.dart:874`, dentro de `_buildMapa()` (`:873`), que se pinta desde `ParentMapView.build` (`:815`). El panel lo inserta en `lib/parent_home_screen.dart:268`.

**"¿Y el del conductor?"**
`lib/screens/driver_ruta_screen.dart:1492`, dentro de `_buildMapa()` (`:1485`), en la pestaña "Ruta" (`:1221`).

**"¿Cómo se dibuja la línea de la ruta?"**
Se pide a OSRM (`lib/services/route_service.dart:52`), se guardan los puntos y se pinta una `Polyline`: padre en `parent_map_view.dart:891`, conductor en `driver_ruta_screen.dart:1689`.

**"¿Cómo sabe el padre dónde está el bus?"**
El conductor escribe `buses/{placa}` con el GPS (`bus_location_service.dart:58`); el padre escucha ese documento (`parent_map_view.dart:253`) y coloca el marcador (`:913`).

**"¿Cómo se marca que el hijo subió al bus?"**
El conductor pulsa "Ya recogí" → `_marcarSubio` (`driver_ruta_screen.dart:871`) escribe `subioEn`. El padre lo lee de `rutas/{driverUid}.estadoParadas` (`parent_map_view.dart:384`) y actualiza `_subidos`.

**"¿Cómo se avisa al padre de que el bus llegó?"**
El conductor no escribe en `recogida` (no tiene permiso). Lo marca en `rutas/{uid}.estadoParadas` (`llegoEn`). El padre lo detecta (`parent_map_view.dart:444`), muestra el SnackBar (`:628`) y confirma escribiendo `recogida/{studentId}.avisoVistoEn` (`:664`). Si no responde en 10 s, se auto-confirma (`:651`).

**"¿Cómo se vinculan padre y conductor?"**
El conductor genera un código de 6 caracteres (`hijos_service.dart:259`) y lo comparte como QR (`driver_qr_screen.dart`) o a mano. El padre lo escribe o lo escanea (`child_form_screen.dart:88`), se resuelve con `resolverCodigo` (`hijos_service.dart:118`) y el hijo queda con `busPlate`/`driverUid`. Las reglas exigen que el `busPlate` venga con un código activo que apunte a esa placa (`firestore.rules:122`).

**"¿Por qué un conductor no puede entrar sin aprobación?"**
Porque `session_router.dart:71` (login) y `:239` (arranque desde caché) lo mandan a `PantallaSolicitudRevision` si `isApproved != true`. Es una puerta de navegación, no de reglas.

**"¿Qué pasa si rechazan al conductor?"**
No se borra su ficha: se guarda `estadoSolicitud: 'rechazado'` + `motivoRechazo` (`admin_service.dart:33`). Al volver a entrar ve el motivo y puede corregir y reenviar, conservando los adjuntos.

**"¿Por qué el padre no ve los datos de los otros niños?"**
Porque `recogida` solo la leen el padre dueño, el conductor y el admin (`firestore.rules:229`). El padre ve los puntos de los demás como `{id, lat, lng}` anónimos en `buses/{placa}.paradasPublicas`, que publica el conductor (`driver_ruta_screen.dart:570`).

**"¿Por qué el spinner de 'Mis datos' giraba para siempre?"**
Porque `snapshots()` es broadcast y no repite el último evento a un oyente tardío. Lo resuelve `CanalCompartido` (`canal_compartido.dart:30`), y el test de regresión está en `test/canal_compartido_test.dart`.

---

## 21. Cómo verificar que todo sigue en pie

Los únicos gates son manuales (no hay CI, ni pre-commit, ni task runner):

```
flutter analyze      # debe salir limpio
flutter test         # 17/17
flutter build apk --release
```

El build de release deja `build/app/outputs/flutter-apk/app-release.apk` (~77 MB).

Para comprobar la firma real del APK:

```
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

(necesita `JAVA_HOME`; `apksigner` está en `%LOCALAPPDATA%\Android\Sdk\build-tools\<versión>\`).

---

## 22. Deuda conocida y avisos

- **El repositorio público no lleva credenciales.** `google-services.json` y `local.properties` están en `.gitignore`; `firebase_options.dart` y `web/index.html` traen marcadores. Los pasos para configurarlo están en el `README.md`. Si algo falla al arrancar ("Firebase no configurado", mapa en gris), lo primero es revisar esos tres archivos.
- **Google Sign-In depende de la consola de Firebase**, no solo del código: la SHA-1 de la keystore con la que se firma el APK debe estar registrada. Un `operation-not-allowed` o un `clientConfigurationError` no se arreglan cambiando Dart.
- **El admin está duplicado** en `lib/admin_service.dart:5` y `firestore.rules:12`. Cambiar uno sin el otro produce o un pass de cliente con rechazo de reglas, o un admin de reglas sin UI.
- **`StreamsDeDocumento.olvidar` no lo llama nadie.** No lo presentes como parte del flujo.
- **La app no tiene notificaciones push ni distribución automatizada.** Son mejoras futuras, no funcionalidad existente.
- **No hay prueba de punta a punta en dispositivo/emulador** en el entorno de desarrollo actual; solo `analyze`, `test` y build.
