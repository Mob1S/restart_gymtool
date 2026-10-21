package com.mobis.gym_tracker.review

import android.content.Context
import android.graphics.*
import android.view.Surface
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import org.json.JSONArray
import org.json.JSONObject
import org.opencv.android.OpenCVLoader

class MotionEngine(context: Context) : AutoCloseable {
    private val tracker = BarTracker()
    private var last = -1L
    private var segment = 0
    private var anchored = false
    private val pose: PoseLandmarker?
    private var poseError: String? = null
    init {
        check(OpenCVLoader.initLocal()) { "OpenCV 无法初始化" }
        pose = try { PoseLandmarker.createFromOptions(context, PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("pose_landmarker_lite.task").build())
            .setRunningMode(RunningMode.VIDEO).setNumPoses(1).build()) }
        catch(e: Exception) {poseError="骨架模型加载失败：${e.message}";null}
    }
    fun frame(bitmap: Bitmap, t: Long, anchor: Map<String, Any?>?): JSONObject {
        val began=System.nanoTime()
        val gap=last>=0 && (t-last>250 || t<=last)
        if(gap) tracker.close()
        if(anchor!=null) { segment++;anchored=true }
        last=t
        val point=tracker.update(bitmap,anchor)
        val landmarks=JSONArray()
        if(pose!=null) {
            val input=BitmapImageBuilder(bitmap).build()
            try { pose.detectForVideo(input,t).landmarks().firstOrNull()?.forEach { p ->
                landmarks.put(JSONObject().put("x",p.x()).put("y",p.y()).put("v",minOf(p.visibility().orElse(0f),p.presence().orElse(0f))))
            } } catch(e: Exception) {poseError="本帧骨架不可用：${e.message}"} finally {input.close()}
        }
        return JSONObject().put("t",t).put("x",point?.x ?: JSONObject.NULL).put("y",point?.y ?: JSONObject.NULL)
            .put("pose",landmarks).put("segment",segment).put("width",bitmap.width).put("height",bitmap.height)
            .put("missingReason",if(point!=null) JSONObject.NULL else if(!anchored) "unmarked" else if(gap) "gap" else "lost")
            .put("poseError",poseError ?: JSONObject.NULL).put("processingMs",(System.nanoTime()-began)/1e6)
    }
    fun mark(bitmap:Bitmap, anchor:Map<String,Any?>) {tracker.update(bitmap,anchor);segment++;anchored=true}
    override fun close() {tracker.close();pose?.close()}
}

/** Image and overlays are rendered together; platform channels carry observations, never frame pixels. */
class MotionRenderer(private val surface: Surface) {
    @Volatile var skeleton=true
    @Volatile var trajectory=true
    private val path=mutableListOf<JSONObject>()
    @Volatile var radius=.08
    fun draw(bitmap: Bitmap, row: JSONObject) {
        val c=surface.lockCanvas(null)
        try {
            c.drawColor(Color.BLACK)
            c.drawBitmap(bitmap,null,Rect(0,0,c.width,c.height),null)
            val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply {strokeWidth=2.5f;style=Paint.Style.STROKE}
            fun position(p: JSONObject)=PointF((p.getDouble("x")*c.width).toFloat(),(p.getDouble("y")*c.height).toFloat())
            path.add(row)
            if(path.size>6000)path.removeAt(0)
            if(trajectory) for(i in 1 until path.size) {
                val a=path[i-1];val b=path[i]
                if(a.isNull("x")||b.isNull("x")||b.getLong("t")-a.getLong("t")>250||a.getInt("segment")!=b.getInt("segment"))continue
                paint.color=if(b.getDouble("y")>=a.getDouble("y"))Color.rgb(255,170,70)else Color.CYAN
                val p=position(a);val q=position(b);c.drawLine(p.x,p.y,q.x,q.y,paint)
            }
            if(!row.isNull("x")) {paint.color=Color.YELLOW;val p=position(row);c.drawCircle(p.x,p.y,5f,paint);c.drawCircle(p.x,p.y,(radius*minOf(c.width,c.height)).toFloat(),paint)}
            if(skeleton) {
                val pose=row.getJSONArray("pose");paint.color=Color.GREEN
                for(edge in listOf(11 to 13,13 to 15,12 to 14,14 to 16,11 to 12,11 to 23,12 to 24,23 to 24)) {
                    if(pose.length()<=edge.second)continue
                    val a=pose.getJSONObject(edge.first);val b=pose.getJSONObject(edge.second)
                    if(a.getDouble("v")<.7||b.getDouble("v")<.7)continue
                    val p=position(a);val q=position(b);c.drawLine(p.x,p.y,q.x,q.y,paint);c.drawCircle(p.x,p.y,3f,paint);c.drawCircle(q.x,q.y,3f,paint)
                }
            }
        } finally {surface.unlockCanvasAndPost(c)}
    }
    fun reset() {path.clear()}
}

fun JSONObject.channelMap(): Map<String,Any?> = keys().asSequence().associateWith {key ->
    when(val value=get(key)) {JSONObject.NULL->null;is JSONObject->value.channelMap();is JSONArray->value.channelList();else->value}
}
fun JSONArray.channelList(): List<Any?> = (0 until length()).map {i -> when(val value=get(i)) {
    JSONObject.NULL->null;is JSONObject->value.channelMap();is JSONArray->value.channelList();else->value
}}
