import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/fiscalizador_sesion.dart';
import '../services/api_service.dart';
import '../services/gps_service.dart';
import '../services/imagen_service.dart';
import '../services/voz_service.dart';
import '../widgets/form_widgets.dart';

/// Pantalla de Ficha de Inscripcion de Predio.
///
/// Primero muestra un buscador compacto de contribuyente (por nombre o
/// codigo). Al elegir un contribuyente se despliega el formulario completo de
/// `tbl_inspeccion_predio`, con las tablas hijas `tbl_construccion` y
/// `tbl_obra_complementaria` y los campos de imagen.
class FichaInspeccionScreen extends StatefulWidget {
  final FiscalizadorSesion sesion;

  /// Si se indica, se edita la ficha existente en vez de crear una nueva.
  final int? idInspeccion;

  const FichaInspeccionScreen({
    super.key,
    required this.sesion,
    this.idInspeccion,
  });

  @override
  State<FichaInspeccionScreen> createState() => _FichaInspeccionScreenState();
}

class _FichaInspeccionScreenState extends State<FichaInspeccionScreen> {
  // Estado de la busqueda de contribuyente
  final _buscarCtrl = TextEditingController();
  bool _buscando = false;
  List<Map<String, dynamic>> _resultados = [];
  Map<String, dynamic>? _contribuyente;

  // Predio elegido del contribuyente
  Map<String, dynamic>? _predio;
  bool _gpsTomando = false;
  bool _dictando = false;

  // Estado del formulario
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, String?> _sel = {};
  Map<String, dynamic> _catalogos = {};
  int _idInspeccion = 0;
  String _numero = '';

  // Tablas hijas
  List<Map<String, TextEditingController>> _construcciones = [];
  List<Map<String, TextEditingController>> _obras = [];

  // Imagenes
  CapturaImagen? _imgPredio;
  CapturaImagen? _imgFicha;
  bool _cargandoImagen = false;

  bool _cargando = true;
  String _mensajeCarga = 'Cargando catalogos...';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _idInspeccion = widget.idInspeccion ?? 0;
    _inicializar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    // Si el operador sale de la ficha mientras dicta, el microfono queda libre.
    if (_dictando) VozService.detener();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    for (final fila in [..._construcciones, ..._obras]) {
      for (final c in fila.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  // =====================================================================
  // Inicializacion
  // =====================================================================
  Future<void> _inicializar() async {
    setState(() => _mensajeCarga = 'Cargando catalogos...');
    try {
      final cat = await ApiService.catalogos();
      if (!mounted) return;
      setState(() {
        _catalogos = cat;
        _mensajeCarga = 'Generando numero de ficha...';
      });

      if (_idInspeccion > 0) {
        setState(() => _mensajeCarga = 'Cargando ficha...');
        final ficha = await ApiService.detalleFicha(_idInspeccion);
        if (!mounted) return;
        _numero = (ficha['numero'] ?? '').toString();
        _llenarFormulario(ficha);
        if (ficha['tiene_imagen_predio'] == true ||
            ficha['tiene_imagen_ficha'] == true) {
          await _descargarImagenesExistentes();
        }
        setState(() {
          _cargando = false;
          _contribuyente = {
            'codigo': ficha['codigo_contribuyente'],
            'nombre': ficha['razon_social'],
          };
        });
        return;
      }

      final numero = await ApiService.siguienteNumero();
      if (!mounted) return;
      setState(() {
        _numero = numero;
        _prepararValoresIniciales();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _mensajeCarga = e.toString();
      });
    }
  }

  void _prepararValoresIniciales() {
    _crearCtrl('numero', _numero);
    _crearCtrl('distrito', 'TARAPOTO');
    _crearCtrl('lugar', 'TARAPOTO');
    _crearCtrl('tipo_doc', 'DNI');
    _crearCtrl('ubicacion_geo', '');
    // La fecha de cierre la pone la app: el operador no la elige.
    _crearCtrl('fecha_cierre', _ahora());
    for (final campo in _camposCabecera) {
      _crearCtrl(campo, '');
    }
    _construcciones = [];
    _obras = [];
  }

  void _llenarFormulario(Map<String, dynamic> f) {
    for (final campo in _camposCabecera) {
      _crearCtrl(campo, (f[campo] ?? '').toString());
    }
    _sel['tipo_solicitud'] = _txt(f['tipo_solicitud']);
    _sel['nombre_solicitud'] = _txt(f['nombre_solicitud']);
    _sel['tipo_doc'] = _txt(f['tipo_doc']);
    _sel['tipo_sector'] = _txt(f['tipo_sector']);
    _sel['tipo_via'] = _txt(f['tipo_via']);
    _sel['tipo_predio'] = _txt(f['tipo_predio']);
    _sel['condicion_prop'] = _txt(f['condicion_prop']);
    _sel['tipo_res'] = _txt(f['tipo_res']);

    _construcciones = [];
    for (final item in (f['construcciones'] as List? ?? const [])) {
      if (item is! Map) continue;
      _construcciones.add(_crearFilaHijo(_camposConstruccion, item));
    }
    _obras = [];
    for (final item in (f['obras'] as List? ?? const [])) {
      if (item is! Map) continue;
      _obras.add(_crearFilaHijo(_camposObra, item));
    }
  }

  Map<String, TextEditingController> _crearFilaHijo(
      List<String> campos, Map<dynamic, dynamic> datos) {
    return {
      for (final c in campos)
        c: TextEditingController(text: _txt(datos[c])),
    };
  }

  /// Crea (o reemplaza) el controller de un campo. Solo usar cuando el campo
  /// todavia no esta montado (carga inicial).
  void _crearCtrl(String campo, String valor) {
    _ctrl[campo]?.dispose();
    _ctrl[campo] = TextEditingController(text: valor);
  }

  /// Escribe un valor en un campo ya montado. No reemplaza el controller para
  /// evitar que el TextField quede apuntando a uno ya liberado.
  void _setValor(String campo, String valor) {
    final c = _ctrl[campo];
    if (c == null) {
      _crearCtrl(campo, valor);
      return;
    }
    if (c.text != valor) c.text = valor;
  }

  String _txt(dynamic v) => v == null ? '' : v.toString();

  // =====================================================================
  // Busqueda de contribuyente
  // =====================================================================
  Future<void> _buscar() async {
    final texto = _buscarCtrl.text.trim();
    if (texto.length < 2) {
      _aviso('Ingrese al menos 2 caracteres para buscar.');
      return;
    }
    setState(() => _buscando = true);
    try {
      final res = await ApiService.buscarContribuyentes(texto);
      if (!mounted) return;
      setState(() {
        _resultados = res;
        _buscando = false;
      });
      if (res.isEmpty) {
        _aviso('No se encontraron contribuyentes.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _buscando = false);
      _aviso(e.toString());
    }
  }

  void _elegirContribuyente(Map<String, dynamic> c) {
    final predios = (c['predios'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    setState(() {
      _contribuyente = c;
      _resultados = [];
      _buscarCtrl.text = c['nombre']?.toString() ?? '';
      _predio = null;
      _setValor('codigo_contribuyente', _txt(c['codigo']));
      _setValor('razon_social', _txt(c['nombre']));
      _setValor('telefono', _txt(c['telefono']));
      _setValor('num_doc', _txt(c['num_doc']));
      _setValor('lugar', _txt(c['lugar']));
      if (_txt(c['tipo_doc']).isNotEmpty) {
        _sel['tipo_doc'] = _txt(c['tipo_doc']);
      }
    });

    if (predios.length == 1) {
      _aplicarPredio(predios.first);
      _aviso('Contribuyente y predio cargados. Revise y complete lo pendiente.');
    } else if (predios.length > 1) {
      _aviso('El contribuyente tiene ${predios.length} predios. Elija uno en la grilla.');
    } else {
      _aviso('Contribuyente cargado. No tiene predios en el catastro.');
    }
  }

  void _quitarContribuyente() {
    setState(() {
      _contribuyente = null;
      _predio = null;
      _buscarCtrl.clear();
      _resultados = [];
      _setValor('codigo_contribuyente', '');
      _setValor('razon_social', '');
      _setValor('cod_catastral', '');
      _setValor('cod_predio_sat', '');
    });
  }

  /// Rellena la ficha con todo lo que el catastro ya sabe del predio.
  ///
  /// Se llama al elegir un predio de la grilla y tambien cuando el
  /// contribuyente tiene uno solo, para que el operador no vuelva a digitar
  /// lo que ya esta en el catastro.
  void _aplicarPredio(Map<String, dynamic> p) {
    setState(() {
      _predio = p;
      _setValor('cod_catastral', _txt(p['cod_catastral']));
      _setValor('cod_predio_sat', _txt(p['cod_predio']));
      _setValor('nombre_sector', _txt(p['sector']));
      _setValor('nombre_via', _txt(p['nombre_via']));
      _setValor('num_finca', _txt(p['num_finca']));
      _setValor('interior', _txt(p['interior']));
      _setValor('manzana', _txt(p['manzana']));
      _setValor('lote', _txt(p['lote']));
      _setValor('edificio_block', _txt(p['edificio']));
      _setValor('referencia', _txt(p['comentario']));
      _setValor('lugar', _txt(p['lugar']));
      _setValor('area_total_m2', _txt(p['area_titulo']));
      _setValor('area_propio_m2', _txt(p['area_declarada']));
      _setValor('area_matriz_m2', _txt(p['area_verificada']));
      _setValor('porc_propiedad', _txt(p['porcentaje']));
      _setValor('porc_bien_comun', _txt(p['porc_bien_comun']));
      if (_txt(p['telefono']).isNotEmpty &&
          (_ctrl['telefono']?.text ?? '').isEmpty) {
        _setValor('telefono', _txt(p['telefono']));
      }
      if (_txt(p['tipo_predio']).isNotEmpty) {
        _sel['tipo_predio'] = _txt(p['tipo_predio']);
      }
      if (_txt(p['condicion_ficha']).isNotEmpty) {
        _sel['condicion_prop'] = _txt(p['condicion_ficha']);
      }
      if (_txt(p['tipo_via']).isNotEmpty) {
        _sel['tipo_via'] = _txt(p['tipo_via']);
      }
      if (_txt(p['sector']).isNotEmpty) {
        _sel['tipo_sector'] = 'SEC';
      }
    });
    _aviso('Datos del predio aplicados al formulario.');
  }

  // =====================================================================
  // GPS
  // =====================================================================
  Future<void> _capturarGps() async {
    setState(() => _gpsTomando = true);
    try {
      final pos = await GpsService.posicionActual();
      if (!mounted) return;
      _setValor('ubicacion_geo', pos);
      _aviso('Posicion capturada: $pos');
    } catch (e) {
      if (!mounted) return;
      _aviso(e.toString());
    } finally {
      if (mounted) setState(() => _gpsTomando = false);
    }
  }

  // =====================================================================
  // Imagenes
  // =====================================================================
  Future<void> _capturarImagen({required bool esPredio}) async {
    setState(() => _cargandoImagen = true);
    try {
      final img = await ImagenService.elegirOrigen(context);
      if (!mounted) return;
      if (img != null) {
        setState(() {
          if (esPredio) {
            _imgPredio = img;
          } else {
            _imgFicha = img;
          }
        });
      }
    } catch (e) {
      _aviso('No se pudo obtener la imagen: $e');
    } finally {
      if (mounted) setState(() => _cargandoImagen = false);
    }
  }

  Future<void> _descargarImagenesExistentes() async {
    try {
      if (_idInspeccion > 0) {
        if (_imgPredio == null) {
          final b = await ApiService.imagenFicha(_idInspeccion, 'imagen_predio');
          if (b != null) {
            _imgPredio = CapturaImagen(
              bytes: Uint8List.fromList(b),
              base64: base64Encode(b),
              nombreArchivo: 'imagen_predio.jpg',
            );
          }
        }
        if (_imgFicha == null) {
          final b = await ApiService.imagenFicha(_idInspeccion, 'imagen_ficha');
          if (b != null) {
            _imgFicha = CapturaImagen(
              bytes: Uint8List.fromList(b),
              base64: base64Encode(b),
              nombreArchivo: 'imagen_ficha.jpg',
            );
          }
        }
      }
    } catch (_) {
      // Si no se pueden descargar, el usuario puede tomar nuevas fotos.
    }
  }

  void _verImagen(CapturaImagen? img) {
    if (img == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: Image.memory(img.bytes, fit: BoxFit.contain),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================================
  // Filas hijas
  // =====================================================================
  void _agregarConstruccion() {
    if (_construcciones.length >= 60) {
      _aviso('Máximo 60 niveles.');
      return;
    }
    setState(() {
      _construcciones.add({
        for (final c in _camposConstruccion)
          c: TextEditingController(
              text: c == 'nivel' ? '${_construcciones.length + 1}' : ''),
      });
    });
  }

  void _agregarObra() {
    if (_obras.length >= 60) {
      _aviso('Máximo 60 obras complementarias.');
      return;
    }
    setState(() {
      _obras.add({for (final c in _camposObra) c: TextEditingController()});
    });
  }

  void _quitarConstruccion(int i) {
    final fila = _construcciones.removeAt(i);
    setState(() {});
    _liberar(fila);
  }

  void _quitarObra(int i) {
    final fila = _obras.removeAt(i);
    setState(() {});
    _liberar(fila);
  }

  /// Libera los controllers de una fila eliminada. Se hace despues del
  /// rebuild para que ningun TextField montado los use al liberarlos.
  void _liberar(Map<String, TextEditingController> fila) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in fila.values) {
        c.dispose();
      }
    });
  }

  // =====================================================================
  // Guardado
  // =====================================================================
  String _v(String campo) => _ctrl[campo]?.text.trim() ?? '';

  Map<String, dynamic> _armarCabecera() {
    return {
      'numero': _numero.isEmpty ? _v('numero') : _numero,
      'tipo_solicitud': _sel['tipo_solicitud'],
      'nombre_solicitud': _sel['nombre_solicitud'],
      'ubicacion_geo': _v('ubicacion_geo'),
      'codigo_contribuyente': _v('codigo_contribuyente'),
      'razon_social': _v('razon_social'),
      'tipo_doc': _sel['tipo_doc'],
      'num_doc': _v('num_doc'),
      'telefono': _v('telefono'),
      'cod_catastral': _v('cod_catastral'),
      'cod_predio_sat': _v('cod_predio_sat'),
      'distrito': _v('distrito'),
      'tipo_sector': _sel['tipo_sector'],
      'nombre_sector': _v('nombre_sector'),
      'tipo_res': _sel['tipo_res'],
      'nombre_res': _v('nombre_res'),
      'tipo_via': _sel['tipo_via'],
      'nombre_via': _v('nombre_via'),
      'num_finca': _v('num_finca'),
      'interior': _v('interior'),
      'dir_lateral': _v('dir_lateral'),
      'manzana': _v('manzana'),
      'lote': _v('lote'),
      'edificio_block': _v('edificio_block'),
      'piso': _v('piso'),
      'grupo_sector': _v('grupo_sector'),
      'referencia': _v('referencia'),
      'tipo_predio': _sel['tipo_predio'],
      'condicion_prop': _sel['condicion_prop'],
      'porc_propiedad': _v('porc_propiedad'),
      'area_matriz_m2': _v('area_matriz_m2'),
      'porc_bien_comun': _v('porc_bien_comun'),
      'area_propio_m2': _v('area_propio_m2'),
      'area_comun_m2': _v('area_comun_m2'),
      'area_total_m2': _v('area_total_m2'),
      'frente_predio': _v('frente_predio'),
      'observaciones': _v('observaciones'),
      'lugar': _v('lugar'),
      'fecha_cierre': _v('fecha_cierre'),
    };
  }

  Map<String, dynamic> _armarFila(Map<String, TextEditingController> fila) {
    return {for (final e in fila.entries) e.key: e.value.text.trim()};
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _aviso('Revise los campos obligatorios marcados en rojo.');
      return;
    }
    // La hora de cierre es el momento exacto en que se guarda la ficha.
    _setValor('fecha_cierre', _ahora());
    setState(() => _guardando = true);
    try {
      final id = await ApiService.guardarFicha(
        idInspeccion: _idInspeccion,
        dni: widget.sesion.dni,
        nombre: widget.sesion.nombre,
        inspeccion: _armarCabecera(),
        construcciones: _construcciones.map(_armarFila).toList(),
        obras: _obras.map(_armarFila).toList(),
        imagenPredio: _imgPredio?.base64,
        imagenFicha: _imgFicha?.base64,
      );
      if (!mounted) return;
      setState(() {
        _idInspeccion = id;
        _guardando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.verde,
          content: Text('Ficha $_numero guardada correctamente.'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _aviso(e.toString());
    }
  }

  void _aviso(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.rojo,
        content: Text(mensaje),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // =====================================================================
  // Listas de catalogos
  // =====================================================================
  List<CatalogoItem> _cat(String clave) => listaCatalogo(_catalogos[clave]);

  List<CatalogoItem> _catCategorias(String tipo) {
    final cats = _catalogos['categorias'];
    if (cats is! Map) return const [];
    return listaCatalogo(cats[tipo]);
  }

  String _nombreCat(String clave, String codigo) {
    if (codigo.isEmpty) return '';
    final item = _cat(clave).firstWhere(
      (e) => e.codigo == codigo,
      orElse: () => CatalogoItem(codigo, ''),
    );
    return item.nombre;
  }

  // =====================================================================
  // Build
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ficha de Inscripcion')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_mensajeCarga, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_idInspeccion > 0
            ? 'Editar $_numero'
            : 'Ficha $_numero'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          children: [
            _seccionBuscador(),
            if (_resultados.isNotEmpty) _seccionResultados(),
            if (_contribuyente != null) _seccionPredios(),
            _seccionContribuyente(),
            if (_contribuyente != null) _seccionSolicitud(),
            if (_contribuyente != null) _seccionContribuyenteDatos(),
            if (_contribuyente != null) _seccionDireccion(),
            if (_contribuyente != null) _seccionUsoPropiedad(),
            if (_contribuyente != null) _seccionAreas(),
            if (_contribuyente != null) _seccionConstrucciones(),
            if (_contribuyente != null) _seccionObras(),
            if (_contribuyente != null) _seccionImagenes(),
            if (_contribuyente != null) _seccionCierre(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save),
            label: Text(
              _guardando
                  ? 'Guardando...'
                  : (_idInspeccion > 0 ? 'ACTUALIZAR FICHA' : 'GUARDAR FICHA'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.azulModerno,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ),
    );
  }

  // --- Secciones ------------------------------------------------------
  Widget _seccionBuscador() {
    return SeccionFormulario(
      titulo: '1. BUSCAR CONTRIBUYENTE',
      icono: Icons.search,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buscarCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscar(),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Nombre o codigo',
                    isDense: true,
                    prefixIcon: Icon(Icons.person_search, size: 20),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _buscando ? null : _buscar,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.azulModerno,
                  minimumSize: const Size(52, 44),
                ),
                child: _buscando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search),
              ),
            ],
          ),
          if (_contribuyente != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Contribuyente: ${_txt(_contribuyente!['nombre'])}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _quitarContribuyente,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Cambiar', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _seccionResultados() {
    return SeccionFormulario(
      titulo: 'RESULTADOS (${_resultados.length})',
      icono: Icons.list,
      child: Column(
        children: _resultados.map((c) {
          final predios = (c['predios'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
          final doc = [
            if (_txt(c['tipo_doc']).isNotEmpty) _txt(c['tipo_doc']),
            _txt(c['num_doc']),
          ].where((e) => e.isNotEmpty).join(' ');
          final telefono = _txt(c['telefono']);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: ExpansionTile(
              dense: true,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                _txt(c['nombre']),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  'Cod. ${_txt(c['codigo'])}',
                  if (doc.isNotEmpty) doc,
                  if (telefono.isNotEmpty) 'Tel. $telefono',
                  '${predios.length} predio(s)',
                ].join(' - '),
                style: const TextStyle(fontSize: 11, color: AppColors.grisMedio),
              ),
              children: [
                if (predios.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('Este contribuyente no tiene predios registrados.',
                        style: TextStyle(fontSize: 12)),
                  )
                else
                  ...predios.map((p) => ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        title: Text(
                          'Catastro ${_txt(p['cod_catastral'])}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          _txt(p['ubicacion']),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () {
                          _elegirContribuyente(c);
                          _aplicarPredio(p);
                        },
                      )),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                  child: OutlinedButton.icon(
                    onPressed: () => _elegirContribuyente(c),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Elegir contribuyente',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Grilla de predios del contribuyente: codigo catastral y ubicacion.
  ///
  /// Si el contribuyente tiene un solo predio se aplica directo; si tiene
  /// varios, el operador toca el que corresponde y la ficha se completa con
  /// todo lo que el catastro ya tiene.
  Widget _seccionPredios() {
    final predios = (_contribuyente?['predios'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (predios.isEmpty) return const SizedBox.shrink();

    return SeccionFormulario(
      titulo: '1b. PREDIOS DEL CONTRIBUYENTE (${predios.length})',
      icono: Icons.map,
      child: Column(
        children: [
          if (_predio != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.verde.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.verde),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.verde, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Predio elegido: ${_txt(_predio!['cod_catastral'])}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _predio = null),
                    child: const Text('Cambiar'),
                  ),
                ],
              ),
            ),
          ...predios.map(_filaPredio),
        ],
      ),
    );
  }

  Widget _filaPredio(Map<String, dynamic> p) {
    final elegido = _predio?['cod_catastral'] == p['cod_catastral'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: elegido ? 3 : 0,
      color: elegido
          ? AppColors.verde.withValues(alpha: 0.08)
          : AppColors.grisClaro,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: elegido ? AppColors.verde : Colors.grey.shade300,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _aplicarPredio(p),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _txt(p['cod_catastral']),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (elegido)
                    const Icon(Icons.check_circle,
                        color: AppColors.verde, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _txt(p['ubicacion']),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  _datoPredio('Predio', _txt(p['cod_predio'])),
                  _datoPredio('Uso', _txt(p['uso'])),
                  _datoPredio('Area', '${_txt(p['area_titulo'])} m2'),
                  _datoPredio('Condicion', _txt(p['condicion'])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _datoPredio(String etiqueta, String valor) {
    if (valor.isEmpty) return const SizedBox.shrink();
    return Text(
      '$etiqueta: $valor',
      style: const TextStyle(fontSize: 11, color: AppColors.grisMedio),
    );
  }

  Widget _seccionContribuyente() {
    if (_contribuyente == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          'Busque al contribuyente por nombre o codigo para habilitar el '
          'formulario de la ficha de inscripcion.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.grisMedio),
        ),
      );
    }

    return SeccionFormulario(
      titulo: '2. DATOS DEL CONTRIBUYENTE',
      icono: Icons.person,
      child: Column(
        children: [
          CampoTexto(
            controller: _ctrl['codigo_contribuyente']!,
            etiqueta: 'Codigo de contribuyente *',
            maxLength: 11,
            soloLectura: true,
          ),
          CampoTexto(
            controller: _ctrl['razon_social']!,
            etiqueta: 'Razon social / nombre *',
            maxLength: 200,
            lineas: 2,
            validador: _requerido('Razon social es obligatorio'),
          ),
          CampoSelector(
            items: _cat('tipo_doc'),
            etiqueta: 'Tipo de documento',
            valor: _sel['tipo_doc'],
            onChanged: (v) => setState(() => _sel['tipo_doc'] = v),
          ),
          CampoTexto(
            controller: _ctrl['num_doc']!,
            etiqueta: 'Numero de documento',
            maxLength: 20,
            teclado: TextInputType.number,
          ),
          CampoTexto(
            controller: _ctrl['telefono']!,
            etiqueta: 'Telefono',
            maxLength: 20,
            teclado: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  Widget _seccionSolicitud() {
    return SeccionFormulario(
      titulo: '3. TIPO DE SOLICITUD',
      icono: Icons.assignment,
      child: Column(
        children: [
          CampoSelector(
            items: _cat('tipo_solicitud'),
            etiqueta: 'Tipo de solicitud *',
            valor: _sel['tipo_solicitud'],
            validador: (v) =>
                (v == null || v.isEmpty) ? 'Seleccione el tipo' : null,
            onChanged: (v) => setState(() {
              _sel['tipo_solicitud'] = v;
              _sel['nombre_solicitud'] = _nombreCat('tipo_solicitud', v ?? '');
              _setValor('nombre_solicitud', _sel['nombre_solicitud'] ?? '');
            }),
          ),
          CampoTexto(
            controller: _ctrl['nombre_solicitud']!,
            etiqueta: 'Nombre de la solicitud *',
            maxLength: 30,
            validador: _requerido('Nombre de solicitud es obligatorio'),
          ),
        ],
      ),
    );
  }

  Widget _seccionContribuyenteDatos() {
    return SeccionFormulario(
      titulo: '4. UBICACION',
      icono: Icons.place,
      child: Column(
        children: [
          CampoTexto(
            controller: _ctrl['ubicacion_geo']!,
            etiqueta: 'Coordenadas GPS',
            ayuda: 'Formato: latitud, longitud. Toque el boton para capturar '
                'la posicion actual del dispositivo.',
            maxLength: 100,
            boton: IconButton(
              tooltip: _gpsTomando ? 'Buscando posicion...' : 'Capturar GPS',
              onPressed: _gpsTomando ? null : _capturarGps,
              icon: _gpsTomando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionDireccion() {
    return SeccionFormulario(
      titulo: '5. DIRECCION DEL PREDIO',
      icono: Icons.home,
      child: Column(
        children: [
          if (_contribuyente != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                onPressed: _abrirPredios,
                icon: const Icon(Icons.maps_home_work, size: 18),
                label: Text(_predio == null
                    ? 'Cargar predios del contribuyente'
                    : 'Cambiar de predio'),
              ),
            ),
          if (_predio != null) ...[
            // Con el predio cargado ya no hace falta digitar la direccion:
            // se muestra el resumen y el resto de campos quedan ocultos.
            CampoTexto(
              controller: _ctrl['cod_catastral']!,
              etiqueta: 'Codigo catastral',
              maxLength: 30,
              soloLectura: true,
            ),
            CampoTexto(
              controller: _ctrl['cod_predio_sat']!,
              etiqueta: 'Codigo de predio (SAT)',
              maxLength: 24,
              soloLectura: true,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.grisClaro,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Direccion del predio',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.grisMedio)),
                    const SizedBox(height: 2),
                    Text(
                      _direccionCompleta(),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            CampoSelector(
              items: _cat('tipo_predio'),
              etiqueta: 'Tipo de predio',
              valor: _sel['tipo_predio'],
              onChanged: (v) => setState(() => _sel['tipo_predio'] = v),
            ),
          ] else ...[
            CampoTexto(
              controller: _ctrl['cod_catastral']!,
              etiqueta: 'Codigo catastral',
              maxLength: 30,
            ),
            CampoTexto(
              controller: _ctrl['cod_predio_sat']!,
              etiqueta: 'Codigo de predio (SAT)',
              maxLength: 24,
            ),
            CampoSelector(
              items: _cat('tipo_sector'),
              etiqueta: 'Tipo de sector',
              valor: _sel['tipo_sector'],
              onChanged: (v) => setState(() {
                _sel['tipo_sector'] = v;
                _setValor('nombre_sector', _nombreCat('tipo_sector', v ?? ''));
              }),
            ),
            CampoTexto(
              controller: _ctrl['nombre_sector']!,
              etiqueta: 'Nombre del sector',
              maxLength: 50,
            ),
            CampoSelector(
              items: _cat('tipo_res'),
              etiqueta: 'Tipo de residencia',
              valor: _sel['tipo_res'],
              onChanged: (v) => setState(() => _sel['tipo_res'] = v),
            ),
            CampoTexto(
              controller: _ctrl['nombre_res']!,
              etiqueta: 'Nombre de la residencia',
              maxLength: 50,
            ),
            CampoSelector(
              items: _cat('tipo_via'),
              etiqueta: 'Tipo de via',
              valor: _sel['tipo_via'],
              onChanged: (v) => setState(() => _sel['tipo_via'] = v),
            ),
            CampoTexto(
              controller: _ctrl['nombre_via']!,
              etiqueta: 'Nombre de la via',
              maxLength: 100,
            ),
            CampoTexto(
              controller: _ctrl['num_finca']!,
              etiqueta: 'Numero de finca',
              maxLength: 10,
            ),
            CampoTexto(
              controller: _ctrl['interior']!,
              etiqueta: 'Interior',
              maxLength: 20,
            ),
            CampoTexto(
              controller: _ctrl['dir_lateral']!,
              etiqueta: 'Direccion lateral',
              maxLength: 150,
              lineas: 2,
            ),
            CampoTexto(
              controller: _ctrl['manzana']!,
              etiqueta: 'Manzana',
              maxLength: 20,
            ),
            CampoTexto(
              controller: _ctrl['lote']!,
              etiqueta: 'Lote',
              maxLength: 10,
            ),
            CampoTexto(
              controller: _ctrl['edificio_block']!,
              etiqueta: 'Edificio / Block',
              maxLength: 50,
            ),
            CampoTexto(
              controller: _ctrl['piso']!,
              etiqueta: 'Piso',
              maxLength: 10,
            ),
            CampoTexto(
              controller: _ctrl['grupo_sector']!,
              etiqueta: 'Grupo / Sector',
              maxLength: 50,
            ),
            CampoTexto(
              controller: _ctrl['referencia']!,
              etiqueta: 'Referencia',
              maxLength: 250,
              lineas: 2,
            ),
          ],
        ],
      ),
    );
  }

  /// Direccion del predio compuesta con lo que ya se cargo.
  String _direccionCompleta() {
    final partes = <String>[
      if (_v('nombre_via').isNotEmpty) _v('nombre_via'),
      if (_v('num_finca').isNotEmpty) 'Nro ${_v('num_finca')}',
      if (_v('manzana').isNotEmpty) 'Mz ${_v('manzana')}',
      if (_v('lote').isNotEmpty) 'Lt ${_v('lote')}',
      if (_v('interior').isNotEmpty) 'Int ${_v('interior')}',
    ];
    if (partes.isEmpty) return _v('dir_lateral');
    return partes.join(' ');
  }

  /// Abre la grilla de predios del contribuyente para elegir uno.
  Future<void> _abrirPredios() async {
    final predios = (_contribuyente?['predios'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (predios.isEmpty) {
      _aviso('El contribuyente no tiene predios registrados.');
      return;
    }
    final elegido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoPredios(predios: predios),
    );
    if (elegido != null) _aplicarPredio(elegido);
  }

  Widget _seccionUsoPropiedad() {
    return SeccionFormulario(
      titulo: '6. USO Y PROPIEDAD',
      icono: Icons.verified_user,
      child: Column(
        children: [
          CampoSelector(
            items: _cat('tipo_predio'),
            etiqueta: 'Tipo de predio',
            valor: _sel['tipo_predio'],
            onChanged: (v) => setState(() => _sel['tipo_predio'] = v),
          ),
          CampoSelector(
            items: _cat('condicion_prop'),
            etiqueta: 'Condicion de propiedad',
            valor: _sel['condicion_prop'],
            onChanged: (v) => setState(() => _sel['condicion_prop'] = v),
          ),
          if (_predio != null && _txt(_predio!['condicion']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'En el catastro figura como: ${_txt(_predio!['condicion'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.grisMedio),
              ),
            ),
        ],
      ),
    );
  }

  Widget _seccionAreas() {
    final campos = <MapEntry<String, String>>[
      const MapEntry('porc_propiedad', 'Porcentaje de propiedad'),
      const MapEntry('area_matriz_m2', 'Area de la matriz'),
      const MapEntry('porc_bien_comun', 'Porcentaje de bien comun'),
      const MapEntry('area_propio_m2', 'Area propia'),
      const MapEntry('area_comun_m2', 'Area comun'),
      const MapEntry('area_total_m2', 'Area total'),
      const MapEntry('frente_predio', 'Frente del predio'),
    ];
    // La unidad va dentro del campo para que el operador no tenga que
    // adivinar si el numero se mide en metros cuadrados o en metros.
    final unidades = <String, String>{
      'porc_propiedad': '%',
      'area_matriz_m2': 'm2',
      'porc_bien_comun': '%',
      'area_propio_m2': 'm2',
      'area_comun_m2': 'm2',
      'area_total_m2': 'm2',
      'frente_predio': 'm',
    };
    return SeccionFormulario(
      titulo: '7. AREAS Y MEDIDAS',
      icono: Icons.square_foot,
      child: Column(
        children: campos
            .map((e) => CampoTexto(
                  controller: _ctrl[e.key]!,
                  etiqueta: e.value,
                  sufijo: unidades[e.key],
                  maxLength: 12,
                  teclado:
                      const TextInputType.numberWithOptions(decimal: true),
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,9}[.,]?\d{0,2}')),
                  ],
                ))
            .toList(),
      ),
    );
  }

  Widget _seccionConstrucciones() {
    return SeccionFormulario(
      titulo: '8. CONSTRUCCIONES (${_construcciones.length})',
      icono: Icons.apartment,
      accion: IconButton(
        tooltip: 'Agregar construccion',
        onPressed: _agregarConstruccion,
        icon: const Icon(Icons.add_circle, color: Colors.white),
      ),
      child: Column(
        children: [
          if (_construcciones.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Registre las construcciones por nivel (piso).',
                style: TextStyle(fontSize: 12, color: AppColors.grisMedio),
              ),
            ),
          ..._construcciones.asMap().entries.map((e) => _tarjetaConstruccion(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _tarjetaConstruccion(int index, Map<String, TextEditingController> fila) {
    final num = index + 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppColors.grisClaro,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Construccion $num',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  onPressed: () => _quitarConstruccion(index),
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.rojo),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: fila['nivel'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Nivel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CampoSelectorBuscable(
                    items: _cat('uso'),
                    etiqueta: 'Uso',
                    valor: fila['uso']?.text.isNotEmpty == true
                        ? fila['uso']!.text
                        : null,
                    onChanged: (v) =>
                        setState(() => fila['uso']!.text = v ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            CampoSelector(
              items: _cat('clasificacion'),
              etiqueta: 'Clasificacion',
              valor: _selEmpty(fila, 'clasificacion'),
              onChanged: (v) =>
                  setState(() => fila['clasificacion']!.text = v ?? ''),
            ),
            CampoSelector(
              items: _cat('material_predom'),
              etiqueta: 'Material predominante',
              valor: _selEmpty(fila, 'material_predom'),
              onChanged: (v) =>
                  setState(() => fila['material_predom']!.text = v ?? ''),
            ),
            CampoSelector(
              items: _cat('estado_conserv'),
              etiqueta: 'Estado de conservacion',
              valor: _selEmpty(fila, 'estado_conserv'),
              onChanged: (v) =>
                  setState(() => fila['estado_conserv']!.text = v ?? ''),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fila['fc_mes'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Mes construccion'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fila['fc_anio'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Anio construccion'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _selectorCategoria('Muros', fila, 'cat_muros', '1'),
            _selectorCategoria('Techos', fila, 'cat_techos', '2'),
            _selectorCategoria('Pisos', fila, 'cat_pisos', '3'),
            _selectorCategoria('Puertas y ventanas', fila, 'cat_puertas_vent', '4'),
            _selectorCategoria('Revestimientos', fila, 'cat_revestim', '5'),
            _selectorCategoria('Banos', fila, 'cat_banos', '6'),
            _selectorCategoria('Instalaciones', fila, 'cat_inst_elec', '7'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fila['fcat_mes'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Mes ficha categ.'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fila['fcat_anio'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Anio ficha categ.'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: fila['area_construida'],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              maxLength: 12,
              decoration: _dec('Area construida', sufijo: 'm2'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _selectorCategoria(
    String etiqueta,
    Map<String, TextEditingController> fila,
    String campo,
    String tipo,
  ) {
    final items = _catCategorias(tipo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: AppColors.texto),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () async {
                final v = await showDialog<String>(
                  context: context,
                  builder: (_) => _DialogoCategoria(
                    titulo: etiqueta,
                    items: items,
                    valor: fila[campo]!.text,
                  ),
                );
                // Sin setState el campo no se redibuja y parece que no cargo.
                if (v != null) setState(() => fila[campo]!.text = v);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  suffixIcon: const Icon(Icons.arrow_drop_down, size: 20),
                ),
                child: Text(
                  _etiquetaCategoria(items, fila[campo]!.text, etiqueta),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _etiquetaCategoria(
      List<CatalogoItem> items, String codigo, String etiqueta) {
    if (codigo.isEmpty) return 'Seleccione';
    final item = items.firstWhere(
      (e) => e.codigo == codigo,
      orElse: () => CatalogoItem(codigo, ''),
    );
    if (item.nombre.isEmpty) return codigo;
    return '$codigo - ${item.nombre}';
  }

  String? _selEmpty(Map<String, TextEditingController> fila, String campo) {
    final v = fila[campo]?.text ?? '';
    return v.isEmpty ? null : v;
  }

  /// Unidad que corresponde a la medida de una obra: M2 son metros cuadrados
  /// y M3 metros cubicos, segun lo que el operador elija en la fila.
  String? _unidadMedida(Map<String, TextEditingController> fila) {
    final u = (fila['unidad_medida']?.text ?? '').toUpperCase();
    if (u == 'M3') return 'm3';
    if (u == 'M2') return 'm2';
    return null;
  }

  InputDecoration _dec(String etiqueta, {String? sufijo}) {    return InputDecoration(
      labelText: etiqueta,
      // La unidad se muestra dentro del campo para que el operador sepa en
      // que se mide cada numero sin tener que leer la etiqueta.
      suffixText: sufijo,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  Widget _seccionObras() {
    return SeccionFormulario(
      titulo: '9. OBRAS COMPLEMENTARIAS (${_obras.length})',
      icono: Icons.construction,
      accion: IconButton(
        tooltip: 'Agregar obra',
        onPressed: _agregarObra,
        icon: const Icon(Icons.add_circle, color: Colors.white),
      ),
      child: Column(
        children: [
          if (_obras.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Registre cercos, tanques, pipelines y demas obras del predio.',
                style: TextStyle(fontSize: 12, color: AppColors.grisMedio),
              ),
            ),
          ..._obras.asMap().entries.map((e) => _tarjetaObra(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _tarjetaObra(int index, Map<String, TextEditingController> fila) {
    final num = index + 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: AppColors.grisClaro,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Obra $num',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  onPressed: () => _quitarObra(index),
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.rojo),
                ),
              ],
            ),
            TextField(
              controller: fila['descripcion'],
              maxLength: 200,
              maxLines: 2,
              decoration: _dec('Descripcion de la obra'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fila['fc_mes'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Mes'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fila['fc_anio'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec('Anio'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            CampoSelector(
              items: _cat('unidad_medida'),
              etiqueta: 'Unidad de medida',
              valor: _selEmpty(fila, 'unidad_medida'),
              onChanged: (v) =>
                  setState(() => fila['unidad_medida']!.text = v ?? ''),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fila['medida_valor'],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    maxLength: 12,
                    decoration: _dec('Medida',
                        sufijo: _unidadMedida(fila)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fila['largo'],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    maxLength: 10,
                    decoration: _dec('Largo', sufijo: 'm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fila['ancho'],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    maxLength: 10,
                    decoration: _dec('Ancho', sufijo: 'm'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fila['alto'],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    maxLength: 10,
                    decoration: _dec('Alto', sufijo: 'm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            CampoSelector(
              items: _cat('material_predom'),
              etiqueta: 'Material predominante',
              valor: _selEmpty(fila, 'material_predom'),
              onChanged: (v) =>
                  setState(() => fila['material_predom']!.text = v ?? ''),
            ),
            const SizedBox(height: 10),
            CampoSelector(
              items: _cat('estado_conserv'),
              etiqueta: 'Estado de conservacion',
              valor: _selEmpty(fila, 'estado_conserv'),
              onChanged: (v) =>
                  setState(() => fila['estado_conserv']!.text = v ?? ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: fila['ubic_construccion'],
              maxLength: 30,
              decoration: _dec('Ubicacion en la construccion'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccionImagenes() {
    return SeccionFormulario(
      titulo: '10. FOTOGRAFIAS',
      icono: Icons.photo_camera,
      child: Column(
        children: [
          SelectorImagen(
            etiqueta: 'Imagen del predio',
            imagenes: _imgPredio == null ? const [] : [_imgPredio!.bytes],
            capturando: _cargandoImagen,
            onCamara: () => _capturarImagen(esPredio: true),
            onGaleria: () => _capturarImagen(esPredio: true),
            onVer: () => _verImagen(_imgPredio),
            onLimpiar: () => setState(() => _imgPredio = null),
          ),
          const Divider(height: 28),
          SelectorImagen(
            etiqueta: 'Imagen de la ficha',
            imagenes: _imgFicha == null ? const [] : [_imgFicha!.bytes],
            capturando: _cargandoImagen,
            onCamara: () => _capturarImagen(esPredio: false),
            onGaleria: () => _capturarImagen(esPredio: false),
            onVer: () => _verImagen(_imgFicha),
            onLimpiar: () => setState(() => _imgFicha = null),
          ),
        ],
      ),
    );
  }

  Widget _seccionCierre() {
    return SeccionFormulario(
      titulo: '11. CIERRE DE LA FICHA',
      icono: Icons.check_circle_outline,
      child: Column(
        children: [
          CampoTexto(
            controller: _ctrl['observaciones']!,
            etiqueta: 'Observaciones',
            ayuda: VozService.consejo(),
            maxLength: 500,
            lineas: 4,
            boton: IconButton(
              tooltip: _dictando ? 'Detener dictado' : 'Dictar con el microfono',
              onPressed: _dictando ? _detenerDictado : _iniciarDictado,
              icon: Icon(
                _dictando ? Icons.mic : Icons.mic_none,
                size: 20,
                color: _dictando ? AppColors.rojo : AppColors.azulModerno,
              ),
            ),
          ),
          CampoTexto(
            controller: _ctrl['fecha_cierre']!,
            etiqueta: 'Fecha y hora de cierre',
            ayuda: 'Se toma automaticamente del dispositivo y no se edita.',
            maxLength: 19,
            soloLectura: true,
          ),
        ],
      ),
    );
  }

  /// Fecha y hora del dispositivo en el formato que guarda la ficha.
  String _ahora() {
    final a = DateTime.now();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${a.year}-${p2(a.month)}-${p2(a.day)} '
        '${p2(a.hour)}:${p2(a.minute)}:${p2(a.second)}';
  }

  Future<void> _iniciarDictado() async {
    // El texto que ya estaba escrito se conserva: el dictado se agrega despues
    // y no lo pisa. Sin esto, cada resultado parcial vuelve a escribir lo mismo.
    final base = _ctrl['observaciones']?.text ?? '';
    final ok = await VozService.escuchar((texto) {
      if (texto.isEmpty) return;
      // Los resultados parciales traen todo lo reconocido hasta el momento,
      // asi que se reemplaza en vez de concatenar para no repetir palabras.
      final separador = base.isEmpty || base.endsWith(' ') ? '' : ' ';
      _setValor('observaciones', '$base$separador$texto');
    });
    if (!mounted) return;
    if (!ok) {
      _aviso('No se pudo usar el microfono. Revise el permiso en Ajustes.');
      return;
    }
    setState(() => _dictando = true);
  }

  Future<void> _detenerDictado() async {
    await VozService.detener();
    if (mounted) setState(() => _dictando = false);
  }

  String? Function(String?) _requerido(String mensaje) {
    return (v) => (v == null || v.trim().isEmpty) ? mensaje : null;
  }
}

/// Dialogo para elegir el predio del contribuyente.
///
/// Trae un cuadro de busqueda que filtra por codigo catastral o por la
/// direccion, y una grilla con un check para marcar cual cargar.
class _DialogoPredios extends StatefulWidget {
  final List<Map<String, dynamic>> predios;

  const _DialogoPredios({required this.predios});

  @override
  State<_DialogoPredios> createState() => _DialogoPrediosState();
}

class _DialogoPrediosState extends State<_DialogoPredios> {
  final _buscarCtrl = TextEditingController();
  String _filtro = '';
  int? _elegido;

  @override
  void initState() {
    super.initState();
    // Con un solo predio no hay que elegir: viene marcado.
    if (widget.predios.length == 1) _elegido = 0;
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibles {
    final t = _filtro.trim().toUpperCase();
    if (t.isEmpty) return widget.predios;
    return widget.predios.where((p) {
      final cat = (p['cod_catastral'] ?? '').toString().toUpperCase();
      final dir = (p['ubicacion'] ?? '').toString().toUpperCase();
      return cat.contains(t) || dir.contains(t);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    return AlertDialog(
      title: const Text('Predios del contribuyente',
          style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _buscarCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _filtro = v),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Buscar por catastral o direccion...',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: visibles.isEmpty
                  ? const Center(
                      child: Text('Sin coincidencias',
                          style: TextStyle(fontSize: 12)))
                  : ListView.builder(
                      itemCount: visibles.length,
                      itemBuilder: (_, i) {
                        final p = visibles[i];
                        final elegido = _elegido == i;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          elevation: elegido ? 2 : 0,
                          color: elegido
                              ? AppColors.azulModerno.withValues(alpha: 0.06)
                              : AppColors.grisClaro,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: elegido
                                  ? AppColors.azulModerno
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _elegido = i),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: elegido,
                                    onChanged: (_) =>
                                        setState(() => _elegido = i),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (p['cod_catastral'] ?? '').toString(),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700),
                                        ),
                                        Text(
                                          (p['ubicacion'] ?? '').toString(),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.grisMedio),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.azulModerno),
          onPressed: _elegido == null
              ? null
              : () => Navigator.pop(context, visibles[_elegido!]),
          child: const Text('Cargar'),
        ),
      ],
    );
  }
}

/// Dialogo para elegir la categoria de un elemento de construccion.
class _DialogoCategoria extends StatefulWidget {
  final String titulo;
  final List<CatalogoItem> items;
  final String valor;

  const _DialogoCategoria({
    required this.titulo,
    required this.items,
    required this.valor,
  });

  @override
  State<_DialogoCategoria> createState() => _DialogoCategoriaState();
}

class _DialogoCategoriaState extends State<_DialogoCategoria> {
  String? _filtro;

  @override
  Widget build(BuildContext context) {
    final items = _filtro == null || _filtro!.trim().isEmpty
        ? widget.items
        : widget.items
            .where((e) => e.nombre.toUpperCase().contains(_filtro!.toUpperCase()))
            .toList();
    return AlertDialog(
      title: Text(widget.titulo, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _filtro = v),
              decoration: const InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final e = items[i];
                  return ListTile(
                    dense: true,
                    selected: e.codigo == widget.valor,
                    title: Text(e.nombre, style: const TextStyle(fontSize: 12)),
                    leading: CircleAvatar(
                      radius: 12,
                      child: Text(e.codigo,
                          style: const TextStyle(fontSize: 10)),
                    ),
                    onTap: () => Navigator.pop(context, e.codigo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Quitar'),
        ),
      ],
    );
  }
}

// =====================================================================
// Definicion de campos
// =====================================================================
const List<String> _camposCabecera = [
  'codigo_contribuyente', 'razon_social', 'num_doc', 'telefono',
  'cod_catastral', 'cod_predio_sat', 'distrito', 'nombre_sector', 'nombre_res',
  'nombre_via', 'num_finca', 'interior', 'dir_lateral', 'manzana', 'lote',
  'edificio_block', 'piso', 'grupo_sector', 'referencia', 'porc_propiedad',
  'area_matriz_m2', 'porc_bien_comun', 'area_propio_m2', 'area_comun_m2',
  'area_total_m2', 'frente_predio', 'observaciones', 'lugar', 'fecha_cierre',
  'ubicacion_geo', 'nombre_solicitud',
];

const List<String> _camposConstruccion = [
  'nivel', 'clasificacion', 'material_predom', 'estado_conserv', 'uso',
  'fc_mes', 'fc_anio', 'cat_muros', 'cat_techos', 'cat_pisos',
  'cat_puertas_vent', 'cat_revestim', 'cat_banos', 'cat_inst_elec',
  'fcat_mes', 'fcat_anio', 'area_construida',
];

const List<String> _camposObra = [
  'descripcion', 'fc_mes', 'fc_anio', 'unidad_medida', 'medida_valor',
  'largo', 'ancho', 'alto', 'material_predom', 'estado_conserv',
  'ubic_construccion',
];
