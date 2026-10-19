package com.mobis.gym_tracker.review

import android.content.Context
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.*
import org.json.JSONArray
import org.json.JSONObject
import org.opencv.android.OpenCVLoader
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class ReviewPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    private var sink: EventChannel.EventSink? = null
    private val active = mutableSetOf<String>()
    private val root get() = File(context.noBackupFilesDir, "video_reviews").apply { mkdirs() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "gym_tracker/review").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "gym_tracker/review_progress").also { it.setStreamHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cancelled.set(true); worker.shutdownNow(); channel.setMethodCallHandler(null); events.setStreamHandler(null)
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun folder(name: String): File {
        require(name.matches(Regex("[0-9a-f-]{36}"))) { "无效的复盘目录" }
        val file = File(root, name).canonicalFile
        require(file.parentFile == root.canonicalFile) { "复盘目录越界" }
        return file
    }
    private fun resultFile(dir: File, name: String): File {
        require(name.matches(Regex("result-[0-9a-f-]{36}\\.json"))) { "无效的结果文件" }
        return File(dir, name)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") { cancelled.set(true); result.success(null); return }
        if (call.method == "analyze" || call.method == "frame" || call.method == "import") cancelled.set(false)
        worker.execute {
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val name = args["folder"] as? String
                val value: Any? = when (call.method) {
                    "capabilities" -> mapOf("supported" to true)
                    "import" -> {
                        val source = File(args["path"] as String)
                        require(source.isFile) { "视频文件不可读取" }
                        val dir = folder(UUID.randomUUID().toString()).apply { mkdirs() }
                        try {
                            require(dir.usableSpace > source.length() + 32 * 1024 * 1024) { "手机剩余空间不足" }
                            source.inputStream().use { input -> File(dir, "video").outputStream().use { output ->
                                val buffer = ByteArray(65536)
                                while (true) {
                                    if (cancelled.get()) throw java.util.concurrent.CancellationException("已取消导入")
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                }
                            } }
                            val metadata = metadata(dir)
                            active.add(dir.name)
                            metadata
                        } catch (e: Exception) { dir.deleteRecursively(); throw e }
                    }
                    "open" -> { val dir = folder(name!!); val data = metadata(dir); active.add(name); data }
                    "release" -> { active.remove(name); null }
                    "load" -> resultFile(folder(name!!), args["result"] as String).readText()
                    "collect" -> {
                        val keep = (args["keep"] as List<*>).filterIsInstance<String>().toSet() + active
                        root.listFiles()?.filter { it.isDirectory && it.name !in keep }?.forEach {
                            // Resolve the exact target before recursive deletion; never follow a link outside root.
                            val target = folder(it.name)
                            if (!target.deleteRecursively()) error("部分复盘文件暂未清理，下次重试")
                        }
                        // Old analysis versions are removed only when no editor holds the folder.
                        val referenced = args["results"] as? Map<*, *>
                        referenced?.forEach { (key, resultName) ->
                            if (key is String && resultName is String && key !in active) {
                                val dir = folder(key)
                                resultFile(dir, resultName) // Validate the retained filename too.
                                dir.listFiles()?.filter { it.name.startsWith("result-") && it.name != resultName }?.forEach {
                                    val target = resultFile(dir, it.name).canonicalFile
                                    require(target.parentFile == dir.canonicalFile) { "结果文件越界" }
                                    if (!target.delete()) error("旧结果暂未清理，下次重试")
                                }
                            }
                        }
                        null
                    }
                    "frame" -> {
                        val time = (args["t"] as Number).toLong()
                        var data: Map<String, Any>? = null
                        VideoFrames(File(folder(name!!), "video")).read(time, Long.MAX_VALUE, cancelled) { t, get ->
                            val bitmap = get()
                            try {
                                val bytes = ByteArrayOutputStream()
                                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, bytes)
                                data = mapOf("t" to t, "bytes" to bytes.toByteArray())
                            } finally { bitmap.recycle() }
                            false
                        }
                        data ?: error("此时间没有可读取的视频帧")
                    }
                    "analyze" -> analyze(folder(name!!), args)
                    else -> throw IllegalArgumentException("不支持的复盘操作")
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error(if (cancelled.get()) "cancelled" else "review_error", e.message ?: "视频处理失败", null) }
            }
        }
    }

    private fun metadata(dir: File): Map<String, Any> {
        val file = File(dir, "video")
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0
            require(duration > 0) { "无法读取视频时长" }
            return mapOf("folder" to dir.name, "uri" to file.toURI().toString(), "duration" to duration)
        } finally { retriever.release() }
    }

    private fun analyze(dir: File, args: Map<*, *>): Map<String, Any> {
        check(OpenCVLoader.initLocal()) { "杠铃追踪引擎未能加载" }
        val start = (args["start"] as Number).toLong()
        val end = (args["end"] as Number).toLong()
        require(start >= 0 && end > start && end - start <= 180000) { "请选择不超过 3 分钟的一组视频" }
        @Suppress("UNCHECKED_CAST")
        val anchors = (args["anchors"] as List<Map<String, Any?>>).sortedBy { (it["t"] as Number).toLong() }
        require(anchors.isNotEmpty()) { "请先标记杠铃片中心" }
        anchors.forEach {
            require((it["x"] as Number).toDouble() in 0.0..1.0 && (it["y"] as Number).toDouble() in 0.0..1.0)
            require((it["radius"] as Number).toDouble() in .02..0.3)
        }
        var pose: PoseLandmarker? = null
        var poseError: String? = null
        try {
            pose = PoseLandmarker.createFromOptions(context, PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetPath("pose_landmarker_lite.task").build())
                .setRunningMode(RunningMode.VIDEO).setNumPoses(1).build())
        } catch (_: Exception) { poseError = "骨架模型不可用，已保留杠铃分析" }
        val tracker = BarTracker()
        val frames = JSONArray()
        val times = JSONArray()
        var nextAnchor = 0
        var lastSample = -1000L
        var width = 0; var height = 0
        try {
            VideoFrames(File(dir, "video")).read(start, end, cancelled) { t, get ->
                times.put(t)
                var anchor: Map<String, Any?>? = null
                while (nextAnchor < anchors.size && (anchors[nextAnchor]["t"] as Number).toLong() <= t) {
                    anchor = anchors[nextAnchor++]
                }
                if (t - lastSample >= 66 || anchor != null) {
                    lastSample = t
                    val bitmap = get()
                    try {
                        width = bitmap.width; height = bitmap.height
                        val point = tracker.update(bitmap, anchor)
                        val row = JSONObject().put("t", t).put("x", point?.x ?: JSONObject.NULL).put("y", point?.y ?: JSONObject.NULL)
                        val landmarks = JSONArray()
                        if (pose != null) {
                            val input = BitmapImageBuilder(bitmap).build()
                            try {
                                pose!!.detectForVideo(input, t).landmarks().firstOrNull()?.forEach { p ->
                                    landmarks.put(JSONObject().put("x", p.x()).put("y", p.y()).put("v", minOf(p.visibility().orElse(0f), p.presence().orElse(0f))))
                                }
                            } catch (_: Exception) {
                                poseError = "部分骨架无法识别，杠铃分析仍可查看"
                                pose?.close(); pose = null
                            } finally { input.close() }
                        }
                        row.put("pose", landmarks); frames.put(row)
                    } finally { bitmap.recycle() }
                    val progress = (t - start).toDouble() / (end - start)
                    main.post { sink?.success(mapOf("folder" to dir.name, "progress" to progress)) }
                }
                true
            }
        } finally { tracker.close(); pose?.close() }
        check(frames.length() > 1) { "片段没有足够的有效视频帧" }
        if (cancelled.get()) throw java.util.concurrent.CancellationException("已取消分析")
        val payload = JSONObject().put("version", 1).put("algorithm", "lk-fb-1").put("model", "pose-lite-f16-1")
            .put("width", width).put("height", height).put("frames", frames).put("times", times).put("poseError", poseError ?: JSONObject.NULL)
        val name = "result-${UUID.randomUUID()}.json"
        resultFile(dir, name).writeText(payload.toString())
        return mapOf("result" to name)
    }
}
