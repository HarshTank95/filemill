package com.filemill.filemill

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Receives ACTION_VIEW intents ("Open with FileMill" on a PDF), copies the
/// content:// stream into the app cache (we may not hold a persistable
/// permission on the source), and hands {path, name} to Flutter.
class MainActivity : FlutterActivity() {
    private var pendingViewUri: Uri? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "filemill/open_intent"
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getOpenedPdf" -> {
                    val uri = pendingViewUri
                    pendingViewUri = null
                    result.success(if (uri == null) null else copyToCache(uri))
                }
                else -> result.notImplemented()
            }
        }
        captureViewIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (captureViewIntent(intent)) {
            // App was already running: tell Flutter a document just arrived.
            channel?.invokeMethod("onOpenedPdf", null)
        }
    }

    private fun captureViewIntent(intent: Intent?): Boolean {
        if (intent?.action == Intent.ACTION_VIEW && intent.data != null) {
            pendingViewUri = intent.data
            return true
        }
        return false
    }

    private fun copyToCache(uri: Uri): Map<String, String>? {
        return try {
            val name = displayName(uri) ?: "document.pdf"
            val outFile = File(cacheDir, "viewed_${System.currentTimeMillis()}_$name")
            contentResolver.openInputStream(uri)?.use { input ->
                outFile.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            mapOf("path" to outFile.absolutePath, "name" to name)
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) return cursor.getString(idx)
        }
        return null
    }
}
