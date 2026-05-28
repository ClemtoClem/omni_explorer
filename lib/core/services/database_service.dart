/// @file database_service.dart
/// @brief Service de base de données SQLite pour la persistance des données.
///
/// Gère les tables :
/// - `trash`     : éléments de la corbeille
/// - `shortcuts` : raccourcis/favoris
/// - `playlists` : playlists média
///
/// @author OmniExplorer
/// @version 1.0

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/file_item.dart';

/// Modèle de playlist pour la base de données.
class PlaylistModel {
  final int?   id;
  final String name;
  final String filePaths;    // chemins séparés par '|'
  final String createdAt;
  final String? lastPlayedAt;
  final int    currentIndex;

  const PlaylistModel({
    this.id,
    required this.name,
    required this.filePaths,
    required this.createdAt,
    this.lastPlayedAt,
    this.currentIndex = 0,
  });

  List<String> get tracks =>
      filePaths.isEmpty ? [] : filePaths.split('|');

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'filePaths': filePaths,
    'createdAt': createdAt,
    'lastPlayedAt': lastPlayedAt,
    'currentIndex': currentIndex,
  };

  factory PlaylistModel.fromMap(Map<String, dynamic> m) => PlaylistModel(
    id:           m['id'] as int?,
    name:         m['name'] as String,
    filePaths:    m['filePaths'] as String,
    createdAt:    m['createdAt'] as String,
    lastPlayedAt: m['lastPlayedAt'] as String?,
    currentIndex: m['currentIndex'] as int,
  );
}

/// Service singleton d'accès à la base de données SQLite.
class DatabaseService {
  DatabaseService._();

  /// Instance unique (singleton).
  static final DatabaseService instance = DatabaseService._();

  static Database? _db;

  // ─── Initialisation ───────────────────────────────────────────────────────

  /// Retourne la base de données, l'initialise si nécessaire.
  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  /// Ouvre ou crée la base de données.
  /// En cas de corruption, supprime et recrée la DB.
  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'omni_explorer.db');

    try {
      return await openDatabase(
        fullPath,
        version: 1,
        onCreate: _createTables,
        onUpgrade: _onUpgrade,
      );
    } catch (_) {
      await deleteDatabase(fullPath);
      return openDatabase(
        fullPath,
        version: 1,
        onCreate: _createTables,
        onUpgrade: _onUpgrade,
      );
    }
  }

  /// Crée toutes les tables lors de la première ouverture.
  Future<void> _createTables(Database db, int version) async {
    // ── Table corbeille ───────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE trash (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        originalPath TEXT NOT NULL,
        trashPath   TEXT NOT NULL,
        name        TEXT NOT NULL,
        deletedAt   TEXT NOT NULL,
        size        INTEGER NOT NULL DEFAULT 0,
        isDirectory INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Table raccourcis ──────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE shortcuts (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        name  TEXT NOT NULL,
        path  TEXT NOT NULL UNIQUE,
        type  INTEGER NOT NULL DEFAULT 0,
        orderIndex INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Index unique sur le chemin du raccourci ────────────────────────────
    await db.execute(
        'CREATE UNIQUE INDEX idx_shortcuts_path ON shortcuts(path)');

    // ── Table playlists ───────────────────────────────────────────────────
    await db.execute('''
      CREATE TABLE playlists (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        filePaths     TEXT NOT NULL DEFAULT '',
        createdAt     TEXT NOT NULL,
        lastPlayedAt  TEXT,
        currentIndex  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Migration des tables lors d'une mise à jour de version.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migrations futures ici
  }

  // ─── CRUD Corbeille ───────────────────────────────────────────────────────

  /// Insère un élément dans la corbeille.
  Future<int> insertTrashItem(TrashItem item) async {
    final db = await database;
    return db.insert('trash', item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retourne tous les éléments de la corbeille, triés par date décroissante.
  Future<List<TrashItem>> getAllTrashItems() async {
    final db = await database;
    final maps = await db.query('trash', orderBy: 'deletedAt DESC');
    return maps
      .map<TrashItem>((map) => TrashItem.fromMap(map))
      .toList();
  }

  /// Supprime un élément de la corbeille par son id.
  Future<void> deleteTrashItem(int id) async {
    final db = await database;
    await db.delete('trash', where: 'id = ?', whereArgs: [id]);
  }

  /// Vide entièrement la table corbeille.
  Future<void> clearTrash() async {
    final db = await database;
    await db.delete('trash');
  }

  // ─── CRUD Raccourcis ──────────────────────────────────────────────────────

  /// Insère ou remplace un raccourci.
  Future<int> insertShortcut(ShortcutItem item) async {
    final db = await database;
    return db.insert(
      'shortcuts',
      {
        'name': item.name,
        'path': item.path,
        'type': 0,
        'orderIndex': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retourne tous les raccourcis triés par ordre.
  Future<List<ShortcutItem>> getAllShortcuts() async {
    final db = await database;
    final maps = await db.query('shortcuts', orderBy: 'orderIndex ASC');
    return maps
        .map((m) => ShortcutItem(
              id:   (m['id'] as int).toString(),
              name: m['name'] as String,
              path: m['path'] as String,
            ))
        .toList();
  }

  /// Supprime un raccourci par son chemin.
  Future<void> deleteShortcutByPath(String path) async {
    final db = await database;
    await db.delete('shortcuts', where: 'path = ?', whereArgs: [path]);
  }

  /// Met à jour le nom d'un raccourci.
  Future<void> updateShortcutName(int id, String name) async {
    final db = await database;
    await db.update('shortcuts', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Vérifie si un chemin est déjà dans les raccourcis.
  Future<bool> isShortcutExists(String path) async {
    final db = await database;
    final result = await db
        .query('shortcuts', where: 'path = ?', whereArgs: [path], limit: 1);
    return result.isNotEmpty;
  }

  // ─── CRUD Playlists ───────────────────────────────────────────────────────

  /// Insère une nouvelle playlist.
  Future<int> insertPlaylist(PlaylistModel playlist) async {
    final db = await database;
    return db.insert('playlists', playlist.toMap());
  }

  /// Retourne toutes les playlists.
  Future<List<PlaylistModel>> getAllPlaylists() async {
    final db = await database;
    final maps = await db.query('playlists', orderBy: 'createdAt DESC');
    return maps.map(PlaylistModel.fromMap).toList();
  }

  /// Retourne une playlist par son id.
  Future<PlaylistModel?> getPlaylistById(int id) async {
    final db = await database;
    final maps =
        await db.query('playlists', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isEmpty ? null : PlaylistModel.fromMap(maps.first);
  }

  /// Met à jour une playlist existante.
  Future<void> updatePlaylist(PlaylistModel playlist) async {
    final db = await database;
    await db.update(
      'playlists',
      playlist.toMap(),
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
  }

  /// Supprime une playlist par son id.
  Future<void> deletePlaylist(int id) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Nettoyage ────────────────────────────────────────────────────────────

  /// Ferme la connexion à la base de données.
  Future<void> close() async {
    final db = _db;
    if (db != null && db.isOpen) {
      await db.close();
      _db = null;
    }
  }
}
