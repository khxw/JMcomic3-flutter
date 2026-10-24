package com.jmcomic3.yee

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.Display
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.io.File
import opensource.jenny.Jni
import java.util.concurrent.LinkedBlockingQueue
import android.hardware.biometrics.BiometricPrompt
import java.util.concurrent.TimeUnit
import android.os.CancellationSignal

class MainActivity : FlutterActivity() {

    companion object {
        private const val DIRECTORY_PICKER_REQUEST = 7412
        private const val STORAGE_PERMISSION_REQUEST = 7413
        private const val ALL_FILES_SETTINGS_REQUEST = 7414
    }

    private val uiThreadHandler = Handler(Looper.getMainLooper())
    private val pool =
        Executors.newCachedThreadPool { runnable -> Thread(runnable).also { it.isDaemon = true } }
    private var pendingDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // 初始化
        Jni.init(context.filesDir.absolutePath)
        // channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "methods").setMethodCallHandler(
            this::methods
        )
        //
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "volume_button")
            .setStreamHandler(volumeStreamHandler)
        // super
        super.configureFlutterEngine(flutterEngine)
    }

    private fun methods(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "androidGetRefreshModes" -> {
                runOnUiThread(result) { refreshModes() }
                return
            }
            "androidSetRefreshMode" -> {
                runOnUiThread(result) {
                    setRefreshMode(call.argument<Int>("mode_id"))
                }
                return
            }
            "androidPickDownloadDirectory" -> {
                uiThreadHandler.post { pickDownloadDirectory(result) }
                return
            }
        }
        result.withCoroutine {
            when (call.method) {
                "invoke" -> Jni.invoke(call.arguments<String>())
                "saveImageFileToGallery" -> saveImageFileToGallery(call.arguments<String>()!!)
                "androidGetModes" -> {
                    modes()
                }
                "androidSetMode" -> {
                    setMode(call.argument("mode")!!)
                }
                "androidGetVersion" -> Build.VERSION.SDK_INT
                "androidStorageRoot" -> storageRoot()
                "androidDefaultExportsDir" -> androidDefaultExportsDir().absolutePath
                "androidDirectoryWritable" -> androidDirectoryWritable(
                    call.arguments<String>() ?: "",
                )
                "androidMkdirs" -> androidMkdirs(
                    call.arguments<String>() ?: throw Exception("need arg"),
                )
                "picturesDir" -> picturesDir().absolutePath
                "verifyAuthentication" -> auth()
                else -> notImplementedToken
            }
        }
    }

    private fun runOnUiThread(
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        uiThreadHandler.post {
            try {
                val data = block()
                result.success(if (data is Unit) null else data)
            } catch (e: Exception) {
                Log.e("Method", "UI method exception", e)
                result.error("", e.message, "")
            }
        }
    }

    private val notImplementedToken = Any()
    private fun MethodChannel.Result.withCoroutine(exec: () -> Any?) {
        pool.submit {
            try {
                val data = exec()
                uiThreadHandler.post {
                    when (data) {
                        notImplementedToken -> {
                            notImplemented()
                        }
                        is Unit, null -> {
                            success(null)
                        }
                        else -> {
                            success(data)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("Method", "Exception", e)
                uiThreadHandler.post {
                    error("", e.message, "")
                }
            }

        }
    }

    private fun saveImageFileToGallery(path: String) {
        BitmapFactory.decodeFile(path)?.let { bitmap ->
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, System.currentTimeMillis().toString())
                put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { //this one
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
            contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                ?.let { uri ->
                    contentResolver.openOutputStream(uri)?.use { fos ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 100, fos)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { //this one
                        contentValues.clear()
                        contentValues.put(MediaStore.Video.Media.IS_PENDING, 0)
                        contentResolver.update(uri, contentValues, null, null)
                    }
                }
        }
    }

    // fps mods
    private fun mixDisplay(): Display? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.let {
                return it
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            windowManager.defaultDisplay?.let {
                return it
            }
        }
        return null
    }

    private fun modes(): List<String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            mixDisplay()?.let { display ->
                return display.supportedModes.map { mode ->
                    mode.toString()
                }
            }
        }
        return ArrayList()
    }

    private fun refreshModes(): List<Map<String, Any>> {
        return mixDisplay()?.supportedModes?.map { mode ->
            mapOf(
                "id" to mode.modeId,
                "width" to mode.physicalWidth,
                "height" to mode.physicalHeight,
                "refresh_rate" to mode.refreshRate.toDouble(),
            )
        } ?: emptyList()
    }

    private fun setRefreshMode(modeId: Int?) {
        val display = mixDisplay() ?: return
        val mode = modeId
            ?.takeIf { it > 0 }
            ?.let { requestedId ->
                display.supportedModes.firstOrNull { it.modeId == requestedId }
            }

        val attributes = window.attributes
        attributes.preferredDisplayModeId = mode?.modeId ?: 0
        attributes.preferredRefreshRate = mode?.refreshRate ?: 0f
        window.attributes = attributes
    }

    private fun setMode(string: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            mixDisplay()?.let { display ->
                if (string == "") {
                    uiThreadHandler.post {
                        window.attributes = window.attributes.also { attr ->
                            attr.preferredDisplayModeId = 0
                        }
                    }
                    return
                }
                return display.supportedModes.forEach { mode ->
                    if (mode.toString() == string) {
                        uiThreadHandler.post {
                            window.attributes = window.attributes.also { attr ->
                                attr.preferredDisplayModeId = mode.modeId
                            }
                        }
                        return
                    }
                }
            }
        }
    }

// volume_buttons

    private var volumeEvents: EventChannel.EventSink? = null

    private val volumeStreamHandler = object : EventChannel.StreamHandler {

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            volumeEvents = events
        }

        override fun onCancel(arguments: Any?) {
            volumeEvents = null
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        volumeEvents?.let {
            if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                uiThreadHandler.post {
                    it.success("DOWN")
                }
                return true
            }
            if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                uiThreadHandler.post {
                    it.success("UP")
                }
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    fun storageRoot(): String {
        return Environment.getExternalStorageDirectory().absolutePath
    }

    private fun picturesDir(): File {
        return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            ?: throw java.lang.IllegalStateException()
    }

    private fun downloadsDir(): File {
        return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            ?: throw java.lang.IllegalStateException()
    }

    private fun defaultJennyDir(): File {
        return File(downloadsDir(), "jmtt2mic")
    }

    private fun androidDefaultExportsDir(): File {
        return File(defaultJennyDir(), "exports")
    }

    private fun androidMkdirs(path: String) {
        val dir = File(path)
        if (!dir.exists()) {
            dir.mkdirs()
        }
    }

    private fun androidDirectoryWritable(path: String): Boolean {
        if (path.isBlank()) return false
        return try {
            val dir = File(path)
            if (!dir.exists() && !dir.mkdirs()) return false
            val probe = File.createTempFile(".jmcomic-write-", ".tmp", dir)
            probe.writeText("ok")
            probe.delete()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun pickDownloadDirectory(result: MethodChannel.Result) {
        if (pendingDirectoryResult != null) {
            result.error("picker_busy", "A directory picker is already open.", null)
            return
        }
        pendingDirectoryResult = result
        if (hasDownloadStorageAccess()) {
            launchDownloadDirectoryPicker()
        } else {
            requestDownloadStorageAccess()
        }
    }

    private fun hasDownloadStorageAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestDownloadStorageAccess() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val appSettings = Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
                startActivityForResult(appSettings, ALL_FILES_SETTINGS_REQUEST)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                requestPermissions(
                    arrayOf(
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    ),
                    STORAGE_PERMISSION_REQUEST,
                )
            } else {
                launchDownloadDirectoryPicker()
            }
        } catch (e: Exception) {
            try {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                    ALL_FILES_SETTINGS_REQUEST,
                )
            } catch (fallbackError: Exception) {
                completePendingDirectoryError(
                    "permission_settings_unavailable",
                    fallbackError.message ?: e.message ?: "无法打开存储权限设置",
                )
            }
        }
    }

    private fun launchDownloadDirectoryPicker() {
        val result = pendingDirectoryResult ?: return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, DIRECTORY_PICKER_REQUEST)
        } catch (e: Exception) {
            completePendingDirectoryError("picker_unavailable", e.message)
        }
    }

    private fun completePendingDirectoryError(code: String, message: String?) {
        val result = pendingDirectoryResult
        pendingDirectoryResult = null
        result?.error(code, message, null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ALL_FILES_SETTINGS_REQUEST) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                Environment.isExternalStorageManager()
            ) {
                launchDownloadDirectoryPicker()
            } else {
                completePendingDirectoryError(
                    "permission_denied",
                    "请允许“所有文件访问”后再选择下载目录。",
                )
            }
            return
        }
        if (requestCode != DIRECTORY_PICKER_REQUEST) return
        val result = pendingDirectoryResult
        pendingDirectoryResult = null
        if (result == null) return

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val persistFlags = (data?.flags ?: 0) and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        try {
            contentResolver.takePersistableUriPermission(uri, persistFlags)
        } catch (_: Exception) {
            // Some document providers only grant temporary tree access.
        }
        val path = localPathForTreeUri(uri)
        if (path == null) {
            result.error(
                "unsupported_directory",
                "请选择本机存储中的文件夹，而不是云端盘或虚拟目录。",
                null,
            )
            return
        }
        result.success(path)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST) return
        if (hasDownloadStorageAccess()) {
            launchDownloadDirectoryPicker()
        } else {
            completePendingDirectoryError(
                "permission_denied",
                "请允许存储权限后再选择下载目录。",
            )
        }
    }

    private fun localPathForTreeUri(uri: Uri): String? {
        val documentId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (_: Exception) {
            return null
        }
        if (documentId.startsWith("raw:")) {
            return documentId.removePrefix("raw:").takeIf { it.isNotBlank() }
        }
        if (uri.authority?.contains("downloads.documents") == true) {
            return Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            ).absolutePath
        }
        val separator = documentId.indexOf(':')
        val volumeId = if (separator >= 0) {
            documentId.substring(0, separator)
        } else {
            documentId
        }
        val relativePath = if (separator >= 0) {
            documentId.substring(separator + 1)
        } else {
            ""
        }
        val root = if (volumeId.equals("primary", ignoreCase = true)) {
            Environment.getExternalStorageDirectory()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val storageManager = getSystemService(StorageManager::class.java)
            storageManager.storageVolumes
                .firstOrNull { it.uuid?.equals(volumeId, ignoreCase = true) == true }
                ?.directory
        } else {
            null
        } ?: return null
        return if (relativePath.isBlank()) {
            root.absolutePath
        } else {
            File(root, relativePath).absolutePath
        }
    }

    private fun auth(): Boolean {
        var queue = LinkedBlockingQueue<Boolean>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            var mBiometricPrompt = BiometricPrompt.Builder(this)
                .setTitle("验证身份")
                .setDescription("需要验证您的身份")
                .setNegativeButton(
                    "取消", mainExecutor
                ) { _, _ -> queue.add(false) }
                .build()


            var mCancellationSignal = CancellationSignal()
            mCancellationSignal.setOnCancelListener {
                queue.add(false)
            }

            var mAuthenticationCallback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    super.onAuthenticationError(errorCode, errString)
                    queue.add(false)
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    queue.add(false)
                }

                override fun onAuthenticationSucceeded(result1: BiometricPrompt.AuthenticationResult?) {
                    super.onAuthenticationSucceeded(result1)
                    queue.add(true)
                }
            }

            mBiometricPrompt.authenticate(
                mCancellationSignal,
                mainExecutor,
                mAuthenticationCallback
            )

        } else {
            queue.add(false)
        }

        return queue.poll(5, TimeUnit.MINUTES) ?: false
    }

}
