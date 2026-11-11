# Manual de usuario — BusTrack

BusTrack es una app para Android que sigue en vivo el bus escolar de tus hijos.
El **padre** ve dónde va el bus, marca el punto donde recoge a su hijo y puede
llamar al conductor. El **conductor** comparte su ubicación, ve la lista de
estudiantes de su bus y registra cuándo recoge a cada uno. El **administrador**
aprueba las cuentas de los conductores.

> Esta versión se instala con un archivo APK, no desde Play Store. Las
> notificaciones automáticas todavía no existen: al padre le llega la
> información al abrir la app o al dejarla abierta.

---

## Contenido

1. [Instalar la app](#1-instalar-la-app)
2. [Crear una cuenta e iniciar sesión](#2-crear-una-cuenta-e-iniciar-sesión)
3. [Guía del padre](#3-guía-del-padre)
4. [Guía del conductor](#4-guía-del-conductor)
5. [Guía del administrador](#5-guía-del-administrador)
6. [Problemas frecuentes](#6-problemas-frecuentes)

---

## 1. Instalar la app

1. Copia el archivo `app-release.apk` al teléfono (por WhatsApp, cable USB,
   Google Drive, etc.).
2. Ábrelo desde el administrador de archivos o desde la notificación de
   descarga.
3. Si Android pregunta si permitir la instalación desde esa app, elige
   **Permitir** y vuelve a tocar el archivo.
4. Toca **Instalar**. Si aparece un aviso de "app desconocida", es normal: el
   APK no viene de Play Store.

Al abrir la app por primera vez verás la pantalla de bienvenida con dos botones:
**Iniciar sesión** y **Registrarse**.

---

## 2. Crear una cuenta e iniciar sesión

### Registro

1. En la bienvenida toca **Registrarse**.
2. Escribe correo y contraseña, o toca **Continuar con Google**.
3. Elige el tipo de cuenta:
   - **Padre de familia** — para seguir a un estudiante.
   - **Conductor** — para manejar un bus escolar.
4. Completa el formulario que corresponda (ver las guías más abajo).

### Iniciar sesión

1. Escribe tu correo y contraseña, o toca **Ingresar con Google**.
2. Deja marcada la casilla **Recordarme** si quieres que la sesión se conserve
   al cerrar la app. Si la desmarcas, la app cierra la sesión la próxima vez que
   la abras.
3. Si olvidaste la contraseña, toca **¿Olvidaste tu contraseña?**, escribe tu
   correo y revisa tu bandeja de entrada.

> Si el botón de Google falla con un mensaje de configuración, usa el ingreso
> por correo y contraseña mientras el administrador revisa el proyecto.

---

## 3. Guía del padre

### 3.1 Registro

El formulario **Registro de Padre** pide:

- **Nombre completo** y **número de teléfono** del padre.
- **Nombre del estudiante**, **edad** y **colegio** (edad y colegio son
  opcionales).
- **Código que te dio el conductor** (opcional). Si no lo tienes a mano, puedes
  dejar el campo vacío y vincular el bus después.

Al guardar entras directamente al panel.

### 3.2 Vincular a tu hijo con un bus

El código lo entrega el conductor. Tiene seis caracteres y no usa letras que se
confunden (`0`, `O`, `1`, `I`, `L`).

Desde **Mi Perfil → Mis hijos**:

1. Toca **Agregar hijo** (o el lápiz de un hijo existente).
2. Escribe el nombre del estudiante.
3. En **Código del conductor**, escribe el código o toca **Escanear QR** y
   apunta la cámara al QR que muestra el conductor.
4. Toca **Verificar**. Si el código es correcto, verás el bus y el nombre del
   conductor.
5. Toca **Guardar**.

Un hijo puede quedar **sin bus** si no tienes el código: se crea igual y lo
puedes vincular más adelante. Para cambiarlo de bus, abre su edición, toca
**Quitar vínculo con el bus** y verifica un código nuevo.

### 3.3 Marcar el punto de recogida

El conductor necesita saber dónde recoger a tu hijo.

1. En la pestaña **Ruta**, toca **Marcar mi punto de recogida** (o **Cambiar mi
   punto** si ya existe).
2. Mueve el mapa hasta que el pin quede en la entrada de tu casa o en el punto
   acordado.
3. Si el mapa no está cerca de ti, toca **Mi ubicación**. La primera vez
   Android pedirá permiso de ubicación: acéptalo. Si lo bloqueaste, el aviso
   ofrece un botón **Ajustes** para activarlo.
4. Toca **Guardar punto**.

El punto se puede cambiar o eliminar en cualquier momento desde la misma
pantalla. Si tu hijo todavía no tiene punto, en el mapa aparece el aviso para
marcarlo.

> Marcar el punto también comparte tu teléfono con el conductor de ese bus, para
> que él pueda llamarte desde la pestaña **Estudiantes**.

### 3.4 Las cuatro pestañas del panel

| Pestaña | Qué muestra |
| --- | --- |
| **Ruta** | Mapa en vivo con el bus, tu punto y el camino. Abre por defecto. |
| **Recorrido** | El itinerario completo con horas, paradas y el estado de cada una. |
| **Conductor** | Los datos del bus y del conductor, con el botón para llamarlo. |
| **Mi Perfil** | Tus datos, tus hijos, cambio de contraseña, "Acerca de" y cerrar sesión. |

**En la pestaña Ruta** verás el bus moviéndose y un panel con el estado del
viaje: si el bus viene hacia tu hijo, cuántas paradas faltan o si ya lo recogió.
Mientras tu hijo no haya subido, la línea del mapa va del bus a **tu** punto;
después apunta a la siguiente parada pendiente y, al final, al colegio.

**En Recorrido** el itinerario marca con color la parada actual y muestra la
hora de las que ya se atendieron.

### 3.5 Varios hijos

Un padre puede tener varios hijos, cada uno en un bus distinto. Cuando hay más
de uno, en la parte superior del panel aparece un selector: toca el nombre del
hijo para ver su ruta, su recorrido, su conductor y su punto.

Para volver a un hijo desde **Mis hijos**, toca su fila: el panel se abre con
ese hijo ya seleccionado.

### 3.6 Mis datos y contraseña

- **Mi Perfil → Mis datos** muestra tu nombre, correo y teléfono. Toca
  **Editar mis datos** para corregirlos. Al guardar, el teléfono nuevo se copia
  a los puntos de recogida de todos tus hijos.
- **Mi Perfil → Cambiar contraseña** pide la contraseña actual y la nueva.
- **Mi Perfil → Acerca de** muestra la versión de la app, el correo del
  administrador (toca para copiarlo) y los servicios que usa.
- **Mi Perfil → Cerrar sesión** vuelve a la pantalla de ingreso.

---

## 4. Guía del conductor

### 4.1 Registro y aprobación

El registro tiene dos páginas.

**Página 1 — Datos personales**

- Nombres y apellidos completos.
- Tipo y número de documento (cédula de ciudadanía, cédula de extranjería o
  pasaporte).
- **Teléfono de contacto** (obligatorio; es el número que verán los padres).
- Una **selfie** para la verificación.

**Página 2 — Vehículo y documentos**

- **Placa** del bus (por ejemplo `ABC123`), marca, modelo y año.
- **Documentos**: cédula y licencia de conducción son obligatorios; SOAT y
  tecnomecánica son opcionales.
- Toca **Enviar a Aprobación**.

Después de enviar verás la pantalla **Solicitud enviada**. El administrador
debe aprobar la cuenta y **mientras no la apruebe no podrás entrar al panel**:
si vuelves a abrir la app, verás esa misma pantalla con el estado de tu
solicitud.

Si el administrador **rechaza** la solicitud, la pantalla mostrará el motivo y
tendrás un botón **Corregir y reenviar**: abre el formulario con tus datos ya
cargados (no tienes que volver a subir los documentos que no cambies) y la
solicitud vuelve a la cola de pendientes.

### 4.2 Código del bus (QR)

En la parte superior del panel hay un botón de QR. Ábrelo para ver el **código
del bus**:

- **Copiar código**: solo el código.
- **Copiar mensaje para WhatsApp**: un texto listo para enviar al padre.
- **Cambiar el código**: desactiva el anterior. Un padre que tenga el código
  viejo deberá pedirte el nuevo.

El padre puede escribir el código o escanear el QR desde **Mis hijos**.

### 4.3 Las cuatro pestañas del panel

| Pestaña | Qué hace |
| --- | --- |
| **Ruta** | Mapa en vivo y control del viaje. Abre por defecto. |
| **Recorrido** | El itinerario que también ve el padre. |
| **Estudiantes** | Los hijos vinculados a tu bus y el botón para llamar al padre. |
| **Mi Perfil** | Tus datos, cambio de contraseña, "Acerca de" y cerrar sesión. |

### 4.4 Iniciar la ruta

1. En **Ruta**, toca **Elegir colegio en el mapa**.
2. Mueve el mapa y pon el pin sobre el colegio de destino.
3. Escribe el nombre del colegio y confirma.
4. Toca **Iniciar Ruta**. La app pedirá permiso de ubicación y de
   notificaciones; acéptalos para que el seguimiento no se corte al bloquear la
   pantalla.
5. Mantén la app abierta o en segundo plano con la ruta activa. El padre verá
   tu posición en vivo.

Durante la ruta el panel muestra la **siguiente parada** y la distancia. Cuando
llegues, toca **Ya recogí a [nombre]** para cerrar esa parada y pasar a la
siguiente. Cuando ya no queden paradas pendientes, el panel lo indica y la línea
del mapa apunta al colegio.

Al terminar, toca **Finalizar Ruta**. El viaje queda guardado en el recorrido
del padre y el mapa deja de mostrar el bus.

### 4.5 Pestaña Estudiantes

La lista muestra **todos** los hijos vinculados a tu bus, aunque el padre
todavía no haya marcado el punto de recogida:

- Con punto: aparece `Padre: [nombre]` y el botón de llamada está activo.
- Sin punto: aparece **Sin punto de recogida**, y el botón de llamada queda
  deshabilitado porque el teléfono del padre viaja con ese punto. En ese caso
  pídele que lo marque desde su pestaña **Ruta**.

Esta pestaña **no** marca recogidas: eso se hace en **Ruta** con **Ya recogí**.

### 4.6 Mis datos

**Mi Perfil → Mis datos** muestra tu cuenta y los datos del bus. **Cambiar
contraseña**, **Acerca de** y **Cerrar sesión** están en la misma lista.

---

## 5. Guía del administrador

El administrador entra con su correo autorizado y ve un panel con un menú
lateral (las tres líneas de la banda superior). Las secciones son:

| Sección | Qué lista |
| --- | --- |
| **Usuarios totales** | Todas las cuentas (padres y conductores). |
| **Solicitudes de Conductores pendientes** | Conductores que todavía no fueron aprobados. |
| **Perfiles de Conductores Aprobados** | Conductores ya habilitados. |

### Revisar una solicitud

1. Abre **Solicitudes de Conductores pendientes**.
2. Toca **Ver** en la fila del conductor.
3. Revisa sus datos, su teléfono, el bus y los documentos adjuntos. Los
   archivos se pueden abrir desde la misma hoja.
4. Elige:
   - **Aprobar**: la cuenta queda aprobada y el conductor puede entrar al panel.
   - **Rechazar**: te pide un **motivo**, que el conductor verá en su pantalla
     de solicitud para poder corregir y reenviar. La ficha **no se borra**. En
     la lista de pendientes solo aparecen conductores, así que el botón no
     afecta a los padres.

La hoja de un padre carga bajo demanda a sus hijos registrados.

---

## 6. Problemas frecuentes

### "Me saca de la cuenta" al abrir la app

La app guarda la sesión y la restaura al arrancar. Si desmarcaste
**Recordarme**, es normal que te pida entrar otra vez. Si la desmarcaste sin
querer, inicia sesión y deja la casilla marcada.

### Envié mi solicitud de conductor y no puedo entrar al panel

Mientras el administrador no apruebe la cuenta, la app muestra la pantalla de
**Solicitud enviada** en vez del panel. Si fue **rechazada**, ahí verás el
motivo y el botón **Corregir y reenviar**. Revisa también que hayas iniciado
sesión con el mismo correo con el que te registraste.

### No puedo entrar con Google

Usa el correo y la contraseña mientras se habilita el proveedor de Google. Si
escribes por correo, asegúrate de tocar **Iniciar sesión** y no el botón de
Google: los dos botones están a la vista y el segundo se reconoce por el logo de
Google.

### "Mi ubicación" no funciona en el mapa

La app pide el permiso de ubicación la primera vez que tocas ese botón.
Si lo negaste:

1. Toca **Mi ubicación** otra vez y acepta el permiso.
2. Si no aparece el diálogo, abre **Ajustes del teléfono → Apps → BusTrack →
   Permisos → Ubicación** y elige **Permitir solo con la app abierta**.
3. Activa también la ubicación (GPS) del teléfono.

Sin señal de GPS (interiores, sótanos) la app usa tu última ubicación conocida
y te lo avisa.

### El bus no aparece en el mapa

- El conductor debe haber tocado **Iniciar Ruta**.
- El teléfono del conductor debe tener GPS e internet.
- Tu hijo debe estar vinculado al bus correcto. Revisa **Mis hijos** y el
  código.

### Mi hijo no aparece en la lista del conductor

Revisa que el hijo esté vinculado al bus (código o QR) y que el conductor haya
abierto la app después del vínculo. Aunque no tenga punto de recogida,
aparecerá con **Sin punto de recogida**; para que aparezca la llamada, marca el
punto.

### El mapa muestra una línea recta en vez del camino

La app calcula el camino con un servicio público gratuito. Si falla o no hay
internet, dibuja una línea recta entre los puntos; la posición del bus sigue
siendo real. Vuelve a intentarlo cuando tengas conexión.

### No recibo avisos cuando el bus está cerca

Esta versión **todavía no envía notificaciones**. Debes abrir la app y mirar la
pestaña **Ruta** o **Recorrido**. Las notificaciones quedaron para una versión
posterior.

### El escáner de QR se queda en negro

Android necesita permiso de cámara. Si lo negaste, actívalo en **Ajustes del
teléfono → Apps → BusTrack → Permisos → Cámara**. Como alternativa, escribe el
código de seis caracteres a mano.

### El conductor adjunta documentos y no lo deja

El selector de archivos no necesita permisos especiales en Android moderno. Si
la app avisa de un permiso denegado, puedes seguir usando el selector; si el
aviso ofrece **Ajustes**, actívalo desde ahí.

---

## Recomendaciones

- Mantén el GPS y los datos móviles encendidos en el teléfono del conductor.
- No fuerces el cierre de la app del conductor durante la ruta.
- Marca el punto de recogida en un lugar seguro y reconocible (portería,
  esquina, entrada del conjunto).
- Si cambias de número de teléfono, actualízalo en **Mis datos** para que el
  conductor y los administradores vean el correcto.
- Comparte el código del bus solo con los padres que correspondan; si se
  filtró, usa **Cambiar el código**.
