# ── Règles ProGuard / R8 ──────────────────────────────────────────────────────
# Ces règles ne sont appliquées que si isMinifyEnabled = true. Elles évitent
# que R8 ne supprime l'enregistrement natif des plugins Flutter (cause typique
# d'un MissingPluginException dans l'APK release alors que tout marche en debug).

# Flutter embedding & plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# media_kit (lecteur vidéo)
-keep class com.alexmercerind.** { *; }
-keep class media.kit.** { *; }
-dontwarn com.alexmercerind.**

# ffmpeg_kit (éditeur vidéo)
-keep class com.arthenica.** { *; }
-dontwarn com.arthenica.**

# just_audio / audio_service
-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

# Conserver les annotations utilisées par la réflexion des plugins
-keepattributes *Annotation*
-keepattributes Signature
