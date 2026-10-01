import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'city_controller.dart';
import 'city_layout.dart';
import 'city_painter.dart';
import 'city_view.dart';
import 'detail_panel.dart';
import 'model.dart';
import 'scanner.dart';

class CodeCityPage extends StatefulWidget {
  const CodeCityPage({
    super.key,
    this.initialRoot = r'C:\dev\flutterapp\cloud_health',
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final String initialRoot;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<CodeCityPage> createState() => _CodeCityPageState();
}

class _CodeCityPageState extends State<CodeCityPage> {
  final _controller = CityController();
  final _viewKey = GlobalKey<CityViewState>();
  late final _path = TextEditingController(text: widget.initialRoot);
  bool _skipBackups = true;
  bool _skipGenerated = true;
  bool _includeTests = false;

  @override
  void initState() {
    super.initState();
    if (Directory(widget.initialRoot).existsSync()) _scan();
  }

  @override
  void dispose() {
    _controller.dispose();
    _path.dispose();
    super.dispose();
  }

  void _scan() => _controller.scan(
        _path.text.trim(),
        ScanOptions(
          skipBackups: _skipBackups,
          skipGenerated: _skipGenerated,
          includeTests: _includeTests,
        ),
      );

  Future<void> _browse() async {
    final dir = await getDirectoryPath(initialDirectory: _path.text);
    if (dir == null) return;
    _path.text = dir;
    _scan();
  }

  void _goToFn(FnRef r) => _viewKey.currentState?.focusWindow(r);

  void _goToBuilding(int i) {
    _controller.selectHit(CityHit(building: i));
    _viewKey.currentState?.focusBuilding(i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          children: [
            _toolbar(context),
            if (_controller.scanning) LinearProgressIndicator(value: _controller.progress),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 270, child: _buildingList(context)),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: CityView(key: _viewKey, controller: _controller),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 480,
                    child: DetailPanel(
                      controller: _controller,
                      onGoToFn: _goToFn,
                      onGoToBuilding: _goToBuilding,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final busy = _controller.scanning;
    Widget check(String label, bool value, ValueChanged<bool> onChanged) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: value, onChanged: busy ? null : (v) => setState(() => onChanged(v!))),
            Text(label),
          ],
        );
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            const Icon(Icons.location_city),
            const SizedBox(width: 8),
            Text('Cidade do Código', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _path,
                enabled: !busy,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  labelText: 'Pasta do sistema (cada pubspec.yaml vira um prédio)',
                ),
                onSubmitted: (_) => _scan(),
              ),
            ),
            IconButton(
              tooltip: 'Escolher pasta',
              onPressed: busy ? null : _browse,
              icon: const Icon(Icons.folder_open),
            ),
            FilledButton.icon(
              onPressed: busy ? null : _scan,
              icon: const Icon(Icons.refresh),
              label: const Text('Escanear'),
            ),
            const SizedBox(width: 8),
            check('ignorar *backup*', _skipBackups, (v) => _skipBackups = v),
            check('ignorar gerados', _skipGenerated, (v) => _skipGenerated = v),
            check('incluir test/', _includeTests, (v) => _includeTests = v),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Altura do andar (achata torres com muitos arquivos)',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.height, size: 18),
                  SizedBox(
                    width: 130,
                    child: Slider(
                      min: 0.04,
                      max: CityDims.floorHeight,
                      value: _controller.floorHeight.clamp(0.04, CityDims.floorHeight),
                      onChanged: _controller.projects.isEmpty
                          ? null
                          : _controller.setFloorHeight,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Enquadrar cidade',
              onPressed: () => _viewKey.currentState?.fit(),
              icon: const Icon(Icons.fit_screen),
            ),
            _themeButton(),
          ],
        ),
      ),
    );
  }

  /// Alterna sistema → claro → escuro.
  Widget _themeButton() {
    final (icon, label, next) = switch (widget.themeMode) {
      ThemeMode.system => (Icons.brightness_auto, 'Tema: sistema', ThemeMode.light),
      ThemeMode.light => (Icons.light_mode, 'Tema: claro', ThemeMode.dark),
      ThemeMode.dark => (Icons.dark_mode, 'Tema: escuro', ThemeMode.system),
    };
    return IconButton(
      tooltip: label,
      icon: Icon(icon),
      onPressed: widget.onThemeModeChanged == null
          ? null
          : () => widget.onThemeModeChanged!(next),
    );
  }

  Widget _buildingList(BuildContext context) {
    final c = _controller;
    final order = [
      for (var i = 0; i < c.projects.length; i++)
        if (c.matchesFilter(c.projects[i])) i,
    ]..sort((a, b) => c.projects[b].functionCount - c.projects[a].functionCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Filtrar prédios',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => c.filter = v,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Tooltip(
            message: c.status,
            child: Text(
              c.status,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: order.length,
            itemBuilder: (context, k) {
              final i = order[k];
              final p = c.projects[i];
              return ListTile(
                dense: true,
                selected: c.selectedBuilding == i,
                leading: Container(width: 12, height: 28, color: buildingHue(p.name)),
                minLeadingWidth: 12,
                title: Text(p.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${p.files.length} andares · ${p.functionCount} funções · '
                  'larg. ${p.maxFunctionsPerFile}',
                ),
                onTap: () => _goToBuilding(i),
              );
            },
          ),
        ),
      ],
    );
  }
}
