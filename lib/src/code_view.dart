import 'package:flutter/material.dart';

/// Código com números de linha e um realce de sintaxe Dart simples (por
/// linha: comentário, string, palavra-chave, número, tipo).
class CodeView extends StatelessWidget {
  const CodeView({super.key, required this.code, required this.firstLine});

  final String code;
  final int firstLine;

  static const _keywords = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'default', 'do', 'dynamic', 'else',
    'enum', 'extends', 'extension', 'factory', 'false', 'final', 'finally',
    'for', 'get', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'mixin', 'new', 'null', 'on', 'operator', 'override', 'required',
    'rethrow', 'return', 'sealed', 'set', 'static', 'super', 'switch', 'this',
    'throw', 'true', 'try', 'typedef', 'var', 'void', 'when', 'while', 'with',
    'yield',
  };

  static final _token = RegExp(
    r'''(//.*$)|('(?:\\.|[^'\\])*'?|"(?:\\.|[^"\\])*"?)|(@?[A-Za-z_$][\w$]*)|(\d+(?:\.\d+)?)''',
  );

  static const _base = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Cascadia Mono', 'Courier New', 'monospace'],
    fontSize: 12.5,
    height: 1.45,
  );

  List<TextSpan> _highlight(String line, _CodeColors k) {
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _token.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      final t = m.group(0)!;
      Color? color;
      if (m.group(1) != null) {
        color = k.comment;
      } else if (m.group(2) != null) {
        color = k.string;
      } else if (m.group(3) != null) {
        if (t.startsWith('@')) {
          color = k.annotation;
        } else if (_keywords.contains(t)) {
          color = k.keyword;
        } else if (t[0].toUpperCase() == t[0] && t[0] != '_' && t[0] != r'$') {
          color = k.type;
        }
      } else {
        color = k.number;
      }
      spans.add(TextSpan(text: t, style: color == null ? null : TextStyle(color: color)));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final k = Theme.of(context).brightness == Brightness.dark
        ? _CodeColors.dark
        : _CodeColors.light;
    final lines = code.replaceAll('\r\n', '\n').split('\n');
    final width = '${firstLine + lines.length}'.length;
    final numbers = [
      for (var i = 0; i < lines.length; i++)
        '${firstLine + i}'.padLeft(width),
    ].join('\n');
    final spans = <TextSpan>[];
    for (var i = 0; i < lines.length; i++) {
      spans.addAll(_highlight(lines[i], k));
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return Container(
      color: k.background,
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(numbers, style: _base.copyWith(color: k.lineNumber)),
            const SizedBox(width: 12),
            SelectableText.rich(
              TextSpan(style: _base.copyWith(color: k.text), children: spans),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeColors {
  const _CodeColors({
    required this.background,
    required this.text,
    required this.lineNumber,
    required this.comment,
    required this.string,
    required this.keyword,
    required this.type,
    required this.number,
    required this.annotation,
  });

  static const dark = _CodeColors(
    background: Color(0xFF1E1E1E),
    text: Color(0xFFD4D4D4),
    lineNumber: Color(0xFF6E7681),
    comment: Color(0xFF6A9955),
    string: Color(0xFFCE9178),
    keyword: Color(0xFF569CD6),
    type: Color(0xFF4EC9B0),
    number: Color(0xFFB5CEA8),
    annotation: Color(0xFFDCDCAA),
  );

  static const light = _CodeColors(
    background: Color(0xFFF6F8FA),
    text: Color(0xFF1F2328),
    lineNumber: Color(0xFF8C959F),
    comment: Color(0xFF6E7781),
    string: Color(0xFF0A3069),
    keyword: Color(0xFFCF222E),
    type: Color(0xFF953800),
    number: Color(0xFF0550AE),
    annotation: Color(0xFF8250DF),
  );

  final Color background;
  final Color text;
  final Color lineNumber;
  final Color comment;
  final Color string;
  final Color keyword;
  final Color type;
  final Color number;
  final Color annotation;
}
