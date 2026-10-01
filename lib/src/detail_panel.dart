import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'city_controller.dart';
import 'city_layout.dart';
import 'city_painter.dart';
import 'code_view.dart';
import 'model.dart';

/// Painel da direita: o que está selecionado na cidade.
class DetailPanel extends StatelessWidget {
  const DetailPanel({
    super.key,
    required this.controller,
    required this.onGoToFn,
    required this.onGoToBuilding,
  });

  final CityController controller;
  final void Function(FnRef) onGoToFn;
  final void Function(int) onGoToBuilding;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final b = c.selectedBuilding;
    if (b == null || b >= c.projects.length) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Clique numa janela para ver o código da função.\n\n'
            'Clique na parede para ver o andar (arquivo) e no telhado '
            'para ver o prédio (projeto).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final fn = c.selectedFn;
    if (fn != null) {
      return _FnDetail(
        key: ValueKey(fn),
        c: c,
        ref: fn,
        onGoToFn: onGoToFn,
      );
    }
    final floor = c.selectedFloor;
    if (floor != null) {
      return _FloorDetail(c: c, building: b, floor: floor, onGoToFn: onGoToFn);
    }
    return _BuildingDetail(c: c, building: b, onGoToBuilding: onGoToBuilding);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                SelectableText(subtitle, style: t.bodySmall),
              ],
            ),
          ),
          ...?trailing,
        ],
      ),
    );
  }
}

Widget _kindDot(FnInfo fn) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: windowColor(fn.kind, lengthLevel(fn)),
        borderRadius: BorderRadius.circular(2),
      ),
    );

class _FnTile extends StatelessWidget {
  const _FnTile({required this.c, required this.ref, required this.onTap, this.current = false});

  final CityController c;
  final FnRef ref;
  final VoidCallback onTap;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final fn = c.fnAt(ref);
    final file = c.fileAt(ref.building, ref.floor);
    return ListTile(
      dense: true,
      selected: current,
      leading: _kindDot(fn),
      minLeadingWidth: 12,
      title: Text(fn.label, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${c.projects[ref.building].name} · ${file.relPath}:${fn.startLine}',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${fn.lines} l', style: Theme.of(context).textTheme.bodySmall),
      onTap: onTap,
    );
  }
}

class _FnDetail extends StatefulWidget {
  const _FnDetail({super.key, required this.c, required this.ref, required this.onGoToFn});

  final CityController c;
  final FnRef ref;
  final void Function(FnRef) onGoToFn;

  @override
  State<_FnDetail> createState() => _FnDetailState();
}

class _FnDetailState extends State<_FnDetail> {
  late final Future<String> _code = widget.c.readCode(widget.ref);
  late final List<(String, List<FnRef>)> _calls = widget.c.callsOf(widget.ref);
  late final List<FnRef> _callers = widget.c.callersOf(widget.ref);

  void _go(FnRef r) {
    widget.c.selectFn(r);
    widget.onGoToFn(r);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final ref = widget.ref;
    final fn = c.fnAt(ref);
    final file = c.fileAt(ref.building, ref.floor);
    final project = c.projects[ref.building];
    final siblings = file.functions.length;

    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: fn.label,
            subtitle: '${fn.kind.label} · linhas ${fn.startLine}–${fn.endLine} '
                '(${fn.lines})\n${project.name} · andar ${ref.floor + 1} · '
                'janela ${ref.index + 1} (${_faceName(c, ref)})\n${file.relPath}',
            trailing: [
              IconButton(
                tooltip: 'Centralizar na janela',
                icon: const Icon(Icons.center_focus_strong),
                onPressed: () => widget.onGoToFn(ref),
              ),
              IconButton(
                tooltip: 'Copiar caminho:linha',
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: '${file.path}:${fn.startLine}'),
                ),
              ),
            ],
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: 'Código'),
              Tab(text: 'Chama (${_calls.length})'),
              Tab(text: 'Chamada por (${_callers.length})'),
              Tab(text: 'Mesmo andar ($siblings)'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                FutureBuilder<String>(
                  future: _code,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Não foi possível ler: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return SingleChildScrollView(
                      child: CodeView(code: snap.data!, firstLine: fn.startLine),
                    );
                  },
                ),
                _callsTab(context),
                _callersTab(context),
                ListView.builder(
                  itemCount: siblings,
                  itemBuilder: (context, i) {
                    final r = FnRef(ref.building, ref.floor, i);
                    return _FnTile(c: c, ref: r, current: i == ref.index, onTap: () => _go(r));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _faceName(CityController c, FnRef r) =>
      switch (c.layout.buildings[r.building].faceOf(r.index)) {
        Face.south => 'frente',
        Face.east => 'lado direito',
        Face.north => 'fundos',
        Face.west => 'lado esquerdo',
      };

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _callsTab(BuildContext context) {
    if (_calls.isEmpty) {
      return _note('Nenhuma chamada para funções da cidade '
          '(só APIs externas, ou nenhuma).');
    }
    return ListView(
      children: [
        _note('Ligação por nome, sem resolução de tipos: homônimos aparecem '
            'juntos, os do mesmo arquivo/projeto primeiro.'),
        for (final (name, defs) in _calls)
          ExpansionTile(
            dense: true,
            initiallyExpanded: defs.length <= 3,
            title: Text('$name()'),
            subtitle: Text(defs.length == 1 ? '1 definição' : '${defs.length} definições'),
            children: [
              for (final r in defs.take(30))
                _FnTile(c: widget.c, ref: r, onTap: () => _go(r)),
              if (defs.length > 30) _note('… e mais ${defs.length - 30}'),
            ],
          ),
      ],
    );
  }

  Widget _callersTab(BuildContext context) {
    final fn = widget.c.fnAt(widget.ref);
    final homonyms = widget.c.definitionsNamed(fn.name);
    return ListView(
      children: [
        _note(homonyms > 1
            ? 'Há $homonyms funções chamadas "${fn.name}" na cidade; '
                'quem chama qualquer uma delas aparece aqui.'
            : 'Funções que chamam "${fn.name}".'),
        for (final r in _callers) _FnTile(c: widget.c, ref: r, onTap: () => _go(r)),
      ],
    );
  }
}

class _FloorDetail extends StatelessWidget {
  const _FloorDetail({
    required this.c,
    required this.building,
    required this.floor,
    required this.onGoToFn,
  });

  final CityController c;
  final int building;
  final int floor;
  final void Function(FnRef) onGoToFn;

  @override
  Widget build(BuildContext context) {
    final file = c.fileAt(building, floor);
    final p = c.projects[building];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: file.fileName,
          subtitle: '${p.name} · andar ${floor + 1} de ${p.files.length}\n'
              '${file.relPath}\n${file.lineCount} linhas · '
              '${file.functions.length} funções',
          trailing: [
            IconButton(
              tooltip: 'Copiar caminho',
              icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: file.path)),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: file.functions.isEmpty
              ? const Center(child: Text('Andar sem janelas: o arquivo não declara funções.'))
              : ListView.builder(
                  itemCount: file.functions.length,
                  itemBuilder: (context, i) {
                    final r = FnRef(building, floor, i);
                    return _FnTile(
                      c: c,
                      ref: r,
                      onTap: () {
                        c.selectFn(r);
                        onGoToFn(r);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BuildingDetail extends StatelessWidget {
  const _BuildingDetail({required this.c, required this.building, required this.onGoToBuilding});

  final CityController c;
  final int building;
  final void Function(int) onGoToBuilding;

  @override
  Widget build(BuildContext context) {
    final p = c.projects[building];
    final g = c.layout.buildings[building];
    final floors = p.files.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: p.name,
          subtitle: '$floors andares · ${p.functionCount} funções · '
              '${p.lineCount} linhas\nplanta: ${g.side} janelas por face, '
              '${g.capacity} por andar (maior arquivo: '
              '${p.maxFunctionsPerFile})\n${p.path}',
          trailing: [
            IconButton(
              tooltip: 'Enquadrar prédio',
              icon: const Icon(Icons.center_focus_strong),
              onPressed: () => onGoToBuilding(building),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          // Do último andar para o térreo, como o diretório de um prédio.
          child: ListView.builder(
            itemCount: floors,
            itemBuilder: (context, i) {
              final f = floors - 1 - i;
              final file = p.files[f];
              return ListTile(
                dense: true,
                leading: SizedBox(
                  width: 40,
                  child: Text('${f + 1}º', textAlign: TextAlign.right),
                ),
                title: Text(file.relPath, overflow: TextOverflow.ellipsis),
                trailing: Text('${file.functions.length}'),
                onTap: () => c.selectFloor(building, f),
              );
            },
          ),
        ),
      ],
    );
  }
}
