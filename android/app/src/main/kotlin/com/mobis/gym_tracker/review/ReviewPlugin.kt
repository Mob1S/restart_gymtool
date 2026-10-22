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
import java.util.concurrent.ExecutorService
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

class ReviewPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var worker: ExecutorService? = null
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var cancelled = AtomicBoolean(false)
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingCamera: (() -> Unit)? = null
    private lateinit var texture: TextureRegistry.SurfaceTextureEntry
    private lateinit var previewSurface: Surface
    private lateinit var renderer: MotionRenderer
    private lateinit var textures: TextureRegistry
    private var mediaReady = false
    private var accepting = true // Existing bridge callers remain compatible.
    private var closing = false
    @Volatile private var generation = 0L
    @Volatile private var cameraRequest = 0L
    private var pendingCameraResult: MethodChannel.Result? = null
    private val closeResults = mutableListOf<MethodChannel.Result>()
    private val cameraClosures = CopyOnWriteArrayList<CompletableFuture<Unit>>()
    private var showSkeleton = true
    private var showTrajectory = true
    @Volatile private var camera: MotionCamera? = null
    private var sink: EventChannel.EventSink? = null
    private val active = mutableSetOf<String>()
    private val root get() = File(context.noBackupFilesDir, "video_reviews").apply { mkdirs() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textures = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, "gym_tracker/review").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "gym_tracker/review_progress").also { it.setStreamHandler(this) }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        accepting=false;closeResources(null);sink=null
        channel.setMethodCallHandler(null); events.setStreamHandler(null)
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }
    override fun onAttachedToActivity(binding:ActivityPluginBinding){activity=binding.activity;activityBinding=binding;binding.addRequestPermissionsResultListener(this)}
    override fun onDetachedFromActivityForConfigChanges(){onDetachedFromActivity()}
    override fun onReattachedToActivityForConfigChanges(binding:ActivityPluginBinding){onAttachedToActivity(binding)}
    override fun onDetachedFromActivity(){closeResources(null);activityBinding?.removeRequestPermissionsResultListener(this);activityBinding=null;activity=null}
    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray):Boolean {
        if(requestCode!=621)return false
        val action=pendingCamera;pendingCamera=null;action?.invoke();return true
    }
    private fun emit(event:Map<String,Any?>, owner:Long){main.post {
        if(owner==generation && accepting && !closing && mediaReady)sink?.success(event + ("textureId" to texture.id()))
    }}

    private fun ensureWorker(): ExecutorService = worker ?: Executors.newSingleThreadExecutor().also {worker=it}
    private fun ensureMedia() {
        if(mediaReady)return
        texture=textures.createSurfaceTexture()
        texture.surfaceTexture().setDefaultBufferSize(640,480)
        previewSurface=Surface(texture.surfaceTexture());renderer=MotionRenderer(previewSurface)
        renderer.skeleton=showSkeleton;renderer.trajectory=showTrajectory
        mediaReady=true
    }

    /** Acknowledge only after camera callbacks, queued work and worker shutdown finish. */
    private fun closeResources(result:MethodChannel.Result?) {
        result?.let {closeResults.add(it)}
        if(closing)return
        closing=true;generation++;cameraRequest++;cancelled.set(true)
        pendingCamera=null
        pendingCameraResult?.error("cancelled","已取消摄像头操作",null);pendingCameraResult=null
        val ownedCamera=camera;camera=null
        val ownedWorker=worker
        ownedCamera?.let {cameraClosures.add(it.close())}
        val cameraClosed=CompletableFuture.allOf(*cameraClosures.toTypedArray())
        cameraClosed.whenComplete {_,cameraError->
            // Wait off the UI thread, including any synchronous native frame work.
            CompletableFuture.runAsync {
                var failure:Throwable?=cameraError
                try {
                    ownedWorker?.shutdown()
                    if(ownedWorker!=null && !ownedWorker.awaitTermination(30,TimeUnit.SECONDS))error("媒体任务尚未关闭")
                }catch(error:Throwable){failure=error}
                main.post {
                    if(failure==null) {
                        worker=null
                        if(mediaReady){renderer.reset();previewSurface.release();texture.release();mediaReady=false}
                        // A cancelled analysis can still have unsaved media in
                        // its editor. Only plugin deactivation revokes all holds;
                        // normal session cleanup releases each folder explicitly.
                        if(!accepting)active.clear()
                        cameraClosures.clear()
                    }
                    closing=false
                    val waiting=closeResults.toList();closeResults.clear()
                    waiting.forEach {if(failure==null)it.success(null)else it.error("close_failed","媒体资源尚未关闭，请重试",null)}
                }
            }
        }
    }

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
        if(call.method=="capabilities") {result.success(mapOf("supported" to true));return}
        if(call.method=="deactivate") {accepting=false;closeResources(result);return}
        if(call.method=="activate") {
            if(closing){result.error("busy","媒体会话正在关闭",null);return}
            if(worker?.isShutdown==true){result.error("close_failed","媒体资源尚未关闭，请先重试停用",null);return}
            accepting=true;result.success(null);return
        }
        if (call.method == "cancel" || call.method == "close") {closeResources(result);return}
        if(!accepting){result.error("pluginDisabled","动作分析已停用",null);return}
        if(closing){result.error("busy","媒体会话正在关闭",null);return}
        val ownerGeneration=generation
        if(call.method=="renderOptions") {
            showSkeleton=immediate["skeleton"]!=false;showTrajectory=immediate["trajectory"]!=false
            if(mediaReady){renderer.skeleton=showSkeleton;renderer.trajectory=showTrajectory}
            result.success(null);return
        }
        val executor=ensureWorker()
        if(call.method=="camera") {
            val request=++cameraRequest
            pendingCameraResult?.error("cancelled","已取消上次摄像头操作",null)
            pendingCameraResult=null;pendingCamera=null
            val owner=activity
            if(owner==null){result.error("camera_error","摄像头需要前台页面",null);return}
            val open:()->Unit={
                pendingCameraResult=null
                if(ownerGeneration!=generation || request!=cameraRequest || !accepting)result.error("cancelled","已取消摄像头操作",null)
                else if(owner.checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED)result.error("camera_permission","摄像头权限被拒绝，请在系统设置中允许",null)
                else {
                    ensureMedia()
                    val previous=camera;camera=null
                    previous?.let {cameraClosures.add(it.close())}
                    // Another superseded request may already be closing the
                    // previous camera. The newest request waits for it too.
                    val ready=CompletableFuture.allOf(*cameraClosures.toTypedArray())
                    ready.whenComplete {_,closeError->main.post {
                        if(ownerGeneration!=generation || request!=cameraRequest || !accepting)result.error("cancelled","已取消摄像头操作",null)
                        else if(closeError!=null)result.error("camera_error","上次摄像头尚未关闭",null)
                        else {
                            renderer.reset()
                            camera=MotionCamera(owner,executor,root,renderer,{event->if(request==cameraRequest)emit(event,ownerGeneration)})
                            camera!!.open(immediate["deviceId"] as? String,immediate["session"] as String){value,error->main.post {
                                if(ownerGeneration!=generation || request!=cameraRequest)result.error("cancelled","已取消摄像头操作",null)
                                else if(error==null)result.success(value?.plus("textureId" to texture.id()))else result.error("camera_error",error,null)
                            }}
                        }
                    }}
                }
            }
            if(owner.checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){pendingCamera=open;pendingCameraResult=result;owner.requestPermissions(arrayOf(Manifest.permission.CAMERA),621)}else open()
            return
        }
        if(call.method=="mark"){@Suppress("UNCHECKED_CAST") val anchor=immediate["anchor"] as Map<String,Any?>;camera?.mark(anchor);result.success(null);return}
        if(call.method=="freezeCamera"){camera?.freeze {main.post {result.success(null)}} ?: result.success(null);return}
        if(call.method=="startCamera"){camera?.start {error->main.post{if(error==null)result.success(null)else result.error("record_error",error,null)}} ?: result.error("camera_error","摄像头尚未准备",null);return}
        val token=if(call.method in listOf("analyze","frame","import")){cancelled.set(true);AtomicBoolean(false).also {cancelled=it}}else cancelled
        if(call.method=="analyze")ensureMedia()
        executor.execute {
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val name = args["folder"] as? String
                val value: Any? = when (call.method) {
                    "stopCamera" -> {val owned=camera;val value=owned?.stop(args["interrupted"]==true) ?: emptyMap();owned?.let {cameraClosures.add(it.close())};camera=null;(value["folder"] as? String)?.let {active.add(it)};value}
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
                    "analyze" -> analyze(folder(name!!), args, token, ownerGeneration)
                    else -> throw IllegalArgumentException("不支持的复盘操作")
                }
                main.post {if(ownerGeneration==generation)result.success(value)else result.error("cancelled","已取消",null)}
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

    private fun analyze(dir: File, args: Map<*, *>, token: AtomicBoolean, ownerGeneration:Long): Map<String, Any> {
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
                        emit(mapOf("session" to args["session"],"folder" to dir.name,"frame" to row.channelMap(),"progress" to progress,"phase" to "analyzing"),ownerGeneration)
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
