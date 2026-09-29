import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

/// Item de un catalogo {codigo, nombre}.
class CatalogoItem {
  final String codigo;
  final String nombre;

  const CatalogoItem(this.codigo, this.nombre);

  factory CatalogoItem.fromMap(Map<String, dynamic> m) => CatalogoItem(
        (m['codigo'] ?? '').toString(),
        (m['nombre'] ?? '').toString(),
      );
}

/// Convierte la respuesta de la API en listas de [CatalogoItem].
List<CatalogoItem> listaCatalogo(dynamic datos) {
  if (datos is! List) return const [];
  return datos
      .whereType<Map<String, dynamic>>()
      .map(CatalogoItem.fromMap)
      .where((e) => e.codigo.isNotEmpty)
      .toList();
}

/// Tarjeta seccion del formulario.
class SeccionFormulario extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Widget child;
  final Widget? accion;

  const SeccionFormulario({
    super.key,
    required this.titulo,
    required this.icono,
    required this.child,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: const BoxDecoration(
              color: AppColors.azulModerno,
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icono, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (accion case final a?) a,
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
}

/// Campo de texto con etiqueta, usado en todo el formulario.
class CampoTexto extends StatelessWidget {
  final TextEditingController controller;
  final String etiqueta;
  final String? ayuda;
  final TextInputType? teclado;
  final int? maxLength;
  final int lineas;
  final List<TextInputFormatter>? formatters;
  final bool soloLectura;
  final VoidCallback? onTap;
  final String? Function(String?)? validador;

  /// Unidad de medida que se muestra pegada al valor, por ejemplo '%' o 'm2'.
  final String? sufijo;

  /// Boton que se dibuja dentro del campo, a la derecha.
  final Widget? boton;

  const CampoTexto({
    super.key,
    required this.controller,
    required this.etiqueta,
    this.ayuda,
    this.teclado,
    this.maxLength,
    this.lineas = 1,
    this.formatters,
    this.soloLectura = false,
    this.onTap,
    this.validador,
    this.sufijo,
    this.boton,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: teclado,
        maxLength: maxLength,
        maxLines: lineas,
        minLines: lineas,
        readOnly: soloLectura,
        onTap: onTap,
        inputFormatters: formatters,
        validator: validador,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: etiqueta,
          helperText: ayuda,
          helperMaxLines: 2,
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.azulModerno, width: 2),
          ),
          filled: soloLectura,
          fillColor: soloLectura ? AppColors.grisClaro : null,
          // La unidad va antes del boton para que este quede al borde.
          suffixIcon: boton == null && sufijo == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sufijo case final s?) Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        s,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ?boton,
                  ],
                ),
        ),
      ),
    );
  }
}

/// Desplegable que elige un codigo de catalogo y escribe su nombre en [detalle].
class CampoSelector extends StatelessWidget {
  final List<CatalogoItem> items;
  final String etiqueta;
  final String? valor;
  final ValueChanged<String?> onChanged;
  final String Function(String codigo)? nombreDe;
  final String? Function(String?)? validador;

  const CampoSelector({
    super.key,
    required this.items,
    required this.etiqueta,
    required this.onChanged,
    this.valor,
    this.nombreDe,
    this.validador,
  });

  @override
  Widget build(BuildContext context) {
    final existe = items.any((e) => e.codigo == valor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        // La key cambia con el valor para que el campo se resetee cuando el
        // valor se modifica desde fuera (por ejemplo al elegir un predio).
        key: ValueKey<String?>('$etiqueta#${existe ? valor : ''}'),
        initialValue: existe ? valor : null,
        isExpanded: true,
        validator: validador,
        hint: Text(etiqueta, style: const TextStyle(fontSize: 14)),
        style: const TextStyle(fontSize: 14, color: AppColors.texto),
        items: items
            .map((e) => DropdownMenuItem<String>(
                  value: e.codigo,
                  child: Text(
                    // Cuando el codigo y el nombre son el mismo (p. ej. los
                    // tipos de solicitud) se muestra una sola vez, si no el
                    // combo repetiria "ADULTO MAYOR - NO PENSIONISTA - ADULTO
                    // MAYOR - NO PENSIONISTA".
                    e.nombre.isEmpty
                        ? e.codigo
                        : (e.codigo == e.nombre
                            ? e.nombre
                            : '${e.codigo} - ${e.nombre}'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// Selector con busqueda, para catalogos largos (316 usos prediales).
class CampoSelectorBuscable extends StatefulWidget {
  final List<CatalogoItem> items;
  final String etiqueta;
  final String? valor;
  final ValueChanged<String?> onChanged;
  final String Function(String codigo)? nombreDe;

  const CampoSelectorBuscable({
    super.key,
    required this.items,
    required this.etiqueta,
    required this.onChanged,
    this.valor,
    this.nombreDe,
  });

  @override
  State<CampoSelectorBuscable> createState() => _CampoSelectorBuscableState();
}

class _CampoSelectorBuscableState extends State<CampoSelectorBuscable> {
  String _etiquetaActual() {
    if (widget.valor == null || widget.valor!.isEmpty) return widget.etiqueta;
    final item = widget.items.firstWhere(
      (e) => e.codigo == widget.valor,
      orElse: () => CatalogoItem(widget.valor!, widget.valor!),
    );
    return item.nombre.isEmpty ? item.codigo : '${item.codigo} - ${item.nombre}';
  }

  Future<void> _abrirBuscador() async {
    final elegido = await showDialog<String>(
      context: context,
      builder: (_) => _BuscadorCatalogo(items: widget.items, valor: widget.valor),
    );
    if (elegido != null) widget.onChanged(elegido);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _abrirBuscador,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: widget.etiqueta,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            suffixIcon: const Icon(Icons.search, size: 20),
          ),
          child: Text(
            _etiquetaActual(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: (widget.valor ?? '').isEmpty
                  ? Colors.grey.shade600
                  : AppColors.texto,
            ),
          ),
        ),
      ),
    );
  }
}

class _BuscadorCatalogo extends StatefulWidget {
  final List<CatalogoItem> items;
  final String? valor;

  const _BuscadorCatalogo({required this.items, this.valor});

  @override
  State<_BuscadorCatalogo> createState() => _BuscadorCatalogoState();
}

class _BuscadorCatalogoState extends State<_BuscadorCatalogo> {
  final _ctrl = TextEditingController();
  List<CatalogoItem> _visibles = [];

  @override
  void initState() {
    super.initState();
    _visibles = widget.items;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filtrar(String texto) {
    final t = texto.trim().toUpperCase();
    setState(() {
      _visibles = t.isEmpty
          ? widget.items
          : widget.items
              .where((e) =>
                  e.nombre.toUpperCase().contains(t) ||
                  e.codigo.toUpperCase().contains(t))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _filtrar,
                decoration: InputDecoration(
                  hintText: 'Buscar...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text('${_visibles.length} opciones',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.grisMedio)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('Quitar'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _visibles.length,
                itemBuilder: (_, i) {
                  final e = _visibles[i];
                  final seleccionado = e.codigo == widget.valor;
                  return ListTile(
                    dense: true,
                    selected: seleccionado,
                    title: Text(
                      e.nombre.isEmpty ? e.codigo : e.nombre,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(e.codigo,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.grisMedio)),
                    onTap: () => Navigator.pop(context, e.codigo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boton para capturar una imagen con camara o galeria.
class SelectorImagen extends StatelessWidget {
  final String etiqueta;
  final List<Uint8List> imagenes;
  final bool capturando;
  final VoidCallback onCamara;
  final VoidCallback onGaleria;
  final VoidCallback onVer;
  final VoidCallback onLimpiar;

  const SelectorImagen({
    super.key,
    required this.etiqueta,
    required this.imagenes,
    required this.capturando,
    required this.onCamara,
    required this.onGaleria,
    required this.onVer,
    required this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.texto),
        ),
        const SizedBox(height: 8),
        if (capturando)
          const LinearProgressIndicator(minHeight: 3)
        else if (imagenes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.grisClaro,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Column(
              children: [
                Icon(Icons.image_outlined, size: 30, color: AppColors.grisMedio),
                SizedBox(height: 6),
                Text('Sin imagen',
                    style: TextStyle(fontSize: 12, color: AppColors.grisMedio)),
              ],
            ),
          )
        else
          Row(
            children: [
              ...imagenes.asMap().entries.take(4).map((e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: onVer,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          e.value,
                          width: 74,
                          height: 74,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  )),
              if (imagenes.length > 4)
                Text('+${imagenes.length - 4}',
                    style: const TextStyle(fontSize: 12)),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: capturando ? null : onCamara,
                icon: const Icon(Icons.photo_camera, size: 18),
                label: const Text('Camara', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: capturando ? null : onGaleria,
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Galeria', style: TextStyle(fontSize: 12)),
              ),
            ),
            if (imagenes.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Ver imagen',
                onPressed: onVer,
                icon: const Icon(Icons.visibility, size: 20),
              ),
              IconButton(
                tooltip: 'Quitar imagen',
                onPressed: onLimpiar,
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.rojo),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Muestra dialogo con informacion de un valor de catalogo.
void mostrarDetalle(BuildContext context, String titulo, String texto) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo, style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(child: Text(texto)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}
