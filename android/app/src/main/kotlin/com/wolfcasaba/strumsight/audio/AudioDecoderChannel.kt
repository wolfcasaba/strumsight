package com.wolfcasaba.strumsight.audio

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Compressed audio file -> mono float32 PCM, fully on device, no network.
 *
 * Only the FIRST track whose MIME starts with "audio/" is ever selected, so an
 * MP4 that also carries a picture track decodes its soundtrack and nothing
 * else. All work runs on a dedicated [HandlerThread]; replies are posted back
 * to the main looper, because a MethodChannel.Result must be answered on the
 * platform thread.
 *
 * `decodeToPcm(path, targetSampleRate?, maxSeconds?)` replies with
 * `sampleRate`, `channelCount` (always 1), `frames`, and `pcm` — a ByteArray of
 * little-endian float32 samples, which the StandardMessageCodec hands to Dart
 * as a Uint8List. Bytes rather than a Float64List keep the payload at 4 bytes
 * per frame instead of 8. `targetSampleRate` is optional: absent, the decoder's
 * own output rate survives and nothing is resampled. `maxSeconds` stops the
 * decode early instead of failing.
 *
 * `probe(path)` reports `durationMs` (negative when undeclared), `sampleRate`,
 * `channelCount` and `mime` without decoding a frame.
 *
 * Errors arrive as PlatformException with the stable codes `no_audio_track`,
 * `unsupported_container`, `decoder_failed`, `file_not_found` and `too_long`.
 * No manifest permission is involved: paths come from the Storage Access
 * Framework, which grants per-file access to the app already.
 */
class AudioDecoderChannel(messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val worker = HandlerThread("strumsight-audio-decoder").apply { start() }
    private val workerHandler = Handler(worker.looper)
    private val mainHandler = Handler(Looper.getMainLooper())

    init { channel.setMethodCallHandler(this) }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.quitSafely()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error(ERR_FILE_NOT_FOUND, "path argument is required", null)
            return
        }
        when (call.method) {
            "decodeToPcm" -> {
                val rate = call.argument<Int>("targetSampleRate")
                val maxSeconds = call.argument<Double>("maxSeconds")
                offMainThread(result) { decodeToPcm(path, rate, maxSeconds) }
            }
            "probe" -> offMainThread(result) { probe(path) }
            else -> result.notImplemented()
        }
    }

    private fun offMainThread(result: MethodChannel.Result, work: () -> Map<String, Any?>) {
        workerHandler.post {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (error: DecodeException) {
                mainHandler.post { result.error(error.code, error.message, null) }
            } catch (error: Throwable) {
                val detail = error.message ?: error.javaClass.simpleName
                mainHandler.post { result.error(ERR_DECODER_FAILED, detail, null) }
            }
        }
    }

    private fun probe(path: String): Map<String, Any?> {
        val extractor = openExtractor(path)
        try {
            val format = extractor.getTrackFormat(firstAudioTrack(extractor))
            return mapOf(
                "durationMs" to durationUs(format) / 1000L,
                "sampleRate" to format.getInteger(MediaFormat.KEY_SAMPLE_RATE),
                "channelCount" to format.getInteger(MediaFormat.KEY_CHANNEL_COUNT),
                "mime" to (format.getString(MediaFormat.KEY_MIME) ?: ""),
            )
        } finally {
            extractor.release()
        }
    }

    private fun decodeToPcm(path: String, targetRate: Int?, maxSeconds: Double?): Map<String, Any?> {
        val extractor = openExtractor(path)
        var codec: MediaCodec? = null
        try {
            val track = firstAudioTrack(extractor)
            val format = extractor.getTrackFormat(track)
            if (maxSeconds == null && durationUs(format) > MAX_DURATION_US) {
                throw DecodeException(ERR_TOO_LONG, "clip longer than the decode budget")
            }
            val mime = format.getString(MediaFormat.KEY_MIME)
                ?: throw DecodeException(ERR_NO_AUDIO_TRACK, "track declares no mime type")
            extractor.selectTrack(track)
            codec = try {
                MediaCodec.createDecoderByType(mime)
            } catch (error: Exception) {
                throw DecodeException(ERR_UNSUPPORTED_CONTAINER, "no decoder for $mime")
            }
            codec.configure(format, null, null, 0)
            codec.start()
            val decoded = drain(extractor, codec, format, maxSeconds)
            val rate = if (targetRate != null && targetRate > 0) targetRate else decoded.second
            val pcm = resample(decoded.first, decoded.second, rate)
            return mapOf(
                "sampleRate" to rate,
                "channelCount" to 1,
                "frames" to pcm.size,
                "pcm" to littleEndianBytes(pcm),
            )
        } finally {
            val open = codec
            if (open != null) {
                // A codec that never started throws from stop(); release must still run.
                try { open.stop() } catch (ignored: Throwable) { }
                open.release()
            }
            extractor.release()
        }
    }

    private fun drain(
        extractor: MediaExtractor, codec: MediaCodec,
        inputFormat: MediaFormat, maxSeconds: Double?,
    ): Pair<FloatArray, Int> {
        var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var encoding = AudioFormat.ENCODING_PCM_16BIT
        var maxFrames = frameBudget(maxSeconds, sampleRate)
        val sink = FloatSink()
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var done = false
        while (!done) {
            if (!inputDone) inputDone = feed(extractor, codec)
            val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val output = codec.outputFormat
                sampleRate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                if (output.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    encoding = output.getInteger(MediaFormat.KEY_PCM_ENCODING)
                }
                maxFrames = frameBudget(maxSeconds, sampleRate)
            } else if (index >= 0) {
                val buffer = if (info.size > 0) codec.getOutputBuffer(index) else null
                if (buffer != null) {
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    appendMono(buffer, encoding, channels, sink, maxFrames)
                }
                codec.releaseOutputBuffer(index, false)
                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) done = true
            }
            if (sink.size >= maxFrames) done = true
        }
        if (sink.size == 0) throw DecodeException(ERR_DECODER_FAILED, "decoder produced no PCM")
        return Pair(sink.toArray(), sampleRate)
    }

    /** Queues one compressed access unit. Returns true once the stream is drained. */
    private fun feed(extractor: MediaExtractor, codec: MediaCodec): Boolean {
        val index = codec.dequeueInputBuffer(TIMEOUT_US)
        if (index < 0) return false
        val buffer = codec.getInputBuffer(index)
        val size = if (buffer == null) -1 else extractor.readSampleData(buffer, 0)
        if (size < 0) {
            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            return true
        }
        codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
        extractor.advance()
        return false
    }

    /** Averages every source channel into one float per frame, up to [maxFrames]. */
    private fun appendMono(
        buffer: ByteBuffer, encoding: Int, channelCount: Int,
        sink: FloatSink, maxFrames: Int,
    ) {
        val channels = if (channelCount > 0) channelCount else 1
        val ordered = buffer.order(ByteOrder.nativeOrder())
        when (encoding) {
            AudioFormat.ENCODING_PCM_FLOAT -> {
                val floats = ordered.asFloatBuffer()
                while (floats.remaining() >= channels && sink.size < maxFrames) {
                    var sum = 0.0f
                    repeat(channels) { sum += floats.get() }
                    sink.add(sum / channels)
                }
            }
            AudioFormat.ENCODING_PCM_16BIT -> {
                val shorts = ordered.asShortBuffer()
                while (shorts.remaining() >= channels && sink.size < maxFrames) {
                    var sum = 0.0f
                    repeat(channels) { sum += shorts.get() / 32768.0f }
                    sink.add(sum / channels)
                }
            }
            else -> throw DecodeException(ERR_DECODER_FAILED, "PCM encoding $encoding")
        }
    }

    private fun openExtractor(path: String): MediaExtractor {
        val file = File(path)
        if (!file.isFile || !file.canRead()) {
            throw DecodeException(ERR_FILE_NOT_FOUND, "no readable file at the given path")
        }
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
        } catch (error: Exception) {
            extractor.release()
            throw DecodeException(ERR_UNSUPPORTED_CONTAINER, "cannot open container")
        }
        return extractor
    }

    /** The first track the container declares as "audio/..." — never another kind. */
    private fun firstAudioTrack(extractor: MediaExtractor): Int {
        for (index in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
            if (mime != null && mime.startsWith("audio/")) return index
        }
        throw DecodeException(ERR_NO_AUDIO_TRACK, "container declares no audio track")
    }

    private fun durationUs(format: MediaFormat): Long =
        if (format.containsKey(DURATION)) format.getLong(DURATION) else -1L

    private fun frameBudget(maxSeconds: Double?, rate: Int): Int {
        if (maxSeconds == null || maxSeconds <= 0.0 || rate <= 0) return Int.MAX_VALUE
        return (maxSeconds * rate).coerceAtMost(Int.MAX_VALUE.toDouble()).toInt()
    }

    /** Linear interpolation — cheap and good enough ahead of the analysis window. */
    private fun resample(input: FloatArray, from: Int, to: Int): FloatArray {
        if (from == to || from <= 0 || to <= 0 || input.isEmpty()) return input
        val length = (input.size.toLong() * to / from).toInt()
        if (length <= 0) return FloatArray(0)
        val output = FloatArray(length)
        val step = from.toDouble() / to.toDouble()
        for (i in 0 until length) {
            val position = i * step
            val low = position.toInt()
            val high = if (low + 1 < input.size) low + 1 else low
            val fraction = (position - low).toFloat()
            output[i] = input[low] * (1.0f - fraction) + input[high] * fraction
        }
        return output
    }

    private fun littleEndianBytes(pcm: FloatArray): ByteArray {
        val bytes = ByteArray(pcm.size * 4)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        for (sample in pcm) buffer.putFloat(sample)
        return bytes
    }

    private class DecodeException(val code: String, override val message: String) :
        RuntimeException(message)

    /** Growable float buffer — avoids boxing every sample into an ArrayList. */
    private class FloatSink {
        private var data = FloatArray(1 shl 16)
        var size = 0
            private set

        fun add(value: Float) {
            if (size == data.size) data = data.copyOf(data.size * 2)
            data[size++] = value
        }

        fun toArray(): FloatArray = data.copyOf(size)
    }

    companion object {
        const val CHANNEL_NAME = "strumsight/audio_decoder"

        private const val TIMEOUT_US = 10_000L
        private const val MAX_DURATION_US = 10L * 60L * 1_000_000L

        private const val ERR_NO_AUDIO_TRACK = "no_audio_track"
        private const val ERR_UNSUPPORTED_CONTAINER = "unsupported_container"
        private const val ERR_DECODER_FAILED = "decoder_failed"
        private const val ERR_FILE_NOT_FOUND = "file_not_found"
        private const val ERR_TOO_LONG = "too_long"

        private val DURATION = MediaFormat.KEY_DURATION
    }
}
