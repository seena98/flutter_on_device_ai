#include "include/flutter_on_device_ai/flutter_on_device_ai_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_on_device_ai_plugin.h"

void FlutterOnDeviceAiPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_on_device_ai::FlutterOnDeviceAiPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
