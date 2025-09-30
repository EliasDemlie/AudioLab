package com.beamlinetech.audiolab.recorder

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import java.io.File
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max

/** Decodes audio into a fixed-size envelope without retaining the PCM recording. */
object RecordingWaveform {
    private data class CacheKey(
        val path: String,
        val length: Long,
        val modifiedAt: Long,
        val sampleCount: Int,
    )

    // Accessed on RecordingFiles.io. Reopening the same editor avoids decoding again.
    private var cachedKey: CacheKey? = null
    private var cachedWaveform: Map<String, Any>? = null

    /** Must run on RecordingFiles.io, alongside the other serialized file operations. */
    fun extract(source: File, sampleCount: Int): Map<String, Any> {
        require(source.isFile) { "Recording file was not found." }
        val key = CacheKey(source.absolutePath, source.length(), source.lastModified(), sampleCount)
        if (cachedKey == key) cachedWaveform?.let { return it }

        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(source.absolutePath)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: error("No audio was found in this recording.")
            val format = extractor.getTrackFormat(track)
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION)
            } else {
                (RecordingFiles.durationMillis(source) ?: 0L) * 1_000L
            }
            require(durationUs > 0) { "The recording duration is unavailable." }
            extractor.selectTrack(track)

            val mime = requireNotNull(format.getString(MediaFormat.KEY_MIME))
            val codec = MediaCodec.createDecoderByType(mime)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            val peaks = DoubleArray(sampleCount)
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var outputEnded = false
            var decodedFrames = 0L
            var lastProgress = SystemClock.elapsedRealtime()

            while (!outputEnded) {
                check(!Thread.currentThread().isInterrupted) { "Waveform loading was interrupted." }
                check(SystemClock.elapsedRealtime() - lastProgress < 15_000L) {
                    "The audio decoder stopped responding. Try loading the waveform again."
                }
                if (!inputEnded) {
                    val inputIndex = codec.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val input = requireNotNull(codec.getInputBuffer(inputIndex))
                        input.clear()
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(
                                inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                            )
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(inputIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                }

                when (val outputIndex = codec.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val outputFormat = codec.outputFormat
                        sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        encoding = if (outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        } else AudioFormat.ENCODING_PCM_16BIT
                        require(
                            encoding == AudioFormat.ENCODING_PCM_16BIT ||
                                encoding == AudioFormat.ENCODING_PCM_FLOAT,
                        ) { "This recording's decoded audio format is unsupported." }
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                    else -> if (outputIndex >= 0) {
                        try {
                            val output = codec.getOutputBuffer(outputIndex)
                            if (output != null && info.size > 0 &&
                                info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                            ) {
                                require(sampleRate > 0 && channels > 0) {
                                    "The decoded audio format is invalid."
                                }
                                output.order(ByteOrder.nativeOrder())
                                output.limit(info.offset + info.size)
                                output.position(info.offset)
                                val sampleBytes = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                                val frameCount = output.remaining() / (channels * sampleBytes)
                                for (frame in 0 until frameCount) {
                                    var peak = 0.0
                                    repeat(channels) {
                                        val amplitude = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) {
                                            abs(output.float.toDouble())
                                        } else abs(output.short.toInt()) / 32768.0
                                        if (amplitude.isFinite()) peak = max(peak, amplitude)
                                    }
                                    val sampleUs = info.presentationTimeUs + frame * 1_000_000L / sampleRate
                                    val bin = ((sampleUs.toDouble() / durationUs) * sampleCount)
                                        .toInt().coerceIn(0, sampleCount - 1)
                                    peaks[bin] = max(peaks[bin], peak.coerceAtMost(1.0))
                                }
                                decodedFrames += frameCount
                            }
                            outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        } finally {
                            codec.releaseOutputBuffer(outputIndex, false)
                        }
                        lastProgress = SystemClock.elapsedRealtime()
                    }
                }
            }
            check(decodedFrames > 0) { "No audio samples could be decoded." }
            val loudest = peaks.maxOrNull() ?: 0.0
            val waveform = mapOf<String, Any>(
                "durationMillis" to (durationUs / 1_000L).coerceAtLeast(1L),
                "peaks" to peaks.map { if (loudest > 0.0) it / loudest else 0.0 },
            )
            cachedKey = key
            cachedWaveform = waveform
            return waveform
        } finally {
            decoder?.runCatching { stop() }
            decoder?.runCatching { release() }
            extractor.release()
        }
    }
}
