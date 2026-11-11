# BusTrack

Aplicación Flutter para **Android** que hace seguimiento del bus escolar en
tiempo real: el conductor comparte la ubicación del bus, el padre ve dónde va su
hijo y el administrador aprueba a los conductores antes de que puedan operar.

Trabajo académico. La interfaz, los comentarios del código y las reglas de
seguridad están **en español** a propósito.

| | |
|---|---|
| Versión | 1.0.0 (`1.0.0+1`) |
| Plataforma objetivo | Android (`compileSdk`/`targetSdk` 36) |
| Paquete | `com.practica.bus_track` |
| Backend | Firebase Authentication + Cloud Firestore |
| Estado | `flutter analyze` limpio, `flutter test` 17/17, `flutter build apk --release` OK |

> **Este repositorio no incluye credenciales.** La configuración de Firebase y
> la clave de Google Maps vienen como plantillas (`.example`). Para compilar y
> ejecutar contra tu propio proyecto hay que completar tres pasos; están en
> [Configuración local](#configuración-local).

## Qué hace

### Padre

- Mapa en vivo con la posición del bus y la ruta que le falta por recorrer.
- Varios hijos por cuenta, cada uno puede ir en un bus distinto.
- Vinculación al bus con un **código de seis caracteres o un QR** que comparte
  el conductor; nunca escribiendo la placa a mano.
- Punto de recogida propio sobre el mapa: tocando el mapa o con "Mi ubicación".
- "Recorrido" con el itinerario de paradas y el estado de cada una.
- Datos y llamada al conductor, y edición del perfil y de los hijos.

### Conductor

- Ruta con paradas ordenadas; el colegio de destino se elige sobre el mapa.
- Inicio y fin de ruta, y marca de "Ya recogí" por estudiante.
- GPS con intervalo adaptativo: 5 s detenido, 2 s en ciudad, 1 s en carretera.
- QR de vinculación propio y lista de estudiantes con teléfono del padre.
- Solicitud de alta que el administrador revisa; si la rechaza, puede
  corregirla y reenviarla conservando los documentos ya subidos.

### Administrador

- Cola de conductores pendientes, con los documentos adjuntos.
- Aprobar o rechazar con motivo (el motivo se le muestra al conductor).
- Listado de usuarios totales y de perfiles aprobados.

### Común

- Login con correo/contraseña o con Google, y casilla "Recordarme".
- Arranque que restaura la sesión sin mostrar la bienvenida de más.
- Pantalla "Acerca de" con la versión y el correo de soporte.

## Stack

- **Flutter / Dart** (SDK `^3.13.3`), sin gestor de estado ni router: `Navigator`
  y `StreamBuilder`.
- **Firebase**: `firebase_auth`, `cloud_firestore`, `firebase_core`.
- **Mapas y ubicación**: `google_maps_flutter`, `geolocator`.
- **Autenticación Google**: `google_sign_in` 7.x (Credential Manager en Android).
- **QR**: `qr_flutter` (genera) y `mobile_scanner` (lee).
- **Archivos**: `file_picker`, `permission_handler`, `image` (compresión a
  JPEG 1280 px antes de subir).
- **Red**: `http` contra OSRM (OpenStreetMap) para el trazado por calles;
  `url_launcher` para llamar al conductor.
- **Preferencias**: `shared_preferences`.

## Requisitos

- Flutter 3.47.x (Dart 3.13).
- JDK 17 o superior (el que trae Android Studio sirve).
- Android SDK 36 y NDK (Gradle los descarga solo).
- En Windows: **Modo desarrollador** activado, o la terminal como
  administrador. Flutter necesita crear enlaces simbólicos para los plugins; si
  no, falla con `Building with plugins requires symlink support`.

```bash
flutter pub get
flutter analyze     # debe salir limpio
flutter test        # 17 tests
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk` (~77 MB).

## Configuración local

Los tres archivos de configuración **no se versionan** porque llevan
identificadores del proyecto de Firebase y la clave de Google Maps. En el repo
están sus plantillas.

### 1. Firebase (`android/app/google-services.json` y `lib/firebase_options.dart`)

La vía recomendada, que genera los dos de una vez:

```bash
npm install -g firebase-tools          # CLI de Firebase
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=tu-proyecto
```

Si prefieres hacerlo a mano, descarga `google-services.json` desde Firebase
Console → *Configuración del proyecto* → *Tus apps* → app Android
`com.practica.bus_track`, guárdalo en `android/app/` y rellena
`lib/firebase_options.dart` con los valores de *Configuración del proyecto*.
La plantilla comentada está en
[`android/app/google-services.json.example`](android/app/google-services.json.example).

### 2. Clave de Google Maps (`android/local.properties`)

`AndroidManifest.xml` no lleva la clave escrita: usa el marcador
`${mapsApiKey}`, que `android/app/build.gradle.kts` rellena desde
`android/local.properties`.

```properties
MAPS_API_KEY=tu_clave_de_google_maps
```

Plantilla completa en
[`android/local.properties.example`](android/local.properties.example).
Sin esta línea la app compila y arranca, pero el mapa sale en gris.

Restringe la clave en Google Cloud a la app Android `com.practica.bus_track` y a
tu huella SHA-1.

### 3. Google Sign-In

Login con Google solo funciona si la huella **SHA-1** del keystore con el que se
firma el APK está registrada en Firebase:

1. Obtén tu huella:
   - keystore de debug: `keytool -list -v -alias androiddebugkey -keystore %USERPROFILE%\.android\debug.keystore` (contraseña `android`);
   - o sobre el APK ya compilado: `apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk`.
2. Firebase Console → *Configuración del proyecto* → *Tus apps* →
   `com.practica.bus_track` → *Agregar huella digital* (SHA-1 y SHA-256).
3. Vuelve a descargar `google-services.json` (o corre `flutterfire configure`
   otra vez). La propagación tarda unos minutos.

Si el APK se firma con otra keystore, la huella cambia y Google Sign-In falla
con un error genérico aunque el resto de la app funcione.

> El build de release usa la keystore de **debug** (`android/app/build.gradle.kts`),
> así que la huella que cuenta es la de debug. Sirve para pruebas y entrega
> académica; **no** para publicar en Play Store.

### Reglas e índices de Firestore

Las reglas de seguridad son la autoridad del backend y viven en
**`firestore.rules`**. Hay que publicarlas en el proyecto para que coincidan con
el código:

```bash
firebase deploy --only firestore --project=tu-proyecto
```

Ese comando sube `firestore.rules` y `firestore.indexes.json` (el índice
compuesto que usa el panel de administrador). Unas reglas viejas producen
errores `permission-denied` que parecen bugs de código.

## Estructura

```
lib/
  main.dart              # arranque, tema y paleta
  admin_service.dart     # consultas y acciones del administrador
  parent_home_screen.dart
  screens/               # pantallas (login, paneles, registro, ruta, mapas...)
  services/              # Firebase, sesión, GPS, hijos, rutas, ubicación
  widgets/               # mapa, itinerario, navegación, campos compartidos
  models/                # Hijo, CodigoBus
test/                    # tests de lógica pura (sin red ni Firebase)
android/                 # manifiesto, Gradle y plantillas de configuración
firestore.rules          # reglas de seguridad (fuente de verdad)
firestore.indexes.json   # índices compuestos
```

## Documentación

- [`GUIA_DEL_CODIGO.md`](GUIA_DEL_CODIGO.md) — guía técnica: por dónde empieza
  la ejecución, cómo se comunican las pantallas, el esquema de Firestore, por
  qué cada regla está escrita así y preguntas frecuentes con referencias
  `archivo:línea`.
- [`MANUAL_DE_USUARIO.md`](MANUAL_DE_USUARIO.md) — guía para padres,
  conductores y administrador.

## Seguridad y datos

- No se publica ningún archivo con credenciales: ni `google-services.json`, ni
  `local.properties`, ni keystores (`*.jks`, `*.keystore`), ni APKs. Están todos
  en [`.gitignore`](.gitignore).
- Las claves de Firebase (`apiKey`, `appId`) no son contraseñas —viajan dentro
  del APK y son extraíbles—; la protección real son las reglas de Firestore.
  Aun así se dejan fuera por higiene y para que cada quien use su proyecto.
- El correo del administrador sí aparece en el código
  (`lib/admin_service.dart` y `firestore.rules`): es un dato de contacto, no una
  credencial. Si se cambia en un sitio hay que cambiarlo en el otro.

## Notas

- No hay CI, ni pre-commit, ni task runner: los únicos gates son manuales,
  `flutter analyze` y `flutter test`.
- El proyecto no usa Google Places ni ninguna API de pago: el mapa es Google
  Maps (con clave restringida) y el trazado de calles viene de OSRM, gratuito y
  sin cuenta.
- `permission_handler` y `file_picker` solo funcionan en dispositivos o
  emuladores reales, no en escritorio ni en tests.
