package com.mobis.gym_tracker.review

import android.graphics.Bitmap
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.video.Video
import kotlin.math.*

/** Conservative local translation tracker. A lost track stays lost until re-anchored. */
class BarTracker : AutoCloseable {
    private var previous: Mat? = null
    private var points = emptyList<Point>()
    private var center: Point? = null
    private var radius = 0.0
    private var template: Mat? = null
    private fun median(values: List<Double>) = values.sorted()[values.size / 2]

    fun update(bitmap: Bitmap, anchor: Map<String, Any?>?): Point? {
        val rgba = Mat()
        val gray = Mat()
        Utils.bitmapToMat(bitmap, rgba)
        Imgproc.cvtColor(rgba, gray, Imgproc.COLOR_RGBA2GRAY)
        rgba.release()
        try {
            if (anchor != null) {
                center = Point((anchor["x"] as Number).toDouble() * gray.cols(), (anchor["y"] as Number).toDouble() * gray.rows())
                radius = (anchor["radius"] as Number).toDouble() * min(gray.cols(), gray.rows())
                points = features(gray, center!!)
                template?.release(); template = patch(gray, center!!)
                // A user anchor is an observed point even when the region has no usable texture.
            } else if (previous != null && center != null && points.size >= 4) {
                val from = MatOfPoint2f(*points.toTypedArray())
                val next = MatOfPoint2f()
                val back = MatOfPoint2f()
                val status = MatOfByte()
                val backStatus = MatOfByte()
                val errors = MatOfFloat()
                val backErrors = MatOfFloat()
                try {
                    Video.calcOpticalFlowPyrLK(previous, gray, from, next, status, errors)
                    Video.calcOpticalFlowPyrLK(gray, previous, next, back, backStatus, backErrors)
                    val ns = next.toArray(); val bs = back.toArray()
                    val good = points.indices.filter {
                        status.toArray()[it].toInt() != 0 && backStatus.toArray()[it].toInt() != 0 &&
                        hypot(points[it].x - bs[it].x, points[it].y - bs[it].y) < 1.5 &&
                        errors.toArray()[it] < 25 && ns[it].x in 0.0..gray.cols().toDouble() && ns[it].y in 0.0..gray.rows().toDouble()
                    }
                    if (good.size < max(4, ceil(points.size * .6).toInt())) center = null
                    else {
                        val dx = median(good.map { ns[it].x - points[it].x })
                        val dy = median(good.map { ns[it].y - points[it].y })
                        val spread = median(good.map { hypot(ns[it].x - points[it].x - dx, ns[it].y - points[it].y - dy) })
                        val c = Point(center!!.x + dx, center!!.y + dy)
                        center = if (spread > 2.5 || hypot(dx, dy) > radius || c.x !in 0.0..gray.cols().toDouble() || c.y !in 0.0..gray.rows().toDouble()) null else c
                        if (center != null) {
                            val candidate = patch(gray, center!!)
                            val score = Mat()
                            try {
                                if (candidate == null || template == null || candidate.size() != template!!.size()) center = null
                                else {
                                    Imgproc.matchTemplate(candidate, template, score, Imgproc.TM_CCOEFF_NORMED)
                                    val similarity = score.get(0, 0)[0]
                                    if (!similarity.isFinite() || similarity < .65) center = null
                                    else Core.addWeighted(template, .95, candidate, .05, 0.0, template)
                                }
                            } finally { candidate?.release(); score.release() }
                        }
                        points = if (center == null) emptyList() else good.map { ns[it] }
                        // Replenish only after a valid step and only in the target region.
                        if (center != null && points.size < 12) points = features(gray, center!!)
                    }
                } finally { listOf(from, next, back, status, backStatus, errors, backErrors).forEach { it.release() } }
            } else center = null
            previous?.release()
            previous = gray.clone()
            return center?.let { Point(it.x / gray.cols(), it.y / gray.rows()) }
        } finally { gray.release() }
    }

    private fun patch(gray: Mat, c: Point): Mat? {
        val r = max(3, (radius * .65).roundToInt())
        val x = c.x.roundToInt() - r; val y = c.y.roundToInt() - r
        if (x < 0 || y < 0 || x + 2*r >= gray.cols() || y + 2*r >= gray.rows()) return null
        val view = gray.submat(Rect(x, y, 2*r+1, 2*r+1))
        return try { view.clone() } finally { view.release() }
    }

    private fun features(gray: Mat, c: Point): List<Point> {
        val mask = Mat.zeros(gray.size(), CvType.CV_8UC1)
        val corners = MatOfPoint()
        try {
            Imgproc.circle(mask, c, radius.roundToInt(), Scalar(255.0), -1)
            Imgproc.goodFeaturesToTrack(gray, corners, 60, .02, 4.0, mask)
            return corners.toList()
        } finally { mask.release(); corners.release() }
    }

    override fun close() { previous?.release(); previous = null; template?.release(); template = null; points = emptyList(); center = null }
}
