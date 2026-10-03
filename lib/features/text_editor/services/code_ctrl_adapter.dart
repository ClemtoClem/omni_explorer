/// @file code_ctrl_adapter.dart
/// @brief Présente un [CodeLineEditingController] comme une valeur
/// [TextEditingValue] (texte + décalages), pour le clavier personnalisé et
/// les opérations sur les lignes.

import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

class CodeCtrlAdapter {
  CodeLineEditingController codeCtrl;
  CodeCtrlAdapter(this.codeCtrl);

  TextEditingValue get value {
    final text = codeCtrl.text;
    final sel = codeCtrl.selection;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: _toFlat(text, sel.baseIndex, sel.baseOffset),
        extentOffset: _toFlat(text, sel.extentIndex, sel.extentOffset),
      ),
    );
  }

  set value(TextEditingValue val) {
    codeCtrl.text = val.text;
    final base = _toLC(val.text, val.selection.baseOffset);
    final ext = _toLC(val.text, val.selection.extentOffset);
    codeCtrl.selection = CodeLineSelection(
      baseIndex: base.$1,
      baseOffset: base.$2,
      extentIndex: ext.$1,
      extentOffset: ext.$2,
    );
  }

  int _toFlat(String t, int line, int col) {
    final lines = t.split('\n');
    int off = 0;
    for (int i = 0; i < line && i < lines.length; i++) {
      off += lines[i].length + 1;
    }
    return off + col;
  }

  (int, int) _toLC(String t, int flat) {
    if (flat <= 0) return (0, 0);
    final lines = t.split('\n');
    int cur = 0;
    for (int i = 0; i < lines.length; i++) {
      if (cur + lines[i].length >= flat) return (i, flat - cur);
      cur += lines[i].length + 1;
    }
    return (lines.length - 1, lines.last.length);
  }
}
