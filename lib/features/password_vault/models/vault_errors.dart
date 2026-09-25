/// @file vault_errors.dart
/// @brief Erreurs du coffre-fort, avec un message destiné à l'utilisateur.
///
/// Les messages ne contiennent jamais de secret (mot de passe, contenu).

sealed class VaultException implements Exception {
  final String message;
  const VaultException(this.message);

  @override
  String toString() => message;
}

/// Le mot de passe maître ne permet pas d'ouvrir le coffre.
class WrongPasswordException extends VaultException {
  const WrongPasswordException() : super('Mot de passe incorrect.');
}

/// Le fichier du coffre est illisible ou a été modifié.
class VaultCorruptedException extends VaultException {
  /// Détail technique (sans secret), utile pour le diagnostic.
  final String detail;

  const VaultCorruptedException(this.detail)
      : super('Le fichier du coffre est endommagé ou a été modifié.');
}

/// Coffre créé par une version plus récente de l'application.
class VaultTooNewException extends VaultException {
  const VaultTooNewException()
      : super('Ce coffre a été créé par une version plus récente '
            'd\'OmniExplorer : mettez l\'application à jour pour l\'ouvrir.');
}

/// Mot de passe maître refusé à la création ou au changement.
class WeakPasswordException extends VaultException {
  const WeakPasswordException(super.message);
}

/// Le calcul de la clé a échoué (mémoire insuffisante sur l'appareil…).
class VaultKeyDerivationException extends VaultException {
  const VaultKeyDerivationException()
      : super('Impossible de dériver la clé du coffre (mémoire '
            'insuffisante ?).');
}

/// Le fichier choisi pour l'import n'est pas un export du coffre-fort.
class NotAnExportException extends VaultException {
  const NotAnExportException()
      : super('Ce fichier n\'est pas un export de coffre-fort OmniExplorer.');
}

/// Fichier d'import trop volumineux pour être un export de coffre.
class ExportTooLargeException extends VaultException {
  const ExportTooLargeException()
      : super('Fichier trop volumineux pour être un export de coffre-fort.');
}
