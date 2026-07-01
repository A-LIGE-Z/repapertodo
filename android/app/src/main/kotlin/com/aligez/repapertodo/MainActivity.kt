package com.aligez.repapertodo

import android.content.ActivityNotFoundException
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
                "openUri" -> {
                    val uri = call.arguments as? String
                    if (uri.isNullOrBlank()) {
                        result.error("invalid_uri", "The URI is empty.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
                        result.success(null)
                    } catch (error: ActivityNotFoundException) {
                        result.error("open_uri_failed", "Unable to open the URI.", null)
                    }
                }
                "openExternalFile" -> {
                    val path = call.arguments as? String
                    if (path.isNullOrBlank()) {
                        result.error("invalid_path", "The file path is empty.", null)
                        return@setMethodCallHandler
                    }

                    val file = File(path)
                    if (!file.exists()) {
                        result.error("file_not_found", "The file does not exist.", null)
                        return@setMethodCallHandler
                    }

                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.fileprovider",
                        file
                    )
                    for (mimeType in mimeTypesFor(file)) {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        try {
                            startActivity(intent)
                            result.success(null)
                            return@setMethodCallHandler
                        } catch (error: ActivityNotFoundException) {
                            continue
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
}
