# Regenerating the demo GIF

`doc/assets/demo.gif` is rendered headlessly from the example app. The app and the
library are the real ones; only the model's replies are scripted (see `_reply` in
`example/test/demo_frames_test.dart`) and served through `FakeOnDeviceAiPlatform`.
It is an illustration, and the README says so next to it.

```sh
mkdir -p /tmp/frames
cd example
DEMO_FRAMES_DIR=/tmp/frames flutter test test/demo_frames_test.dart
cd /tmp/frames
args=(); while read f d; do args+=( -delay $((d/10)) "$f" ); done < manifest.txt
magick -loop 0 "${args[@]}" -resize 360x -layers Optimize -colors 128 <repo>/doc/assets/demo.gif
```

Needs ImageMagick. For a capture of a real model on real hardware, see the recording
commands in `AGENTS.md` and replace this file's GIF.
