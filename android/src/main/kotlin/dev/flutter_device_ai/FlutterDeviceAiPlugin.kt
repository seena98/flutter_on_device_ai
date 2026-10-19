package dev.flutter_device_ai

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.Content
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.SystemInstruction
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Android backend: Gemini Nano through Google AICore, using the ML Kit GenAI
 * Prompt API. The Prompt API is stateless, so conversations are kept here and
 * replayed on every turn.
 */
class FlutterDeviceAiPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var downloadChannel: EventChannel
    private var context: Context? = null

    private var eventSink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var model: GenerativeModel? = null
    private val sessions = mutableMapOf<String, Conversation>()

    private class Turn(val role: String, val text: String)

    private class Conversation(val system: String?) {
        val history = mutableListOf<Turn>()
        val pendingText = mutableListOf<String>()
        val pendingImages = mutableListOf<Bitmap>()
        var job: Job? = null
    }

    companion object {
        private const val AICORE_PACKAGE = "com.google.android.aicore"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "flutter_device_ai")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "flutter_device_ai/events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        downloadChannel = EventChannel(binding.binaryMessenger, "flutter_device_ai/download")
        downloadChannel.setStreamHandler(object : EventChannel.StreamHandler {
            private var job: Job? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                job?.cancel()
                job = scope.launch { runDownload(events) }
            }

            override fun onCancel(arguments: Any?) {
                job?.cancel()
                job = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        downloadChannel.setStreamHandler(null)
        scope.cancel()
        runCatching { model?.close() }
        model = null
        sessions.clear()
        context = null
    }

    // --- helpers ----------------------------------------------------------------

    private fun client(): GenerativeModel = model ?: Generation.getClient().also { model = it }

    private fun aiCoreInstalled(): Boolean {
        val ctx = context ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ctx.packageManager.getPackageInfo(AICORE_PACKAGE, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                ctx.packageManager.getPackageInfo(AICORE_PACKAGE, 0)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun availabilityMap(status: String, reason: String, message: String) =
        mapOf("status" to status, "reason" to reason, "message" to message)

    private suspend fun availability(): Map<String, Any> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return availabilityMap("unavailable", "osTooOld", "Android 8.0 (API 26) or newer is required.")
        }
        if (!aiCoreInstalled()) {
            return availabilityMap(
                "unavailable", "systemComponentMissing",
                "Google AICore is not installed. Install or update it from the Play Store."
            )
        }
        return try {
            when (client().checkStatus()) {
                FeatureStatus.AVAILABLE ->
                    availabilityMap("available", "ready", "Gemini Nano is ready.")
                FeatureStatus.DOWNLOADABLE ->
                    availabilityMap("downloadable", "modelNotReady", "Gemini Nano must be downloaded first.")
                FeatureStatus.DOWNLOADING ->
                    availabilityMap("downloading", "modelNotReady", "Gemini Nano is downloading.")
                else ->
                    availabilityMap("unavailable", "deviceNotEligible", "This device does not support Gemini Nano.")
            }
        } catch (e: Exception) {
            availabilityMap("unavailable", "unknown", "Could not query AICore: ${e.message}")
        }
    }

    private fun post(block: () -> Unit) = main.post(block)

    private fun errorCode(e: Throwable): Pair<String, String> = when (e) {
        is CancellationException -> "CANCELLED" to "Generation cancelled."
        is GenAiException -> when (e.errorCode) {
            GenAiException.ErrorCode.CANCELLED -> "CANCELLED" to "Generation cancelled."
            GenAiException.ErrorCode.BUSY -> "SESSION_BUSY" to (e.message ?: "The model is busy.")
            GenAiException.ErrorCode.NOT_AVAILABLE,
            GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE,
            GenAiException.ErrorCode.AICORE_INCOMPATIBLE,
            GenAiException.ErrorCode.NOT_ENOUGH_DISK_SPACE ->
                "UNAVAILABLE" to "Gemini Nano is not available: ${e.message ?: "code ${e.errorCode}"}"
            GenAiException.ErrorCode.NOT_SUPPORTED -> "UNSUPPORTED" to (e.message ?: "Not supported on this device.")
            else -> "GENERATION_FAILED" to (e.message ?: "GenAI error ${e.errorCode}")
        }
        else -> "GENERATION_FAILED" to (e.message ?: e.toString())
    }

    private fun sendEvent(sessionId: String, type: String, extra: Map<String, Any?> = emptyMap()) {
        eventSink?.success(mapOf("sessionId" to sessionId, "type" to type) + extra)
    }

    // --- method channel ------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        val id = call.argument<String>("sessionId") ?: ""
        when (call.method) {
            "getAvailability" -> scope.launch { result.success(availability()) }

            "getPlatformInfo" -> {
                val usable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && aiCoreInstalled()
                result.success(
                    mapOf(
                        "backend" to if (usable) "androidMlKitGenAi" else "unsupported",
                        "supportsToolCalling" to false,
                        "supportsStructuredOutput" to false,
                        "supportsVision" to usable,
                        "supportsModelDownload" to usable,
                        "supportsPlayStoreRedirect" to true,
                        "supportsExactTokenCounts" to usable,
                        "isConfigured" to true,
                        "diagnosticNotes" to "Android SDK ${Build.VERSION.SDK_INT}, AICore installed: ${aiCoreInstalled()}"
                    )
                )
            }

            "openAICorePlayStore" -> result.success(openPlayStore())

            "createSession" -> {
                sessions[id] = Conversation(call.argument<String>("systemInstruction")?.takeIf { it.isNotEmpty() })
                result.success(null)
            }

            "sessionAddQuery" -> {
                val convo = sessions[id] ?: return notFound(id, result)
                convo.pendingText.add(call.argument<String>("text") ?: "")
                result.success(null)
            }

            "sessionAddImage" -> {
                val convo = sessions[id] ?: return notFound(id, result)
                val bytes = call.argument<ByteArray>("imageBytes")
                val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                if (bitmap == null) {
                    result.error("UNSUPPORTED", "The image bytes could not be decoded.", null)
                } else {
                    convo.pendingImages.add(bitmap)
                    result.success(null)
                }
            }

            "sessionGetResponse" -> respond(id, call, result)
            "sessionStartStream" -> stream(id, call, result)

            "sessionCountTokens" -> scope.launch {
                val convo = sessions[id] ?: return@launch notFound(id, result)
                try {
                    val text = call.argument<String>("text")
                    val request = if (text != null) {
                        GenerateContentRequest.Builder(com.google.mlkit.genai.prompt.TextPart(text)).build()
                    } else {
                        buildRequest(convo, call.argument<Map<String, Any?>>("config"), peek = true)
                    }
                    result.success(client().countTokens(request).totalTokens)
                } catch (e: Exception) {
                    val (code, message) = errorCode(e)
                    result.error(code, message, null)
                }
            }

            "sessionStopGeneration" -> {
                sessions[id]?.job?.cancel()
                result.success(null)
            }

            "sessionClose" -> {
                sessions.remove(id)?.job?.cancel()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun notFound(id: String, result: Result) =
        result.error("SESSION_NOT_FOUND", "Session $id does not exist.", null)

    private fun openPlayStore(): Boolean {
        val ctx = context ?: return false
        val uris = listOf(
            "market://details?id=$AICORE_PACKAGE",
            "https://play.google.com/store/apps/details?id=$AICORE_PACKAGE"
        )
        for (uri in uris) {
            try {
                ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    // --- generation -----------------------------------------------------------------

    /** Renders the conversation (and the pending turn) as one request. */
    private fun buildRequest(
        convo: Conversation,
        config: Map<String, Any?>?,
        peek: Boolean = false,
    ): GenerateContentRequest {
        val prompt = StringBuilder()
        for (turn in convo.history) prompt.append(turn.role).append(": ").append(turn.text).append('\n')
        val hasHistory = convo.history.isNotEmpty()
        val pending = convo.pendingText.joinToString("\n")
        if (hasHistory) prompt.append("User: ").append(pending).append("\nAssistant:") else prompt.append(pending)

        val content = Content.Builder().apply {
            convo.pendingImages.forEach { image(it) }
            text(prompt.toString())
        }.build()

        val builder = GenerateContentRequest.Builder(content)
        convo.system?.let { builder.systemInstruction = SystemInstruction(it) }
        (config?.get("temperature") as? Number)?.let { builder.temperature = it.toFloat() }
        (config?.get("topK") as? Number)?.let { builder.topK = it.toInt() }
        (config?.get("maxTokens") as? Number)?.let { builder.maxOutputTokens = it.toInt() }
        builder.candidateCount = 1
        return builder.build()
    }

    private fun commitTurn(convo: Conversation, answer: String) {
        convo.history.add(Turn("User", convo.pendingText.joinToString("\n")))
        convo.history.add(Turn("Assistant", answer))
        convo.pendingText.clear()
        convo.pendingImages.clear()
    }

    private fun respond(id: String, call: MethodCall, result: Result) {
        val convo = sessions[id] ?: return notFound(id, result)
        if (convo.job?.isActive == true) {
            return result.error("SESSION_BUSY", "Session $id is still generating.", null)
        }
        if (convo.pendingText.isEmpty()) {
            return result.error("EMPTY_TURN", "Nothing to answer: add a query first.", null)
        }
        val config = call.argument<Map<String, Any?>>("config")
        val started = System.currentTimeMillis()
        convo.job = scope.launch {
            try {
                val response = client().generateContent(buildRequest(convo, config))
                val text = response.candidates.firstOrNull()?.text.orEmpty()
                commitTurn(convo, text)
                result.success(
                    mapOf(
                        "text" to text,
                        "tokenCount" to maxOf(1, text.length / 4),
                        "generationTimeMs" to (System.currentTimeMillis() - started).toInt()
                    )
                )
            } catch (e: Throwable) {
                val (code, message) = errorCode(e)
                result.error(code, message, null)
            }
        }
    }

    private fun stream(id: String, call: MethodCall, result: Result) {
        val convo = sessions[id] ?: return notFound(id, result)
        if (convo.job?.isActive == true) {
            return result.error("SESSION_BUSY", "Session $id is still generating.", null)
        }
        if (convo.pendingText.isEmpty()) {
            return result.error("EMPTY_TURN", "Nothing to answer: add a query first.", null)
        }
        val config = call.argument<Map<String, Any?>>("config")
        convo.job = scope.launch {
            val full = StringBuilder()
            try {
                client().generateContentStream(buildRequest(convo, config)).collect { response ->
                    val piece = response.candidates.firstOrNull()?.text.orEmpty()
                    // Some builds emit the text so far instead of a delta.
                    val delta = if (full.isNotEmpty() && piece.startsWith(full)) piece.substring(full.length) else piece
                    if (delta.isNotEmpty()) {
                        full.append(delta)
                        sendEvent(id, "chunk", mapOf("text" to delta))
                    }
                }
                commitTurn(convo, full.toString())
                sendEvent(id, "done")
            } catch (e: Throwable) {
                val (code, message) = errorCode(e)
                sendEvent(id, "error", mapOf("code" to code, "message" to message))
            }
        }
        result.success(null)
    }

    // --- model download ----------------------------------------------------------------

    private suspend fun runDownload(events: EventChannel.EventSink?) {
        fun emit(map: Map<String, Any?>) = post { events?.success(map) }
        try {
            val current = availability()
            when (current["status"]) {
                "available" -> {
                    emit(mapOf("status" to "available", "progress" to 1.0))
                    post { events?.endOfStream() }
                    return
                }
                "unavailable" -> {
                    emit(mapOf("status" to "unavailable", "errorMessage" to current["message"]))
                    post { events?.endOfStream() }
                    return
                }
            }
            var total = 0L
            client().download().collect { status ->
                when (status) {
                    is DownloadStatus.DownloadStarted -> {
                        total = status.bytesToDownload
                        emit(mapOf("status" to "downloading", "progress" to 0.0, "totalBytes" to total))
                    }
                    is DownloadStatus.DownloadProgress -> {
                        val done = status.totalBytesDownloaded
                        emit(
                            mapOf(
                                "status" to "downloading",
                                "progress" to if (total > 0) done.toDouble() / total else null,
                                "bytesDownloaded" to done,
                                "totalBytes" to total
                            )
                        )
                    }
                    is DownloadStatus.DownloadCompleted ->
                        emit(mapOf("status" to "available", "progress" to 1.0))
                    is DownloadStatus.DownloadFailed ->
                        emit(mapOf("status" to "unavailable", "errorMessage" to status.e.message))
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            emit(mapOf("status" to "unavailable", "errorMessage" to (e.message ?: e.toString())))
        }
        post { events?.endOfStream() }
    }
}
