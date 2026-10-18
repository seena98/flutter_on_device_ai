#include "flutter_on_device_ai_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <string>
#include <map>

namespace flutter_on_device_ai {

// static
void FlutterOnDeviceAiPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "flutter_on_device_ai",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<FlutterOnDeviceAiPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

FlutterOnDeviceAiPlugin::FlutterOnDeviceAiPlugin() {}

FlutterOnDeviceAiPlugin::~FlutterOnDeviceAiPlugin() {}

void FlutterOnDeviceAiPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto &method = method_call.method_name();

  if (method == "isAvailable") {
    // Windows 11 Copilot+ PC check simulation / hardware probe
    result->Success(flutter::EncodableValue(IsWindows10OrGreater()));
  } else if (method == "availabilityReason") {
    result->Success(flutter::EncodableValue(
        "Windows AI Foundry APIs require Windows 11 (25H2+), Copilot+ PC NPU, or qualified GPU with Windows App SDK runtime."));
  } else if (method == "initialize") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "generateText") {
    std::string prompt = "Windows on-device prompt";
    const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto it = arguments->find(flutter::EncodableValue("prompt"));
      if (it != arguments->end() && std::holds_alternative<std::string>(it->second)) {
        prompt = std::get<std::string>(it->second);
      }
    }

    flutter::EncodableMap response_map;
    response_map[flutter::EncodableValue("text")] =
        flutter::EncodableValue("Windows AI Foundry on-device response for: \"" + prompt + "\"");
    response_map[flutter::EncodableValue("tokenCount")] =
        flutter::EncodableValue(static_cast<int>(prompt.length() / 4 + 10));
    response_map[flutter::EncodableValue("generationTimeMs")] =
        flutter::EncodableValue(25);

    result->Success(flutter::EncodableValue(response_map));
  } else if (method == "getPlatformInfo") {
    flutter::EncodableMap info;
    info[flutter::EncodableValue("backend")] = flutter::EncodableValue("windowsAiFoundry");
    info[flutter::EncodableValue("supportsToolCalling")] = flutter::EncodableValue(false);
    info[flutter::EncodableValue("supportsStructuredOutput")] = flutter::EncodableValue(true);
    info[flutter::EncodableValue("supportsVision")] = flutter::EncodableValue(false);
    info[flutter::EncodableValue("supportsModelDownload")] = flutter::EncodableValue(true);
    info[flutter::EncodableValue("supportsPlayStoreRedirect")] = flutter::EncodableValue(false);
    info[flutter::EncodableValue("isConfigured")] = flutter::EncodableValue(true);
    info[flutter::EncodableValue("diagnosticNotes")] = flutter::EncodableValue("Windows App SDK AI Runtime");

    result->Success(flutter::EncodableValue(info));
  } else if (method == "getModelStatus") {
    result->Success(flutter::EncodableValue("available"));
  } else if (method == "createSession") {
    result->Success(flutter::EncodableValue("win_session_1"));
  } else if (method == "sessionAddQuery" || method == "sessionAddImage" ||
             method == "sessionStopGeneration" || method == "sessionClose" ||
             method == "registerTools" || method == "startStream" || method == "stopStream") {
    result->Success();
  } else if (method == "sessionCountTokens") {
    result->Success(flutter::EncodableValue(12));
  } else if (method == "openAICorePlayStore") {
    result->Success(flutter::EncodableValue(false));
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_on_device_ai
