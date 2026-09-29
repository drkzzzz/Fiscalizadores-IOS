import 'package:geolocator/geolocator.dart';

/// Captura la posicion del dispositivo para llenar las coordenadas GPS.
///
/// La ficha guarda la coordenada como texto "latitud, longitud", que es el
/// formato que muestra la municipalidad en sus mapas.
class GpsService {
  GpsService._();

  /// Devuelve "latitud, longitud" o lanza una exception con un mensaje que
  /// el operador puede entender (permiso denegado, GPS apagado, etc).
  static Future<String> posicionActual() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception(
        'El GPS esta apagado. Active la ubicacion en el dispositivo e intente de nuevo.',
      );
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied) {
      throw Exception('Permiso de ubicacion denegado.');
    }
    if (permiso == LocationPermission.deniedForever) {
      throw Exception(
        'Permiso de ubicacion denegado de forma permanente. '
        'Activalo en Ajustes > Aplicaciones > Fiscalizadores SAT-T.',
      );
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
    return '${_redondea(pos.latitude)}, ${_redondea(pos.longitude)}';
  }

  /// Siete decimales equivalen a poco mas de un centimetro, que es mas que
  /// suficiente para ubicar un predio y evita ruido del sensor.
  static String _redondea(double valor) {
    return valor.toStringAsFixed(7);
  }
}
