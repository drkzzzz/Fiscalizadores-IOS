import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/fiscalizador_sesion.dart';
import '../screens/configuracion_screen.dart';
import '../screens/consultas_screen.dart';
import '../screens/lista_fip_screen.dart';
import '../screens/login_screen.dart';

/// Pantalla principal que se muestra despues de iniciar sesion.
class HomeFiscalizadorScreen extends StatelessWidget {
  final FiscalizadorSesion sesion;

  const HomeFiscalizadorScreen({super.key, required this.sesion});

  static const String telefonoDesarrollador = '978590000';
  static const String whatsappDesarrollador = '51009546915';

  Future<void> _contactoDesarrollador(BuildContext context) async {
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
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.green, size: 28),
              title: const Text(
                'Llamar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('+51 978 590 000'),
              onTap: () {
                Navigator.pop(sheetContext);
                _abrir('tel:$telefonoDesarrollador');
              },
            ),
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green, size: 28),
              title: const Text(
                'WhatsApp',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('+51 954 691 515'),
              onTap: () {
                Navigator.pop(sheetContext);
                _abrir('https://wa.me/$whatsappDesarrollador');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrir(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _cerrarSesion(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesion'),
        content: const Text('Desea salir de la aplicacion?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ---------------------------------------------------------------
            // Encabezado: logo SATT grande + titulo FISCALIZACION centrado
            // ---------------------------------------------------------------
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              decoration: const BoxDecoration(
                color: AppColors.azulModerno,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Salir, alineado a la derecha para no invadir el logo.
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Cerrar sesion',
                      onPressed: () => _cerrarSesion(context),
                      icon: const Icon(Icons.logout, color: Colors.white),
                    ),
                  ),

                  // Logo del SATT, grande y centrado. El asset viene con
                  // fondo blanco, por eso va sobre una tarjeta blanca.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Image.asset(
                      'assets/logo_sat.png',
                      height: 92,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.account_balance,
                        color: AppColors.azulModerno,
                        size: 64,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Titulo centrado.
                  const Text(
                    'FISCALIZACION',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Ficha del operador.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Operador',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sesion.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'DNI ${sesion.dni}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------------
            // Zona media: 3 botones
            // ---------------------------------------------------------------
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                child: Column(
                  children: [
                    _MenuButton(
                      icono: Icons.grid_on_outlined,
                      titulo: 'FICHA DE INSPECCION DE PREDIO - FIP',
                      color: AppColors.azulModerno,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ListaFipScreen(sesion: sesion),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _MenuButton(
                      icono: Icons.search_outlined,
                      titulo: 'CONSULTAS',
                      color: AppColors.azulOscuro,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConsultasScreen(sesion: sesion),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _MenuButton(
                      icono: Icons.settings_outlined,
                      titulo: 'CONFIGURACION',
                      color: AppColors.azulOscuro.withValues(alpha: 0.8),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ConfiguracionScreen(sesion: sesion),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ---------------------------------------------------------------
            // Pie: franja azul con el dato del desarrollador
            // ---------------------------------------------------------------
            Container(
              width: double.infinity,
              color: AppColors.azulModerno,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: GestureDetector(
                onTap: () => _contactoDesarrollador(context),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_outline,
                      color: Colors.white,
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Desarrollado por NINO BARTRA DEL AGUILA '
                        'para SAT-TARAPOTO',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boton rectangular del menu principal.
class _MenuButton extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final Color color;
  final VoidCallback onPressed;

  const _MenuButton({
    required this.icono,
    required this.titulo,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      shadowColor: color.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
