#!/usr/bin/env bash
# Exit 1 while a hover reaches the auto View but not the box-only View or the View inside a ScrollView with
# scrollEnabled={false} on the attached Android device, 0 once each sends TYPE_VIEW_HOVER_ENTER, 2 when another step fails.
# Needs adb with one Android 11+ device attached (ANDROID_SERIAL picks one of several), node, yarn and a JDK.
set -u

package=com.reproducerapp
control_label="auto View"
box_only_label="box-only View"
scroll_view_label="View inside a ScrollView with scrollEnabled false"

fail_step() {
    echo "step failed: $1"
    exit 2
}

# The path as the platform's own programs take it: Git Bash's /c/... becomes C:/... for adb on Windows.
native_path() {
    if command -v cygpath > /dev/null; then
        cygpath -m "$1"
    else
        printf '%s\n' "$1"
    fi
}

hover_enter_line() {
    local events=$1 label=$2
    awk -v description="ContentDescription: ${label};" \
        'index($0, "EventType: TYPE_VIEW_HOVER_ENTER;") && index($0, description) { print; exit }' "${events}"
}

report_hover() {
    local events=$1 label=$2 line
    line="$(hover_enter_line "${events}" "${label}")"
    if [[ -n "${line}" ]]; then
        echo "${label}: TYPE_VIEW_HOVER_ENTER"
        return 0
    fi
    echo "${label}: no TYPE_VIEW_HOVER_ENTER"
    return 1
}

# Sets the named variable to a device property, without the carriage return adb's shell ends it with.
read_device_property() {
    local value
    value="$(adb shell getprop "$2")" || fail_step "adb shell getprop $2: ${value}"
    printf -v "$1" '%s' "${value//$'\r'/}"
}

# Reads `uiautomator events` output and exits with the verdict.
report_verdict() {
    local events=$1 control_entered=0 box_only_entered=0 scroll_view_entered=0
    report_hover "${events}" "${control_label}" && control_entered=1
    report_hover "${events}" "${box_only_label}" && box_only_entered=1
    report_hover "${events}" "${scroll_view_label}" && scroll_view_entered=1
    if [[ "${control_entered}" -eq 0 ]]; then
        echo "SUMMARY: the stylus hover reached no view, so the run shows nothing"
        exit 2
    fi
    if [[ "${box_only_entered}" -eq 1 && "${scroll_view_entered}" -eq 1 ]]; then
        echo "SUMMARY: a hover reaches the box-only View and the View inside the ScrollView with scrollEnabled={false}"
        exit 0
    fi
    local missed=()
    [[ "${box_only_entered}" -eq 0 ]] && missed+=("the box-only View")
    [[ "${scroll_view_entered}" -eq 0 ]] && missed+=("the View inside the ScrollView with scrollEnabled={false}")
    if [[ "${#missed[@]}" -eq 2 ]]; then
        echo "SUMMARY: a hover reaches the auto View but neither ${missed[0]} nor ${missed[1]}"
    else
        echo "SUMMARY: a hover reaches the auto View but not ${missed[0]}"
    fi
    exit 1
}

# Prints "x y" for a point inside the node whose content-desc is the label and above the Text centred in it, which sends
# hover events of its own, from a `uiautomator dump`.
hover_point_of() {
    local hierarchy=$1 label=$2 bounds
    bounds="$(sed -nE "s/.*content-desc=\"${label}\"[^>]*bounds=\"\[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\]\".*/\1 \2 \3 \4/p" \
        "${hierarchy}")"
    [[ -n "${bounds}" ]] || return 1
    read -r left top right bottom <<< "${bounds}"
    echo "$(((left + right) / 2)) $((top + (bottom - top) / 5))"
}

# A stylus held in range over a point is a hover; `uinput` takes a configuration entry's type before its data.
stylus_session() {
    local width=$1 height=$2
    shift 2
    printf '{"id":1,"command":"register","name":"Hover reproducer stylus","vid":4617,"pid":1,"bus":"usb","configuration":[{"type":100,"data":[1,3]},{"type":101,"data":[320,330]},{"type":103,"data":[0,1]},{"type":110,"data":[1]}],"abs_info":[{"code":0,"info":{"value":0,"minimum":0,"maximum":%d,"fuzz":0,"flat":0,"resolution":0}},{"code":1,"info":{"value":0,"minimum":0,"maximum":%d,"fuzz":0,"flat":0,"resolution":0}}]}\n' \
        "$((width - 1))" "$((height - 1))"
    printf '%s\n' '{"id":1,"command":"delay","duration":2000}'
    while [[ $# -ge 2 ]]; do
        printf '{"id":1,"command":"inject","events":[3,0,%d,3,1,%d,1,320,1,0,0,0]}\n' "$1" "$2"
        printf '%s\n' '{"id":1,"command":"delay","duration":1500}'
        printf '%s\n' '{"id":1,"command":"inject","events":[1,320,0,0,0,0]}'
        printf '%s\n' '{"id":1,"command":"delay","duration":1000}'
        shift 2
    done
}

main() {
    local here app work
    here="$(cd "$(dirname "$0")" && pwd)"
    app="${here}/ReproducerApp"
    work="$(mktemp -d)"
    trap 'rm -rf "${work}"' EXIT

    local system node_version java_version
    system="$(uname -sm)"
    node_version="$(node --version 2>&1)" || fail_step "node --version: ${node_version}"
    java_version="$(java -version 2>&1)" || fail_step "java -version: ${java_version}"
    echo "${system}, node ${node_version}, ${java_version%%$'\n'*}"

    local device_state
    device_state="$(adb get-state 2>&1)"
    [[ "${device_state}" == "device" ]] || fail_step "adb get-state: ${device_state}"
    local model release sdk abi
    read_device_property model ro.product.model
    read_device_property release ro.build.version.release
    read_device_property sdk ro.build.version.sdk
    read_device_property abi ro.product.cpu.abi
    echo "device: ${model}, Android ${release} (API ${sdk}), ${abi}"
    [[ "${sdk}" -ge 30 ]] || fail_step "the device's shell has uinput from Android 11 (API 30); this one runs API ${sdk}"

    local install_output react_native_version
    install_output="$(cd "${app}" && yarn install --frozen-lockfile --non-interactive 2>&1)" ||
        { printf '%s\n' "${install_output}" | tail -n 20; fail_step "yarn install"; }
    react_native_version="$(cd "${app}" && node -p 'require("react-native/package.json").version' 2>&1)" ||
        fail_step "reading react-native's version: ${react_native_version}"
    echo "react-native ${react_native_version}"

    echo "== ./gradlew :app:assembleRelease -PreactNativeArchitectures=${abi}"
    local build_output
    build_output="$(cd "${app}/android" && ./gradlew --no-daemon --console=plain :app:assembleRelease \
        "-PreactNativeArchitectures=${abi}" 2>&1)" ||
        { printf '%s\n' "${build_output}" | tail -n 40; fail_step "the release build"; }

    local apk install_result
    apk="$(native_path "${app}/android/app/build/outputs/apk/release/app-release.apk")"
    install_result="$(adb install -r "${apk}" 2>&1)" || fail_step "adb install: ${install_result}"
    adb shell am force-stop "${package}"
    adb shell am start -W -n "${package}/.MainActivity" > /dev/null || fail_step "starting ${package}"

    local attempt hierarchy="${work}/hierarchy.xml" ready=0
    for ((attempt = 1; attempt <= 30; attempt += 1)); do
        adb shell uiautomator dump /sdcard/hover-reproducer.xml > /dev/null 2>&1
        adb exec-out cat /sdcard/hover-reproducer.xml > "${hierarchy}" 2> /dev/null
        if grep -qF "content-desc=\"${scroll_view_label}\"" "${hierarchy}"; then
            ready=1
            break
        fi
        sleep 1
    done
    adb shell rm -f /sdcard/hover-reproducer.xml
    [[ "${ready}" -eq 1 ]] || fail_step "the app showed no \"${scroll_view_label}\" after ${attempt} reads of its window"

    local sizes physical override physical_width physical_height logical_width logical_height
    sizes="$(adb shell wm size)" || fail_step "adb shell wm size: ${sizes}"
    sizes="${sizes//$'\r'/}"
    physical="$(sed -nE 's/^Physical size: ([0-9]+x[0-9]+)$/\1/p' <<< "${sizes}")"
    override="$(sed -nE 's/^Override size: ([0-9]+x[0-9]+)$/\1/p' <<< "${sizes}")"
    [[ -n "${physical}" ]] || fail_step "wm size: ${sizes}"
    physical_width="${physical%x*}"
    physical_height="${physical#*x}"
    logical_width="${override:-${physical}}"
    logical_width="${logical_width%x*}"
    logical_height="${override:-${physical}}"
    logical_height="${logical_height#*x}"

    local points=() label point x y
    for label in "${control_label}" "${box_only_label}" "${scroll_view_label}"; do
        point="$(hover_point_of "${hierarchy}" "${label}")" || fail_step "no bounds for \"${label}\""
        read -r x y <<< "${point}"
        echo "hovering \"${label}\" at (${x}, ${y})"
        points+=("$((x * physical_width / logical_width))" "$((y * physical_height / logical_height))")
    done

    local events="${work}/events.txt" events_pid
    adb shell uiautomator events > "${events}" 2>&1 &
    events_pid=$!
    sleep 3
    stylus_session "${physical_width}" "${physical_height}" "${points[@]}" > "${work}/stylus.jsonl"
    local stylus_output
    stylus_output="$(adb shell uinput - < "${work}/stylus.jsonl" 2>&1)" || fail_step "uinput: ${stylus_output}"
    sleep 1
    adb shell pkill -f uiautomator > /dev/null 2>&1
    kill "${events_pid}" > /dev/null 2>&1
    wait "${events_pid}" 2> /dev/null

    report_verdict "${events}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
