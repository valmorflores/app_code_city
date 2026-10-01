import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'city_controller.dart';
import 'city_layout.dart';
import 'city_painter.dart';
import 'city_palette.dart';
import 'model.dart';

/// Canvas da cidade.
///
/// Botão esquerdo arrasta = gira/inclina; direito/meio (ou Shift+esquerdo)
/// = pan; scroll = zoom no cursor; clique = seleciona janela/andar/prédio.
class CityView extends StatefulWidget {
  const CityView({super.key, required this.controller});

  final CityController controller;

  @override
  State<CityView> createState() => CityViewState();
}

class CityViewState extends State<CityView> {
  final Map<String, TextPainter> _labelCache = {};
  Size _size = Size.zero;
  Offset? _down;
  bool _moved = false;
  Offset _hoverPos = Offset.zero;

  CityController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.fitRequests.addListener(_fit);
  }

  @override
  void dispose() {
    for (final tp in _labelCache.values) {
      tp.dispose();
    }
    c.fitRequests.removeListener(_fit);
    super.dispose();
  }

  void _fit() {
    if (_size.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
      return;
    }
    c.layout.fit(c.camera, _size);
  }

  void fit() => _fit();

  void focusBuilding(int index) {
    c.layout.focusBuilding(c.camera, c.layout.buildings[index], _size);
  }

  void focusWindow(FnRef ref) => c.layout.focusWindow(c.camera, ref, _size);

  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  void _onDown(PointerDownEvent e) {
    _down = e.localPosition;
    _moved = false;
  }

  void _onMove(PointerMoveEvent e) {
    final start = _down;
    if (start == null) return;
    if ((e.localPosition - start).distance > 4) _moved = true;
    if (!_moved) return;
    final pan = e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0 ||
        _shift;
    if (pan) {
      c.camera.panBy(e.delta);
    } else {
      c.camera.rotateBy(e.delta.dx, e.delta.dy);
    }
    c.hover.value = null;
  }

  void _onUp(PointerUpEvent e) {
    final wasClick = _down != null && !_moved;
    _down = null;
    if (!wasClick) return;
    c.selectHit(c.layout.hitTest(c.camera, e.localPosition));
  }

  void _onHover(PointerHoverEvent e) {
    _hoverPos = e.localPosition;
    final hit = c.layout.hitTest(c.camera, e.localPosition);
    final old = c.hover.value;
    if (old?.building != hit?.building ||
        old?.floor != hit?.floor ||
        old?.fn != hit?.fn) {
      c.hover.value = hit;
    } else {
      setState(() {});
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      c.camera.zoomAt(e.localPosition, e.scrollDelta.dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size != _size) {
        final first = _size.isEmpty;
        _size = size;
        if (first && c.layout.buildings.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
        }
      }
      return MouseRegion(
        cursor: SystemMouseCursors.precise,
        onExit: (_) => c.hover.value = null,
        child: Listener(
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerUp: _onUp,
          onPointerHover: _onHover,
          onPointerSignal: _onSignal,
          child: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: CityPainter(
                      c,
                      CityPalette.of(Theme.of(context).brightness),
                      _labelCache,
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<CityHit?>(
                valueListenable: c.hover,
                builder: (context, hit, _) => _tooltip(context, hit),
              ),
              const Positioned(left: 12, bottom: 12, child: _Legend()),
            ],
          ),
        ),
      );
    });
  }

  Widget _tooltip(BuildContext context, CityHit? hit) {
    if (hit == null || c.projects.isEmpty) return const SizedBox.shrink();
    final p = c.projects[hit.building];
    final lines = <String>[p.name];
    if (hit.floor != null) {
      final file = p.files[hit.floor!];
      lines.add('Andar ${hit.floor! + 1}: ${file.relPath}');
      if (hit.fn != null) {
        final fn = c.fnAt(hit.fn!);
        lines.add('${fn.label}  ·  ${fn.kind.label}  ·  ${fn.lines} linhas');
      } else {
        lines.add('${file.functions.length} funções');
      }
    } else {
      lines.add('${p.files.length} andares · ${p.functionCount} funções');
    }
    var left = _hoverPos.dx + 16;
    var top = _hoverPos.dy + 16;
    if (left > _size.width - 360) left = _hoverPos.dx - 360;
    if (top > _size.height - 80) top = _hoverPos.dy - 80;
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: left.clamp(0, _size.width),
      top: top.clamp(0, _size.height),
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.inverseSurface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < lines.length; i++)
                Text(
                  lines[i],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onInverseSurface,
                    fontSize: 12,
                    fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 11, color: scheme.onSurface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 10,
              children: [
                for (final k in FnKind.values)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, color: kKindColors[k]),
                    const SizedBox(width: 4),
                    Text(k.label),
                  ]),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Prédio = projeto · andar = arquivo · janela = função '
              '(mais clara = mais longa)\n'
              'Arraste: girar/inclinar · Shift/botão direito: mover · '
              'Scroll: zoom · Clique: abrir código',
            ),
          ],
        ),
      ),
    );
  }
}
