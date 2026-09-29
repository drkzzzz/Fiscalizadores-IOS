import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/fiscalizador_sesion.dart';
import '../services/api_service.dart';
import '../screens/home_fiscalizador_screen.dart';

/// Pantalla CONFIGURACION: datos del fiscalizador, cambio de clave y
/// contacto con el desarrollador.
class ConfiguracionScreen extends StatefulWidget {
  final FiscalizadorSesion sesion;

  const ConfiguracionScreen({super.key, required this.sesion});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _repetirCtrl = TextEditingController();
  bool _mostrarClaves = false;
  bool _guardando = false;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _repetirCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiarClave() async {
    final actual = _actualCtrl.text.trim();
    final nueva = _nuevaCtrl.text;
    final repetir = _repetirCtrl.text;

    if (actual.isEmpty) {
      _snack('Ingrese su clave actual.', AppColors.rojo);
      return;
    }
    if (nueva.length < 4) {
      _snack('La clave nueva debe tener al menos 4 caracteres.', AppColors.rojo);
      return;
    }
    if (nueva != repetir) {
      _snack('La clave nueva no coincide con la repetida.', AppColors.rojo);
      return;
    }
    if (nueva == actual) {
      _snack('La clave nueva debe ser diferente de la actual.', AppColors.rojo);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambio de clave'),
        content: const Text(
          'La clave se cambiara en el sistema municipal. Desea continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _guardando = true);
    try {
      final msg = await ApiService.cambiarClave(
        dni: widget.sesion.dni,
        claveActual: actual,
        claveNueva: nueva,
      );
      if (!mounted) return;
      setState(() => _guardando = false);
      _actualCtrl.clear();
      _nuevaCtrl.clear();
      _repetirCtrl.clear();
      _snack(msg, AppColors.verde);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _snack(e.toString(), AppColors.rojo);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: color, content: Text(msg)),
    );
  }

  Future<void> _contactoDesarrollador() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Contactar al desarrollador',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'NINO BARTRA DEL AGUILA',
              style: TextStyle(fontSize: 13, color: AppColors.grisMedio),
            ),
            const SizedBox(height: 16),
            _contacto(
              icono: Icons.phone,
              titulo: 'Llamar',
              subtitulo: '+51 978 590 000',
              onTap: () {
                Navigator.pop(sheetContext);
                _abrir('tel:${HomeFiscalizadorScreen.telefonoDesarrollador}');
              },
            ),
            _contacto(
              icono: Icons.message,
              titulo: 'WhatsApp',
              subtitulo: '+51 954 691 515',
              onTap: () {
                Navigator.pop(sheetContext);
                _abrir(
                    'https://wa.me/${HomeFiscalizadorScreen.whatsappDesarrollador}');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _contacto({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icono, color: Colors.green, size: 28),
      title: Text(titulo,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitulo),
      onTap: onTap,
    );
  }

  Future<void> _abrir(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracion')),
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        children: [
          // ------------------------------------------------ Fiscalizador
          _seccion(
            titulo: 'FISCALIZADOR',
            icono: Icons.badge_outlined,
            child: Column(
              children: [
                _dato('Nombre', widget.sesion.nombre),
                _dato('DNI', widget.sesion.dni),
                _dato('Codigo', widget.sesion.id.toString()),
                _dato('Correo', widget.sesion.email.isEmpty ? '-' : widget.sesion.email),
              ],
            ),
          ),

          // ------------------------------------------------ Servidor
          _seccion(
            titulo: 'CONEXION',
            icono: Icons.cloud_outlined,
            child: Column(
              children: [
                _dato('Servidor', ApiService.baseUrl),
                _dato('Estado', 'Configurado en tiempo de compilacion'),
              ],
            ),
          ),

          // ------------------------------------------------ Clave
          _seccion(
            titulo: 'CAMBIAR CLAVE',
            icono: Icons.lock_outline,
            child: Column(
              children: [
                _campo(_actualCtrl, 'Clave actual', obscure: !_mostrarClaves),
                _campo(_nuevaCtrl, 'Clave nueva', obscure: !_mostrarClaves),
                _campo(_repetirCtrl, 'Repetir clave nueva',
                    obscure: !_mostrarClaves),
                Row(
                  children: [
                    Checkbox(
                      value: _mostrarClaves,
                      activeColor: AppColors.azulModerno,
                      onChanged: (v) =>
                          setState(() => _mostrarClaves = v ?? false),
                    ),
                    const Text('Mostrar claves',
                        style: TextStyle(fontSize: 13)),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _cambiarClave,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.azulModerno,
                      ),
                      icon: _guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save, size: 18),
                      label: Text(
                        _guardando ? 'Guardando...' : 'Cambiar clave',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ------------------------------------------------ Desarrollador
          _seccion(
            titulo: 'SOPORTE',
            icono: Icons.support_agent,
            child: Column(
              children: [
                const Text(
                  'Desarrollado por NINO BARTRA DEL AGUILA para SAT-TARAPOTO',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.azulModerno,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _contactoDesarrollador,
                  icon: const Icon(Icons.contact_phone_outlined),
                  label: const Text('Contactar al desarrollador'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccion({
    required String titulo,
    required IconData icono,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.azulModerno,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icono, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(etiqueta,
                style: const TextStyle(fontSize: 12, color: AppColors.grisMedio)),
          ),
          Expanded(
            child: Text(
              valor,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController ctrl, String etiqueta,
      {required bool obscure}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(fontSize: 14),
        inputFormatters: obscure
            ? [FilteringTextInputFormatter.deny(RegExp(r'\s'))]
            : null,
        decoration: InputDecoration(
          labelText: etiqueta,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.azulModerno, width: 2),
          ),
        ),
      ),
    );
  }
}
