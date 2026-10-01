import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import 'city_controller.dart';
import 'city_layout.dart';
import 'city_palette.dart';
import 'model.dart';

/// Cor da janela por tipo de função.
const Map<FnKind, Color> kKindColors = {
  FnKind.function: Color(0xFF43A047),
  FnKind.method: Color(0xFF1E88E5),
  FnKind.constructor: Color(0xFFFB8C00),
  FnKind.getter: Color(0xFF8E24AA),
  FnKind.setter: Color(0xFFD81B60),
};

/// Brilho da janela pelo tamanho da função: até 10 linhas, até 40, mais.
int lengthLevel(FnInfo fn) => fn.lines < 10 ? 0 : (fn.lines < 40 ? 1 : 2);

Color windowColor(FnKind kind, int level) {
  final base = kKindColors[kind]!;
  return switch (level) {
    0 => Color.lerp(base, const Color(0xFF263238), 0.35)!,
    1 => base,
    _ => Color.lerp(base, Colors.white, 0.38)!,
  };
}

Color buildingHue(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.55, 0.52).toColor();
}

Color _shade(Color c, double f) => Color.from(
      alpha: c.a,
      red: (c.r * f).clamp(0.0, 1.0),
      green: (c.g * f).clamp(0.0, 1.0),
      blue: (c.b * f).clamp(0.0, 1.0),
    );

class CityPainter extends CustomPainter {
  CityPainter(this.c, this.palette, this._labelCache)
      : super(repaint: Listenable.merge([c, c.camera, c.hover]));

  final CityController c;
  final CityPalette palette;

  /// Do estado da view: o painter é recriado a cada build, o cache não.
  final Map<String, TextPainter> _labelCache;

  /// Luz fixa no mundo, vinda de noroeste-alto.
  static const double _lx = -0.45;
  static const double _ly = 0.89;

  Color get _dimInk => palette.dimInk;

  final Paint _fill = Paint()..style = PaintingStyle.fill;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final cam = c.camera;
    final layout = c.layout;
    final rect = Offset.zero & size;
    canvas.clipRect(rect);

    _fill.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: palette.sky,
    ).createShader(rect);
    canvas.drawRect(rect, _fill);
    _fill.shader = null;
    if (palette.dark) {
      canvas.drawPoints(
        PointMode.points,
        [
          for (final s in CityPalette.stars)
            Offset(s.dx * size.width, s.dy * size.height),
        ],
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }

    if (layout.buildings.isEmpty) return;

    _paintGround(canvas, layout);
    final faces = CityLayout.visibleFaces(cam);
    final order = layout.drawOrder(cam);
    final view = rect.inflate(60);

    _paintShadows(canvas, order);
    for (final b in order) {
      _paintBuilding(canvas, b, faces, view);
    }
    _paintHighlights(canvas, faces);
    _paintLabels(canvas, order, view);
  }

  Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  void _paintGround(Canvas canvas, CityLayout layout) {
    final cam = c.camera;
    final r = layout.bounds.inflate(6);
    final island = _poly([
      cam.project(r.left, r.top, 0),
      cam.project(r.right, r.top, 0),
      cam.project(r.right, r.bottom, 0),
      cam.project(r.left, r.bottom, 0),
    ]);
    canvas.drawPath(island, _fill..color = palette.grass);
    canvas.drawPath(
      island,
      _stroke
        ..color = palette.grassEdge
        ..strokeWidth = 3,
    );

    final lots = Path();
    for (final b in layout.buildings) {
      const m = 0.8;
      lots.addPolygon([
        cam.project(b.x - m, b.y - m, 0),
        cam.project(b.x1 + m, b.y - m, 0),
        cam.project(b.x1 + m, b.y1 + m, 0),
        cam.project(b.x - m, b.y1 + m, 0),
      ], true);
    }
    canvas.drawPath(lots, _fill..color = palette.lot);
  }

  /// Sombra no chão: casco convexo da base com o topo deslocado pela luz.
  void _paintShadows(Canvas canvas, List<BuildingGeom> order) {
    final cam = c.camera;
    final shadows = Path();
    const k = 0.32;
    for (final b in order) {
      final sx = -_lx * b.h * k;
      final sy = -_ly * b.h * k;
      final pts = <Offset>[
        cam.project(b.x, b.y, 0),
        cam.project(b.x1, b.y, 0),
        cam.project(b.x1, b.y1, 0),
        cam.project(b.x, b.y1, 0),
        cam.project(b.x + sx, b.y + sy, 0),
        cam.project(b.x1 + sx, b.y + sy, 0),
        cam.project(b.x1 + sx, b.y1 + sy, 0),
        cam.project(b.x + sx, b.y1 + sy, 0),
      ];
      shadows.addPolygon(_hull(pts), true);
    }
    canvas.drawPath(shadows, _fill..color = palette.shadow);
  }

  static List<Offset> _hull(List<Offset> pts) {
    pts.sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    final lower = <Offset>[];
    for (final p in pts) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    return [...lower..removeLast(), ...upper..removeLast()];
  }

  double _light(Face f) => 0.80 + 0.20 * (f.nx * _lx + f.ny * _ly);

  void _paintBuilding(
    Canvas canvas,
    BuildingGeom b,
    List<Face> faces,
    Rect view,
  ) {
    final cam = c.camera;
    final top = CityLayout.topQuad(cam, b, b.h);
    final base = CityLayout.topQuad(cam, b, 0);
    final bounds = _poly([...top, ...base]).getBounds();
    if (!bounds.overlaps(view)) return;

    final dim = !c.matchesFilter(b.project);
    final hue = dim ? _dimInk : buildingHue(b.project.name);
    final wall = dim ? Color.lerp(palette.wall, _dimInk, 0.6)! : palette.wall;

    for (final face in faces) {
      final fr = FaceFrame(cam, b, face);
      final light = _light(face);
      Path band(double z0, double z1) => _poly([
            fr.at(fr.u0, z0),
            fr.at(fr.u1, z0),
            fr.at(fr.u1, z1),
            fr.at(fr.u0, z1),
          ]);

      canvas.drawPath(band(0, b.h), _fill..color = _shade(wall, light));
      canvas.drawPath(
        band(0.05, CityDims.lobbyHeight * 0.82),
        _fill
          ..color = _shade(dim ? _dimInk : palette.lobbyGlass, light * 0.95),
      );
      canvas.drawPath(
        band(b.h - CityDims.crownHeight, b.h),
        _fill..color = _shade(hue, light),
      );

      _paintWindows(canvas, b, fr, view, dim);

      canvas.drawPath(
        band(0, b.h),
        _stroke
          ..color = palette.outline
          ..strokeWidth = 1,
      );
    }

    final roof = _poly(top);
    canvas.drawPath(
      roof,
      _fill..color = _shade(Color.lerp(hue, palette.roofTint, 0.45)!, 1.05),
    );
    canvas.drawPath(
      roof,
      _stroke
        ..color = palette.outline
        ..strokeWidth = 1,
    );
  }

  void _paintWindows(
    Canvas canvas,
    BuildingGeom b,
    FaceFrame fr,
    Rect view,
    bool dim,
  ) {
    final files = b.project.files;
    final pxCell = CityDims.cell * fr.du.distance;
    final pxFloor = b.floorH * fr.zScale;
    final coarse = pxCell < 3 || pxFloor < 2.5;

    final lit = <int, Path>{};
    final off = Path();
    final strip = Path();

    void quad(Path p, double u0, double u1, double z0, double z1) {
      final a = fr.at(u0, z0);
      final bb = fr.at(u1, z0);
      final cc = fr.at(u1, z1);
      final d = fr.at(u0, z1);
      p
        ..moveTo(a.dx, a.dy)
        ..lineTo(bb.dx, bb.dy)
        ..lineTo(cc.dx, cc.dy)
        ..lineTo(d.dx, d.dy)
        ..close();
    }

    final face = fr.face;
    final side = b.side;
    final first = face.turn * side;
    final (uA, _) = b.slotSpan(face, 0);
    final (_, uB) = b.slotSpan(face, side - 1);
    final uL = math.min(uA, uB);
    final uR = math.max(uA, uB);

    /// Faixa de u ocupada pelas células [from, to) desta face.
    (double, double) span(int from, int to) {
      final (a0, a1) = b.slotSpan(face, from);
      final (b0, b1) = b.slotSpan(face, to - 1);
      return (math.min(a0, b0), math.max(a1, b1));
    }

    for (var f = 0; f < files.length; f++) {
      final z0 = b.floorZ(f) + b.winPadZ;
      final z1 = b.floorZ(f) + b.floorH - b.winPadZ;
      final yTop = math.min(fr.at(uL, z1).dy, fr.at(uR, z1).dy);
      final yBot = math.max(fr.at(uL, z0).dy, fr.at(uR, z0).dy);
      if (yBot < view.top || yTop > view.bottom) continue;

      final fns = files[f].functions;
      final count = (fns.length - first).clamp(0, side);
      if (coarse) {
        if (count > 0) {
          final (s0, s1) = span(0, count);
          quad(strip, s0, s1, z0, z1);
        }
        if (count < side) {
          final (s0, s1) = span(count, side);
          quad(off, s0, s1, z0, z1);
        }
        continue;
      }
      for (var j = 0; j < side; j++) {
        final (c0, c1) = b.slotSpan(face, j);
        final u0 = c0 + CityDims.winPadX;
        final u1 = c1 - CityDims.winPadX;
        if (j < count) {
          final fn = fns[first + j];
          final key = fn.kind.index * 3 + lengthLevel(fn);
          quad(lit[key] ??= Path(), u0, u1, z0, z1);
        } else {
          quad(off, u0, u1, z0, z1);
        }
      }
    }

    canvas.drawPath(off, _fill..color = palette.glassOff);
    if (coarse) {
      canvas.drawPath(
        strip,
        _fill..color = dim ? _dimInk : palette.coarseStrip,
      );
      return;
    }
    for (final e in lit.entries) {
      final kind = FnKind.values[e.key ~/ 3];
      final lit = windowColor(kind, e.key % 3);
      canvas.drawPath(
        e.value,
        _fill
          ..color = dim
              ? _dimInk
              : Color.lerp(lit, Colors.white, palette.windowGlow)!,
      );
    }
  }

  void _paintHighlights(Canvas canvas, List<Face> faces) {
    final cam = c.camera;
    final layout = c.layout;
    final sb = c.selectedBuilding;
    if (sb != null && sb < layout.buildings.length) {
      final b = layout.buildings[sb];
      final glow = _stroke
        ..color = const Color(0xFFFFB300)
        ..strokeWidth = 2.5;
      for (final face in faces) {
        final fr = FaceFrame(cam, b, face);
        canvas.drawPath(
          _poly([fr.at(fr.u0, 0), fr.at(fr.u1, 0), fr.at(fr.u1, b.h), fr.at(fr.u0, b.h)]),
          glow,
        );
      }
      canvas.drawPath(_poly(CityLayout.topQuad(cam, b, b.h)), glow);

      final floor = c.selectedFloor;
      if (floor != null) {
        for (final face in faces) {
          final fr = FaceFrame(cam, b, face);
          final z0 = b.floorZ(floor);
          final z1 = z0 + b.floorH;
          canvas.drawPath(
            _poly([fr.at(fr.u0, z0), fr.at(fr.u1, z0), fr.at(fr.u1, z1), fr.at(fr.u0, z1)]),
            _stroke
              ..color = const Color(0xFFFF6F00)
              ..strokeWidth = 1.5,
          );
        }
      }
    }

    void mark(FnRef r, Color color, double width, {bool fill = false}) {
      if (r.building >= layout.buildings.length) return;
      final b = layout.buildings[r.building];
      final face = b.faceOf(r.index);
      final fr = FaceFrame(cam, b, face);
      final (u0, u1) = b.slotSpan(face, b.slotOf(r.index));
      final z0 = b.floorZ(r.floor);
      final z1 = z0 + b.floorH;
      final center = fr.at((u0 + u1) / 2, (z0 + z1) / 2);
      _stroke
        ..color = color
        ..strokeWidth = width;
      // Janela numa face de costas: só um anel, para não pintar por cima da
      // fachada que está na frente dela.
      if (!faces.contains(face)) {
        canvas.drawCircle(center, 7, _stroke..strokeWidth = 1.5);
        return;
      }
      final path = _poly([fr.at(u0, z0), fr.at(u1, z0), fr.at(u1, z1), fr.at(u0, z1)]);
      if (fill) canvas.drawPath(path, _fill..color = color.withValues(alpha: 0.55));
      canvas.drawPath(path, _stroke);
      // Em zoom baixo a janela some: um alvo em volta continua achando ela.
      if (fr.du.distance * CityDims.cell < 8) {
        canvas.drawCircle(center, 9, _stroke..strokeWidth = 2);
      }
    }

    final hover = c.hover.value?.fn;
    if (hover != null) mark(hover, Colors.white, 2);
    final sel = c.selectedFn;
    if (sel != null) mark(sel, const Color(0xFFFFEB3B), 3, fill: true);
  }

  void _paintLabels(Canvas canvas, List<BuildingGeom> order, Rect view) {
    final cam = c.camera;
    if (cam.zoom < 0.12) return;
    for (final b in order) {
      final dim = !c.matchesFilter(b.project);
      if (dim && c.filter.isNotEmpty) continue;
      final selected = c.selectedBuilding == b.index;
      final key = '${b.project.name}|$selected|${palette.dark}';
      final tp = _labelCache[key] ??= TextPainter(
        text: TextSpan(
          text: b.project.name,
          style: TextStyle(
            color: selected ? const Color(0xFF3E2723) : palette.labelInk,
            fontSize: selected ? 13 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final anchor = cam.project(b.midX, b.midY, b.h);
      if (!view.contains(anchor)) continue;
      final box = Rect.fromCenter(
        center: anchor - Offset(0, tp.height / 2 + 12),
        width: tp.width + 12,
        height: tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(6)),
        _fill
          ..color = selected ? const Color(0xF0FFD54F) : palette.labelBg,
      );
      tp.paint(canvas, box.topLeft + const Offset(6, 2));
    }
  }

  @override
  bool shouldRepaint(CityPainter oldDelegate) =>
      oldDelegate.c != c || oldDelegate.palette != palette;
}
