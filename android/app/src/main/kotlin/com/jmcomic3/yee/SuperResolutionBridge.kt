package com.jmcomic3.yee

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

object SuperResolutionBridge {
    private const val MAX_INPUT_PIXELS = 5_000_000L
    private const val THREADS = 4

    init {
        System.loadLibrary("ncnn")
        System.loadLibrary("jmcomic3_super_resolution")
    }

    fun upscaleFile(
        inputPath: String,
        modelDirectory: String,
        cacheDirectory: File,
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
            ).joinToString("|"),
        )
        val outputFile = File(outputDirectory, "$identity.png")
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

        val output = Bitmap.createBitmap(
            input.width * 2,
            input.height * 2,
            Bitmap.Config.ARGB_8888,
        )
        val temporary = File(outputDirectory, ".$identity-${System.nanoTime()}.part")
        try {
            if (!nativeUpscale(
                    input,
                    output,
                    paramFile.absolutePath,
                    weightsFile.absolutePath,
                    THREADS,
                )
            ) {
                throw IllegalStateException("Super-resolution inference failed")
            }
            FileOutputStream(temporary).use { stream ->
                if (!output.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
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
    ): Boolean
}
