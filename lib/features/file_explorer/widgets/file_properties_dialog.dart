/// @file file_properties_dialog.dart
/// @brief Dialogue « Propriétés » d'un fichier ou dossier (style Xed/gestionnaire).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../core/models/file_item.dart';
import '../../../core/utils/file_utils.dart';

/// Ouvre le dialogue des propriétés pour [item].
void showFilePropertiesDialog(BuildContext context, FileItem item) {
  showDialog<void>(
    context: context,
    builder: (_) => _FilePropertiesDialog(item: item),
  );
}

class _FilePropertiesDialog extends StatefulWidget {
  final FileItem item;
  const _FilePropertiesDialog({required this.item});

  @override
  State<_FilePropertiesDialog> createState() => _FilePropertiesDialogState();
}

class _FilePropertiesDialogState extends State<_FilePropertiesDialog> {
  int? _computedSize; // Taille calculée (récursive pour les dossiers).
  int? _itemCount; // Nombre d'éléments directs (dossiers uniquement).
  FileStat? _stat;
  bool _computing = true;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      _stat = await FileSystemEntity.isDirectory(widget.item.path)
          ? await Directory(widget.item.path).stat()
          : await File(widget.item.path).stat();
    } catch (_) {}

    if (widget.item.isDirectory) {
      int total = 0;
      int count = 0;
      try {
        final dir = Directory(widget.item.path);
        await for (final e in dir.list(followLinks: false)) {
          count++;
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          } else if (e is Directory) {
            total += await _dirSize(e);
          }
        }
      } catch (_) {}
      _computedSize = total;
      _itemCount = count;
    } else {
      _computedSize = widget.item.size;
    }

    if (mounted) setState(() => _computing = false);
  }

  Future<int> _dirSize(Directory dir) async {
    int total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  String get _permissions {
    final mode = _stat?.modeString();
    return mode ?? '—';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FileUtils.iconOf(item.category, path: item.path),
            color: FileUtils.colorOf(item.category),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Type', item.isDirectory ? 'Dossier' : _typeLabel(item)),
            _row('Emplacement', p.dirname(item.path)),
            _row(
              'Taille',
              _computing
                  ? 'Calcul…'
                  : FileUtils.formatSize(_computedSize ?? item.size),
            ),
            if (item.isDirectory)
              _row('Contenu',
                  _computing ? '…' : '${_itemCount ?? 0} élément(s)'),
            _row('Modifié', FileUtils.formatDate(item.modified)),
            if (_stat != null)
              _row('Accédé', FileUtils.formatDate(_stat!.accessed)),
            _row('Permissions', _permissions),
            _row('Caché', item.isHidden ? 'Oui' : 'Non'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  String _typeLabel(FileItem item) {
    final ext = item.extension;
    final cat = item.category.name;
    return ext.isEmpty ? cat : '$cat · .$ext';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
