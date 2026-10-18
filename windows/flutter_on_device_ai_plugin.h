#ifndef FLUTTER_PLUGIN_FLUTTER_ON_DEVICE_AI_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_ON_DEVICE_AI_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace flutter_on_device_ai {

class FlutterOnDeviceAiPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FlutterOnDeviceAiPlugin();

  virtual ~FlutterOnDeviceAiPlugin();

  // Disallow copy and assign.
  FlutterOnDeviceAiPlugin(const FlutterOnDeviceAiPlugin&) = delete;
  FlutterOnDeviceAiPlugin& operator=(const FlutterOnDeviceAiPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace flutter_on_device_ai

#endif  // FLUTTER_PLUGIN_FLUTTER_ON_DEVICE_AI_PLUGIN_H_
