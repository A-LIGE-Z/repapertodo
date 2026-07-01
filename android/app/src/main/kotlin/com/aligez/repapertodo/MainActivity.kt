package com.aligez.repapertodo

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
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
                else -> result.notImplemented()
            }
        }
    }
}
