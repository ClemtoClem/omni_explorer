package com.example.omni_explorer

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PersistableBundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.omni_explorer/settings"
    private val SECURITY_CHANNEL = "com.example.omni_explorer/security"

    /** Libellé des copies faites par le coffre-fort (reconnaissance au nettoyage). */
    private val VAULT_CLIP_LABEL = "omni-vault"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openWriteSettings") {
                    val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                    intent.data = Uri.parse("package:${packageName}")
                    startActivity(intent)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Bloque captures et enregistrements d'écran, et masque la
                    // vignette de l'application dans les applications récentes.
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    // Copie marquée « sensible » : Android 13+ n'affiche pas
                    // son contenu dans l'aperçu du presse-papiers.
                    "copySensitive" -> {
                        val text = call.argument<String>("text") ?: ""
                        val clip = ClipData.newPlainText(VAULT_CLIP_LABEL, text)
                        clip.description.extras = PersistableBundle().apply {
                            val key = if (Build.VERSION.SDK_INT >= 33) {
                                ClipDescription.EXTRA_IS_SENSITIVE
                            } else {
                                "android.content.extra.IS_SENSITIVE"
                            }
                            putBoolean(key, true)
                        }
                        clipboard().setPrimaryClip(clip)
                        result.success(null)
                    }
                    // Efface le presse-papiers s'il contient encore une copie du
                    // coffre. Depuis Android 10, une application en arrière-plan
                    // ne peut pas le lire : dans ce cas, on efface quand même
                    // (mieux vaut perdre une autre copie que laisser un mot de
                    // passe dans le presse-papiers).
                    "clearVaultClip" -> {
                        val cm = clipboard()
                        val description = try {
                            cm.primaryClipDescription
                        } catch (e: SecurityException) {
                            null
                        }
                        val ours = description == null ||
                            description.label?.toString() == VAULT_CLIP_LABEL
                        if (ours) {
                            if (Build.VERSION.SDK_INT >= 28) {
                                cm.clearPrimaryClip()
                            } else {
                                cm.setPrimaryClip(ClipData.newPlainText("", ""))
                            }
                        }
                        result.success(ours)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun clipboard(): ClipboardManager =
        getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
}
