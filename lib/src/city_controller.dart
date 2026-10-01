import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'city_layout.dart';
import 'iso_camera.dart';
import 'model.dart';
import 'scanner.dart';

class CityController extends ChangeNotifier {
  final IsoCamera camera = IsoCamera();
  final ValueNotifier<CityHit?> hover = ValueNotifier(null);

  List<ProjectInfo> projects = const [];
  CityLayout layout = CityLayout.build(const []);

  bool scanning = false;
  String status = '';
  double? progress;

  int? selectedBuilding;
  int? selectedFloor;
  FnRef? selectedFn;

  String _filter = '';
  String get filter => _filter;
  set filter(String v) {
    _filter = v.trim().toLowerCase();
    notifyListeners();
  }

  bool matchesFilter(ProjectInfo p) =>
      _filter.isEmpty || p.name.toLowerCase().contains(_filter);

  /// nome → todas as funções com esse nome, na cidade inteira.
  Map<String, List<FnRef>> _byName = const {};

  /// Pedido para a view reenquadrar (a view é quem sabe o tamanho).
  final ValueNotifier<int> fitRequests = ValueNotifier(0);

  Future<void> scan(String root, ScanOptions options) async {
    if (scanning) return;
    if (!Directory(root).existsSync()) {
      status = 'Pasta não encontrada: $root';
      notifyListeners();
      return;
    }
    scanning = true;
    progress = null;
    status = 'Procurando projetos…';
    notifyListeners();
    try {
      final dirs = await discoverProjectsInIsolate(root, options);
      if (dirs.isEmpty) {
        status = 'Nenhum projeto Dart (pubspec.yaml + lib/) encontrado.';
        return;
      }
      final sw = Stopwatch()..start();
      final result = await scanProjects(
        dirs,
        options,
        onProgress: (done, total, current) {
          progress = done / total;
          status = 'Analisando $done/$total — $current';
          notifyListeners();
        },
      );
      _setProjects(result);
      final fns = result.fold<int>(0, (s, p) => s + p.functionCount);
      final files = result.fold<int>(0, (s, p) => s + p.files.length);
      status = '${result.length} prédios · $files andares · $fns janelas '
          '(${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)';
    } catch (e, st) {
      debugPrint('Erro ao escanear: $e\n$st');
      status = 'Erro ao escanear: $e';
    } finally {
      scanning = false;
      progress = null;
      notifyListeners();
    }
  }

  double floorHeight = CityDims.floorHeight;

  /// Achata/estica a cidade sem mexer na seleção.
  void setFloorHeight(double v) {
    floorHeight = v;
    layout = CityLayout.build(projects, floorHeight: v);
    notifyListeners();
  }

  /// Altura de andar que deixa a torre mais alta do tamanho do terreno.
  /// Com a altura fixa, um projeto de 2.000 arquivos vira uma agulha e
  /// achata o resto da cidade no enquadramento.
  static double _autoFloorHeight(List<ProjectInfo> list, CityLayout layout) {
    final maxFloors = list.fold<int>(0, (m, p) => math.max(m, p.files.length));
    if (maxFloors == 0) return CityDims.floorHeight;
    final extent = math.max(layout.bounds.width, layout.bounds.height);
    return (extent * 0.9 / maxFloors).clamp(0.04, CityDims.floorHeight);
  }

  void _setProjects(List<ProjectInfo> list) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    projects = list;
    floorHeight = _autoFloorHeight(list, CityLayout.build(list));
    layout = CityLayout.build(list, floorHeight: floorHeight);
    selectedBuilding = null;
    selectedFloor = null;
    selectedFn = null;
    hover.value = null;

    final byName = <String, List<FnRef>>{};
    for (var b = 0; b < list.length; b++) {
      final files = list[b].files;
      for (var f = 0; f < files.length; f++) {
        final fns = files[f].functions;
        for (var i = 0; i < fns.length; i++) {
          (byName[fns[i].name] ??= []).add(FnRef(b, f, i));
        }
      }
    }
    _byName = byName;
    fitRequests.value++;
  }

  FnInfo fnAt(FnRef r) => projects[r.building].files[r.floor].functions[r.index];
  SourceFileInfo fileAt(int building, int floor) =>
      projects[building].files[floor];

  void selectHit(CityHit? hit) {
    selectedBuilding = hit?.building;
    selectedFloor = hit?.floor;
    selectedFn = hit?.fn;
    notifyListeners();
  }

  void selectFn(FnRef r) {
    selectedBuilding = r.building;
    selectedFloor = r.floor;
    selectedFn = r;
    notifyListeners();
  }

  void selectFloor(int building, int floor) {
    selectedBuilding = building;
    selectedFloor = floor;
    selectedFn = null;
    notifyListeners();
  }

  void clearSelection() => selectHit(null);

  /// Definições com o mesmo nome de cada chamada feita por [r]. Ordenadas
  /// do mais provável (mesmo arquivo, mesmo projeto) para o menos.
  List<(String, List<FnRef>)> callsOf(FnRef r) {
    final out = <(String, List<FnRef>)>[];
    for (final name in fnAt(r).calls) {
      final defs = _byName[name];
      if (defs == null) continue;
      final sorted = [...defs]..sort((a, b) => _affinity(r, b) - _affinity(r, a));
      out.add((name, sorted));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  /// Funções que invocam o nome de [r]. Mesma heurística por nome.
  List<FnRef> callersOf(FnRef r, {int limit = 200}) {
    final name = fnAt(r).name;
    final out = <FnRef>[];
    for (var b = 0; b < projects.length; b++) {
      final files = projects[b].files;
      for (var f = 0; f < files.length; f++) {
        final fns = files[f].functions;
        for (var i = 0; i < fns.length; i++) {
          if (fns[i].calls.contains(name)) out.add(FnRef(b, f, i));
        }
      }
    }
    out.sort((a, b) => _affinity(r, b) - _affinity(r, a));
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  int definitionsNamed(String name) => _byName[name]?.length ?? 0;

  static int _affinity(FnRef origin, FnRef other) {
    if (origin.building != other.building) return 0;
    return origin.floor == other.floor ? 2 : 1;
  }

  Future<String> readCode(FnRef r) async {
    final file = fileAt(r.building, r.floor);
    final fn = fnAt(r);
    final bytes = await File(file.path).readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    if (fn.offset + fn.length > text.length) {
      return '// O arquivo mudou desde o escaneamento. Escaneie de novo.';
    }
    return text.substring(fn.offset, fn.offset + fn.length);
  }

  @override
  void dispose() {
    camera.dispose();
    hover.dispose();
    fitRequests.dispose();
    super.dispose();
  }
}
