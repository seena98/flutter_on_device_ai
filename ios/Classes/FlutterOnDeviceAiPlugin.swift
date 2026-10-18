#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import Cocoa
import FlutterMacOS
#endif
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Flutter bridge for Apple Foundation Models (iOS 26+, macOS 26+).
///
/// Everything that touches `FoundationModels` lives in `AppleEngine`, which is
/// compiled only when the SDK provides the framework and is created only on an
/// OS that ships it. On older systems the plugin reports `unavailable`.
public class FlutterOnDeviceAiPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private let events = EventRelay()
  private let downloads = DownloadRelay()
  private var engineStorage: Any?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #else
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "flutter_on_device_ai", binaryMessenger: messenger)
    let instance = FlutterOnDeviceAiPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    FlutterEventChannel(name: "flutter_on_device_ai/events", binaryMessenger: messenger)
      .setStreamHandler(instance.events)
    FlutterEventChannel(name: "flutter_on_device_ai/download", binaryMessenger: messenger)
      .setStreamHandler(instance.downloads)
    instance.downloads.availabilityProvider = { [weak instance] in instance?.availability() ?? [:] }
  }

  #if canImport(FoundationModels)
  @available(iOS 26.0, macOS 26.0, *)
  private var engine: AppleEngine {
    if let existing = engineStorage as? AppleEngine { return existing }
    let created = AppleEngine(channel: channel, events: events)
    engineStorage = created
    return created
  }
  #endif

  private func availability() -> [String: Any] {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
      return AppleEngine.availability()
    }
    #endif
    return [
      "status": "unavailable",
      "reason": "osTooOld",
      "message": "Apple Foundation Models need iOS 26 / macOS 26 or newer (built with a matching SDK).",
    ]
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getAvailability":
      result(availability())

    case "getPlatformInfo":
      var usable = false
      #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) { usable = true }
      #endif
      result([
        "backend": usable ? "appleFoundationModels" : "unsupported",
        "supportsToolCalling": usable,
        "supportsStructuredOutput": usable,
        "supportsVision": false,
        "supportsModelDownload": usable,
        "supportsPlayStoreRedirect": false,
        "supportsExactTokenCounts": false,
        "isConfigured": true,
        "diagnosticNotes": ProcessInfo.processInfo.operatingSystemVersionString,
      ])

    case "openAICorePlayStore":
      result(false)

    default:
      #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        engine.handle(call.method, args: args, result: result)
        return
      }
      #endif
      result(FlutterError(code: "UNAVAILABLE", message: availability()["message"] as? String, details: nil))
    }
  }
}

/// Multiplexed stream of generation events (`chunk`, `done`, `error`).
final class EventRelay: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func send(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.sink?(event) }
  }
}

/// Reports model readiness while Apple prepares the on-device model.
final class DownloadRelay: NSObject, FlutterStreamHandler {
  var availabilityProvider: (() -> [String: Any])?
  private var polling: Task<Void, Never>?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    polling?.cancel()
    polling = Task { [weak self] in
      while !Task.isCancelled {
        let state = self?.availabilityProvider?() ?? [:]
        let status = state["status"] as? String ?? "unavailable"
        var event: [String: Any] = ["status": status]
        if status == "available" { event["progress"] = 1.0 }
        if status == "unavailable" { event["errorMessage"] = state["message"] as? String ?? "unavailable" }
        let snapshot = event
        DispatchQueue.main.async { events(snapshot) }
        if status == "available" || status == "unavailable" {
          DispatchQueue.main.async { events(FlutterEndOfEventStream) }
          return
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    polling?.cancel()
    polling = nil
    return nil
  }
}

#if canImport(FoundationModels)

@available(iOS 26.0, macOS 26.0, *)
final class AppleEngine {
  private struct Entry {
    let session: LanguageModelSession
    var pending: [String] = []
    var task: Task<Void, Never>?
  }

  private let channel: FlutterMethodChannel
  private let events: EventRelay
  private var sessions: [String: Entry] = [:]

  init(channel: FlutterMethodChannel, events: EventRelay) {
    self.channel = channel
    self.events = events
  }

  // MARK: availability

  static func availability() -> [String: Any] {
    switch SystemLanguageModel.default.availability {
    case .available:
      return ["status": "available", "reason": "ready", "message": "Apple Foundation Models are ready."]
    case .unavailable(let reason):
      switch reason {
      case .deviceNotEligible:
        return ["status": "unavailable", "reason": "deviceNotEligible",
                "message": "This device cannot run Apple Intelligence."]
      case .appleIntelligenceNotEnabled:
        return ["status": "unavailable", "reason": "featureDisabled",
                "message": "Apple Intelligence is turned off. Enable it in Settings."]
      case .modelNotReady:
        return ["status": "downloading", "reason": "modelNotReady",
                "message": "Apple Intelligence is still preparing its model. Try again shortly."]
      @unknown default:
        return ["status": "unavailable", "reason": "unknown",
                "message": "Apple Foundation Models are unavailable."]
      }
    }
  }

  // MARK: dispatch

  func handle(_ method: String, args: [String: Any], result: @escaping FlutterResult) {
    let id = args["sessionId"] as? String ?? ""
    switch method {
    case "createSession":
      do {
        try createSession(id: id, args: args)
        result(nil)
      } catch {
        result(FlutterError(code: "GENERATION_FAILED", message: "\(error)", details: nil))
      }

    case "sessionAddQuery":
      guard sessions[id] != nil else { return notFound(id, result) }
      sessions[id]?.pending.append(args["text"] as? String ?? "")
      result(nil)

    case "sessionAddImage":
      result(FlutterError(code: "UNSUPPORTED", message: "Image input needs the iOS 27 / macOS 27 SDK and is not enabled in this build.", details: nil))

    case "sessionGetResponse":
      respond(id: id, args: args, result: result)

    case "sessionStartStream":
      stream(id: id, args: args, result: result)

    case "sessionCountTokens":
      let text = args["text"] as? String ?? sessions[id]?.pending.joined(separator: "\n") ?? ""
      result(max(text.isEmpty ? 0 : 1, Int((Double(text.count) / 4).rounded(.up))))

    case "sessionStopGeneration":
      sessions[id]?.task?.cancel()
      result(nil)

    case "sessionClose":
      sessions[id]?.task?.cancel()
      sessions.removeValue(forKey: id)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func notFound(_ id: String, _ result: FlutterResult) {
    result(FlutterError(code: "SESSION_NOT_FOUND", message: "Session \(id) does not exist.", details: nil))
  }

  // MARK: sessions

  private func createSession(id: String, args: [String: Any]) throws {
    var tools: [any Tool] = []
    for decl in args["tools"] as? [[String: Any]] ?? [] {
      let name = decl["name"] as? String ?? ""
      let schemaMap = decl["parameterSchema"] as? [String: Any] ?? ["type": "object"]
      let schema = try SchemaBuilder.generationSchema(from: schemaMap, name: name)
      tools.append(DartTool(
        name: name,
        description: decl["description"] as? String ?? "",
        parameters: schema,
        sessionId: id,
        channel: ChannelBox(channel)))
    }
    let instructions = (args["systemInstruction"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let session: LanguageModelSession
    if let instructions {
      session = LanguageModelSession(tools: tools, instructions: instructions)
    } else {
      session = LanguageModelSession(tools: tools)
    }
    sessions[id] = Entry(session: session)
  }

  private func options(from config: [String: Any]?) -> GenerationOptions {
    var sampling: GenerationOptions.SamplingMode?
    if let topK = config?["topK"] as? Int {
      sampling = .random(top: topK)
    } else if let topP = (config?["topP"] as? NSNumber)?.doubleValue {
      sampling = .random(probabilityThreshold: topP)
    }
    return GenerationOptions(
      sampling: sampling,
      temperature: (config?["temperature"] as? NSNumber)?.doubleValue,
      maximumResponseTokens: config?["maxTokens"] as? Int)
  }

  private func takePrompt(_ id: String) -> String? {
    guard var entry = sessions[id], !entry.pending.isEmpty else { return nil }
    let prompt = entry.pending.joined(separator: "\n\n")
    entry.pending.removeAll()
    sessions[id] = entry
    return prompt
  }

  private func errorPayload(_ error: Error) -> (code: String, message: String) {
    if error is CancellationError { return ("CANCELLED", "Generation cancelled.") }
    if let gen = error as? LanguageModelSession.GenerationError {
      if case .assetsUnavailable = gen { return ("UNAVAILABLE", "The on-device model is not available: \(gen.localizedDescription)") }
      return ("GENERATION_FAILED", gen.localizedDescription)
    }
    return ("GENERATION_FAILED", "\(error)")
  }

  private func respond(id: String, args: [String: Any], result: @escaping FlutterResult) {
    guard let entry = sessions[id] else { return notFound(id, result) }
    if entry.session.isResponding || entry.task != nil {
      return result(FlutterError(code: "SESSION_BUSY", message: "Session \(id) is still generating.", details: nil))
    }
    guard let prompt = takePrompt(id) else {
      return result(FlutterError(code: "EMPTY_TURN", message: "Nothing to answer: add a query first.", details: nil))
    }
    let config = args["config"] as? [String: Any]
    let opts = options(from: config)
    let schemaMap = (config?["responseFormat"] as? String) == "json" ? config?["schema"] as? [String: Any] : nil
    let started = Date()

    let task = Task { [weak self] in
      do {
        let text: String
        if let schemaMap {
          let schema = try SchemaBuilder.generationSchema(from: schemaMap, name: "Response")
          text = try await entry.session.respond(to: prompt, schema: schema, options: opts).content.jsonString
        } else {
          text = try await entry.session.respond(to: prompt, options: opts).content
        }
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        await self?.finish(id) {
          result(["text": text, "tokenCount": max(1, text.count / 4), "generationTimeMs": elapsed])
        }
      } catch {
        let e = self?.errorPayload(error) ?? ("GENERATION_FAILED", "\(error)")
        await self?.finish(id) { result(FlutterError(code: e.0, message: e.1, details: nil)) }
      }
    }
    sessions[id]?.task = task
  }

  private func stream(id: String, args: [String: Any], result: @escaping FlutterResult) {
    guard let entry = sessions[id] else { return notFound(id, result) }
    if entry.session.isResponding || entry.task != nil {
      return result(FlutterError(code: "SESSION_BUSY", message: "Session \(id) is still generating.", details: nil))
    }
    guard let prompt = takePrompt(id) else {
      return result(FlutterError(code: "EMPTY_TURN", message: "Nothing to answer: add a query first.", details: nil))
    }
    let opts = options(from: args["config"] as? [String: Any])

    let task = Task { [weak self] in
      var sent = ""
      do {
        for try await snapshot in entry.session.streamResponse(to: prompt, options: opts) {
          let full = snapshot.content
          let delta = full.hasPrefix(sent) ? String(full.dropFirst(sent.count)) : full
          sent = full
          if !delta.isEmpty { self?.events.send(["sessionId": id, "type": "chunk", "text": delta]) }
        }
        self?.events.send(["sessionId": id, "type": "done"])
      } catch {
        let e = self?.errorPayload(error) ?? ("GENERATION_FAILED", "\(error)")
        self?.events.send(["sessionId": id, "type": "error", "code": e.0, "message": e.1])
      }
      await self?.finish(id) {}
    }
    sessions[id]?.task = task
    result(nil)
  }

  @MainActor
  private func finish(_ id: String, _ reply: @escaping () -> Void) {
    sessions[id]?.task = nil
    reply()
  }
}

/// `FlutterMethodChannel` is thread-confined to the platform thread; calls are
/// always hopped onto the main queue before use.
final class ChannelBox: @unchecked Sendable {
  let value: FlutterMethodChannel
  init(_ value: FlutterMethodChannel) { self.value = value }
}

/// Bridges a Dart tool into FoundationModels' `Tool` protocol.
@available(iOS 26.0, macOS 26.0, *)
struct DartTool: Tool {
  let name: String
  let description: String
  let parameters: GenerationSchema
  let sessionId: String
  let channel: ChannelBox

  func call(arguments: GeneratedContent) async throws -> String {
    var decoded: Any = [String: Any]()
    if let data = arguments.jsonString.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) {
      decoded = object
    }
    let payload: [String: Any] = ["sessionId": sessionId, "name": name, "arguments": decoded]
    let reply: Any? = await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        channel.value.invokeMethod("onToolCall", arguments: payload) { continuation.resume(returning: $0) }
      }
    }
    var output: [String: Any] = ["error": "The tool returned nothing."]
    if let map = reply as? [String: Any] {
      if let result = map["result"] { output = ["result": result] }
      else if let error = map["error"] { output = ["error": error] }
    } else if let flutterError = reply as? FlutterError {
      output = ["error": flutterError.message ?? flutterError.code]
    }
    // Errors go back to the model as data so it can recover or explain.
    guard JSONSerialization.isValidJSONObject(output),
          let data = try? JSONSerialization.data(withJSONObject: output),
          let text = String(data: data, encoding: .utf8) else {
      return "{\"error\":\"The tool result was not JSON serializable.\"}"
    }
    return text
  }
}

/// Converts the JSON-Schema subset used by this plugin into Apple's schema types.
@available(iOS 26.0, macOS 26.0, *)
enum SchemaBuilder {
  struct Unsupported: Error, CustomStringConvertible {
    let description: String
  }

  static func generationSchema(from schema: [String: Any], name: String) throws -> GenerationSchema {
    try GenerationSchema(root: dynamicSchema(schema, name: name), dependencies: [])
  }

  static func dynamicSchema(_ schema: [String: Any], name: String) throws -> DynamicGenerationSchema {
    let description = schema["description"] as? String
    if let options = schema["enum"] as? [String] {
      return DynamicGenerationSchema(name: name, description: description, anyOf: options)
    }
    switch schema["type"] as? String {
    case "object":
      let required = Set(schema["required"] as? [String] ?? [])
      let properties = schema["properties"] as? [String: Any] ?? [:]
      let built: [DynamicGenerationSchema.Property] = try properties.keys.sorted().map { key in
        let sub = properties[key] as? [String: Any] ?? [:]
        return DynamicGenerationSchema.Property(
          name: key,
          description: sub["description"] as? String,
          schema: try dynamicSchema(sub, name: key),
          isOptional: !required.contains(key))
      }
      return DynamicGenerationSchema(name: name, description: description, properties: built)
    case "array":
      let items = schema["items"] as? [String: Any] ?? ["type": "string"]
      return DynamicGenerationSchema(
        arrayOf: try dynamicSchema(items, name: name + "Item"),
        minimumElements: schema["minItems"] as? Int,
        maximumElements: schema["maxItems"] as? Int)
    case "string": return DynamicGenerationSchema(type: String.self)
    case "integer": return DynamicGenerationSchema(type: Int.self)
    case "number": return DynamicGenerationSchema(type: Double.self)
    case "boolean": return DynamicGenerationSchema(type: Bool.self)
    default:
      throw Unsupported(description: "Unsupported JSON Schema type at \(name): \(String(describing: schema["type"]))")
    }
  }
}

#endif
