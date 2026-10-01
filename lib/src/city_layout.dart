import 'dart:math' as math;
import 'dart:ui';

import 'iso_camera.dart';
import 'model.dart';

/// Medidas do prédio, em unidades de mundo (1 = um tile).
abstract final class CityDims {
  /// Largura de uma janela (coluna).
  static const double cell = 0.55;
  static const double margin = 0.45;

  /// Altura padrão do andar; o usuário pode achatar a cidade (ver
  /// [CityLayout.build]) quando um projeto tem milhares de arquivos.
  static const double floorHeight = 0.42;
  static const double lobbyHeight = 0.8;
  static const double crownHeight = 0.28;

  /// Mínimo de janelas por face.
  static const int minSide = 3;

  static const double gapX = 3.2;
  static const double gapY = 4.0;

  /// Folga da janela dentro da célula (horizontal) e fração do andar
  /// (vertical).
  static const double winPadX = 0.09;
  static const double winPadZFrac = 0.19;

  /// Janelas por face para que o maior arquivo caiba no perímetro.
  static int sideFor(int maxFunctionsPerFile) =>
      math.max(minSide, (maxFunctionsPerFile / 4).ceil());
}

/// Face vertical do prédio.
enum Face { south, north, east, west }

extension FaceGeom on Face {
  double get nx => switch (this) {
        Face.east => 1,
        Face.west => -1,
        _ => 0,
      };
  double get ny => switch (this) {
        Face.south => 1,
        Face.north => -1,
        _ => 0,
      };

  /// u = x nas faces sul/norte e u = y nas leste/oeste.
  bool get alongX => this == Face.south || this == Face.north;

  /// Posição da face na volta do andar (ver [BuildingGeom.perimeter]).
  int get turn => switch (this) {
        Face.south => 0,
        Face.east => 1,
        Face.north => 2,
        Face.west => 3,
      };

  /// Yaw em que a câmera olha a face de frente.
  double get facingYaw => switch (this) {
        Face.south => -math.pi / 4,
        Face.east => math.pi / 4,
        Face.north => 3 * math.pi / 4,
        Face.west => -3 * math.pi / 4,
      };
}

class BuildingGeom {
  BuildingGeom({
    required this.index,
    required this.project,
    required this.row,
    required this.x,
    required this.y,
    required this.side,
    required this.floorH,
  })  : w = side * CityDims.cell + 2 * CityDims.margin,
        h = CityDims.lobbyHeight +
            project.files.length * floorH +
            CityDims.crownHeight;

  /// Ordem das faces ao dar a volta no andar: as funções de um arquivo
  /// correm frente → direita → fundos → esquerda, contínuas na quina.
  static const perimeter = [Face.south, Face.east, Face.north, Face.west];

  final int index;
  final ProjectInfo project;

  /// Fileira (quadra) do terreno — chave do painter's algorithm.
  final int row;
  final double x;
  final double y;

  /// Janelas por face; o andar comporta `4 * side` funções.
  final int side;
  final double floorH;

  /// Planta quadrada: [w] é largura e profundidade.
  final double w;
  final double h;

  double get d => w;
  double get x1 => x + w;
  double get y1 => y + w;
  double get midX => x + w / 2;
  double get midY => y + w / 2;
  double get winPadZ => floorH * CityDims.winPadZFrac;
  int get capacity => 4 * side;

  double floorZ(int floor) => CityDims.lobbyHeight + floor * floorH;

  /// Faixa (u0, u1) da célula [slot] na [face]. Nas faces leste e norte a
  /// volta anda no sentido negativo do eixo.
  (double, double) slotSpan(Face face, int slot) {
    final start = face.alongX ? x : y;
    final end = start + w;
    return switch (face) {
      Face.south || Face.west => (
          start + CityDims.margin + slot * CityDims.cell,
          start + CityDims.margin + (slot + 1) * CityDims.cell,
        ),
      Face.east || Face.north => (
          end - CityDims.margin - (slot + 1) * CityDims.cell,
          end - CityDims.margin - slot * CityDims.cell,
        ),
    };
  }

  int? slotAt(Face face, double u) {
    final start = face.alongX ? x : y;
    final end = start + w;
    final t = switch (face) {
      Face.south || Face.west => u - start - CityDims.margin,
      Face.east || Face.north => end - CityDims.margin - u,
    };
    final slot = (t / CityDims.cell).floor();
    return t < 0 || slot >= side ? null : slot;
  }

  Face faceOf(int fnIndex) => perimeter[(fnIndex ~/ side) % 4];
  int slotOf(int fnIndex) => fnIndex % side;
  int fnIndexAt(Face face, int slot) => face.turn * side + slot;
}

/// Uma face projetada é afim em (u, z): `tela = base + u*du + z*(0,-zScale)`.
class FaceFrame {
  FaceFrame(IsoCamera cam, BuildingGeom b, this.face) : zScale = cam.zScale {
    if (face.alongX) {
      final y = face == Face.south ? b.y1 : b.y;
      base = cam.project(0, y, 0);
      du = cam.project(1, y, 0) - base;
      u0 = b.x;
      u1 = b.x1;
    } else {
      final x = face == Face.east ? b.x1 : b.x;
      base = cam.project(x, 0, 0);
      du = cam.project(x, 1, 0) - base;
      u0 = b.y;
      u1 = b.y1;
    }
  }

  final Face face;
  final double zScale;
  late final Offset base;
  late final Offset du;
  late final double u0;
  late final double u1;

  Offset at(double u, double z) =>
      Offset(base.dx + u * du.dx, base.dy + u * du.dy - z * zScale);

  /// Inverso de [at]. `null` se a face está de perfil.
  (double u, double z)? solve(Offset p) {
    if (du.dx.abs() < 1e-6) return null;
    final u = (p.dx - base.dx) / du.dx;
    final z = -((p.dy - base.dy) - u * du.dy) / zScale;
    return (u, z);
  }
}

class CityHit {
  const CityHit({required this.building, this.floor, this.fn});

  final int building;
  final int? floor;
  final FnRef? fn;
}

class CityLayout {
  CityLayout._(this.buildings, this.bounds);

  final List<BuildingGeom> buildings;

  /// Retângulo de mundo (x, y) que contém todos os lotes.
  final Rect bounds;

  /// Distribui os prédios em quadras (fileiras ao longo de x), mirando num
  /// terreno mais ou menos quadrado.
  factory CityLayout.build(
    List<ProjectInfo> projects, {
    double floorHeight = CityDims.floorHeight,
  }) {
    if (projects.isEmpty) return CityLayout._(const [], Rect.zero);

    final sides = [for (final p in projects) CityDims.sideFor(p.maxFunctionsPerFile)];
    final widths = [for (final s in sides) s * CityDims.cell + 2 * CityDims.margin];
    final area = widths.fold<double>(
      0,
      (s, w) => s + (w + CityDims.gapX) * (w + CityDims.gapY),
    );
    final rowW = math.max(widths.reduce(math.max), math.sqrt(area) * 1.1);

    final placed = <(int, int, double, double)>[];
    var row = 0;
    var cx = 0.0;
    var cy = 0.0;
    var rowDepth = 0.0;
    var maxX = 0.0;
    for (var i = 0; i < projects.length; i++) {
      if (cx > 0 && cx + widths[i] > rowW) {
        row++;
        cx = 0;
        cy += rowDepth + CityDims.gapY;
        rowDepth = 0;
      }
      placed.add((i, row, cx, cy));
      cx += widths[i] + CityDims.gapX;
      rowDepth = math.max(rowDepth, widths[i]);
      maxX = math.max(maxX, cx - CityDims.gapX);
    }
    final maxY = cy + rowDepth;
    final ox = -maxX / 2;
    final oy = -maxY / 2;

    final buildings = [
      for (final (i, r, x, y) in placed)
        BuildingGeom(
          index: i,
          project: projects[i],
          row: r,
          x: x + ox,
          y: y + oy,
          side: sides[i],
          floorH: floorHeight,
        ),
    ];
    return CityLayout._(
      buildings,
      Rect.fromLTRB(ox, oy, ox + maxX, oy + maxY),
    );
  }

  /// Ordem do painter's algorithm (de trás para frente).
  ///
  /// Fileiras ocupam faixas de y que não se sobrepõem, e dentro da fileira
  /// os prédios estão separados em x: ordenar por fileira e depois por x,
  /// cada eixo no sentido em que a câmera olha, é uma ordem total correta.
  List<BuildingGeom> drawOrder(IsoCamera cam) {
    final vx = cam.viewX;
    final vy = cam.viewY;
    final list = [...buildings];
    list.sort((a, b) {
      if (a.row != b.row) {
        return vy >= 0 ? a.row.compareTo(b.row) : b.row.compareTo(a.row);
      }
      return vx >= 0 ? a.x.compareTo(b.x) : b.x.compareTo(a.x);
    });
    return list;
  }

  static List<Face> visibleFaces(IsoCamera cam) => [
        for (final f in Face.values)
          if (f.nx * cam.viewX + f.ny * cam.viewY > 1e-4) f,
      ];

  static List<Offset> topQuad(IsoCamera cam, BuildingGeom b, double z) => [
        cam.project(b.x, b.y, z),
        cam.project(b.x1, b.y, z),
        cam.project(b.x1, b.y1, z),
        cam.project(b.x, b.y1, z),
      ];

  CityHit? hitTest(IsoCamera cam, Offset p) {
    final faces = visibleFaces(cam);
    final order = drawOrder(cam);
    for (final b in order.reversed) {
      for (final face in faces) {
        final frame = FaceFrame(cam, b, face);
        final s = frame.solve(p);
        if (s == null) continue;
        final (u, z) = s;
        if (u < frame.u0 || u > frame.u1 || z < 0 || z > b.h) continue;
        return _hitOnFace(b, face, u, z);
      }
      if (_inPolygon(topQuad(cam, b, b.h), p)) {
        return CityHit(building: b.index);
      }
    }
    return null;
  }

  CityHit _hitOnFace(BuildingGeom b, Face face, double u, double z) {
    final floor = ((z - CityDims.lobbyHeight) / b.floorH).floor();
    if (floor < 0 || floor >= b.project.files.length) {
      return CityHit(building: b.index);
    }
    final slot = b.slotAt(face, u);
    if (slot != null) {
      final i = b.fnIndexAt(face, slot);
      if (i < b.project.files[floor].functions.length) {
        return CityHit(building: b.index, floor: floor, fn: FnRef(b.index, floor, i));
      }
    }
    return CityHit(building: b.index, floor: floor);
  }

  static bool _inPolygon(List<Offset> poly, Offset p) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i];
      final c = poly[j];
      if ((a.dy > p.dy) != (c.dy > p.dy) &&
          p.dx < (c.dx - a.dx) * (p.dy - a.dy) / (c.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Zoom e origem que enquadram a cidade inteira em [view].
  void fit(IsoCamera cam, Size view) {
    if (buildings.isEmpty || view.isEmpty) return;
    cam.origin = Offset.zero;
    cam.zoom = 1;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void add(Offset o) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }

    for (final b in buildings) {
      for (final z in [0.0, b.h]) {
        topQuad(cam, b, z).forEach(add);
      }
    }
    final zoom = math.min(
      view.width * 0.9 / math.max(1, maxX - minX),
      view.height * 0.85 / math.max(1, maxY - minY),
    );
    cam.zoom = zoom.clamp(IsoCamera.kMinZoom, IsoCamera.kMaxZoom);
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2) * cam.zoom;
    cam.origin = Offset(view.width / 2, view.height / 2) - center;
    cam.changed();
  }

  /// Aproxima a câmera de um prédio para ele caber em [view].
  void focusBuilding(IsoCamera cam, BuildingGeom b, Size view) {
    final unitH = IsoCamera.baseTileWidth *
        math.sqrt(1 - cam.pitch * cam.pitch) *
        0.5774;
    final byH = view.height * 0.75 / (b.h * unitH + b.w * 10);
    final byW = view.width * 0.7 / (2 * b.w * IsoCamera.baseTileWidth * 0.75);
    cam.zoom = math.min(byH, byW).clamp(IsoCamera.kMinZoom, IsoCamera.kMaxZoom);
    cam.centerOn(b.midX, b.midY, b.h / 2, view.center(Offset.zero));
  }

  /// Gira a câmera para a face da janela e centraliza nela.
  void focusWindow(IsoCamera cam, FnRef ref, Size view) {
    final b = buildings[ref.building];
    final face = b.faceOf(ref.index);
    // Um pouco fora do eixo da face para a vizinha também aparecer.
    cam.yaw = face.facingYaw + 0.4;
    cam.zoom = math.max(cam.zoom, 2.2);
    final (u0, u1) = b.slotSpan(face, b.slotOf(ref.index));
    final u = (u0 + u1) / 2;
    final z = b.floorZ(ref.floor) + b.floorH / 2;
    final (wx, wy) = switch (face) {
      Face.south => (u, b.y1),
      Face.north => (u, b.y),
      Face.east => (b.x1, u),
      Face.west => (b.x, u),
    };
    cam.centerOn(wx, wy, z, view.center(Offset.zero));
  }
}
