import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/fiscalizador_sesion.dart';
import '../services/api_service.dart';
import '../services/imagen_service.dart';
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
    setState(() {
      _contribuyente = c;
      _resultados = [];
      _buscarCtrl.text = c['nombre']?.toString() ?? '';
      _setValor('codigo_contribuyente', _txt(c['codigo']));
      _setValor('razon_social', _txt(c['nombre']));
      if (_txt(c['lugar']).isNotEmpty) {
        _setValor('lugar', _txt(c['lugar']));
      }
    });
    _aviso('Contribuyente seleccionado. Ahora elija el predio en la seccion Direccion.');
  }

  void _quitarContribuyente() {
    setState(() {
      _contribuyente = null;
      _buscarCtrl.clear();
      _resultados = [];
      _setValor('codigo_contribuyente', '');
      _setValor('razon_social', '');
      _setValor('cod_catastral', '');
    });
  }

  /// Rellena los campos de direccion con los datos de un predio del contribuyente.
  void _elegirPredio(Map<String, dynamic> p) {
    setState(() {
      _setValor('cod_catastral', _txt(p['cod_catastral']));
      if (_txt(p['manzana']).isNotEmpty) _setValor('manzana', _txt(p['manzana']));
      if (_txt(p['lote']).isNotEmpty) _setValor('lote', _txt(p['lote']));
      if (_txt(p['numero']).isNotEmpty) _setValor('num_finca', _txt(p['numero']));
      if (_txt(p['edificio']).isNotEmpty) {
        _setValor('edificio_block', _txt(p['edificio']));
      }
      if (_txt(p['interior']).isNotEmpty) {
        _setValor('interior', _txt(p['interior']));
      }
      if (_txt(p['area_titulo']).isNotEmpty) {
        _setValor('area_total_m2', _txt(p['area_titulo']));
      }
      // Predio urbano siempre es urbano segun el catalogo
      if (_txt(p['cod_tipo_predio']).isNotEmpty) {
        _sel['tipo_predio'] = 'U';
      }
    });
    _aviso('Datos del predio aplicados al formulario.');
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
          final predios = (c['predios'] as List? ?? const []);
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
                'Cod. ${_txt(c['codigo'])} - ${predios.length} predio(s)',
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
                          'Mz ${_txt(p['manzana'])} Lt ${_txt(p['lote'])} '
                          'Nro ${_txt(p['numero'])} | ${_txt(p['uso'])}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () {
                          _elegirContribuyente(c);
                          _elegirPredio(p);
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
            ayuda: 'Formato: latitud, longitud',
            maxLength: 100,
          ),
          CampoTexto(
            controller: _ctrl['distrito']!,
            etiqueta: 'Distrito',
            maxLength: 30,
          ),
          CampoTexto(
            controller: _ctrl['lugar']!,
            etiqueta: 'Lugar',
            maxLength: 80,
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
      ),
    );
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
        ],
      ),
    );
  }

  Widget _seccionAreas() {
    final campos = <MapEntry<String, String>>[
      const MapEntry('porc_propiedad', 'Porcentaje de propiedad (%)'),
      const MapEntry('area_matriz_m2', 'Area de la matriz (m2)'),
      const MapEntry('porc_bien_comun', 'Porcentaje de bien comun (%)'),
      const MapEntry('area_propio_m2', 'Area propia (m2)'),
      const MapEntry('area_comun_m2', 'Area comun (m2)'),
      const MapEntry('area_total_m2', 'Area total (m2)'),
      const MapEntry('frente_predio', 'Frente del predio (m)'),
    ];
    return SeccionFormulario(
      titulo: '7. AREAS Y MEDIDAS',
      icono: Icons.square_foot,
      child: Column(
        children: campos
            .map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          e.value,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.texto),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctrl[e.key],
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d{0,9}[.,]?\d{0,2}')),
                          ],
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
                    onChanged: (v) => fila['uso']!.text = v ?? '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            CampoSelector(
              items: _cat('clasificacion'),
              etiqueta: 'Clasificacion',
              valor: _selEmpty(fila, 'clasificacion'),
              onChanged: (v) => fila['clasificacion']!.text = v ?? '',
            ),
            CampoSelector(
              items: _cat('material_predom'),
              etiqueta: 'Material predominante',
              valor: _selEmpty(fila, 'material_predom'),
              onChanged: (v) => fila['material_predom']!.text = v ?? '',
            ),
            CampoSelector(
              items: _cat('estado_conserv'),
              etiqueta: 'Estado de conservacion',
              valor: _selEmpty(fila, 'estado_conserv'),
              onChanged: (v) => fila['estado_conserv']!.text = v ?? '',
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
              decoration: _dec('Area construida (m2)'),
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
                if (v != null) fila[campo]!.text = v;
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

  InputDecoration _dec(String etiqueta) {
    return InputDecoration(
      labelText: etiqueta,
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
              onChanged: (v) => fila['unidad_medida']!.text = v ?? '',
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: fila['medida_valor'],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('Medida'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fila['largo'],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('Largo (m)'),
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
                    decoration: _dec('Ancho (m)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: fila['alto'],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _dec('Alto (m)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: fila['material_predom'],
              maxLength: 30,
              decoration: _dec('Material predominante'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: fila['estado_conserv'],
              maxLength: 30,
              decoration: _dec('Estado de conservacion'),
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
            maxLength: 500,
            lineas: 4,
          ),
          CampoTexto(
            controller: _ctrl['fecha_cierre']!,
            etiqueta: 'Fecha de cierre',
            ayuda: 'Formato: AAAA-MM-DD',
            maxLength: 10,
            teclado: TextInputType.datetime,
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d-]'))],
            onTap: () async {
              final f = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2010),
                lastDate: DateTime(2100),
              );
              if (f != null) {
                _setValor(
                  'fecha_cierre',
                  '${f.year}-${f.month.toString().padLeft(2, '0')}-'
                  '${f.day.toString().padLeft(2, '0')}',
                );
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  String? Function(String?) _requerido(String mensaje) {
    return (v) => (v == null || v.trim().isEmpty) ? mensaje : null;
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
