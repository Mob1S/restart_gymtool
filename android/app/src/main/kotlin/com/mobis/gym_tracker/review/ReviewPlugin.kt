package com.mobis.gym_tracker.review

import android.content.Context
import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.view.Surface
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.view.TextureRegistry
import io.flutter.plugin.common.*
import org.json.JSONArray
import org.json.JSONObject
import org.opencv.android.OpenCVLoader
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class ReviewPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var cancelled = AtomicBoolean(false)
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingCamera: (() -> Unit)? = null
    private lateinit var texture: TextureRegistry.SurfaceTextureEntry
    private lateinit var previewSurface: Surface
    private lateinit var renderer: MotionRenderer
    private var camera: MotionCamera? = null
    private var sink: EventChannel.EventSink? = null
    private val active = mutableSetOf<String>()
    private val root get() = File(context.noBackupFilesDir, "video_reviews").apply { mkdirs() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        texture = binding.textureRegistry.createSurfaceTexture()
        texture.surfaceTexture().setDefaultBufferSize(640,480)
        previewSurface=Surface(texture.surfaceTexture());renderer=MotionRenderer(previewSurface)
        channel = MethodChannel(binding.binaryMessenger, "gym_tracker/review").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "gym_tracker/review_progress").also { it.setStreamHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cancelled.set(true);camera?.close();worker.shutdown();previewSurface.release();texture.release(); channel.setMethodCallHandler(null); events.setStreamHandler(null)
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }
    override fun onAttachedToActivity(binding:ActivityPluginBinding){activity=binding.activity;activityBinding=binding;binding.addRequestPermissionsResultListener(this)}
    override fun onDetachedFromActivityForConfigChanges(){onDetachedFromActivity()}
    override fun onReattachedToActivityForConfigChanges(binding:ActivityPluginBinding){onAttachedToActivity(binding)}
    override fun onDetachedFromActivity(){camera?.close();camera=null;activityBinding?.removeRequestPermissionsResultListener(this);activityBinding=null;activity=null;pendingCamera=null}
    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray):Boolean {
        if(requestCode!=621)return false
        val action=pendingCamera;pendingCamera=null;action?.invoke();return true
    }
    private fun emit(event:Map<String,Any?>){main.post {sink?.success(event + ("textureId" to texture.id()))}}

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
        val immediate=call.arguments as? Map<*,*> ?: emptyMap<Any,Any>()
        if (call.method == "cancel" || call.method == "close") { cancelled.set(true);camera?.close();camera=null; result.success(null); return }
        if(call.method=="camera") {
            val owner=activity
            if(owner==null){result.error("camera_error","摄像头需要前台页面",null);return}
            val open={
                if(owner.checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)result.error("camera_permission","摄像头权限被拒绝，请在系统设置中允许",null)
                else {
                    camera?.close();renderer.reset()
                    camera=MotionCamera(owner,worker,root,renderer,::emit)
                    camera!!.open(immediate["deviceId"] as? String,immediate["session"] as String){value,error->main.post {if(error==null)result.success(value)else result.error("camera_error",error,null)}}
                }
            }
            if(owner.checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){pendingCamera=open;owner.requestPermissions(arrayOf(Manifest.permission.CAMERA),621)}else open()
            return
        }
        if(call.method=="mark"){@Suppress("UNCHECKED_CAST") val anchor=immediate["anchor"] as Map<String,Any?>;camera?.mark(anchor);result.success(null);return}
        if(call.method=="freezeCamera"){camera?.freeze {main.post {result.success(null)}} ?: result.success(null);return}
        if(call.method=="renderOptions"){renderer.skeleton=immediate["skeleton"]!=false;renderer.trajectory=immediate["trajectory"]!=false;result.success(null);return}
        if(call.method=="startCamera"){camera?.start {error->main.post{if(error==null)result.success(null)else result.error("record_error",error,null)}} ?: result.error("camera_error","摄像头尚未准备",null);return}
        val token=if(call.method in listOf("analyze","frame","import")){cancelled.set(true);AtomicBoolean(false).also {cancelled=it}}else cancelled
        worker.execute {
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val name = args["folder"] as? String
                val value: Any? = when (call.method) {
                    "capabilities" -> mapOf("supported" to true,"textureId" to texture.id())
                    "stopCamera" -> {val value=camera?.stop(args["interrupted"]==true) ?: emptyMap();camera=null;(value["folder"] as? String)?.let {active.add(it)};value}
                    "import" -> {
                        val source = File(args["path"] as String)
                        require(source.isFile) { "视频文件不可读取" }
                        val dir = folder(UUID.randomUUID().toString()).apply { mkdirs() }
                        try {
                            require(dir.usableSpace > source.length() + 32 * 1024 * 1024) { "手机剩余空间不足" }
                            source.inputStream().use { input -> File(dir, "video").outputStream().use { output ->
                                val buffer = ByteArray(65536)
                                while (true) {
                                    if (token.get()) throw java.util.concurrent.CancellationException("已取消导入")
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
                        VideoFrames(File(folder(name!!), "video")).read(time, Long.MAX_VALUE, token) { t, get ->
                            val bitmap = get()
                            try {
                                val bytes = ByteArrayOutputStream()
                                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, bytes)
                                data = mapOf("t" to t, "bytes" to bytes.toByteArray(),"width" to bitmap.width,"height" to bitmap.height)
                            } finally { bitmap.recycle() }
                            false
                        }
                        data ?: error("此时间没有可读取的视频帧")
                    }
                    "analyze" -> analyze(folder(name!!), args, token)
                    else -> throw IllegalArgumentException("不支持的复盘操作")
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error(if (token.get()) "cancelled" else "review_error", e.message ?: "视频处理失败", null) }
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

    private fun analyze(dir: File, args: Map<*, *>, token: AtomicBoolean): Map<String, Any> {
        val start=(args["start"] as Number).toLong();val end=(args["end"] as Number).toLong()
        require(start>=0&&end>start&&end-start<=180000) {"请选择不超过 3 分钟的一组视频"}
        @Suppress("UNCHECKED_CAST")
        val anchors=(args["anchors"] as? List<Map<String,Any?>> ?: emptyList()).sortedBy {(it["t"] as Number).toLong()}
        anchors.forEach {require((it["x"] as Number).toDouble() in 0.0..1.0 && (it["y"] as Number).toDouble() in 0.0..1.0 && (it["radius"] as Number).toDouble() in .02..0.3)}
        val frames=JSONArray();val times=JSONArray();var next=0;var last=-1000L;var width=640;var height=360
        renderer.reset()
        MotionEngine(context).use {engine ->
            VideoFrames(File(dir,"video")).read(start,end,token) {t,get ->
                times.put(t)
                var anchor:Map<String,Any?>?=null
                while(next<anchors.size&&(anchors[next]["t"] as Number).toLong()<=t)anchor=anchors[next++]
                if(t-last>=66||anchor!=null) {
                    last=t
                    val bitmap=get()
                    try {
                        width=bitmap.width;height=bitmap.height
                        texture.surfaceTexture().setDefaultBufferSize(width,height)
                        anchor?.let {renderer.radius=(it["radius"] as Number).toDouble()}
                        val row=engine.frame(bitmap,t,anchor).put("session",args["session"]);frames.put(row);renderer.draw(bitmap,row)
                        val progress=(t-start).toDouble()/(end-start)
                        emit(mapOf("session" to args["session"],"folder" to dir.name,"frame" to row.channelMap(),"progress" to progress,"phase" to "analyzing"))
                    } finally {bitmap.recycle()}
                }
                true
            }
        }
        check(frames.length()>1) {"片段没有足够的可读取视频帧"}
        if(token.get())throw java.util.concurrent.CancellationException("已取消分析")
        val payload=JSONObject().put("version",2).put("algorithm","lk-fb-template-2").put("model","pose-lite-f16-1")
            .put("width",width).put("height",height).put("frames",frames).put("times",times).put("coordinateSpace","upright-normalized").put("rotationCorrected",true)
        val name="result-${UUID.randomUUID()}.json"
        val temp=File(dir,"pending-${UUID.randomUUID()}.json");temp.writeText(payload.toString())
        check(temp.renameTo(resultFile(dir,name))) {"分析结果保存失败"}
        return mapOf("result" to name,"data" to payload.channelMap())
    }
}
