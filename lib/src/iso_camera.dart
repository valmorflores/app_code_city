import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Câmera isométrica com giro (yaw), inclinação (pitch), zoom e pan — o mesmo
/// modelo da comparação 3D de hospitais do app_spy.
///
/// Projeção: `tela = origem + zoom * f(mundo)`. Por ser linear no zoom em
/// torno da origem, dá para dar zoom mantendo fixo o ponto sob o cursor.
class IsoCamera extends ChangeNotifier {
  IsoCamera({double yaw = -0.4, this.pitch = 0.5, this.zoom = 1.0})
      : _yaw = yaw,
        _cos = math.cos(yaw),
        _sin = math.sin(yaw);

  static const double baseTileWidth = 42;
  static const double kMinZoom = 0.01;
  static const double kMaxZoom = 12;
  static const double kMinPitch = 0.12;
  static const double kMaxPitch = 0.94;

  Offset origin = Offset.zero;
  double pitch;
  double zoom;

  double _yaw;
  double _cos;
  double _sin;

  double get yaw => _yaw;
  set yaw(double v) {
    _yaw = v;
    _cos = math.cos(v);
    _sin = math.sin(v);
  }

  double get tileWidth => baseTileWidth * zoom;
  double get tileHeight => tileWidth * pitch;
  double get zScale => tileWidth * math.sqrt(1 - pitch * pitch) * 0.5774;

  /// Direção "para a câmera" no plano do chão: `n·v > 0` ⇒ a face com
  /// normal `n` está virada para quem olha.
  double get viewX => _cos + _sin;
  double get viewY => _cos - _sin;

  Offset project(double x, double y, double z) {
    final rx = x * _cos - y * _sin;
    final ry = x * _sin + y * _cos;
    return Offset(
      origin.dx + (rx - ry) * (tileWidth / 2),
      origin.dy + (rx + ry) * (tileHeight / 2) - z * zScale,
    );
  }

  void changed() => notifyListeners();

  void rotateBy(double dx, double dy) {
    yaw = _yaw + dx * 0.008;
    pitch = (pitch + dy * 0.0022).clamp(kMinPitch, kMaxPitch);
    notifyListeners();
  }

  void panBy(Offset delta) {
    origin += delta;
    notifyListeners();
  }

  /// Zoom multiplicativo mantendo [focal] parado na tela.
  void zoomAt(Offset focal, double scrollDy) {
    setZoomAt(focal, zoom * math.exp(-scrollDy * 0.0016));
  }

  void setZoomAt(Offset focal, double newZoom) {
    final z = newZoom.clamp(kMinZoom, kMaxZoom);
    origin = focal + (origin - focal) * (z / zoom);
    zoom = z;
    notifyListeners();
  }

  /// Leva o ponto de mundo (x,y,z) para [screen].
  void centerOn(double x, double y, double z, Offset screen) {
    origin += screen - project(x, y, z);
    notifyListeners();
  }
}
