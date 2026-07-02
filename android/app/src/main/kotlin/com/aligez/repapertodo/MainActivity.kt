package com.aligez.repapertodo

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "repapertodo/android"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFilesDirectory" -> {
                    result.success(filesDir.absolutePath)
                }
                "openUri" -> {
                    val uri = call.arguments as? String
                    if (uri.isNullOrBlank()) {
                        result.error("invalid_uri", "The URI is empty.", null)
                        return@setMethodCallHandler
                    }
                    val trimmedUri = uri.trim()
                    val parsedUri = Uri.parse(trimmedUri)
                    if (parsedUri.scheme.isNullOrBlank()) {
                        result.error("invalid_uri", "The URI must include a scheme.", null)
                        return@setMethodCallHandler
                    }
                    if (hasUnsafeExternalUriCharacter(trimmedUri)) {
                        result.error("invalid_uri", "The URI contains unsupported characters.", null)
                        return@setMethodCallHandler
                    }
                    if (!isAllowedExternalUri(parsedUri)) {
                        result.error("invalid_uri", "The URI scheme is not supported.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, parsedUri).apply {
                            addCategory(Intent.CATEGORY_BROWSABLE)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (error: ActivityNotFoundException) {
                        result.error("open_uri_failed", "Unable to open the URI.", null)
                    } catch (error: SecurityException) {
                        result.error("open_uri_failed", "The URI cannot be opened securely.", null)
                    }
                }
                "openExternalFile" -> {
                    val path = call.arguments as? String
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "The file path is empty.", null)
                        return@setMethodCallHandler
                    }

                    val trimmedPath = path.trim()
                    val file = File(trimmedPath)
                    if (!file.isFile) {
                        result.error("file_not_found", "The file does not exist.", null)
                        return@setMethodCallHandler
                    }

                    val uri = try {
                        FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            file
                        )
                    } catch (error: IllegalArgumentException) {
                        result.error(
                            "file_provider_failed",
                            "The file is outside the configured share paths.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    for (mimeType in mimeTypesFor(file)) {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            clipData = ClipData.newUri(contentResolver, file.name, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        try {
                            startActivity(intent)
                            result.success(null)
                            return@setMethodCallHandler
                        } catch (error: ActivityNotFoundException) {
                            continue
                        } catch (error: SecurityException) {
                            result.error(
                                "open_external_file_failed",
                                "The external file cannot be shared securely.",
                                null
                            )
                            return@setMethodCallHandler
                        }
                    }

                    result.error(
                        "open_external_file_failed",
                        "Unable to open the external file.",
                        null
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun mimeTypesFor(file: File): List<String> {
        return when (file.extension.lowercase()) {
            "md", "markdown" -> listOf("text/markdown", "text/plain", "*/*")
            "txt" -> listOf("text/plain", "*/*")
            else -> listOf("*/*")
        }
    }

    private fun isAllowedExternalUri(uri: Uri): Boolean {
        return when (uri.scheme?.lowercase()) {
            "http", "https" -> !uri.host.isNullOrBlank()
            "mailto" -> !uri.schemeSpecificPart.isNullOrBlank()
            else -> false
        }
    }

    private fun hasUnsafeExternalUriCharacter(uri: String): Boolean {
        return uri.any { character ->
            character.code <= 0x20 || character.code == 0x7F
        }
    }
}
