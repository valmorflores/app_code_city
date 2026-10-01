import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Cores da cena. Claro = cidade de dia; escuro = cidade à noite, com as
/// janelas das funções acesas sobre paredes escuras.
@immutable
class CityPalette {
  const CityPalette._({
    required this.dark,
    required this.sky,
    required this.grass,
    required this.grassEdge,
    required this.lot,
    required this.wall,
    required this.glassOff,
    required this.lobbyGlass,
    required this.dimInk,
    required this.outline,
    required this.shadow,
    required this.roofTint,
    required this.windowGlow,
    required this.coarseStrip,
    required this.labelBg,
    required this.labelInk,
  });

  static const light = CityPalette._(
    dark: false,
    sky: [Color(0xFF7FB8EA), Color(0xFFD8ECFA)],
    grass: Color(0xFF9CCC65),
    grassEdge: Color(0xFF7CB342),
    lot: Color(0xFFCFD8DC),
    wall: Color(0xFFF4F6F8),
    glassOff: Color(0x7390A4AE),
    lobbyGlass: Color(0xFF4FC3F7),
    dimInk: Color(0xFFB8C2CA),
    outline: Color(0x55263238),
    shadow: Color(0x22000000),
    roofTint: Colors.white,
    windowGlow: 0,
    coarseStrip: Color(0xFF42A5F5),
    labelBg: Color(0xDDFFFFFF),
    labelInk: Color(0xFF263238),
  );

  static const night = CityPalette._(
    dark: true,
    sky: [Color(0xFF070D1A), Color(0xFF1B2A48)],
    grass: Color(0xFF1C3326),
    grassEdge: Color(0xFF2E5A40),
    lot: Color(0xFF29313D),
    wall: Color(0xFF3B4656),
    glassOff: Color(0xCC161D29),
    lobbyGlass: Color(0xFFFFC857),
    dimInk: Color(0xFF4A5462),
    outline: Color(0x88000000),
    shadow: Color(0x33000000),
    roofTint: Color(0xFF2A3340),
    windowGlow: 0.18,
    coarseStrip: Color(0xFF64B5F6),
    labelBg: Color(0xDD1E2733),
    labelInk: Color(0xFFE6EDF3),
  );

  static CityPalette of(Brightness b) => b == Brightness.dark ? night : light;

  final bool dark;
  final List<Color> sky;
  final Color grass;
  final Color grassEdge;
  final Color lot;
  final Color wall;

  /// Janela vazia (posição sem função no andar).
  final Color glassOff;
  final Color lobbyGlass;

  /// Prédios fora do filtro.
  final Color dimInk;
  final Color outline;
  final Color shadow;

  /// Para onde a cor do terraço é puxada a partir da cor do prédio.
  final Color roofTint;

  /// Quanto as janelas acesas clareiam (brilho noturno).
  final double windowGlow;
  final Color coarseStrip;
  final Color labelBg;
  final Color labelInk;

  /// Estrelas em coordenadas normalizadas, sorteadas uma vez.
  static final List<Offset> stars = () {
    final rnd = math.Random(20261001);
    return [
      for (var i = 0; i < 90; i++)
        Offset(rnd.nextDouble(), rnd.nextDouble() * 0.6),
    ];
  }();
}
