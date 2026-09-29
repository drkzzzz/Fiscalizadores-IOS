import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';

/// Resultado de capturar una imagen.
class CapturaImagen {
  final Uint8List bytes;
  final String base64;
  final String nombreArchivo;

  const CapturaImagen({
    required this.bytes,
    required this.base64,
    required this.nombreArchivo,
  });
}

/// Captura y compresion de imagenes para las fichas de inspeccion.
///
/// Las fotos se redimensionan antes de codificarse porque la ficha las
/// almacena en columnas varbinary(max) y el envio se hace en base64 dentro del
/// cuerpo JSON (el servidor limita cada imagen a 4 MB).
class ImagenService {
  ImagenService._();

  static final ImagePicker _picker = ImagePicker();

  static const int _largoMaximo = 1400;
  static const int _calidadJpeg = 82;

  /// Toma una foto con la camara.
  static Future<CapturaImagen?> desdeCamara() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _largoMaximo.toDouble(),
      maxHeight: _largoMaximo.toDouble(),
      imageQuality: _calidadJpeg,
    );
    if (x == null) return null;
    return _preparar(await x.readAsBytes(), x.name);
  }

  /// Elige una imagen de la galeria.
  static Future<CapturaImagen?> desdeGaleria() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _largoMaximo.toDouble(),
      maxHeight: _largoMaximo.toDouble(),
      imageQuality: _calidadJpeg,
    );
    if (x == null) return null;
    return _preparar(await x.readAsBytes(), x.name);
  }

  /// Muestra una hoja con las dos opciones de origen.
  static Future<CapturaImagen?> elegirOrigen(BuildContext context) async {
    final origen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.azulModerno),
              title: const Text('Tomar foto con la camara'),
              onTap: () => Navigator.pop(ctx, 'camara'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.azulModerno),
              title: const Text('Elegir de la galeria'),
              onTap: () => Navigator.pop(ctx, 'galeria'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (origen == 'camara') return desdeCamara();
    if (origen == 'galeria') return desdeGaleria();
    return null;
  }

  static CapturaImagen _preparar(Uint8List bytes, String nombre) {
    return CapturaImagen(
      bytes: bytes,
      base64: _aBase64(bytes),
      nombreArchivo: nombre,
    );
  }

  /// Convierte bytes a base64 (sin prefijo data URI, el servidor lo acepta).
  static String _aBase64(Uint8List bytes) {
    return base64Encode(bytes);
  }
}
