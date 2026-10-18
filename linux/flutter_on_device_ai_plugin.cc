#include "include/flutter_on_device_ai/flutter_on_device_ai_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>

#include "flutter_on_device_ai_plugin_private.h"

#define FLUTTER_ON_DEVICE_AI_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_on_device_ai_plugin_get_type(), \
                              FlutterOnDeviceAiPlugin))

struct _FlutterOnDeviceAiPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FlutterOnDeviceAiPlugin, flutter_on_device_ai_plugin, g_object_get_type())

// Called when a method call is received from Flutter.
static void flutter_on_device_ai_plugin_handle_method_call(
    FlutterOnDeviceAiPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(FlValue) val = fl_value_new_bool(false);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "availabilityReason") == 0) {
    g_autoptr(FlValue) val = fl_value_new_string(
        "Linux OS does not have a native OS-managed AI model. Use the flutter_gemma fallback adapter.");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "initialize") == 0) {
    g_autoptr(FlValue) val = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "generateText") == 0) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "text", fl_value_new_string("[Linux local response]"));
    fl_value_set_string_take(map, "tokenCount", fl_value_new_int(5));
    fl_value_set_string_take(map, "generationTimeMs", fl_value_new_int(10));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "getPlatformInfo") == 0) {
    g_autoptr(FlValue) map = fl_value_new_map();
    fl_value_set_string_take(map, "backend", fl_value_new_string("unsupported"));
    fl_value_set_string_take(map, "supportsToolCalling", fl_value_new_bool(false));
    fl_value_set_string_take(map, "supportsStructuredOutput", fl_value_new_bool(false));
    fl_value_set_string_take(map, "supportsVision", fl_value_new_bool(false));
    fl_value_set_string_take(map, "supportsModelDownload", fl_value_new_bool(false));
    fl_value_set_string_take(map, "supportsPlayStoreRedirect", fl_value_new_bool(false));
    fl_value_set_string_take(map, "isConfigured", fl_value_new_bool(true));
    fl_value_set_string_take(map, "diagnosticNotes", fl_value_new_string("Linux Desktop"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "getModelStatus") == 0) {
    g_autoptr(FlValue) val = fl_value_new_string("unavailable");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "openAICorePlayStore") == 0) {
    g_autoptr(FlValue) val = fl_value_new_bool(false);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "createSession") == 0) {
    g_autoptr(FlValue) val = fl_value_new_string("linux_session_1");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else if (strcmp(method, "sessionAddQuery") == 0 ||
             strcmp(method, "sessionAddImage") == 0 ||
             strcmp(method, "sessionStopGeneration") == 0 ||
             strcmp(method, "sessionClose") == 0 ||
             strcmp(method, "registerTools") == 0 ||
             strcmp(method, "startStream") == 0 ||
             strcmp(method, "stopStream") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "sessionCountTokens") == 0) {
    g_autoptr(FlValue) val = fl_value_new_int(0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void flutter_on_device_ai_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(flutter_on_device_ai_plugin_parent_class)->dispose(object);
}

static void flutter_on_device_ai_plugin_class_init(FlutterOnDeviceAiPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_on_device_ai_plugin_dispose;
}

static void flutter_on_device_ai_plugin_init(FlutterOnDeviceAiPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  FlutterOnDeviceAiPlugin* plugin = FLUTTER_ON_DEVICE_AI_PLUGIN(user_data);
  flutter_on_device_ai_plugin_handle_method_call(plugin, method_call);
}

void flutter_on_device_ai_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterOnDeviceAiPlugin* plugin = FLUTTER_ON_DEVICE_AI_PLUGIN(
      g_object_new(flutter_on_device_ai_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "flutter_on_device_ai",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
