/// @file compress_dialog.dart
/// @brief Création d'une archive à partir d'éléments sélectionnés, dans tous
/// les formats inscriptibles (ZIP chiffrable en AES, TAR, TAR.GZ, TAR.BZ2,
/// GZ et BZ2 pour un fichier unique, 7z sous Linux).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../../../core/services/file_operations_service.dart';
import '../models/archive_entry.dart';
import '../services/archive_service.dart';

/// Affiche le dialogue ; `true` si l'archive a été créée.
Future<bool> showCompressDialog(
  BuildContext context, {
  required List<String> sourcePaths,
  required String destDir,
}) async {
  final types = await ArchiveService.creatableTypes();
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _CompressDialog(
            sourcePaths: sourcePaths, destDir: destDir, types: types),
      ) ??
      false;
}

class _CompressDialog extends StatefulWidget {
  final List<String> sourcePaths;
  final String destDir;
  final List<ArchiveType> types;

  const _CompressDialog({
    required this.sourcePaths,
    required this.destDir,
    required this.types,
  });

  @override
  State<_CompressDialog> createState() => _CompressDialogState();
}

class _CompressDialogState extends State<_CompressDialog> {
  late final _nameCtrl = TextEditingController(
      text: widget.sourcePaths.length == 1
          ? p.basename(widget.sourcePaths.first)
          : 'archive');
  final _pwCtrl = TextEditingController();
  ArchiveType _type = ArchiveType.zip;
  bool _withPassword = false;
  bool _encryptNames = false;
  bool _busy = false;
  String? _error;

  /// Un seul fichier ordinaire : GZ / BZ2 possibles.
  bool get _singleFile =>
      widget.sourcePaths.length == 1 &&
      FileSystemEntity.typeSync(widget.sourcePaths.single,
              followLinks: false) ==
          FileSystemEntityType.file;

  List<ArchiveType> get _available =>
      widget.types.where((t) => !t.isSingleFile || _singleFile).toList();

  bool get _passwordPossible =>
      _type == ArchiveType.zip || _type == ArchiveType.sevenZip;

  String get _fileName =>
      '${_nameCtrl.text.trim()}.${ArchiveService.extensionOf(_type)}';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Nom requis.');
    final invalid = FileNameValidator.validate(_fileName);
    if (invalid != null) return setState(() => _error = invalid);
    final password =
        _withPassword && _passwordPossible && _pwCtrl.text.isNotEmpty
            ? _pwCtrl.text
            : null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ArchiveService.createArchive(
          p.join(widget.destDir, _fileName), widget.sourcePaths, _type,
          password: password,
          encryptNames: password != null &&
              _type == ArchiveType.sevenZip &&
              _encryptNames);
      if (mounted) Navigator.pop(context, true);
    } on ArchiveOpException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Création impossible : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Créer une archive'),
      content: _busy
          ? const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nom',
                      suffixText: '.${ArchiveService.extensionOf(_type)}',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 16),
                  Text('Format', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final t in _available)
                        ChoiceChip(
                          label: Text(t.label),
                          selected: _type == t,
                          onSelected: (_) => setState(() => _type = t),
                        ),
                    ],
                  ),
                  if (_passwordPossible) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Protéger par mot de passe (AES)'),
                      value: _withPassword,
                      onChanged: (v) =>
                          setState(() => _withPassword = v ?? false),
                    ),
                    if (_withPassword)
                      TextField(
                        controller: _pwCtrl,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'Mot de passe'),
                      ),
                    if (_withPassword && _type == ArchiveType.sevenZip)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Chiffrer aussi les noms des '
                            'fichiers'),
                        value: _encryptNames,
                        onChanged: (v) =>
                            setState(() => _encryptNames = v ?? false),
                      ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12)),
                  ],
                ],
              ),
            ),
      actions: _busy
          ? const []
          : [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler')),
              FilledButton(onPressed: _create, child: const Text('Créer')),
            ],
    );
  }
}
