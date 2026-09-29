# fiscalizadores_satt

App Flutter para **Fiscalizacion de Predios** del SAT - Tarapoto.

## Que hace

- **Login** de fiscalizadores contra la API `/api/fiscalizadores/`.
- **FICHA DE INSPECCION DE PREDIO - FIP**: grilla con busqueda (numero de FIP, codigo o
  nombre del contribuyente), filtro de fechas, filtro por estado y paginacion.
  Desde ahi se registran, editan, consultan, ven imagenes y GPS, e **inhabilitan**
  fichas (nunca se borran).
- **CONSULTAS**: listado y detalle de fichas.
- **CONFIGURACION**: datos del fiscalizador y cambio de clave.

## Configuracion de la API

La URL base y la API key se inyectan en tiempo de build:

```
--dart-define=FISCALIZADORES_API_BASE_URL=http://190.119.38.13
--dart-define=FISCALIZADORES_API_KEY=L3nsd@ys
```

## Compilar el APK

```bat
build_apk.bat
```

Genera `build\app\outputs\flutter-apk\app-release.apk` y lo copia al recurso
compartido con el nombre `FISCALIZADORES-SATT-YYYYMMDD-HHMM.apk`.

## Backend

Vistas Django bajo el prefijo `/api/fiscalizadores/`, en el proyecto
`sistema_sat` (`controladores/api_municipalidad/`). La capa Flutter no usa modelos
ORM: consume la API por HTTP.

## Estructura

- `lib/screens/` pantallas (login, menu, grilla FIP, ficha, consultas, configuracion)
- `lib/services/` cliente HTTP y manejo de imagenes
- `lib/widgets/` widgets reutilizables de formulario
- `lib/app_theme.dart` paleta y tema
