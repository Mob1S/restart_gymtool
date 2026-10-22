package com.mobis.gym_tracker.review

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.ImageReader
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Size
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicBoolean

/** acquireLatestImage + one worker slot bounds memory and latency at the source. */
class MotionCamera(private val activity: Activity, private val worker: ExecutorService,
    private val root: File, private val renderer: MotionRenderer,
    private val emit: (Map<String,Any?>)->Unit) {
    private val manager=activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val thread=HandlerThread("motion-camera").apply {start()}
    private val handler=Handler(thread.looper)
    private val processing=AtomicBoolean(false)
    private var camera: CameraDevice?=null
    private var capture: CameraCaptureSession?=null
    private var reader: ImageReader?=null
    private var engine: MotionEngine?=null
    @Volatile private var closed=false
    @Volatile private var opening=false
    private val deviceClosed=CompletableFuture<Unit>()
    private val closedFuture=CompletableFuture<Unit>()
    private var openResult:((Map<String,Any?>?,String?)->Unit)?=null
    private var startResult:((String?)->Unit)?=null
    @Volatile private var recording=false
    @Volatile private var anchor: Map<String,Any?>?=null
    private var session=""
    private var rotation=0
    private var sensorRealtime=false
    private var origin=0L
    private var sensorOffset: Long?=null
    private var recordOrigin=0L
    private var recorder: MediaRecorder?=null
    private var dir: File?=null
    private var frames=JSONArray()
    private var times=JSONArray()
    private var dropped=0
    private var size=Size(640,480)
    private var lastTime=-1L
    @Volatile private var frozen=false
    private var lastBitmap:android.graphics.Bitmap?=null
    fun open(id: String?, session: String, done: (Map<String,Any?>?,String?)->Unit) {
        openResult=done
        fun complete(value:Map<String,Any?>?,error:String?){val callback=openResult;openResult=null;callback?.invoke(value,error)}
        this.session=session
        if(activity.checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED) {complete(null,"摄像头权限被拒绝，请在系统设置中允许");close();return}
        try {
            val selected=id ?: manager.cameraIdList.firstOrNull {manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING)==CameraCharacteristics.LENS_FACING_BACK}
                ?: manager.cameraIdList.firstOrNull() ?: error("没有可用摄像头")
            val characteristics=manager.getCameraCharacteristics(selected)
            val sensor=characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            @Suppress("DEPRECATION")
            val display=activity.windowManager.defaultDisplay.rotation*90
            val front=characteristics.get(CameraCharacteristics.LENS_FACING)==CameraCharacteristics.LENS_FACING_FRONT
            rotation=if(front)(sensor+display)%360 else (sensor-display+360)%360
            sensorRealtime=characteristics.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE)==CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE_REALTIME
            val config=characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
            val recordSizes=config.getOutputSizes(MediaRecorder::class.java).toList()
            size=config.getOutputSizes(ImageFormat.YUV_420_888).filter {candidate->recordSizes.any {it==candidate} && candidate.width<=1280 && candidate.height<=720}
                .minByOrNull {kotlin.math.abs(it.width-640)+kotlin.math.abs(it.height-480)} ?: error("摄像头不支持兼容的预览与录像尺寸")
            origin=SystemClock.elapsedRealtimeNanos()
            worker.execute {try {if(!closed)engine=MotionEngine(activity)}catch(e:Exception){emit(mapOf("session" to session,"error" to e.message,"phase" to "failed"))}}
            reader=ImageReader.newInstance(size.width,size.height,ImageFormat.YUV_420_888,3).also {it.setOnImageAvailableListener({source->
                val image=try {source.acquireLatestImage()}catch(_:Exception){null} ?: return@setOnImageAvailableListener
                if(closed||frozen||!processing.compareAndSet(false,true)){image.close();if(!frozen)dropped++;return@setOnImageAvailableListener}
                val timestamp=image.timestamp
                if(sensorOffset==null)sensorOffset=if(sensorRealtime)0 else SystemClock.elapsedRealtimeNanos()-timestamp
                val sourceTime=(timestamp+sensorOffset!!-origin)/1_000_000
                worker.execute {
                    try {
                        if(!closed&&engine!=null) {
                            val bitmap=VideoFrames(File(root,"unused")).toBitmap(image,rotation)
                            try {
                                val t=maxOf(lastTime+1,sourceTime);lastTime=t
                                val start=SystemClock.elapsedRealtimeNanos()
                                val mark=anchor;anchor=null
                                val row=engine!!.frame(bitmap,t,mark).put("session",session)
                                renderer.draw(bitmap,row)
                                val out=JSONObject(row.toString())
                                if(recording) {out.put("t",maxOf(0,t-recordOrigin));frames.put(out);times.put(out.getLong("t"))}
                                val elapsed=(SystemClock.elapsedRealtimeNanos()-start)/1e6
                                emit(mapOf("session" to session,"frame" to out.channelMap(),"phase" to if(recording)"recording"else"preview",
                                    "fps" to 1000.0/maxOf(1.0,elapsed),"latencyMs" to (SystemClock.elapsedRealtimeNanos()-timestamp-sensorOffset!!)/1e6,"dropped" to dropped))
                                if(recording&&out.getLong("t")>=180000)stop(false)
                            } finally {lastBitmap?.recycle();lastBitmap=bitmap}
                        }
                    } catch(e:Exception){if(recording)stop(true)else close();emit(mapOf("session" to session,"error" to (e.message ?: "摄像头分析失败"),"phase" to "failed"))}
                    finally {image.close();processing.set(false)}
                }
            },handler)}
            opening=true
            manager.openCamera(selected,object:CameraDevice.StateCallback(){
                override fun onOpened(device:CameraDevice){if(closed){device.close();return};camera=device;configure {error->
                    complete(if(error==null) mapOf("canRecord" to true,"devices" to manager.cameraIdList.map {mapOf("id" to it,"label" to "摄像头 $it")}) else null,error)
                }}
                override fun onClosed(device:CameraDevice){opening=false;deviceClosed.complete(Unit)}
                override fun onDisconnected(device:CameraDevice){device.close();emit(mapOf("session" to session,"error" to "摄像头已断开","phase" to "failed"));close()}
                override fun onError(device:CameraDevice,error:Int){device.close();complete(null,"摄像头被占用或无法启动（$error）");close()}
            },handler)
        }catch(e:Exception){opening=false;complete(null,e.message);close()}
    }
    @Suppress("DEPRECATION")
    private fun configure(done:(String?)->Unit) {
        val device=camera ?: return
        capture?.close()
        val outputs=mutableListOf(reader!!.surface)
        recorder?.surface?.let {outputs.add(it)}
        device.createCaptureSession(outputs,object:CameraCaptureSession.StateCallback(){
            override fun onConfigured(value:CameraCaptureSession){
                if(closed){value.close();return};capture=value
                try {
                    val request=device.createCaptureRequest(if(recorder==null)CameraDevice.TEMPLATE_PREVIEW else CameraDevice.TEMPLATE_RECORD)
                    outputs.forEach {request.addTarget(it)}
                    request.set(CaptureRequest.CONTROL_MODE,CaptureRequest.CONTROL_MODE_AUTO)
                    value.setRepeatingRequest(request.build(),null,handler)
                    done(null)
                }catch(e:Exception){done(e.message)}
            }
            override fun onConfigureFailed(value:CameraCaptureSession){done("摄像头无法同时提供预览与录像")}
        },handler)
    }
    fun freeze(done:()->Unit){frozen=true;worker.execute {done()}}
    fun mark(value:Map<String,Any?>){worker.execute {lastBitmap?.let {engine?.mark(it,value)};renderer.radius=(value["radius"] as Number).toDouble();frozen=false}}
    @Suppress("DEPRECATION")
    fun start(done:(String?)->Unit){
        if(closed){done("摄像头已关闭");return}
        if(recording){done(null);return}
        startResult=done
        fun complete(error:String?){val callback=startResult;startResult=null;callback?.invoke(error)}
        try {
            dir=File(root,UUID.randomUUID().toString()).apply {mkdirs()}
            recorder=MediaRecorder().apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE);setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264);setVideoSize(size.width,size.height);setVideoFrameRate(30)
                setVideoEncodingBitRate(3_000_000);setOrientationHint(rotation);setOutputFile(File(dir,"video").path);prepare()
            }
            handler.post {configure {error->
                if(error!=null){complete(error);return@configure}
                try {recorder!!.start();recordOrigin=(SystemClock.elapsedRealtimeNanos()-origin)/1_000_000;frames=JSONArray();times=JSONArray();recording=true;renderer.reset();complete(null)}
                catch(e:Exception){complete(e.message)}
            }}
        }catch(e:Exception){complete(e.message)}
    }
    fun stop(interrupted:Boolean): Map<String,Any?> {
        val wasRecording=recording;recording=false
        var recordError:String?=null
        try {if(wasRecording)recorder?.stop()}catch(e:Exception){recordError=e.message}
        close()
        if(!wasRecording)return emptyMap()
        val folder=dir!!
        val last=frames.optJSONObject(frames.length()-1)
        val data=JSONObject().put("version",2).put("algorithm","lk-fb-template-2").put("model","pose-lite-f16-1")
            .put("width",last?.optInt("width",640) ?: 640).put("height",last?.optInt("height",360) ?: 360).put("frames",frames).put("times",times)
        val name="result-${UUID.randomUUID()}.json"
        File(folder,name).writeText(data.toString())
        val result=mapOf("folder" to folder.name,"uri" to if(recordError==null)File(folder,"video").toURI().toString()else null,
            "result" to name,"data" to data.channelMap(),"duration" to (last?.optLong("t",0) ?: 0),"status" to if(interrupted||recordError!=null)"interrupted"else"stopped","canRecord" to (recordError==null))
        emit(mapOf("session" to session,"completed" to result,"phase" to result["status"]))
        return result
    }
    @Synchronized fun close():CompletableFuture<Unit>{
        if(closed)return closedFuture
        closed=true;recording=false
        val cleanup=CompletableFuture<Unit>()
        handler.post {
            openResult?.invoke(null,"摄像头已关闭");openResult=null
            startResult?.invoke("摄像头已关闭");startResult=null
            capture?.close();capture=null
            val device=camera;camera=null;device?.close()
            if(device==null&&!opening)deviceClosed.complete(Unit)
            reader?.setOnImageAvailableListener(null,null)
            worker.execute {
                try {
                    engine?.close();engine=null;lastBitmap?.recycle();lastBitmap=null
                    reader?.close();reader=null;recorder?.release();recorder=null
                    cleanup.complete(Unit)
                }catch(error:Throwable){cleanup.completeExceptionally(error)}
            }
        }
        CompletableFuture.allOf(deviceClosed,cleanup).whenComplete {_,error->
            thread.quitSafely()
            CompletableFuture.runAsync {
                thread.join(5000)
                if(error!=null)closedFuture.completeExceptionally(error)
                else if(thread.isAlive)closedFuture.completeExceptionally(IllegalStateException("摄像头线程尚未关闭"))
                else closedFuture.complete(Unit)
            }
        }
        return closedFuture
    }
}
