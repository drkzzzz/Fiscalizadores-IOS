import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../services/api_service.dart';
import 'home_fiscalizador_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FiscalizadoresApp());
}

class FiscalizadoresApp extends StatelessWidget {
  const FiscalizadoresApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fiscalizadores SAT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.azulModerno,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.azulModerno,
          primary: AppColors.azulModerno,
        ),
        scaffoldBackgroundColor: AppColors.grisClaro,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.azulModerno,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _dniController = TextEditingController();
  final _claveController = TextEditingController();
  bool _ocultarClave = true;
  bool _ingresando = false;
  String? _error;

  @override
  void dispose() {
    _dniController.dispose();
    _claveController.dispose();
    super.dispose();
  }

  bool get _dniValido => _dniController.text.trim().length == 8;

  bool get _puedeIngresar =>
      _dniValido && _claveController.text.isNotEmpty && !_ingresando;

  Future<void> _iniciar() async {
    final dni = _dniController.text.trim();
    final clave = _claveController.text.trim();

    setState(() {
      _ingresando = true;
      _error = null;
    });

    try {
      final sesion = await ApiService.login(dni, clave);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('operador_dni', sesion.dni);
      await prefs.setString('operador_nombre', sesion.nombre);
      await prefs.setInt('operador_id', sesion.id);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeFiscalizadorScreen(sesion: sesion)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ingresando = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.grisClaro,
      body: SafeArea(
        child: SingleChildScrollView(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 60),
              Image.asset(
                'assets/logo_sat.png',
                width: 150,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              const Text(
                'FISCALIZADORES',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.azulModerno,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'SAT - TARAPOTO',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.grisMedio,
                ),
              ),
              const SizedBox(height: 30),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.rojo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.rojo.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.rojo, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _dniController,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'DNI (8 dígitos)',
                  border: OutlineInputBorder(),
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: Icon(Icons.badge),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _claveController,
                onChanged: (_) => setState(() {}),
                obscureText: _ocultarClave,
                decoration: InputDecoration(
                  labelText: 'Clave',
                  border: const OutlineInputBorder(),
                  fillColor: Colors.white,
                  filled: true,
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _ocultarClave
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () =>
                        setState(() => _ocultarClave = !_ocultarClave),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _puedeIngresar ? _iniciar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.azulModerno,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _ingresando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'INGRESAR',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        width: double.infinity,
        color: AppColors.azulModerno.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: const Text(
          'Desarrollado por NINO BARTRA DEL AGUILA para SAT-TARAPOTO',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}