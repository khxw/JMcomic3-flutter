package com.jmcomic3.yee

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

object SuperResolutionBridge {
    private const val MAX_INPUT_PIXELS = 10_000_000L

    init {
        System.loadLibrary("ncnn")
        System.loadLibrary("jmcomic3_super_resolution")
    }

    fun upscaleFile(
        inputPath: String,
        modelDirectory: String,
        cacheDirectory: File,
        threads: Int,
        tileSize: Int,
        backend: String,
    ): String {
        val inputFile = File(inputPath)
        val modelDir = File(modelDirectory)
        val paramFile = File(modelDir, "scale2.0x_model.param")
        val weightsFile = File(modelDir, "scale2.0x_model.bin")
        if (!inputFile.isFile) {
            throw IllegalArgumentException("Super-resolution input does not exist")
        }
        if (!paramFile.isFile || !weightsFile.isFile) {
            throw IllegalArgumentException("Super-resolution model is incomplete")
        }

        val outputDirectory = File(cacheDirectory, "super_resolution").apply {
            if (!exists() && !mkdirs()) {
                throw IllegalStateException("Unable to create super-resolution cache")
            }
        }
        val identity = sha256(
            listOf(
                inputFile.absolutePath,
                inputFile.length().toString(),
                inputFile.lastModified().toString(),
                paramFile.length().toString(),
                paramFile.lastModified().toString(),
                weightsFile.length().toString(),
                weightsFile.lastModified().toString(),
                "backend-$backend",
                "jpeg-95",
            ).joinToString("|"),
        )
        val outputFile = File(outputDirectory, "$identity.jpg")
        if (outputFile.isFile && outputFile.length() > 0L) {
            return outputFile.absolutePath
        }

        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inMutable = true
        }
        val input = BitmapFactory.decodeFile(inputFile.absolutePath, options)
            ?: throw IllegalArgumentException("Unable to decode super-resolution input")
        val inputPixels = input.width.toLong() * input.height.toLong()
        if (input.width < 2 || input.height < 2) {
            input.recycle()
            throw IllegalArgumentException("Super-resolution input is too small")
        }
        if (inputPixels > MAX_INPUT_PIXELS) {
            input.recycle()
            throw IllegalArgumentException("Super-resolution input is too large")
        }
        val resolvedThreads = threads.coerceIn(1, 8)
        val resolvedTileSize = tileSize.coerceIn(64, 512)
        val backendPreference = when (backend) {
            "gpu" -> 1
            "cpu" -> 2
            else -> 0
        }

        val output = try {
            Bitmap.createBitmap(
                input.width * 2,
                input.height * 2,
                Bitmap.Config.ARGB_8888,
            )
        } catch (error: Throwable) {
            input.recycle()
            throw error
        }
        val temporary = File(outputDirectory, ".$identity-${System.nanoTime()}.part")
        try {
            if (!nativeUpscale(
                    input,
                    output,
                    paramFile.absolutePath,
                    weightsFile.absolutePath,
                    resolvedThreads,
                    resolvedTileSize,
                    backendPreference,
                )
            ) {
                throw IllegalStateException("Super-resolution inference failed")
            }
            FileOutputStream(temporary).use { stream ->
                if (!output.compress(Bitmap.CompressFormat.JPEG, 95, stream)) {
                    throw IllegalStateException("Unable to encode super-resolution result")
                }
                stream.flush()
            }
            if (outputFile.exists()) outputFile.delete()
            if (!temporary.renameTo(outputFile)) {
                throw IllegalStateException("Unable to publish super-resolution result")
            }
            return outputFile.absolutePath
        } finally {
            if (temporary.exists()) temporary.delete()
            input.recycle()
            output.recycle()
        }
    }

    fun capabilities(): Map<String, Any> {
        val available = nativeIsVulkanAvailable()
        return mapOf(
            "vulkan_available" to available,
            "device_name" to if (available) nativeVulkanDeviceName() else "",
        )
    }

    fun clearCache(cacheDirectory: File) {
        val directory = File(cacheDirectory, "super_resolution")
        directory.listFiles()?.forEach { file ->
            if (file.isFile) file.delete()
        }
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    private external fun nativeUpscale(
        input: Bitmap,
        output: Bitmap,
        paramPath: String,
        weightsPath: String,
        threads: Int,
        tileSize: Int,
        backendPreference: Int,
    ): Boolean

    private external fun nativeIsVulkanAvailable(): Boolean

    private external fun nativeVulkanDeviceName(): String
}
