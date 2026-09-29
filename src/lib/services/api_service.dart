import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/fiscalizador_sesion.dart';

/// Error de negocio devuelto por la API (mensaje ya listo para mostrar).
class ApiException implements Exception {
  final String mensaje;
  final int codigo;

  const ApiException(this.mensaje, [this.codigo = 0]);

  @override
  String toString() => mensaje;
}

/// Resultado de una pagina de la grilla de Fichas de Inspeccion de Predio.
class GrillaFichas {
  final List<Map<String, dynamic>> fichas;
  final int total;
  final int pagina;
  final int limite;
  final int paginas;

  const GrillaFichas({
    required this.fichas,
    required this.total,
    required this.pagina,
    required this.limite,
    required this.paginas,
  });

  /// Numero de la primera fila mostrada (0 si no hay resultados).
  int get desde => total == 0 ? 0 : (pagina - 1) * limite + 1;

  /// Numero de la ultima fila mostrada.
  int get hasta => (pagina * limite) > total ? total : pagina * limite;
}

class ApiService {
  static const String _fiscalizadoresBaseUrl = String.fromEnvironment(
    'FISCALIZADORES_API_BASE_URL',
    defaultValue: 'http://190.119.38.13',
  );
  static const String _fiscalizadoresApiKey = String.fromEnvironment(
    'FISCALIZADORES_API_KEY',
    defaultValue: 'L3nsd@ys',
  );

  static const Duration _timeout = Duration(seconds: 45);
  static const Duration _timeoutCarga = Duration(seconds: 120);

  /// URL del servidor municipal (solo lectura, para mostrar en Configuracion).
  static String get baseUrl => _fiscalizadoresBaseUrl;

  static Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        'X-API-Key': _fiscalizadoresApiKey,
      };

  static Uri _uri(String ruta, [Map<String, dynamic>? query]) {
    final base = _fiscalizadoresBaseUrl;
    return Uri.parse('$base$ruta').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
  }

  // =========================================================================
  // Utilidades
  // =========================================================================
  static Map<String, dynamic> _decodificar(http.Response res) {
    dynamic data;
    try {
      data = jsonDecode(res.body);
    } catch (_) {
      if (res.statusCode >= 500) {
        throw ApiException('El servidor no responde correctamente.', res.statusCode);
      }
      throw ApiException('Respuesta inválida del servidor.', res.statusCode);
    }
    if (data is! Map<String, dynamic>) {
      throw ApiException('Respuesta inválida del servidor.', res.statusCode);
    }
    if (res.statusCode != 200) {
      final detalle = (data['detail'] ?? data['mensaje'] ?? '').toString();
      throw ApiException(
        detalle.isEmpty ? _mensajePorCodigo(res.statusCode) : detalle,
        res.statusCode,
      );
    }
    return data;
  }

  static String _mensajePorCodigo(int codigo) {
    switch (codigo) {
      case 400:
        return 'Los datos enviados no son válidos.';
      case 401:
        return 'No autorizado. Verifique la clave de la aplicación.';
      case 404:
        return 'No se encontró la información solicitada.';
      case 503:
        return 'El servicio no está disponible. Inténtalo de nuevo.';
      default:
        return 'Ocurrió un error inesperado ($codigo).';
    }
  }

  /// Envuelve errores de red en mensajes entendibles.
  static Future<T> _conRed<T>(Future<T> Function() accion) async {
    try {
      return await accion();
    } on ApiException {
      rethrow;
    } on http.ClientException {
      throw ApiException('No se pudo conectar con el servidor. Revise su conexión.');
    } on SocketException {
      throw ApiException('Sin conexión a la red municipal.');
    } on FormatException {
      throw ApiException('Respuesta inválida del servidor.');
    } on TimeoutException {
      throw ApiException('El servidor tardó demasiado en responder. Inténtalo de nuevo.');
    } on HandshakeException {
      throw ApiException('No se pudo establecer una conexión segura.');
    }
  }

  // =========================================================================
  // Autenticación
  // =========================================================================
  static Future<FiscalizadorSesion> login(String dni, String clave) async {
    if (_fiscalizadoresApiKey.isEmpty) {
      throw ApiException('La aplicación no tiene configurada la clave de acceso.');
    }

    return _conRed(() async {
      final res = await http
          .post(
            _uri('/api/fiscalizadores/login/'),
            headers: _headers,
            body: jsonEncode({'dni': dni, 'clave': clave}),
          )
          .timeout(_timeout);
      final data = _decodificar(res);
      return _parseFiscalizadorSesion(data, dni);
    });
  }

  /// Cambia la clave del fiscalizador. Devuelve un mensaje de confirmacion.
  static Future<String> cambiarClave({
    required String dni,
    required String claveActual,
    required String claveNueva,
  }) async {
    return _conRed(() async {
      final res = await http
          .post(
            _uri('/api/fiscalizadores/cambiar-clave/'),
            headers: _headers,
            body: jsonEncode({
              'dni': dni,
              'clave_actual': claveActual,
              'clave_nueva': claveNueva,
            }),
          )
          .timeout(_timeout);
      final data = _decodificar(res);
      return (data['detalle'] ?? 'Clave actualizada correctamente.').toString();
    });
  }

  static FiscalizadorSesion _parseFiscalizadorSesion(
      Map<String, dynamic> data, String dni) {
    final fiscal = data['fiscalizador'];
    if (data['status'] != 'ok' || fiscal is! Map<String, dynamic>) {
      throw ApiException('El servidor no devolvió una sesión válida. Intente nuevamente.');
    }
    final id = fiscal['id'];
    final idNum = id is num ? id.toInt() : int.tryParse('$id') ?? 0;
    if (idNum <= 0 || fiscal['dni']?.toString() != dni) {
      throw ApiException('El servidor no devolvió una sesión válida. Intente nuevamente.');
    }
    return FiscalizadorSesion(
      id: idNum,
      dni: fiscal['dni'].toString(),
      nombre: fiscal['nombre']?.toString() ?? '',
      email: fiscal['email']?.toString() ?? '',
    );
  }

  // =========================================================================
  // Ficha de inspeccion predial
  // =========================================================================
  static Future<Map<String, dynamic>> catalogos() async {
    return _conRed(() async {
      final res = await http
          .get(_uri('/api/fiscalizadores/inspeccion/catalogos/'), headers: _headers)
          .timeout(_timeoutCarga);
      final data = _decodificar(res);
      final cat = data['catalogos'];
      if (cat is! Map<String, dynamic>) {
        throw ApiException('No se pudieron cargar los catálogos.');
      }
      return cat;
    });
  }

  /// Busca contribuyentes por codigo o por nombre.
  static Future<List<Map<String, dynamic>>> buscarContribuyentes(
    String texto, {
    int limite = 20,
  }) async {
    final q = texto.trim();
    if (q.length < 2) return [];
    return _conRed(() async {
      final res = await http
          .get(
            _uri('/api/fiscalizadores/inspeccion/contribuyentes/', {'q': q, 'limite': limite}),
            headers: _headers,
          )
          .timeout(_timeoutCarga);
      final data = _decodificar(res);
      final lista = data['resultados'];
      if (lista is! List) return <Map<String, dynamic>>[];
      return lista.whereType<Map<String, dynamic>>().toList();
    });
  }

  /// Siguiente numero correlativo de ficha.
  static Future<String> siguienteNumero() async {
    return _conRed(() async {
      final res = await http
          .get(_uri('/api/fiscalizadores/inspeccion/numero/'), headers: _headers)
          .timeout(_timeout);
      final data = _decodificar(res);
      return (data['numero'] ?? '').toString();
    });
  }

  /// Crea o actualiza una ficha con sus tablas hijas. Devuelve el id generado.
  static Future<int> guardarFicha({
    required int idInspeccion,
    required String dni,
    required String nombre,
    required Map<String, dynamic> inspeccion,
    required List<Map<String, dynamic>> construcciones,
    required List<Map<String, dynamic>> obras,
    String? imagenPredio,
    String? imagenFicha,
  }) async {
    return _conRed(() async {
      final cuerpo = <String, dynamic>{
        'dni_fiscalizador': dni,
        'nombre_fiscalizador': nombre,
        'inspeccion': inspeccion,
        'construcciones': construcciones,
        'obras': obras,
        if (idInspeccion > 0) 'id_inspeccion': idInspeccion,
        if (imagenPredio case final img?) 'imagen_predio': img,
        if (imagenFicha case final img?) 'imagen_ficha': img,
      };
      final res = await http
          .post(
            _uri('/api/fiscalizadores/inspeccion/guardar/'),
            headers: _headers,
            body: jsonEncode(cuerpo),
          )
          .timeout(_timeoutCarga);
      final data = _decodificar(res);
      final id = data['id_inspeccion'];
      return id is num ? id.toInt() : int.tryParse('$id') ?? 0;
    });
  }

  /// Grilla de fichas con busqueda, filtros y paginacion.
  ///
  /// [texto] busca por numero de FIP, codigo o nombre del contribuyente.
  /// [desde]/[hasta] son fechas AAAA-MM-DD. [estado] es A, I o T (todas).
  static Future<GrillaFichas> listarFichas({
    String? dni,
    String? texto,
    String? desde,
    String? hasta,
    String? estado,
    int limite = 20,
    int pagina = 1,
  }) async {
    return _conRed(() async {
      final query = <String, dynamic>{
        'limite': limite,
        'pagina': pagina,
      };
      if (dni != null && dni.isNotEmpty) query['dni'] = dni;
      if (texto != null && texto.trim().isNotEmpty) query['q'] = texto.trim();
      if (desde != null && desde.isNotEmpty) query['desde'] = desde;
      if (hasta != null && hasta.isNotEmpty) query['hasta'] = hasta;
      if (estado != null && estado.isNotEmpty) query['estado'] = estado;

      final res = await http
          .get(_uri('/api/fiscalizadores/inspeccion/listar/', query),
              headers: _headers)
          .timeout(_timeoutCarga);
      final data = _decodificar(res);
      final lista = data['fichas'];
      return GrillaFichas(
        fichas: lista is List
            ? lista.whereType<Map<String, dynamic>>().toList()
            : <Map<String, dynamic>>[],
        total: (data['total'] as num?)?.toInt() ?? 0,
        pagina: (data['pagina'] as num?)?.toInt() ?? pagina,
        limite: (data['limite'] as num?)?.toInt() ?? limite,
        paginas: (data['paginas'] as num?)?.toInt() ?? 0,
      );
    });
  }

  /// Habilita (A) o inhabilita (I) una ficha sin eliminarla.
  static Future<String> cambiarEstadoFicha({
    required int id,
    required String dni,
    required String nombre,
    required String estado,
  }) async {
    return _conRed(() async {
      final res = await http
          .post(
            _uri('/api/fiscalizadores/inspeccion/$id/estado/'),
            headers: _headers,
            body: jsonEncode({
              'dni_fiscalizador': dni,
              'nombre_fiscalizador': nombre,
              'estado': estado,
            }),
          )
          .timeout(_timeout);
      final data = _decodificar(res);
      return (data['detalle'] ?? 'Estado actualizado.').toString();
    });
  }

  /// Detalle completo de una ficha (cabecera + construcciones + obras).
  static Future<Map<String, dynamic>> detalleFicha(int id) async {
    return _conRed(() async {
      final res = await http
          .get(_uri('/api/fiscalizadores/inspeccion/$id/'), headers: _headers)
          .timeout(_timeoutCarga);
      final data = _decodificar(res);
      final ficha = data['ficha'];
      if (ficha is! Map<String, dynamic>) {
        throw ApiException('La ficha no contiene datos.');
      }
      return ficha;
    });
  }

  /// Descarga los bytes de una imagen almacenada de la ficha.
  static Future<List<int>?> imagenFicha(int id, String campo) async {
    return _conRed(() async {
      final res = await http.get(
        _uri('/api/fiscalizadores/inspeccion/$id/imagen/$campo/'),
        headers: {'Accept': 'image/*', 'X-API-Key': _fiscalizadoresApiKey},
      ).timeout(_timeoutCarga);
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    });
  }

  /// Elimina una ficha creada por el fiscalizador indicado.
  static Future<String> eliminarFicha(int id, String dni) async {
    return _conRed(() async {
      final res = await http
          .delete(
            _uri('/api/fiscalizadores/inspeccion/$id/eliminar/', {'dni': dni}),
            headers: _headers,
          )
          .timeout(_timeoutCarga);
      final data = _decodificar(res);
      return (data['detalle'] ?? 'Ficha eliminada.').toString();
    });
  }
}
