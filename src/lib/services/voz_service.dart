import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Dicta texto con el microfono para las observaciones de la ficha.
///
/// El texto reconocido se entrega por tramos en [alReconocer]; quien llama lo
/// va agregando a un campo que puede tener contenido escrito a mano.
class VozService {
  VozService._();

  static final stt.SpeechToText _motor = stt.SpeechToText();

  static bool _inicializado = false;
  static bool _escuchando = false;
  static void Function(String)? _alReconocer;

  /// Indica si el motor ya esta listo y el microfono es utilizable.
  static bool get disponible => _inicializado;

  /// Indica si en este momento se esta escuchando.
  static bool get escuchando => _escuchando;

  /// Prepara el motor. Devuelve false si el dispositivo no tiene
  /// reconocimiento de voz o el usuario no concede permiso de microfono.
  static Future<bool> iniciar() async {
    if (_inicializado) return _motor.isAvailable;
    try {
      _inicializado = await _motor.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _escuchando = false;
        },
        onError: (_) => _escuchando = false,
        debugLogging: false,
      );
    } catch (_) {
      _inicializado = false;
    }
    return _inicializado && _motor.isAvailable;
  }

  /// Empieza a dictar. [alReconocer] recibe cada tramo reconocido.
  /// Devuelve false si no se pudo iniciar (sin permiso, sin motor, o si ya
  /// estaba escuchando y este toque solo la detuvo).
  static Future<bool> escuchar(void Function(String) alReconocer) async {
    if (!await iniciar()) return false;
    // Un segundo toque en el microfono corta la escucha.
    if (_motor.isListening) {
      await detener();
      return false;
    }
    _alReconocer = alReconocer;
    _escuchando = true;
    await _motor.listen(
      onResult: (r) {
        if (r.finalResult) _escuchando = false;
        _alReconocer?.call(r.recognizedWords);
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        // Un silencio de 5 segundos corta la escucha, para no dejar el
        // microfono abierto todo el turno de fiscalizacion.
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(minutes: 5),
      ),
    );
    return _motor.isListening || _escuchando;
  }

  static Future<void> detener() async {
    _alReconocer = null;
    _escuchando = false;
    if (_motor.isListening) await _motor.stop();
  }

  /// Ayuda para el operador, segun el estado actual del microfono.
  static String consejo() => _escuchando
      ? 'Escuchando... toque de nuevo el microfono para detener.'
      : 'Toque el microfono y dicte las observaciones.';
}
