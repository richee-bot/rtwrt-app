package com.cogwheel.LuCIMobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable edge-to-edge display without using deprecated APIs
        setupEdgeToEdge()
    }
    
    private fun setupEdgeToEdge() {
        // Enable edge-to-edge layout
        WindowCompat.setDecorFitsSystemWindows(window, false)
        
        // Use WindowInsetsController instead of deprecated window flags
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller?.let {
            // Make status bar and navigation bar transparent without deprecated APIs
            it.isAppearanceLightStatusBars = false
            it.isAppearanceLightNavigationBars = false
        }
        
        // For Android 15+ (API 35+), use the modern EdgeToEdge API
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            enableModernEdgeToEdge()
        }
    }
    
    private fun enableModernEdgeToEdge() {
        try {
            // Use reflection to call EdgeToEdge.enable() for Android 15+
            val edgeToEdgeClass = Class.forName("androidx.activity.EdgeToEdge")
            val enableMethod = edgeToEdgeClass.getMethod("enable", androidx.activity.ComponentActivity::class.java)
            enableMethod.invoke(null, this)
        } catch (e: Exception) {
            // Fallback is already handled by setupEdgeToEdge()
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "rtwrt/update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> {
                    val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("path", "Missing APK path", null)
                    } else {
                        try {
                            installApk(path)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("install", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
