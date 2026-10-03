/// @file rich_text_controller.dart
/// @brief Texte enrichi de l'éditeur : plages de formatage (gras, italique,
/// souligné, barré, couleur) enregistrées à côté du fichier (`.fmt`).

import 'dart:convert';

import 'package:flutter/material.dart';

enum RichFmt { bold, italic, underline, strikethrough }

class FmtSpan {
  int start;
  int end;
  final Set<RichFmt> formats;
  final Color? textColor;

  FmtSpan(this.start, this.end, this.formats, [this.textColor]);

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'formats': formats.map((f) => f.index).toList(),
        if (textColor != null) 'color': textColor!.toARGB32(),
      };

  factory FmtSpan.fromJson(Map<String, dynamic> j) => FmtSpan(
        j['start'] as int,
        j['end'] as int,
        (j['formats'] as List?)?.map((i) => RichFmt.values[i as int]).toSet() ??
            {},
        j['color'] != null ? Color(j['color'] as int) : null,
      );
}

class RichTextController extends TextEditingController {
  final List<FmtSpan> spans = [];

  RichTextController({super.text});

  void toggleFormat(RichFmt fmt, int start, int end) {
    if (start >= end) return;
    final hasAll = spans.any(
        (s) => s.start <= start && s.end >= end && s.formats.contains(fmt));
    if (hasAll) {
      spans.removeWhere((s) => s.start >= start && s.end <= end);
    } else {
      _merge(FmtSpan(start, end, {fmt}));
    }
    notifyListeners();
  }

  void setTextColor(Color? color, int start, int end) {
    if (start >= end) return;
    _merge(FmtSpan(start, end, {}, color));
    notifyListeners();
  }

  void clearRange(int start, int end) {
    spans.removeWhere((s) => s.start >= start && s.end <= end);
    notifyListeners();
  }

  void _merge(FmtSpan s) {
    spans.removeWhere((e) => e.start >= s.start && e.end <= s.end);
    spans.add(s);
  }

  String get formattingJson =>
      jsonEncode(spans.map((s) => s.toJson()).toList());

  void loadFromJson(String json) {
    spans.clear();
    try {
      final list = jsonDecode(json) as List;
      spans
          .addAll(list.map((e) => FmtSpan.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final src = text;
    if (src.isEmpty || spans.isEmpty) return TextSpan(text: src, style: style);
    final base = style ?? const TextStyle();
    final cs = List<TextStyle>.filled(src.length, base);
    for (final sp in spans) {
      final s = sp.start.clamp(0, src.length);
      final e = sp.end.clamp(0, src.length);
      for (int i = s; i < e; i++) {
        cs[i] = cs[i].copyWith(
          fontWeight:
              sp.formats.contains(RichFmt.bold) ? FontWeight.bold : null,
          fontStyle:
              sp.formats.contains(RichFmt.italic) ? FontStyle.italic : null,
          decoration: _deco(sp.formats),
          color: sp.textColor,
        );
      }
    }
    final result = <InlineSpan>[];
    int i = 0;
    while (i < src.length) {
      int j = i + 1;
      while (j < src.length && cs[j] == cs[i]) {
        j++;
      }
      result.add(TextSpan(text: src.substring(i, j), style: cs[i]));
      i = j;
    }
    return TextSpan(children: result, style: base);
  }

  TextDecoration? _deco(Set<RichFmt> f) {
    final parts = <TextDecoration>[];
    if (f.contains(RichFmt.underline)) parts.add(TextDecoration.underline);
    if (f.contains(RichFmt.strikethrough)) {
      parts.add(TextDecoration.lineThrough);
    }
    return parts.isEmpty ? null : TextDecoration.combine(parts);
  }
}
