#!/usr/bin/env bash
# Renders the app's deterministic fixtures and a scripted gesture run on the
# iOS simulator, so the UI can be reviewed without a Mac.
#
# Output (uploaded by CI as the GymApp-captures artifact):
#   build/captures/frames/<fixture>.png        one frame per fixture (Pro Max)
#   build/captures/frames/gesture-NN-*.png     one frame per gesture step
#   build/captures/gestures.mp4                screen recording of the gestures
#   build/captures/contact-sheet.png           all frames above, labelled
#   build/captures/small/frames/<fixture>.png  fixtures again on a small iPhone
#   build/captures/small/contact-sheet.png
#   build/captures/devices.txt                 which simulators were used
#
# Exits non-zero if any UI test failed, after exporting everything that exists.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/captures
DD=build/dd-sim
mkdir -p build
rm -rf "$OUT" build/ui-fixtures.xcresult build/ui-gestures.xcresult build/ui-fixtures-small.xcresult
mkdir -p "$OUT"

FAILED=0
REC_PID=""

cleanup() {
  if [ -n "$REC_PID" ] && kill -0 "$REC_PID" 2>/dev/null; then
    kill -INT "$REC_PID" 2>/dev/null || true
    wait "$REC_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Fixture order used for the contact sheets (matches UITests/CaptureTests.swift).
FIXTURES=(
  diet-idle diet-held diet-contact diet-settled prism-half diet-intake
  diet-over-target diet-empty train-ready train-rest train-rest-added
  body-idle a11y-xxl
)

# ---------------------------------------------------------------------------
# Simulator selection
# ---------------------------------------------------------------------------

# Prints "<udid>\t<name>\t<runtime>" for the requested kind of iPhone:
#   large: newest-runtime device whose name contains "Pro Max", else newest iPhone
#   small: iPhone SE / 16e-style device, else the first plain iPhone
PICK_PY='
import json, re, sys

mode = sys.argv[1]
devices = json.load(sys.stdin)["devices"]

def runtime_version(key):
    m = re.search(r"iOS-(\d+)(?:-(\d+))?(?:-(\d+))?", key)
    return tuple(int(x or 0) for x in m.groups()) if m else None

def name_key(name):
    # Natural sort: "iPhone 9" < "iPhone 17". re.split with a capture group
    # alternates str/int, so lists always compare like with like.
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", name)]

cands = []
for key, devs in devices.items():
    version = runtime_version(key)
    if version is None:
        continue
    for d in devs:
        if d["name"].startswith("iPhone") and d.get("isAvailable", True):
            cands.append((version, d["name"], d["udid"], key))

if not cands:
    sys.exit("no iPhone simulator found")

def emit(c):
    print("\t".join((c[2], c[1], c[3])))
    sys.exit(0)

if mode == "large":
    pro_max = [c for c in cands if "Pro Max" in c[1]]
    pool = pro_max or cands
    emit(max(pool, key=lambda c: (c[0], name_key(c[1]))))

if mode == "small":
    def small_rank(name):
        if "SE" in name:
            return 2
        if re.search(r"\b\d+e\b", name):  # iPhone 16e, 17e, ...
            return 1
        return 0
    small = [c for c in cands if small_rank(c[1]) > 0]
    if small:
        emit(max(small, key=lambda c: (c[0], small_rank(c[1]), name_key(c[1]))))
    plain = [c for c in cands
             if not any(w in c[1] for w in ("Pro", "Plus", "Max", "Air"))]
    if plain:
        newest = max(c[0] for c in plain)
        emit(min((c for c in plain if c[0] == newest), key=lambda c: name_key(c[1])))
    sys.exit("no small iPhone simulator found")

sys.exit("unknown mode " + mode)
'

pick_device() {
  xcrun simctl list devices available -j | python3 -c "$PICK_PY" "$1"
}

prepare_sim() {
  local udid=$1
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl status_bar "$udid" override \
    --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 \
    || echo "warning: could not override the status bar on $udid"
}

# ---------------------------------------------------------------------------
# Build and test helpers
# ---------------------------------------------------------------------------

XCB_COMMON=(
  -project GymApp.xcodeproj
  -scheme GymApp
  -derivedDataPath "$DD"
  CODE_SIGNING_ALLOWED=NO
)

XCB_TEST_OPTS=(
  -parallel-testing-enabled NO
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 180
  -maximum-test-execution-time-allowance 300
)

# run_tests <udid> <only-testing> <result bundle> <log>
run_tests() {
  local udid=$1 only=$2 bundle=$3 log=$4
  rm -rf "$bundle"
  if ! xcodebuild test-without-building "${XCB_COMMON[@]}" "${XCB_TEST_OPTS[@]}" \
      -destination "id=$udid" \
      "-only-testing:$only" \
      -resultBundlePath "$bundle" \
      | tee "$log"; then
    echo "error: $only failed on $udid (see $log)"
    FAILED=1
  fi
}

# Moves exported attachments to <dest>/<attachment name>.<ext> using the
# manifest.json written by `xcresulttool export attachments`. Attachments that
# are not ours (automatic failure screenshots etc.) go to <dest>/other/.
RENAME_PY='
import json, os, re, shutil, sys

src, dest = sys.argv[1], sys.argv[2]
with open(os.path.join(src, "manifest.json")) as f:
    manifest = json.load(f)

def walk(node):
    if isinstance(node, dict):
        if "exportedFileName" in node:
            yield node
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)

UUID = r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
SUFFIX = re.compile(r"(_\d+)?_" + UUID + r"$")
OURS = re.compile(r"^[a-z0-9][A-Za-z0-9-]*$")
IMAGE = (".png", ".jpg", ".jpeg", ".heic")

moved = 0
for att in walk(manifest):
    exported = att["exportedFileName"]
    path = os.path.join(src, exported)
    if not os.path.isfile(path):
        continue
    ext = os.path.splitext(exported)[1] or ".png"
    name = att.get("name") or att.get("attachmentName")
    if not name:
        stem = os.path.splitext(att.get("suggestedHumanReadableName", ""))[0]
        name = SUFFIX.sub("", stem)
    if name and OURS.match(name) and ext.lower() in IMAGE:
        target_dir = dest
    else:
        target_dir = os.path.join(dest, "other")
        name = os.path.splitext(att.get("suggestedHumanReadableName") or exported)[0]
        name = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
    os.makedirs(target_dir, exist_ok=True)
    target = os.path.join(target_dir, name + ext)
    n = 2
    while os.path.exists(target):
        target = os.path.join(target_dir, "%s-%d%s" % (name, n, ext))
        n += 1
    shutil.move(path, target)
    moved += 1
    print("  " + os.path.relpath(target, dest))

print("exported %d attachment(s) to %s" % (moved, dest))
'

# export_frames <result bundle> <dest dir> <summary json>
export_frames() {
  local bundle=$1 dest=$2 summary=$3
  if [ ! -d "$bundle" ]; then
    echo "warning: no result bundle at $bundle; nothing to export"
    return 0
  fi
  mkdir -p "$dest"
  xcrun xcresulttool get test-results summary --path "$bundle" > "$summary" 2>/dev/null \
    || echo "warning: could not write test summary for $bundle"
  local tmp
  tmp=$(mktemp -d)
  if xcrun xcresulttool export attachments --path "$bundle" --output-path "$tmp"; then
    if [ -f "$tmp/manifest.json" ]; then
      python3 -c "$RENAME_PY" "$tmp" "$dest" || { echo "error: renaming attachments failed"; FAILED=1; }
    else
      echo "warning: no manifest.json in export of $bundle; copying files as-is"
      cp -R "$tmp"/. "$dest"/ || true
    fi
  else
    echo "error: xcresulttool could not export attachments from $bundle"
    FAILED=1
  fi
  rm -rf "$tmp"
}

# make_sheet <frames dir> <output png>
make_sheet() {
  local dir=$1 output=$2
  local montage_cmd=()
  if command -v montage >/dev/null 2>&1; then
    montage_cmd=(montage)
  elif command -v magick >/dev/null 2>&1; then
    montage_cmd=(magick montage)
  else
    echo "ImageMagick not found; skipping contact sheet $output"
    return 0
  fi

  # Fixtures in their declared order, then gesture steps, then anything else.
  local files=() f name seen
  for name in "${FIXTURES[@]}"; do
    for f in "$dir/$name.png" "$dir/$name-NOT-READY.png"; do
      if [ -f "$f" ]; then files+=("$f"); fi
    done
  done
  for f in "$dir"/gesture-*.png; do
    if [ -f "$f" ]; then files+=("$f"); fi
  done
  for f in "$dir"/*.png; do
    [ -f "$f" ] || continue
    seen=0
    for name in "${files[@]+"${files[@]}"}"; do
      if [ "$name" = "$f" ]; then seen=1; break; fi
    done
    if [ "$seen" = 0 ]; then files+=("$f"); fi
  done
  if [ "${#files[@]}" -eq 0 ]; then
    echo "no frames in $dir; skipping contact sheet"
    return 0
  fi

  local font_opt=()
  for f in /System/Library/Fonts/Supplemental/Arial.ttf /System/Library/Fonts/Helvetica.ttc /Library/Fonts/Arial.ttf; do
    if [ -f "$f" ]; then font_opt=(-font "$f"); break; fi
  done

  "${montage_cmd[@]}" "${font_opt[@]+"${font_opt[@]}"}" -pointsize 22 -fill white -background black \
    -label '%t' "${files[@]}" \
    -tile 7x -geometry 320x+12+12 \
    "$output" \
    && echo "wrote $output" \
    || echo "warning: montage failed; no contact sheet at $output"
}

# ---------------------------------------------------------------------------
# Main run: Pro Max
# ---------------------------------------------------------------------------

MAIN_LINE=$(pick_device large) || { echo "error: no iPhone simulator available"; exit 1; }
IFS=$'\t' read -r MAIN_UDID MAIN_NAME MAIN_RUNTIME <<< "$MAIN_LINE"
echo "Capturing on $MAIN_NAME ($MAIN_RUNTIME, $MAIN_UDID)"
echo "main:  $MAIN_NAME  $MAIN_RUNTIME  $MAIN_UDID" > "$OUT/devices.txt"

prepare_sim "$MAIN_UDID"

if ! xcodebuild build-for-testing "${XCB_COMMON[@]}" -destination "id=$MAIN_UDID" \
    | tee build/ui-build.log; then
  echo "error: building the UI tests failed (see build/ui-build.log)"
  exit 1
fi

run_tests "$MAIN_UDID" GymAppUITests/CaptureTests build/ui-fixtures.xcresult build/ui-fixtures.log

# The recording covers only the gesture run.
xcrun simctl io "$MAIN_UDID" recordVideo --codec=h264 --force "$OUT/gestures.mp4" &
REC_PID=$!
sleep 2
run_tests "$MAIN_UDID" GymAppUITests/GestureTests build/ui-gestures.xcresult build/ui-gestures.log
sleep 1
if kill -0 "$REC_PID" 2>/dev/null; then
  kill -INT "$REC_PID" 2>/dev/null || true
fi
# simctl finalises the mp4 when it receives SIGINT and then exits.
wait "$REC_PID" 2>/dev/null || true
REC_PID=""
if [ -s "$OUT/gestures.mp4" ]; then
  echo "wrote $OUT/gestures.mp4"
else
  echo "warning: no gesture video was recorded"
fi

export_frames build/ui-fixtures.xcresult "$OUT/frames" "$OUT/fixtures-summary.json"
export_frames build/ui-gestures.xcresult "$OUT/frames" "$OUT/gestures-summary.json"
make_sheet "$OUT/frames" "$OUT/contact-sheet.png"

# ---------------------------------------------------------------------------
# Second run: smallest iPhone
# ---------------------------------------------------------------------------

if SMALL_LINE=$(pick_device small); then
  IFS=$'\t' read -r SMALL_UDID SMALL_NAME SMALL_RUNTIME <<< "$SMALL_LINE"
  if [ "$SMALL_UDID" = "$MAIN_UDID" ]; then
    echo "Small device is the same as the main device; skipping the second run"
  else
    echo "Capturing fixtures on $SMALL_NAME ($SMALL_RUNTIME, $SMALL_UDID)"
    echo "small: $SMALL_NAME  $SMALL_RUNTIME  $SMALL_UDID" >> "$OUT/devices.txt"
    xcrun simctl shutdown "$MAIN_UDID" || true
    prepare_sim "$SMALL_UDID"
    mkdir -p "$OUT/small"
    run_tests "$SMALL_UDID" GymAppUITests/CaptureTests build/ui-fixtures-small.xcresult build/ui-fixtures-small.log
    export_frames build/ui-fixtures-small.xcresult "$OUT/small/frames" "$OUT/small/fixtures-summary.json"
    make_sheet "$OUT/small/frames" "$OUT/small/contact-sheet.png"
  fi
else
  echo "warning: no small iPhone simulator found; skipping the second run"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "error: one or more UI capture runs failed; captures exported to $OUT"
  exit 1
fi
echo "UI captures complete: $OUT"
