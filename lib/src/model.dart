/// Modelo da "cidade de código": projeto = prédio, arquivo = andar,
/// função = janela.
library;

enum FnKind { function, method, constructor, getter, setter }

extension FnKindLabel on FnKind {
  String get label => switch (this) {
        FnKind.function => 'função',
        FnKind.method => 'método',
        FnKind.constructor => 'construtor',
        FnKind.getter => 'getter',
        FnKind.setter => 'setter',
      };
}

class FnInfo {
  const FnInfo({
    required this.name,
    required this.label,
    required this.owner,
    required this.kind,
    required this.startLine,
    required this.endLine,
    required this.offset,
    required this.length,
    required this.calls,
  });

  /// Nome usado para casar chamadas (`foo` em `x.foo()`; para construtor
  /// sem nome, o nome da classe).
  final String name;

  /// Nome para exibição (`Classe.metodo`).
  final String label;

  /// Classe/mixin/extension dona, ou `null` para função de topo.
  final String? owner;
  final FnKind kind;
  final int startLine;
  final int endLine;

  /// Faixa no texto do arquivo. O código é lido sob demanda: guardar o corpo
  /// de dezenas de milhares de funções em memória não compensa.
  final int offset;
  final int length;

  /// Nomes invocados dentro do corpo (sem resolução de tipos).
  final List<String> calls;

  int get lines => endLine - startLine + 1;
}

class SourceFileInfo {
  const SourceFileInfo({
    required this.path,
    required this.relPath,
    required this.lineCount,
    required this.functions,
  });

  final String path;
  final String relPath;
  final int lineCount;
  final List<FnInfo> functions;

  String get fileName {
    final i = relPath.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? relPath : relPath.substring(i + 1);
  }
}

class ProjectInfo {
  ProjectInfo({required this.name, required this.path, required this.files})
      : functionCount = files.fold(0, (s, f) => s + f.functions.length),
        maxFunctionsPerFile =
            files.fold(0, (m, f) => f.functions.length > m ? f.functions.length : m),
        lineCount = files.fold(0, (s, f) => s + f.lineCount);

  final String name;
  final String path;

  /// Andares, de baixo para cima.
  final List<SourceFileInfo> files;
  final int functionCount;
  final int maxFunctionsPerFile;
  final int lineCount;
}

/// Endereço de uma janela: prédio, andar, posição no andar.
class FnRef {
  const FnRef(this.building, this.floor, this.index);

  final int building;
  final int floor;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is FnRef &&
      other.building == building &&
      other.floor == floor &&
      other.index == index;

  @override
  int get hashCode => Object.hash(building, floor, index);
}
