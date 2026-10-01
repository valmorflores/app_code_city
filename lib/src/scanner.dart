import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'model.dart';

class ScanOptions {
  const ScanOptions({
    this.skipBackups = true,
    this.skipGenerated = true,
    this.includeTests = false,
  });

  /// Pula pastas com "backup" no nome (o monorepo tem cópias inteiras).
  final bool skipBackups;

  /// Pula `*.g.dart`, `*.freezed.dart` etc.
  final bool skipGenerated;
  final bool includeTests;
}

const _skipDirs = {
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  '.claude',
  '.fvm',
  'build',
  'node_modules',
  'android',
  'ios',
  'linux',
  'macos',
  'windows',
  'web',
};

const _generatedSuffixes = [
  '.g.dart',
  '.freezed.dart',
  '.mocks.dart',
  '.gr.dart',
  '.pb.dart',
  '.pbenum.dart',
  '.pbjson.dart',
];

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Pastas com `pubspec.yaml` + `lib/` abaixo de [root]. Não desce dentro de um
/// projeto já encontrado (o `example/` de um pacote não vira outro prédio).
List<String> discoverProjects(String root, ScanOptions options) {
  final found = <String>[];

  void walk(Directory dir, int depth) {
    final name = _baseName(dir.path);
    if (depth > 0) {
      if (_skipDirs.contains(name) || name.startsWith('.')) return;
      if (options.skipBackups && name.toLowerCase().contains('backup')) return;
    }
    final hasPubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml')
        .existsSync();
    final hasLib =
        Directory('${dir.path}${Platform.pathSeparator}lib').existsSync();
    if (hasPubspec && hasLib) {
      found.add(dir.path);
      return;
    }
    if (depth >= 4) return;
    try {
      final children = dir.listSync(followLinks: false).whereType<Directory>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final child in children) {
        walk(child, depth + 1);
      }
    } on FileSystemException {
      // Pasta sem permissão de leitura: segue sem ela.
    }
  }

  walk(Directory(root), 0);
  return found;
}

// Os closures enviados ao isolate nascem em funções de topo para capturar só
// os argumentos: um closure criado dentro de outro leva junto o contexto
// inteiro (e com ele widgets, que não atravessam isolates).
Future<List<String>> discoverProjectsInIsolate(String root, ScanOptions options) =>
    Isolate.run(() => discoverProjects(root, options));

Future<ProjectInfo> _scanInIsolate(String dir, ScanOptions options) =>
    Isolate.run(() => scanProjectSync(dir, options));

/// Escaneia vários projetos em paralelo (um isolate por projeto).
Future<List<ProjectInfo>> scanProjects(
  List<String> dirs,
  ScanOptions options, {
  void Function(int done, int total, String current)? onProgress,
}) async {
  final results = List<ProjectInfo?>.filled(dirs.length, null);
  final workers = math.max(2, math.min(6, Platform.numberOfProcessors - 1));
  var next = 0;
  var done = 0;

  Future<void> worker() async {
    while (next < dirs.length) {
      final i = next++;
      final dir = dirs[i];
      results[i] = await _scanInIsolate(dir, options);
      done++;
      onProgress?.call(done, dirs.length, _baseName(dir));
    }
  }

  await Future.wait(List.generate(workers, (_) => worker()));
  return results
      .whereType<ProjectInfo>()
      .where((p) => p.files.isNotEmpty)
      .toList();
}

ProjectInfo scanProjectSync(String dir, ScanOptions options) {
  final roots = ['lib', 'bin', if (options.includeTests) 'test'];
  final files = <SourceFileInfo>[];
  for (final r in roots) {
    final d = Directory('$dir${Platform.pathSeparator}$r');
    if (!d.existsSync()) continue;
    final dartFiles = d
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) =>
            !options.skipGenerated ||
            !_generatedSuffixes.any((s) => f.path.endsWith(s)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in dartFiles) {
      final info = parseDartFile(f.path, f.path.substring(dir.length + 1));
      if (info != null) files.add(info);
    }
  }
  return ProjectInfo(name: _baseName(dir), path: dir, files: files);
}

SourceFileInfo? parseDartFile(String path, String relPath) {
  String content;
  try {
    content = utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);
  } on FileSystemException {
    return null;
  }
  final result = parseString(content: content, throwIfDiagnostics: false);
  final collector = _FnCollector(result.lineInfo);
  result.unit.accept(collector);
  return SourceFileInfo(
    path: path,
    relPath: relPath,
    lineCount: result.lineInfo.lineCount,
    functions: collector.out,
  );
}

class _FnCollector extends RecursiveAstVisitor<void> {
  _FnCollector(this.lineInfo);

  final LineInfo lineInfo;
  final out = <FnInfo>[];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Função local (dentro de outra) não vira janela própria.
    if (node.parent is! CompilationUnit) return;
    final name = node.name.lexeme;
    _add(
      node,
      name: name,
      label: name,
      owner: null,
      kind: node.isGetter
          ? FnKind.getter
          : node.isSetter
              ? FnKind.setter
              : FnKind.function,
    );
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final owner = _ownerOf(node);
    final name = node.name.lexeme;
    _add(
      node,
      name: name,
      label: '$owner.$name',
      owner: owner,
      kind: node.isGetter
          ? FnKind.getter
          : node.isSetter
              ? FnKind.setter
              : FnKind.method,
    );
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final owner = _ownerOf(node);
    final named = node.name?.lexeme;
    _add(
      node,
      name: named ?? owner,
      label: named == null ? owner : '$owner.$named',
      owner: owner,
      kind: FnKind.constructor,
    );
  }

  void _add(
    AstNode node, {
    required String name,
    required String label,
    required String? owner,
    required FnKind kind,
  }) {
    final calls = _CallCollector();
    node.accept(calls);
    out.add(FnInfo(
      name: name,
      label: label,
      owner: owner,
      kind: kind,
      startLine: lineInfo.getLocation(node.offset).lineNumber,
      endLine: lineInfo.getLocation(node.end).lineNumber,
      offset: node.offset,
      length: node.length,
      calls: calls.names.toList(growable: false),
    ));
  }

  static String _ownerOf(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      switch (p) {
        case ClassDeclaration():
          return p.namePart.typeName.lexeme;
        case EnumDeclaration():
          return p.namePart.typeName.lexeme;
        case ExtensionTypeDeclaration():
          return p.namePart.typeName.lexeme;
        case MixinDeclaration():
          return p.name.lexeme;
        case ExtensionDeclaration():
          return p.name?.lexeme ?? 'extension';
        default:
      }
    }
    return '?';
  }
}

/// Sem resolução de tipos `Foo()` também é um `MethodInvocation`, então isto
/// pega chamadas de função, de método e de construtor pelo nome.
class _CallCollector extends RecursiveAstVisitor<void> {
  final names = <String>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    names.add(node.methodName.name);
    super.visitMethodInvocation(node);
  }
}
