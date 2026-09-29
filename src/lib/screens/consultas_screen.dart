import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fiscalizador_sesion.dart';
import '../services/api_service.dart';
import '../screens/ficha_inspeccion_screen.dart';
import '../widgets/form_widgets.dart';

/// Pantalla CONSULTAS: lista las fichas de inspeccion registradas.
///
/// Por defecto muestra las fichas creadas por el fiscalizador que inicio
/// sesion; se puede cambiar a "Todas las fichas" con el interruptor.
class ConsultasScreen extends StatefulWidget {
  final FiscalizadorSesion sesion;

  const ConsultasScreen({super.key, required this.sesion});

  @override
  State<ConsultasScreen> createState() => _ConsultasScreenState();
}

class _ConsultasScreenState extends State<ConsultasScreen> {
  final _buscarCtrl = TextEditingController();
  List<Map<String, dynamic>> _fichas = [];
  bool _cargando = true;
  bool _soloMias = true;
  String _error = '';
  int _fichaAbierta = 0;
  Map<String, dynamic>? _detalle;
  final Map<String, Uint8List> _imagenes = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final res = await ApiService.listarFichas(
        dni: _soloMias ? widget.sesion.dni : null,
        texto: _buscarCtrl.text,
        limite: 50,
      );
      if (!mounted) return;
      setState(() {
        _fichas = res.fichas;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _abrir(Map<String, dynamic> ficha) async {
    final id = (ficha['id_inspeccion'] is num)
        ? (ficha['id_inspeccion'] as num).toInt()
        : int.tryParse('${ficha['id_inspeccion']}') ?? 0;
    if (id == 0) return;

    setState(() {
      _fichaAbierta = id;
      _detalle = null;
      _imagenes.clear();
    });

    // Se carga en segundo plano: el modal muestra el indicador mientras tanto.
    _cargarDetalle(id);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.97,
        minChildSize: 0.5,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ficha ${_t(ficha['numero'])}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _editar();
                    },
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _eliminar();
                    },
                    icon: const Icon(Icons.delete_outline, color: AppColors.rojo),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _detalle == null
                  ? const Center(child: CircularProgressIndicator())
                  : _detalleFicha(scrollController),
            ),
          ],
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _fichaAbierta = 0;
        _detalle = null;
        _imagenes.clear();
      });
    }
  }

  /// Descarga la ficha y sus imagenes sin bloquear la interfaz.
  Future<void> _cargarDetalle(int id) async {
    try {
      final d = await ApiService.detalleFicha(id);
      if (!mounted || _fichaAbierta != id) return;
      setState(() => _detalle = d);

      for (final campo in const ['imagen_predio', 'imagen_ficha']) {
        if (d['tiene_$campo'] != true) continue;
        final b = await ApiService.imagenFicha(id, campo);
        if (!mounted || _fichaAbierta != id) return;
        if (b != null) {
          setState(() => _imagenes[campo] = Uint8List.fromList(b));
        }
      }
    } catch (e) {
      if (!mounted || _fichaAbierta != id) return;
      _snack(e.toString(), AppColors.rojo);
    }
  }

  Future<void> _editar() async {
    final id = _fichaAbierta;
    if (id == 0) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FichaInspeccionScreen(sesion: widget.sesion, idInspeccion: id),
      ),
    );
    if (ok == true) _cargar();
  }

  Future<void> _eliminar() async {
    if (_fichaAbierta == 0) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ficha'),
        content: const Text(
          'La ficha y sus construcciones y obras complementarias se '
          'eliminaran de forma permanente. Desea continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rojo),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final msg = await ApiService.eliminarFicha(_fichaAbierta, widget.sesion.dni);
      if (!mounted) return;
      _snack(msg, AppColors.verde);
      setState(() {
        _fichaAbierta = 0;
        _detalle = null;
        _imagenes.clear();
      });
      _cargar();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString(), AppColors.rojo);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: color, content: Text(msg)),
    );
  }

  String _t(dynamic v) => v == null ? '' : v.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consultas de fichas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // ------------------------------------------------------ Filtros
          Container(
            color: AppColors.grisClaro,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _buscarCtrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _cargar(),
                        style: const TextStyle(fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Numero, nombre, catastro o documento',
                          isDense: true,
                          prefixIcon: Icon(Icons.search, size: 20),
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
                      onPressed: _cargando ? null : _cargar,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.azulModerno,
                        minimumSize: const Size(52, 44),
                      ),
                      child: const Icon(Icons.search),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppColors.azulModerno,
                        title: const Text(
                          'Solo mis fichas',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: _soloMias,
                        onChanged: (v) {
                          setState(() => _soloMias = v);
                          _cargar();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ------------------------------------------------------ Listado
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? _mensajeError()
                    : _fichas.isEmpty
                        ? const Center(
                            child: Text(
                              'No se encontraron fichas.',
                              style: TextStyle(color: AppColors.grisMedio),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(10),
                            itemCount: _fichas.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) =>
                                _tarjetaFicha(_fichas[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _mensajeError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.grisMedio),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaFicha(Map<String, dynamic> f) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrir(f),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.azulModerno,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _t(f['numero']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _t(f['nombre_solicitud']).isEmpty
                          ? _t(f['tipo_solicitud'])
                          : _t(f['nombre_solicitud']),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (f['tiene_img_predio'] == true ||
                      f['tiene_img_ficha'] == true)
                    const Icon(Icons.photo_camera,
                        size: 18, color: AppColors.grisMedio),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _t(f['razon_social']),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (_t(f['cod_catastral']).isNotEmpty)
                Text('Catastro: ${_t(f['cod_catastral'])}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.grisMedio)),
              if (_t(f['manzana']).isNotEmpty || _t(f['lote']).isNotEmpty)
                Text('Mz ${_t(f['manzana'])} - Lt ${_t(f['lote'])}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.grisMedio)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _chip(Icons.apartment, '${_t(f['n_construcciones'] ?? 0)} constr.'),
                  const SizedBox(width: 6),
                  _chip(Icons.construction, '${_t(f['n_obras'] ?? 0)} obras'),
                  const Spacer(),
                  if (_t(f['fecha_cierre']).isNotEmpty)
                    Text(
                      _t(f['fecha_cierre']).split('T').first,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.grisMedio),
                    ),
                ],
              ),
              if (_t(f['ultimo_fiscalizador']).isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Por: ${_t(f['ultimo_fiscalizador'])}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.grisMedio),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.grisClaro,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.grisMedio),
          const SizedBox(width: 4),
          Text(texto,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.grisMedio)),
        ],
      ),
    );
  }

  // =====================================================================
  // Detalle de la ficha seleccionada
  // =====================================================================
  Widget _detalleFicha(ScrollController scrollController) {
    final d = _detalle;
    if (d == null) return const Center(child: CircularProgressIndicator());

    final construcciones = (d['construcciones'] as List? ?? const []);
    final obras = (d['obras'] as List? ?? const []);

    final secciones = <String, dynamic>{
      'numero': 'Numero de ficha',
      'tipo_solicitud': 'Tipo de solicitud',
      'nombre_solicitud': 'Nombre de solicitud',
      'ubicacion_geo': 'Coordenadas GPS',
      'codigo_contribuyente': 'Codigo de contribuyente',
      'razon_social': 'Razon social',
      'tipo_doc': 'Tipo de documento',
      'num_doc': 'Numero de documento',
      'telefono': 'Telefono',
      'cod_catastral': 'Codigo catastral',
      'cod_predio_sat': 'Codigo de predio (SAT)',
      'distrito': 'Distrito',
      'tipo_sector': 'Tipo de sector',
      'nombre_sector': 'Nombre del sector',
      'tipo_res': 'Tipo de residencia',
      'nombre_res': 'Nombre de la residencia',
      'tipo_via': 'Tipo de via',
      'nombre_via': 'Nombre de la via',
      'num_finca': 'Numero de finca',
      'interior': 'Interior',
      'dir_lateral': 'Direccion lateral',
      'manzana': 'Manzana',
      'lote': 'Lote',
      'edificio_block': 'Edificio / Block',
      'piso': 'Piso',
      'grupo_sector': 'Grupo / Sector',
      'referencia': 'Referencia',
      'tipo_predio': 'Tipo de predio',
      'condicion_prop': 'Condicion de propiedad',
      'porc_propiedad': '% de propiedad',
      'area_matriz_m2': 'Area matriz (m2)',
      'porc_bien_comun': '% bien comun',
      'area_propio_m2': 'Area propia (m2)',
      'area_comun_m2': 'Area comun (m2)',
      'area_total_m2': 'Area total (m2)',
      'frente_predio': 'Frente (m)',
      'lugar': 'Lugar',
      'observaciones': 'Observaciones',
      'fecha_cierre': 'Fecha de cierre',
    };

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(10),
      children: [
        SeccionFormulario(
          titulo: 'DATOS DE LA FICHA',
          icono: Icons.badge_outlined,
          child: Column(
            children: secciones.entries
                .where((e) => _t(e.value).isNotEmpty)
                .map((e) => _filaDato(e.value, _t(d[e.key])))
                .toList(),
          ),
        ),
        if (construcciones.isNotEmpty)
          SeccionFormulario(
            titulo: 'CONSTRUCCIONES (${construcciones.length})',
            icono: Icons.apartment,
            child: Column(
              children: [
                for (final c in construcciones.whereType<Map>())
                  _tarjetaConstruccion(c),
              ],
            ),
          ),
        if (obras.isNotEmpty)
          SeccionFormulario(
            titulo: 'OBRAS COMPLEMENTARIAS (${obras.length})',
            icono: Icons.construction,
            child: Column(
              children: [
                for (final o in obras.whereType<Map>()) _tarjetaObra(o),
              ],
            ),
          ),
        if (_imagenes.isNotEmpty)
          SeccionFormulario(
            titulo: 'FOTOGRAFIAS',
            icono: Icons.photo_camera,
            child: Column(
              children: _imagenes.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key == 'imagen_predio'
                            ? 'Imagen del predio'
                            : 'Imagen de la ficha',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          e.value,
                          fit: BoxFit.contain,
                          height: 220,
                          width: double.infinity,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _filaDato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: AppColors.grisMedio),
            ),
          ),
          Expanded(
            child: Text(
              valor.split('T').first,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaConstruccion(Map c) {
    final partes = <String>[
      if (_t(c['uso']).isNotEmpty) 'Uso: ${_t(c['uso'])}',
      if (_t(c['clasificacion']).isNotEmpty) 'Clasif: ${_t(c['clasificacion'])}',
      if (_t(c['material_predom']).isNotEmpty)
        'Material: ${_t(c['material_predom'])}',
      if (_t(c['estado_conserv']).isNotEmpty)
        'Conserv: ${_t(c['estado_conserv'])}',
      if (_t(c['area_construida']).isNotEmpty)
        'Area: ${_t(c['area_construida'])} m2',
      if (_t(c['fc_mes']).isNotEmpty || _t(c['fc_anio']).isNotEmpty)
        'F constr.: ${_t(c['fc_mes'])}/${_t(c['fc_anio'])}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: AppColors.grisClaro,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nivel ${_t(c['nivel'])}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(partes.join(' | '),
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaObra(Map o) {
    final partes = <String>[
      if (_t(o['unidad_medida']).isNotEmpty) _t(o['unidad_medida']),
      if (_t(o['medida_valor']).isNotEmpty) _t(o['medida_valor']),
      if (_t(o['material_predom']).isNotEmpty) _t(o['material_predom']),
      if (_t(o['ubic_construccion']).isNotEmpty) _t(o['ubic_construccion']),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: AppColors.grisClaro,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(o['descripcion']),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (partes.isNotEmpty)
              Text(partes.join(' | '), style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
