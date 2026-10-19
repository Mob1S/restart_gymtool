package com.mobis.gym_tracker.review

import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/** Bounded-memory decoding; timestamps are presentation timestamps, never FPS estimates. */
class VideoFrames(private val file: File) {
    fun read(startMs: Long, endMs: Long, cancelled: AtomicBoolean,
             visit: (Long, () -> Bitmap) -> Boolean) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: error("文件没有视频轨道")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) format.getInteger(MediaFormat.KEY_ROTATION) else 0
            format.setInteger(MediaFormat.KEY_ROTATION, 0)
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(format, null, null, 0)
            extractor.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            decoder.start()
            var inputDone = false
            var lastTimestamp = -1L
            var lastActivity = System.nanoTime()
            val info = MediaCodec.BufferInfo()
            while (true) {
                if (cancelled.get()) throw CancellationException("已取消分析")
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val buffer = decoder.getInputBuffer(index)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                        lastActivity = System.nanoTime()
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, 10000)
                if (index >= 0) {
                    lastActivity = System.nanoTime()
                    var keepGoing = true
                    try {
                        val t = info.presentationTimeUs / 1000
                        if (t > endMs) return
                        if (info.size > 0 && t >= startMs && t > lastTimestamp) {
                            lastTimestamp = t
                            keepGoing = visit(t) {
                                val frame = decoder.getOutputImage(index) ?: error("此视频解码器不支持图像读取")
                                try { toBitmap(frame, rotation) } finally { frame.close() }
                            }
                        }
                    } finally { decoder.releaseOutputBuffer(index, false) }
                    if (!keepGoing || info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                } else if ((System.nanoTime() - lastActivity) > 30_000_000_000L) {
                    error("视频解码超时，请换一个视频重试")
                }
            }
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            codec?.release()
            extractor.release()
        }
    }

    private fun toBitmap(image: Image, rotation: Int): Bitmap {
        val crop = image.cropRect
        val scale = max(1, (max(crop.width(), crop.height()) + 639) / 640)
        val width = max(1, crop.width() / scale)
        val height = max(1, crop.height() / scale)
        val pixels = IntArray(width * height)
        fun value(plane: Int, x: Int, y: Int): Int {
            val p = image.planes[plane]
            return p.buffer.get(p.buffer.position() + y * p.rowStride + x * p.pixelStride).toInt() and 255
        }
        for (y in 0 until height) for (x in 0 until width) {
            val sx = crop.left + x * scale
            val sy = crop.top + y * scale
            val yy = value(0, sx, sy)
            val u = value(1, sx / 2, sy / 2) - 128
            val v = value(2, sx / 2, sy / 2) - 128
            val c = max(0, yy - 16)
            val r = ((298 * c + 409 * v + 128) shr 8).coerceIn(0, 255)
            val g = ((298 * c - 100 * u - 208 * v + 128) shr 8).coerceIn(0, 255)
            val b = ((298 * c + 516 * u + 128) shr 8).coerceIn(0, 255)
            pixels[y * width + x] = (255 shl 24) or (r shl 16) or (g shl 8) or b
        }
        val bitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        if (rotation == 0) return bitmap
        val result = Bitmap.createBitmap(bitmap, 0, 0, width, height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
        if (result !== bitmap) bitmap.recycle()
        return result
    }
}
