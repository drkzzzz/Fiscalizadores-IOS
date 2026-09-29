import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/fiscalizador_sesion.dart';
import '../screens/ficha_inspeccion_screen.dart';
import '../services/api_service.dart';

/// Grilla de Fichas de Inspeccion de Predio (FIP).
///
/// Muestra todas las fichas con los filtros de busqueda (numero de FIP, codigo
/// o nombre del contribuyente) y de rango de fechas, paginacion por cantidad
/// de registros y las acciones por fila: editar, ver imagen del predio, ver
/// imagen de la ficha, ver GPS e inhabilitar.
class ListaFipScreen extends StatefulWidget {
  final FiscalizadorSesion sesion;

  const ListaFipScreen({super.key, required this.sesion});

  @override
  State<ListaFipScreen> createState() => _ListaFipScreenState();
}

class _ListaFipScreenState extends State<ListaFipScreen> {
  // Filtros
  final _buscarCtrl = TextEditingController();
  String _desde = '';
  String _hasta = '';
  String _estado = 'T'; // A activas, I inhabilitadas, T todas
  bool _soloMias = true;
  int _limite = 20;
  int _pagina = 1;

  // Datos
  List<Map<String, dynamic>> _fichas = [];
  int _total = 0;
  int _paginas = 0;
  bool _cargando = true;
  String _error = '';

  // Cache de imagenes descargadas, indexada por "$id-$campo".
  final Map<String, Uint8List> _imagenes = {};

  static const List<int> _opcionesPagina = [20, 50, 100];

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

  String _t(dynamic v) => v == null ? '' : v.toString();

  int _id(Map<String, dynamic> f) =>
      (f['id_inspeccion'] is num)
          ? (f['id_inspeccion'] as num).toInt()
          : int.tryParse('${f['id_inspeccion']}') ?? 0;

  Future<void> _cargar({int? pagina}) async {
    if (pagina != null) _pagina = pagina;
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await ApiService.listarFichas(
        dni: _soloMias ? widget.sesion.dni : null,
        texto: _buscarCtrl.text,
        desde: _desde,
        hasta: _hasta,
        estado: _estado,
        limite: _limite,
        pagina: _pagina,
      );
      if (!mounted) return;
      setState(() {
        _fichas = r.fichas;
        _total = r.total;
        _paginas = r.paginas;
        _cargando = false;
      });
      // Si la pagina quedo vacia (por un filtro nuevo), se vuelve a la 1.
      if (r.fichas.isEmpty && _pagina > 1) {
        _cargar(pagina: 1);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: color, content: Text(msg)),
    );
  }

  // =========================================================================
  // Acciones
  // =========================================================================
  Future<void> _nuevaFip() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FichaInspeccionScreen(sesion: widget.sesion),
      ),
    );
    if (ok == true) _cargar(pagina: 1);
  }

  Future<void> _editar(Map<String, dynamic> f) async {
    final id = _id(f);
    if (id == 0) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            FichaInspeccionScreen(sesion: widget.sesion, idInspeccion: id),
      ),
    );
    if (ok == true) _cargar();
  }

  /// Descarga la imagen de la fila indicada y la guarda en cache.
  /// La clave combina id y campo porque cada ficha tiene su propia imagen.
  Future<void> _descargarImagen(int id, String campo) async {
    final clave = '$id-$campo';
    if (_imagenes.containsKey(clave)) return;
    try {
      final b = await ApiService.imagenFicha(id, campo);
      if (!mounted || b == null) return;
      setState(() => _imagenes[clave] = Uint8List.fromList(b));
    } catch (_) {
      // La imagen no pudo descargarse; se informa al intentar abrirla.
    }
  }

  /// Muestra las coordenadas y permite abrirlas en el mapa del telefono.
  Future<void> _verGps(Map<String, dynamic> f) async {
    final geo = _t(f['ubicacion_geo']).trim();
    if (geo.isEmpty) {
      _snack('Esta ficha no tiene coordenadas GPS registradas.',
          AppColors.rojo);
      return;
    }
    final partes = geo.split(',');
    if (partes.length < 2) {
      _snack('Las coordenadas no tienen un formato valido.', AppColors.rojo);
      return;
    }
    final lat = double.tryParse(partes[0].trim());
    final lon = double.tryParse(partes[1].trim());
    if (lat == null || lon == null) {
      _snack('Las coordenadas no tienen un formato valido.', AppColors.rojo);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.my_location, color: AppColors.azulModerno, size: 32),
        title: const Text('Ubicacion del predio', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _datoGps('Latitud', lat.toStringAsFixed(6)),
            _datoGps('Longitud', lon.toStringAsFixed(6)),
            const SizedBox(height: 8),
            Text(
              _t(f['razon_social']),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (_t(f['cod_catastral']).isNotEmpty)
              Text(
                'Catastro ${_t(f['cod_catastral'])}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.grisMedio),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.azulModerno),
            onPressed: () async {
              Navigator.pop(ctx);
              final url =
                  'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else if (mounted) {
                _snack('No se pudo abrir el mapa.', AppColors.rojo);
              }
            },
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Ver mapa'),
          ),
        ],
      ),
    );
  }

  Widget _datoGps(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(etiqueta,
                style: const TextStyle(fontSize: 12, color: AppColors.grisMedio)),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// Inhabilita (o rehabilita) la ficha. Nunca la borra.
  Future<void> _alternarEstado(Map<String, dynamic> f) async {
    final id = _id(f);
    if (id == 0) return;
    final inactiva = _t(f['estado']) == 'I';
    final nuevo = inactiva ? 'A' : 'I';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(inactiva ? 'Habilitar FIP' : 'Inhabilitar FIP'),
        content: Text(
          inactiva
              ? 'La ficha ${_t(f['numero'])} volvera a estar activa. '
                  'Desea continuar?'
              : 'La ficha ${_t(f['numero'])} dejara de mostrarse como activa, '
                  'pero su informacion se conservara. Desea continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: inactiva ? AppColors.verde : AppColors.rojo,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(inactiva ? 'Habilitar' : 'Inhabilitar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final msg = await ApiService.cambiarEstadoFicha(
        id: id,
        dni: widget.sesion.dni,
        nombre: widget.sesion.nombre,
        estado: nuevo,
      );
      if (!mounted) return;
      setState(() => f['estado'] = nuevo);
      _snack(msg, inactiva ? AppColors.verde : Colors.orange.shade800);
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString(), AppColors.rojo);
    }
  }

  // =========================================================================
  // Filtros
  // =========================================================================
  Future<void> _elegirFecha({required bool desde}) async {
    final inicial = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
      helpText: desde ? 'Fecha desde' : 'Fecha hasta',
    );
    if (f == null) return;
    final texto =
        '${f.year}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';
    setState(() {
      if (desde) {
        _desde = texto;
      } else {
        _hasta = texto;
      }
    });
    _cargar(pagina: 1);
  }

  void _limpiarFiltros() {
    setState(() {
      _buscarCtrl.clear();
      _desde = '';
      _hasta = '';
      _estado = 'T';
      _soloMias = true;
      _limite = 20;
    });
    _cargar(pagina: 1);
  }

  bool get _hayFiltros =>
      _buscarCtrl.text.trim().isNotEmpty ||
      _desde.isNotEmpty ||
      _hasta.isNotEmpty ||
      _estado != 'T' ||
      !_soloMias;

  // =========================================================================
  // Build
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fichas de Inspeccion de Predio',
            style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : () => _cargar(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          // ------------------------------------------------ Boton nuevo FIP
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            color: AppColors.azulModerno,
            child: FilledButton.icon(
              onPressed: _nuevaFip,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.azulModerno,
                minimumSize: const Size.fromHeight(40),
              ),
              icon: const Icon(Icons.playlist_add, size: 20),
              label: const Text(
                'ADICIONAR NUEVO FIP',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),

          // ------------------------------------------------ Filtros
          _panelFiltros(),

          // ------------------------------------------------ Grilla
          Expanded(child: _cuerpoGrilla()),

          // ------------------------------------------------ Paginacion
          _panelPaginacion(),
        ],
      ),
    );
  }

  Widget _panelFiltros() {
    return Container(
      color: AppColors.grisClaro,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        children: [
          // ---- fila 1: busqueda
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _buscarCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _cargar(pagina: 1),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'N FIP, codigo o nombre contribuyente',
                      hintStyle: const TextStyle(fontSize: 12),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 38,
                child: FilledButton(
                  onPressed: _cargando ? null : () => _cargar(pagina: 1),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.azulModerno,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Icon(Icons.search, size: 18),
                ),
              ),
              if (_hayFiltros)
                SizedBox(
                  height: 38,
                  child: IconButton(
                    tooltip: 'Limpiar filtros',
                    onPressed: _cargando ? null : _limpiarFiltros,
                    icon: const Icon(Icons.filter_alt_off, size: 20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // ---- fila 2: fechas + estado + alcance + por pagina
          Row(
            children: [
              _botonFiltro(
                etiqueta: 'Desde: ${_desde.isEmpty ? '-' : _desde}',
                icono: Icons.event,
                onTap: _cargando ? null : () => _elegirFecha(desde: true),
                activo: _desde.isNotEmpty,
              ),
              const SizedBox(width: 4),
              _botonFiltro(
                etiqueta: 'Hasta: ${_hasta.isEmpty ? '-' : _hasta}',
                icono: Icons.event_available,
                onTap: _cargando ? null : () => _elegirFecha(desde: false),
                activo: _hasta.isNotEmpty,
              ),
              const SizedBox(width: 4),
              _selectorEstado(),
              const Spacer(),
              _selectorPorPagina(),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.azulModerno,
                  title: const Text('Solo mis fichas',
                      style: TextStyle(fontSize: 12)),
                  value: _soloMias,
                  onChanged: (v) {
                    setState(() => _soloMias = v);
                    _cargar(pagina: 1);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonFiltro({
    required String etiqueta,
    required IconData icono,
    required VoidCallback? onTap,
    required bool activo,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: activo ? AppColors.azulModerno : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: activo ? AppColors.azulModerno : Colors.grey.shade400,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 13, color: activo ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 3),
            Text(
              etiqueta,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: activo ? Colors.white : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectorEstado() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: _estado,
          style: const TextStyle(fontSize: 11, color: AppColors.texto),
          items: const [
            DropdownMenuItem(value: 'T', child: Text('Todas')),
            DropdownMenuItem(value: 'A', child: Text('Activas')),
            DropdownMenuItem(value: 'I', child: Text('Inhabilitadas')),
          ],
          onChanged: (v) {
            setState(() => _estado = v ?? 'T');
            _cargar(pagina: 1);
          },
        ),
      ),
    );
  }

  Widget _selectorPorPagina() {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Ver ', style: TextStyle(fontSize: 10.5)),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isDense: true,
              value: _limite,
              style: const TextStyle(fontSize: 11, color: AppColors.texto),
              items: _opcionesPagina
                  .map((n) => DropdownMenuItem(
                        value: n,
                        child: Text('$n', style: const TextStyle(fontSize: 11)),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _limite = v ?? 20);
                _cargar(pagina: 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpoGrilla() {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) return _vistaError();
    if (_fichas.isEmpty) return _vacia();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 32,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 52,
        columnSpacing: 8,
        horizontalMargin: 6,
        headingTextStyle: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
        dataTextStyle: const TextStyle(fontSize: 10.5, color: AppColors.texto),
        headingRowColor: WidgetStateProperty.all(AppColors.azulModerno),
        dividerThickness: 0.5,
        columns: const [
          DataColumn(label: Text('N FIP')),
          DataColumn(label: Text('CODIGO')),
          DataColumn(label: Text('CONTRIBUYENTE')),
          DataColumn(label: Text('PREDIO')),
          DataColumn(label: Text('FECHA')),
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
          DataColumn(label: Text('')),
        ],
        rows: _fichas.map((f) => _fila(f)).toList(),
      ),
    );
  }

  DataRow _fila(Map<String, dynamic> f) {
    final inactiva = _t(f['estado']) == 'I';
    final id = _id(f);
    return DataRow(
      color: WidgetStateProperty.all(
        inactiva ? const Color(0xFFFDECEC) : Colors.white,
      ),
      cells: [
        // --- N FIP (sin el prefijo IP- que solo ensucia la lectura)
        DataCell(
          GestureDetector(
            onTap: () => _editar(f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: inactiva ? Colors.grey.shade400 : AppColors.azulModerno,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _numeroFip(_t(f['numero'])),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        // --- Codigo del contribuyente (columna angosta)
        DataCell(
          SizedBox(
            width: 62,
            child: Text(
              _t(f['codigo_contribuyente']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5),
            ),
          ),
        ),
        // --- Nombre del contribuyente
        DataCell(
          SizedBox(
            width: 150,
            child: Text(
              _t(f['razon_social']),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        // --- Predio: codigo catastral y debajo la direccion
        DataCell(
          SizedBox(
            width: 190,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(f['cod_catastral']).isEmpty
                      ? '-'
                      : _t(f['cod_catastral']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700),
                ),
                Text(
                  _direccion(f),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.grisMedio),
                ),
              ],
            ),
          ),
        ),
        // --- Fecha
        DataCell(
          SizedBox(
            width: 58,
            child: Text(
              _fecha(f),
              style: const TextStyle(fontSize: 9.5),
            ),
          ),
        ),
        // --- Editar
        DataCell(
          _botonIcono(
            icono: Icons.edit_outlined,
            tooltip: 'Editar FIP',
            color: AppColors.azulModerno,
            onTap: () => _editar(f),
          ),
        ),
        // --- Imagen del predio
        DataCell(
          _botonIcono(
            icono: Icons.add_a_photo_outlined,
            tooltip: 'Ver imagen del predio',
            color: f['tiene_imagen_predio'] == true
                ? AppColors.verde
                : Colors.grey.shade300,
            onTap: f['tiene_imagen_predio'] == true
                ? () => _abrirImagen(id, 'imagen_predio')
                : null,
          ),
        ),
        // --- Imagen de la ficha impresa
        DataCell(
          _botonIcono(
            icono: Icons.picture_as_pdf_outlined,
            tooltip: 'Ver imagen de la ficha',
            color: f['tiene_imagen_ficha'] == true
                ? AppColors.verde
                : Colors.grey.shade300,
            onTap: f['tiene_imagen_ficha'] == true
                ? () => _abrirImagen(id, 'imagen_ficha')
                : null,
          ),
        ),
        // --- GPS
        DataCell(
          _botonIcono(
            icono: Icons.my_location,
            tooltip: 'Ver ubicacion GPS',
            color: _t(f['ubicacion_geo']).isEmpty
                ? Colors.grey.shade300
                : AppColors.azulOscuro,
            onTap: () => _verGps(f),
          ),
        ),
        // --- Inhabilitar / habilitar
        DataCell(
          _botonIcono(
            icono: inactiva ? Icons.lock_open : Icons.block,
            tooltip: inactiva ? 'Habilitar FIP' : 'Inhabilitar FIP',
            color: inactiva ? AppColors.verde : AppColors.rojo,
            onTap: () => _alternarEstado(f),
          ),
        ),
      ],
    );
  }

  /// Abre la imagen: la descarga si aun no esta en cache y la muestra.
  Future<void> _abrirImagen(int id, String campo) async {
    if (id == 0) return;
    final clave = '$id-$campo';
    if (!_imagenes.containsKey(clave)) {
      await _descargarImagen(id, campo);
    }
    if (!mounted) return;
    final bytes = _imagenes[clave];
    if (bytes == null) {
      _snack('No se pudo descargar la imagen.', AppColors.rojo);
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      campo == 'imagen_predio'
                          ? 'Imagen del predio'
                          : 'Imagen de la ficha impresa',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _botonIcono({
    required IconData icono,
    required String tooltip,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(
            icono,
            size: 17,
            color: onTap == null ? Colors.grey.shade300 : color,
          ),
        ),
      ),
    );
  }

  /// Compone la direccion del predio en una sola linea.
  String _direccion(Map<String, dynamic> f) {
    final partes = <String>[
      if (_t(f['nombre_via']).isNotEmpty) _t(f['nombre_via']),
      if (_t(f['num_finca']).isNotEmpty) 'Nro ${_t(f['num_finca'])}',
      if (_t(f['manzana']).isNotEmpty) 'Mz ${_t(f['manzana'])}',
      if (_t(f['lote']).isNotEmpty) 'Lt ${_t(f['lote'])}',
      if (_t(f['interior']).isNotEmpty) 'Int ${_t(f['interior'])}',
      if (_t(f['piso']).isNotEmpty) 'Piso ${_t(f['piso'])}',
    ];
    if (partes.isEmpty) return _t(f['dir_lateral']).isEmpty ? '-' : _t(f['dir_lateral']);
    return partes.join(' ');
  }

  String _fecha(Map<String, dynamic> f) {
    final v = _t(f['fecha_cierre']);
    if (v.isEmpty) return '-';
    return v.split('T').first;
  }

  /// El numero de ficha se guarda como IP-2026-00001 pero en la grilla solo
  /// interesa la parte que cambia: el anio y el correlativo.
  String _numeroFip(String numero) {
    final s = numero.trim();
    if (s.startsWith('IP-')) return s.substring(3);
    return s;
  }

  Widget _panelPaginacion() {
    final desde = _total == 0 ? 0 : (_pagina - 1) * _limite + 1;
    final hasta = (_pagina * _limite) > _total ? _total : _pagina * _limite;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _total == 0
                  ? 'Sin registros'
                  : 'Mostrando $desde - $hasta de $_total registro(s)',
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            'Pag ${_paginas == 0 ? 0 : _pagina}/$_paginas',
            style: const TextStyle(fontSize: 11, color: AppColors.grisMedio),
          ),
          const SizedBox(width: 4),
          _botonPaginacion(
            icono: Icons.chevron_left,
            activo: _pagina > 1 && !_cargando,
            onTap: () => _cargar(pagina: _pagina - 1),
          ),
          _botonPaginacion(
            icono: Icons.chevron_right,
            activo: _pagina < _paginas && !_cargando,
            onTap: () => _cargar(pagina: _pagina + 1),
          ),
        ],
      ),
    );
  }

  Widget _botonPaginacion({
    required IconData icono,
    required bool activo,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: activo ? onTap : null,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      icon: Icon(icono, color: activo ? AppColors.azulModerno : Colors.grey.shade300),
    );
  }

  Widget _vacia() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_outlined, size: 46, color: AppColors.grisMedio),
            const SizedBox(height: 10),
            const Text(
              'No hay fichas que cumplan el filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grisMedio),
            ),
            if (_hayFiltros) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _limpiarFiltros,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Limpiar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 46, color: AppColors.grisMedio),
            const SizedBox(height: 10),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _cargar(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
