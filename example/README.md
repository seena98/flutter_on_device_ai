# flutter_on_device_ai example

A small app that exercises every feature of the plugin against whatever model the device has: streaming chat with a stop button, JSON-schema extraction, tool calling, and generated screens.

```sh
flutter run -d <device>
```

On a machine without an OS model the status bar explains why. A switch enables a clearly labelled **demo engine** (canned echo, not an AI) so you can still see the UI.

Check the real model on a capable device:

```sh
flutter test integration_test -d <device>
```
