package com.example.finaudio

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfo

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "com.example.finaudio/newpipe"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            NewPipe.init(OkHttpDownloader.instance)
        } catch (e: Exception) {
            android.util.Log.e("FinAudio", "Failed to init NewPipe: ${e.message}")
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAudioStream" -> {
                    val videoId = call.argument<String>("videoId")
                    if (videoId.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "videoId must not be blank", null)
                        return@setMethodCallHandler
                    }
                    val quality = call.argument<String>("quality")?.lowercase() ?: "high"

                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val url = "https://www.youtube.com/watch?v=$videoId"
                            val streamInfo = StreamInfo.getInfo(ServiceList.YouTube, url)
                            val audioStreams = streamInfo.audioStreams

                            if (audioStreams.isNullOrEmpty()) {
                                withContext(Dispatchers.Main) {
                                    result.error("NO_STREAMS", "No audio streams found for $videoId", null)
                                }
                                return@launch
                            }

                            val bestAudio = when (quality) {
                                "low" -> audioStreams.minByOrNull { it.averageBitrate } ?: audioStreams[0]
                                "medium" -> audioStreams.minByOrNull { kotlin.math.abs(it.averageBitrate - 128000) } ?: audioStreams[0]
                                else -> audioStreams.maxByOrNull { it.averageBitrate } ?: audioStreams[0]
                            }

                            val codecRaw = (bestAudio.codec ?: "").lowercase()
                            val formatRaw = (bestAudio.format?.name ?: "").lowercase()
                            val isOpus = codecRaw.contains("opus") || formatRaw.contains("webm")
                            val detectedCodec = if (isOpus) "OPUS" else "AAC"

                            val res = mapOf(
                                "url" to bestAudio.content,
                                "format" to (bestAudio.format?.name ?: (if (isOpus) "webm" else "m4a")),
                                "codec" to detectedCodec,
                                "bitrate" to bestAudio.averageBitrate,
                                "duration" to streamInfo.duration,
                                "title" to (streamInfo.name ?: ""),
                                "uploader" to (streamInfo.uploaderName ?: "")
                            )

                            withContext(Dispatchers.Main) {
                                result.success(res)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("EXTRACTION_FAILED", e.message, e.stackTraceToString())
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        moveTaskToBack(true)
    }
}
