
/// @file project_tree.dart
/// @brief Arbre de fichiers du projet (panneau gauche de l'editeur).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/file_utils.dart';

/// @class ProjectTree
/// @brief Widget affichant l'arborescence d'un repertoire de projet.
class ProjectTree extends StatefulWidget {
  final String  rootPath;
  final void Function(String path) onFileSelected;
  final String? activeFile;

  const ProjectTree({
    super.key,
    required this.rootPath,
    required this.onFileSelected,
    this.activeFile,
  });

  @override
  State<ProjectTree> createState() => _ProjectTreeState();
}

class _ProjectTreeState extends State<ProjectTree> {
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.rootPath);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
            child: Row(
              children: [
                Text(
                  p.basename(widget.rootPath).toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(letterSpacing: 1.2),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: _buildDir(widget.rootPath, 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDir(String dirPath, int depth) {
    List<FileSystemEntity> entities;
    try {
      entities = Directory(dirPath).listSync()
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
          return p.basename(a.path).compareTo(p.basename(b.path));
        });
    } catch (_) {
      return const SizedBox.shrink();
    }

    final isExpanded = _expanded.contains(dirPath);
    final name = p.basename(dirPath);

    if (depth > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TreeRow(
            name: name,
            icon: isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
            iconColor: AppColors.colorFolder,
            isActive: false,
            depth: depth,
            trailing: Icon(
              isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 14,
            ),
            onTap: () => setState(() {
              if (isExpanded) { _expanded.remove(dirPath); }
              else            { _expanded.add(dirPath); }
            }),
          ),
          if (isExpanded)
            ...entities.map((e) => e is Directory
                ? _buildDir(e.path, depth + 1)
                : _buildFile(e.path, depth + 1)),
        ],
      );
    }

    // Racine du projet : toujours visible
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entities.map((e) => e is Directory
          ? _buildDir(e.path, depth + 1)
          : _buildFile(e.path, depth + 1)).toList(),
    );
  }

  Widget _buildFile(String filePath, int depth) {
    final name     = p.basename(filePath);
    final cat      = FileUtils.categoryOfPath(filePath);
    final color    = FileUtils.colorOf(cat);
    final icon     = FileUtils.iconOf(cat, path: filePath);
    final isActive = filePath == widget.activeFile;

    return _TreeRow(
      name: name,
      icon: icon,
      iconColor: color,
      isActive: isActive,
      depth: depth,
      onTap: () => widget.onFileSelected(filePath),
    );
  }
}

class _TreeRow extends StatelessWidget {
  final String    name;
  final IconData  icon;
  final Color     iconColor;
  final bool      isActive;
  final int       depth;
  final Widget?   trailing;
  final VoidCallback onTap;

  const _TreeRow({
    required this.name,
    required this.icon,
    required this.iconColor,
    required this.isActive,
    required this.depth,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: isActive ? AppColors.accent.withValues(alpha:0.12) : Colors.transparent,
        padding: EdgeInsets.only(
          left: 8.0 + depth * 12,
          right: 8,
          top: 4, bottom: 4,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isActive ? AppColors.accent : null,
                  fontWeight: isActive ? FontWeight.w600 : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
