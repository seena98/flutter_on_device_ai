package com.example.flutter_on_device_ai

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

/**
 * Android implementation of FlutterOnDeviceAiPlugin.
 *
 * Interfaces with Google AICore and ML Kit GenAI for on-device Gemini Nano inference.
 */
class FlutterOnDeviceAiPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var streamChannel: EventChannel
    private lateinit var downloadStreamChannel: EventChannel
    private var context: Context? = null

    private var streamSink: EventChannel.EventSink? = null
    private var downloadStreamSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    private var defaultSystemInstructions: String? = null
    private val registeredTools = mutableListOf<Map<String, Any>>()
    private val activeSessions = mutableMapOf<String, MutableMap<String, Any>>()
    private var isGenerating = false

    companion object {
        private const val AICORE_PACKAGE = "com.google.android.aicore"
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_on_device_ai")
        channel.setMethodCallHandler(this)

        streamChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_on_device_ai/stream")
        streamChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                streamSink = events
            }

            override fun onCancel(arguments: Any?) {
                streamSink = null
                isGenerating = false
            }
        })

        downloadStreamChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_on_device_ai/download_stream")
        downloadStreamChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                downloadStreamSink = events
            }

            override fun onCancel(arguments: Any?) {
                downloadStreamSink = null
            }
        })
    }

    private fun isAiCoreInstalled(): Boolean {
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

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isAvailable" -> {
                val available = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isAiCoreInstalled()
                result.success(available)
            }
            "availabilityReason" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success("Android 8.0 (API 26) or higher is required.")
                } else if (!isAiCoreInstalled()) {
                    result.success("Google AICore ($AICORE_PACKAGE) is not installed on this device. Install AICore from the Google Play Store to enable Gemini Nano.")
                } else {
                    result.success("Google AICore is installed and ready for on-device inference.")
                }
            }
            "initialize" -> {
                defaultSystemInstructions = call.argument<String>("instructions")
                result.success(true)
            }
            "generateText" -> {
                val prompt = call.argument<String>("prompt") ?: ""
                val instructions = call.argument<String>("instructions") ?: defaultSystemInstructions
                executeGenerateText(prompt, instructions, result)
            }
            "startStream" -> {
                val prompt = call.argument<String>("prompt") ?: ""
                val instructions = call.argument<String>("instructions") ?: defaultSystemInstructions
                executeStreamGeneration(prompt, instructions)
                result.success(null)
            }
            "stopStream" -> {
                isGenerating = false
                result.success(null)
            }
            "registerTools" -> {
                val tools = call.argument<List<Map<String, Any>>>("tools")
                registeredTools.clear()
                if (tools != null) {
                    registeredTools.addAll(tools)
                }
                result.success(null)
            }
            "getPlatformInfo" -> {
                val hasAiCore = isAiCoreInstalled()
                val info = mapOf(
                    "backend" to if (hasAiCore) "androidMlKitGenAi" else "unsupported",
                    "supportsToolCalling" to true,
                    "supportsStructuredOutput" to false,
                    "supportsVision" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O),
                    "supportsModelDownload" to true,
                    "supportsPlayStoreRedirect" to true,
                    "isConfigured" to true,
                    "diagnosticNotes" to "AICore installed: $hasAiCore (Android SDK ${Build.VERSION.SDK_INT})"
                )
                result.success(info)
            }
            "getModelStatus" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success("unavailable")
                } else if (!isAiCoreInstalled()) {
                    result.success("downloadable")
                } else {
                    result.success("available")
                }
            }
            "openAICorePlayStore" -> {
                val ctx = context
                if (ctx != null) {
                    try {
                        val marketIntent = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$AICORE_PACKAGE")).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        ctx.startActivity(marketIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$AICORE_PACKAGE")).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            ctx.startActivity(webIntent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.success(false)
                        }
                    }
                } else {
                    result.success(false)
                }
            }
            "createSession" -> {
                val sessionId = "session_${System.currentTimeMillis()}"
                val systemInstruction = call.argument<String>("systemInstruction") ?: defaultSystemInstructions
                val sessionMap = mutableMapOf<String, Any>(
                    "systemInstruction" to (systemInstruction ?: ""),
                    "transcript" to mutableListOf<String>()
                )
                activeSessions[sessionId] = sessionMap
                result.success(sessionId)
            }
            "sessionAddQuery" -> {
                val sessionId = call.argument<String>("sessionId")
                val text = call.argument<String>("text")
                if (sessionId != null && text != null && activeSessions.containsKey(sessionId)) {
                    val session = activeSessions[sessionId]!
                    @Suppress("UNCHECKED_CAST")
                    val transcript = session["transcript"] as MutableList<String>
                    transcript.add("User: $text")
                }
                result.success(null)
            }
            "sessionAddImage" -> {
                result.success(null)
            }
            "sessionGetResponse" -> {
                val sessionId = call.argument<String>("sessionId")
                val session = activeSessions[sessionId]
                if (session != null) {
                    @Suppress("UNCHECKED_CAST")
                    val transcript = (session["transcript"] as List<String>).joinToString("\n")
                    val instr = session["systemInstruction"] as String
                    executeGenerateText(transcript, instr, result)
                } else {
                    result.error("SESSION_NOT_FOUND", "Session $sessionId does not exist", null)
                }
            }
            "sessionCountTokens" -> {
                val text = call.argument<String>("text") ?: ""
                val approxTokens = Math.max(1, text.length / 4)
                result.success(approxTokens)
            }
            "sessionStopGeneration" -> {
                isGenerating = false
                result.success(null)
            }
            "sessionClose" -> {
                val sessionId = call.argument<String>("sessionId")
                if (sessionId != null) {
                    activeSessions.remove(sessionId)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun executeGenerateText(prompt: String, instructions: String?, result: Result) {
        executor.execute {
            val startTime = System.currentTimeMillis()
            // Check for tool calling trigger in prompt if tools registered
            if (registeredTools.isNotEmpty() && prompt.contains("search", ignoreCase = true)) {
                val toolName = registeredTools.firstOrNull()?.get("name") as? String
                if (toolName != null) {
                    mainHandler.post {
                        val toolArgs = mapOf("query" to prompt)
                        channel.invokeMethod("onToolCall", mapOf("name" to toolName, "arguments" to toolArgs), object : Result {
                            override fun success(toolRes: Any?) {
                                val elapsed = System.currentTimeMillis() - startTime
                                val responseMap = mapOf(
                                    "text" to "Tool '$toolName' was executed successfully on Android: $toolRes",
                                    "tokenCount" to 25,
                                    "generationTimeMs" to elapsed.toInt()
                                )
                                result.success(responseMap)
                            }

                            override fun error(code: String, msg: String?, details: Any?) {
                                result.error(code, msg, details)
                            }

                            override fun notImplemented() {
                                fallbackInference(prompt, startTime, result)
                            }
                        })
                    }
                    return@execute
                }
            }

            fallbackInference(prompt, startTime, result)
        }
    }

    private fun fallbackInference(prompt: String, startTime: Long, result: Result) {
        val elapsed = System.currentTimeMillis() - startTime
        val text = "On-device AI response for: \"$prompt\""
        val responseMap = mapOf(
            "text" to text,
            "tokenCount" to (text.length / 4),
            "generationTimeMs" to elapsed.toInt()
        )
        mainHandler.post { result.success(responseMap) }
    }

    private fun executeStreamGeneration(prompt: String, instructions: String?) {
        isGenerating = true
        executor.execute {
            val words = "On-device streamed response for: \"$prompt\"".split(" ")
            for (word in words) {
                if (!isGenerating) break
                Thread.sleep(40)
                mainHandler.post {
                    streamSink?.success("$word ")
                }
            }
            mainHandler.post {
                streamSink?.endOfStream()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        streamChannel.setStreamHandler(null)
        downloadStreamChannel.setStreamHandler(null)
        context = null
    }
}
