/// @file vault_category.dart
/// @brief Catégories d'informations du coffre-fort et leurs champs.
///
/// Chaque entrée a un tag (son nom, obligatoire), une catégorie et des
/// valeurs de champs rangées par clé. La clé d'une catégorie et celles de
/// ses champs sont enregistrées dans le coffre : ne jamais en renommer une
/// existante (ajouter une catégorie ou un champ ne demande pas de
/// migration, les valeurs absentes valent « vide »).

import 'package:flutter/material.dart';

/// Nature d'un champ : saisie, affichage masqué, actions proposées.
enum VaultFieldKind {
  /// Texte court lisible.
  text,

  /// Adresse électronique.
  email,

  /// Adresse web.
  url,

  /// Texte court masqué par défaut (code, numéro sensible).
  secret,

  /// Mot de passe : masqué, avec le générateur.
  password,

  /// Nombre ou code numérique masqué (PIN, cryptogramme).
  pin,

  /// Texte long lisible.
  multiline,

  /// Texte long masqué par défaut (message, phrase de récupération, clé).
  multilineSecret,
}

/// Un champ d'une catégorie.
class VaultField {
  /// Clé enregistrée dans le coffre.
  final String key;
  final String label;
  final VaultFieldKind kind;

  /// Indication sous le champ (format attendu…).
  final String? hint;

  const VaultField(this.key, this.label, this.kind, {this.hint});

  /// Contenu masqué par défaut, exclu de la recherche.
  bool get isSecret => switch (kind) {
        VaultFieldKind.secret ||
        VaultFieldKind.password ||
        VaultFieldKind.pin ||
        VaultFieldKind.multilineSecret =>
          true,
        _ => false,
      };

  bool get isMultiline =>
      kind == VaultFieldKind.multiline ||
      kind == VaultFieldKind.multilineSecret;
}

/// Champ « Notes » présent en fin de chaque catégorie.
const _notes = VaultField('notes', 'Notes', VaultFieldKind.multiline);

/// Catégories proposées, dans l'ordre d'affichage (et de tri par catégorie).
enum VaultCategory {
  website(
    'website',
    'Site web',
    Icons.language_rounded,
    Color(0xFF2196F3),
    [
      VaultField('username', 'Identifiant', VaultFieldKind.text),
      VaultField('password', 'Mot de passe', VaultFieldKind.password),
      VaultField('url', 'Adresse du site (URL)', VaultFieldKind.url),
      _notes,
    ],
    summary: 'username',
    secret: 'password',
  ),
  email(
    'email',
    'Messagerie',
    Icons.alternate_email_rounded,
    Color(0xFFE91E63),
    [
      VaultField('address', 'Adresse e-mail', VaultFieldKind.email),
      VaultField('password', 'Mot de passe', VaultFieldKind.password),
      VaultField('server', 'Serveur (IMAP / SMTP)', VaultFieldKind.text),
      _notes,
    ],
    summary: 'address',
    secret: 'password',
  ),
  message(
    'message',
    'Message secret',
    Icons.sticky_note_2_rounded,
    Color(0xFF9C27B0),
    [
      VaultField('message', 'Message', VaultFieldKind.multilineSecret),
    ],
    secret: 'message',
  ),
  bank(
    'bank',
    'Banque',
    Icons.account_balance_rounded,
    Color(0xFF4CAF50),
    [
      VaultField('bankName', 'Nom de la banque', VaultFieldKind.text),
      VaultField('cardHolder', 'Titulaire de la carte', VaultFieldKind.text),
      VaultField('cardNumber', 'Numéro de carte complet', VaultFieldKind.pin,
          hint: '16 chiffres'),
      VaultField('cardExpiry', 'Date d\'expiration', VaultFieldKind.text,
          hint: 'MM/AA'),
      VaultField('cardCvv', 'Cryptogramme (CVV)', VaultFieldKind.pin),
      VaultField('cardPin', 'Code PIN de la carte', VaultFieldKind.pin),
      VaultField('iban', 'IBAN', VaultFieldKind.secret),
      VaultField('bic', 'BIC / SWIFT', VaultFieldKind.text),
      VaultField('rib', 'RIB (banque, guichet, compte, clé)',
          VaultFieldKind.multilineSecret),
      VaultField('onlineLogin', 'Identifiant d\'accès en ligne',
          VaultFieldKind.text),
      VaultField('onlinePassword', 'Code d\'accès en ligne',
          VaultFieldKind.password),
      _notes,
    ],
    summary: 'bankName',
    secret: 'cardNumber',
  ),
  wifi(
    'wifi',
    'Réseau Wi-Fi',
    Icons.wifi_rounded,
    Color(0xFF00BCD4),
    [
      VaultField('ssid', 'Nom du réseau (SSID)', VaultFieldKind.text),
      VaultField('password', 'Mot de passe', VaultFieldKind.password),
      VaultField('security', 'Sécurité', VaultFieldKind.text,
          hint: 'WPA2, WPA3…'),
      _notes,
    ],
    summary: 'ssid',
    secret: 'password',
  ),
  server(
    'server',
    'Serveur / SSH',
    Icons.dns_rounded,
    Color(0xFF607D8B),
    [
      VaultField('host', 'Hôte', VaultFieldKind.text),
      VaultField('port', 'Port', VaultFieldKind.text),
      VaultField('username', 'Utilisateur', VaultFieldKind.text),
      VaultField('password', 'Mot de passe', VaultFieldKind.password),
      VaultField('privateKey', 'Clé privée', VaultFieldKind.multilineSecret),
      _notes,
    ],
    summary: 'host',
    secret: 'password',
  ),
  identity(
    'identity',
    'Pièce d\'identité',
    Icons.badge_rounded,
    Color(0xFFFF9800),
    [
      VaultField('documentType', 'Type de document', VaultFieldKind.text,
          hint: 'Carte d\'identité, passeport, permis…'),
      VaultField('fullName', 'Nom complet', VaultFieldKind.text),
      VaultField('documentNumber', 'Numéro du document', VaultFieldKind.secret),
      VaultField('issueDate', 'Date de délivrance', VaultFieldKind.text),
      VaultField('expiryDate', 'Date d\'expiration', VaultFieldKind.text),
      VaultField('issuer', 'Délivré par', VaultFieldKind.text),
      _notes,
    ],
    summary: 'documentType',
    secret: 'documentNumber',
  ),
  health(
    'health',
    'Santé',
    Icons.health_and_safety_rounded,
    Color(0xFFF44336),
    [
      VaultField('socialSecurity', 'Numéro de sécurité sociale',
          VaultFieldKind.secret),
      VaultField('insurer', 'Mutuelle', VaultFieldKind.text),
      VaultField('memberNumber', 'Numéro d\'adhérent', VaultFieldKind.secret),
      VaultField('bloodType', 'Groupe sanguin', VaultFieldKind.text),
      _notes,
    ],
    summary: 'insurer',
    secret: 'socialSecurity',
  ),
  phone(
    'phone',
    'Téléphone / SIM',
    Icons.sim_card_rounded,
    Color(0xFF3F51B5),
    [
      VaultField('phoneNumber', 'Numéro de téléphone', VaultFieldKind.text),
      VaultField('operator', 'Opérateur', VaultFieldKind.text),
      VaultField('pin', 'Code PIN', VaultFieldKind.pin),
      VaultField('puk', 'Code PUK', VaultFieldKind.pin),
      VaultField('unlockCode', 'Code de déverrouillage', VaultFieldKind.secret),
      _notes,
    ],
    summary: 'phoneNumber',
    secret: 'pin',
  ),
  license(
    'license',
    'Licence logicielle',
    Icons.vpn_key_rounded,
    Color(0xFF795548),
    [
      VaultField('product', 'Logiciel', VaultFieldKind.text),
      VaultField('licenseKey', 'Clé de licence', VaultFieldKind.secret),
      VaultField('owner', 'Enregistrée au nom de', VaultFieldKind.text),
      VaultField('email', 'E-mail du compte', VaultFieldKind.email),
      _notes,
    ],
    summary: 'product',
    secret: 'licenseKey',
  ),
  crypto(
    'crypto',
    'Portefeuille crypto',
    Icons.currency_bitcoin_rounded,
    Color(0xFFFFC107),
    [
      VaultField('walletName', 'Portefeuille', VaultFieldKind.text),
      VaultField('address', 'Adresse publique', VaultFieldKind.text),
      VaultField('seedPhrase', 'Phrase de récupération',
          VaultFieldKind.multilineSecret),
      VaultField('password', 'Mot de passe', VaultFieldKind.password),
      _notes,
    ],
    summary: 'walletName',
    secret: 'seedPhrase',
  );

  /// Clé enregistrée dans le coffre.
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final List<VaultField> fields;

  /// Champ lisible affiché sous le tag dans la liste.
  final String? summary;

  /// Champ secret principal, copiable depuis la liste.
  final String? secret;

  const VaultCategory(
    this.key,
    this.label,
    this.icon,
    this.color,
    this.fields, {
    this.summary,
    this.secret,
  });

  /// Catégorie de [key] ; `null` si elle est inconnue (coffre écrit par une
  /// version plus récente).
  static VaultCategory? byKey(String key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }

  VaultField? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }
}
