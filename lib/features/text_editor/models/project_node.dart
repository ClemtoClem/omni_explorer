/// @file project_node.dart
/// @brief Nœud de l'arborescence du projet (panneau latéral de l'éditeur).

class ProjectNode {
  final String path;
  final String name;
  final bool isDir;
  final int depth;
  bool expanded = false;
  List<ProjectNode> children = const [];

  ProjectNode({
    required this.path,
    required this.name,
    required this.isDir,
    required this.depth,
  });
}
