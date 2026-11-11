# Android: hover never reaches a `box-only` View or the content of a `ScrollView` with `scrollEnabled={false}`

![Build](https://github.com/YevheniiKotyrlo/rn-box-only-hover-repro/workflows/Pre%20Merge%20Checks/badge.svg)

React Native 0.90.0-nightly-20261111-1273ca128, from the [React Native reproducer template](https://github.com/react-native-community/reproducer-react-native). `App.tsx` renders three accessible Views: one with the default `pointerEvents`, one with `pointerEvents="box-only"`, and one inside a `ScrollView` with `scrollEnabled={false}`.

## Steps

By hand, on an Android device:

1. Build and install the release APK: `cd ReproducerApp/android && ./gradlew assembleRelease && adb install -r app/build/outputs/apk/release/app-release.apk`.
2. Open the app, run `adb shell uiautomator events`, and hover a mouse or a stylus over each View, above its label: the label is a Text that sends hover events of its own. `TYPE_VIEW_HOVER_ENTER` comes from `auto View` only.

Scripted: `./reproduce.sh`, with one Android 11 or newer device attached, builds and installs the app, hovers a stylus registered through the device's `uinput` over each View above its label, and reads `uiautomator events`. It exits 1 while the hover reaches the `auto View` but not the other two, 0 once each sends `TYPE_VIEW_HOVER_ENTER`, and 2 when a step fails.
