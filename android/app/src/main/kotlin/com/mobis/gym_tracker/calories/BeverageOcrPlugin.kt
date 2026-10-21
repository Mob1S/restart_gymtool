package com.mobis.gym_tracker.calories

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.FileProvider
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/** Bundled, on-device Chinese/Latin OCR. Temporary files never enter backups. */
class BeverageOcrPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pending: MethodChannel.Result? = null
    private var photo: File? = null
    private var generation = 0
    private val main = Handler(Looper.getMainLooper())
    private val requestCode = 4827
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "gym_tracker/beverage_ocr")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { cancel(); channel.setMethodCallHandler(null) }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }
    private fun detach() {
        binding?.removeActivityResultListener(this)
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        cancel()
    }
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detach()
    private fun cancel() { generation++; pending?.success(null); pending = null; photo?.delete(); photo = null }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") { cancel(); result.success(null); return }
        if (call.method != "scan") { result.notImplemented(); return }
        val activity = binding?.activity
        if (activity == null) { result.error("unavailable", "没有可用的图片输入界面", null); return }
        if (pending != null) { result.error("busy", "正在识别", null); return }
        pending = result
        if (call.argument<Boolean>("camera") == true) {
            if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), requestCode)
            } else launch(true)
        } else launch(false)
    }
    private fun fail(message: String) { pending?.error("ocr", message, null); pending = null; photo?.delete(); photo = null }
    private fun launch(camera: Boolean) {
        val activity = binding?.activity ?: return fail("图片输入已关闭")
        try {
            val intent = if (camera) {
                val dir = File(activity.cacheDir, "beverage-scans").apply { mkdirs() }
                // Clear abandoned images from a previously killed process.
                dir.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 86400000L }?.forEach { it.delete() }
                val file = File.createTempFile("label-", ".jpg", dir)
                photo = file
                val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.beverage-files", file)
                Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, uri)
                    .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
            activity.startActivityForResult(intent, requestCode)
        } catch (e: Exception) { fail("无法打开相机或图库：${e.localizedMessage}") }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != this.requestCode) return false
        if (pending == null) return true
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) launch(true) else fail("未授予相机权限，可使用导入图片")
        return true
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != this.requestCode) return false
        if (pending == null) return true
        if (resultCode != Activity.RESULT_OK) { cancel(); return true }
        val activity = binding?.activity ?: run { cancel(); return true }
        val uri = photo?.let(Uri::fromFile) ?: data?.data
        if (uri == null) { fail("图片为空"); return true }
        val token = generation
        val tempPhoto = photo
        Thread {
            try {
                val bytes = activity.contentResolver.openInputStream(uri)?.use { stream ->
                    val buffer = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(16384)
                    while (true) {
                        val count = stream.read(chunk)
                        if (count < 0) break
                        if (buffer.size() + count > 20 * 1024 * 1024) throw IllegalArgumentException("图片不能超过 20 MiB")
                        buffer.write(chunk, 0, count)
                    }
                    buffer.toByteArray()
                } ?: throw IllegalArgumentException("无法读取图片")
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0 || bounds.outWidth.toLong() * bounds.outHeight > 24000000) throw IllegalArgumentException("请使用不超过 2400 万像素的清晰图片")
                val image = InputImage.fromFilePath(activity, uri)
                main.post {
                    if (token != generation || pending == null) { tempPhoto?.delete(); return@post }
                    val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
                    recognizer.process(image)
                        .addOnSuccessListener { text ->
                            if (token == generation) { pending?.success(mapOf("text" to text.text, "image" to bytes)); pending = null }
                        }
                        .addOnFailureListener { e -> if (token == generation) fail("标签识别失败：${e.localizedMessage}") }
                        .addOnCompleteListener { recognizer.close(); tempPhoto?.delete(); if (photo == tempPhoto) photo = null }
                }
            } catch (e: Exception) { main.post { if (token == generation) fail(e.localizedMessage ?: "无法识别图片"); tempPhoto?.delete() } }
        }.start()
        return true
    }
}
