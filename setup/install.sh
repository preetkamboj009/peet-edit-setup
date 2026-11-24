#!/usr/bin/env bash
# Peet Edit installer (macOS, Apple Silicon). Same steps and same last-line JSON as install.ps1: everything goes into
# PEET_HOME (default ~/PeetEdit, where the engine and wrappers look). No admin rights, no Xcode or developer tools; safe to run
# again (finished steps are skipped, downloads resume).
#   --release <file|url>  --app-source <dir>  --update  --skip-models  --skip-sounds  --home <dir>  --skills-dir <dir>
# NOTE: written to mirror install.ps1; not yet run on a Mac.
set -uo pipefail

UV_VERSION="0.11.23"
FF_BASE="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2"
FF_SHA="c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"
FP_SHA="fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6"
RVM_URL="https://github.com/PeterL1n/RobustVideoMatting/releases/download/v1.0.0/rvm_mobilenetv3_fp32.onnx"
RVM_SHA="88d4531297118f595bf2fd60f6f566aec2e559393802d1f436c380f0cbbd2828"
WHISPER_REPO="mobiuslabsgmbh/faster-whisper-large-v3-turbo"

HERE="$(cd "$(dirname "$0")" && pwd)"
RELEASE="$HERE/release.json"; APP_SOURCE=""; UPDATE=0; SKIP_MODELS=0; SKIP_SOUNDS=0
H="${PEET_HOME:-$HOME/PeetEdit}"
SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
while [ $# -gt 0 ]; do
  case "$1" in
    --release) RELEASE="$2"; shift ;; --app-source) APP_SOURCE="$2"; shift ;; --update) UPDATE=1 ;;
    --skip-models) SKIP_MODELS=1 ;; --skip-sounds) SKIP_SOUNDS=1 ;; --home) H="$2"; shift ;;
    --skills-dir) SKILLS="$2"; shift ;; *) echo "unknown option $1" >&2; exit 2 ;;
  esac; shift
done
APP="$H/app"; TOOLS="$H/tools"; VENV="$H/venv"; PY="$VENV/bin/python"; UV="$TOOLS/uv/uv"
DL="$H/scratch/downloads"; STATE="$H/state"; LOG="$H/install.log"; TOTAL=11; STEP=start
export UV_CACHE_DIR="${PEET_UV_CACHE:-$H/cache/uv}" UV_PYTHON_INSTALL_DIR="$H/python" HF_HOME="$H/models/hf"
export PLAYWRIGHT_BROWSERS_PATH="$H/browsers" PEET_HOME="$H"
mkdir -p "$H" "$STATE" "$DL" "$TOOLS"

log()  { printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >> "$LOG"; }
info() { echo "    $*"; log "$*"; }
step() { STEP="$2"; echo "[$1/$TOTAL] $3"; log "[$1/$TOTAL] $3"; }
json_str() { python_free_escape="${1//\\/\\\\}"; printf '"%s"' "${python_free_escape//\"/\\\"}"; }
finish() {  # finish <ok:true|false> <extra json fields without braces>
  rm -f "$STATE/install.lock"
  echo "{\"ok\": $1, \"home\": $(json_str "$H")${2:+, $2}}"
  [ "$1" = true ] && exit 0 || exit 1
}
fail() { log "FAILED at $STEP: $1"; echo "FAILED at step '$STEP': $1"
         finish false "\"step\": \"$STEP\", \"error\": $(json_str "$1"), \"hint\": \"Run setup again: it resumes.\""; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
download() {  # download <url|path> <out> [sha256]
  local url="$1" out="$2" want="${3:-}" i
  if [ -f "$out" ] && { [ -z "$want" ] || [ "$(sha "$out")" = "$want" ]; }; then return 0; fi
  mkdir -p "$(dirname "$out")"
  for i in 1 2 3; do
    local hdr=()
    if [[ "$url" =~ ^https://api\.github\.com/ ]]; then  # a GitHub release asset: the file itself, not its JSON
      hdr=(-H "Accept: application/octet-stream")
      local tok="${PEET_GITHUB_TOKEN:-${GH_TOKEN:-}}"
      [ -n "$tok" ] && hdr+=(-H "Authorization: Bearer $tok")
    fi
    if [[ "$url" =~ ^https?:// ]]; then curl -L --fail --silent --show-error --retry 3 -C - "${hdr[@]}" -o "$out.part" "$url" >>"$LOG" 2>&1
    else cp "$url" "$out.part"; fi
    if [ $? -eq 0 ] && { [ -z "$want" ] || [ "$(sha "$out.part")" = "$want" ]; }; then
      mv -f "$out.part" "$out"; info "got $(basename "$out")"; return 0
    fi
    [ -n "$want" ] && [ -f "$out.part" ] && [ "$(sha "$out.part")" != "$want" ] && rm -f "$out.part"
    log "download try $i failed: $url"
  done
  fail "download failed: $url"
}
run() { log "> $*"; "$@" >>"$LOG" 2>&1 || fail "$(basename "$1") failed (see install.log)"; }
rel() { plutil -extract "$1" raw -o - "$RELJSON" 2>/dev/null; }  # macOS reads JSON without Python

if [ -f "$STATE/install.lock" ] && kill -0 "$(cat "$STATE/install.lock")" 2>/dev/null; then
  STEP=busy; finish false "\"step\": \"busy\", \"error\": \"Another Peet Edit setup is already running.\""
fi
echo $$ > "$STATE/install.lock"
log "---- setup start: home=$H update=$UPDATE"

# 1 checks
step 1 platform "Checking this Mac ($H)"
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || \
  { STEP=platform; finish false '"step": "platform", "error": "Peet Edit needs a Mac with Apple Silicon (M1 or newer)."'; }
FREE_GB=$(df -g "$H" | awk 'NR==2{print $4}')
NEED=$([ -x "$PY" ] && echo 2 || echo 6)
[ "${FREE_GB:-99}" -ge "$NEED" ] || { STEP=disk; finish false "\"step\": \"disk\", \"error\": \"Setup needs about $NEED GB free; there is $FREE_GB GB.\""; }
RELJSON="$DL/release.json"
download "$RELEASE" "$RELJSON"
VER="$(rel version)"; info "release $VER"

# 2 app
step 2 app "The Peet Edit app $VER (engine, skills, styles)"
HAVE="$(cat "$STATE/app.version" 2>/dev/null || true)"
if [ -n "$APP_SOURCE" ]; then
  for d in engine plugin; do mkdir -p "$APP/$d"; rsync -a --delete --exclude __pycache__ --exclude .venv "$APP_SOURCE/$d/" "$APP/$d/" || fail "copy $d"; done
  echo local > "$STATE/app.version"
elif [ "$HAVE" != "$VER" ] || [ $UPDATE = 1 ] || [ ! -f "$APP/engine/pyproject.toml" ]; then
  Z="$DL/$(rel app.file)"; download "$(rel app.url)" "$Z" "$(rel app.sha256)"
  rm -rf "$DL/app-x" && mkdir -p "$DL/app-x" && unzip -q "$Z" -d "$DL/app-x" || fail "could not unpack the app"
  rm -rf "$APP" && mkdir -p "$APP" && mv "$DL/app-x/engine" "$DL/app-x/plugin" "$APP/" || fail "app zip incomplete"
  rm -rf "$Z" "$DL/app-x"; echo "$VER" > "$STATE/app.version"
else info "app $VER already in place"; fi

# 3 uv
step 3 uv "uv $UV_VERSION (Python manager)"
if [ -x "$UV" ] && "$UV" --version | grep -q "$UV_VERSION"; then info "already installed"; else
  A="uv-aarch64-apple-darwin.tar.gz"; B="https://github.com/astral-sh/uv/releases/download/$UV_VERSION/$A"
  rm -f "$DL/$A.sha256"; download "$B.sha256" "$DL/$A.sha256"
  download "$B" "$DL/$A" "$(cut -d' ' -f1 < "$DL/$A.sha256")"
  mkdir -p "$TOOLS/uv" && tar -xzf "$DL/$A" -C "$TOOLS/uv" --strip-components 1 || fail "could not unpack uv"
  rm -f "$DL/$A" "$DL/$A.sha256"
fi

# 4 python
step 4 python "Python 3.12 and a virtual environment"
if [ -x "$PY" ] && [ "$("$PY" -c 'import sys; print(sys.version_info[:2] == (3, 12))')" = True ]; then info "already in place"
else rm -rf "$VENV"; run "$UV" python install 3.12; run "$UV" venv "$VENV" --python 3.12; fi

# 5 engine
step 5 engine "The engine and its packages (~500 MB)"
run "$UV" export --project "$APP/engine" --frozen --no-dev --no-emit-project --no-hashes -q -o "$DL/requirements.txt"
run "$UV" pip sync --python "$PY" "$DL/requirements.txt"
run "$UV" pip install --python "$PY" --no-deps -e "$APP/engine"
rm -f "$DL/requirements.txt"

# 6 ffmpeg
step 6 ffmpeg "ffmpeg 9.0.2 + ffprobe (~55 MB, checksum-verified)"
FF="$TOOLS/ffmpeg/bin"; mkdir -p "$FF"
for b in ffmpeg ffprobe; do
  if [ -x "$FF/$b" ]; then info "$b already installed"; continue; fi
  S=$([ $b = ffmpeg ] && echo "$FF_SHA" || echo "$FP_SHA")
  download "$FF_BASE/$b.zip" "$DL/$b.zip" "$S"
  unzip -qo "$DL/$b.zip" -d "$FF" && chmod +x "$FF/$b" && xattr -d com.apple.quarantine "$FF/$b" 2>/dev/null; rm -f "$DL/$b.zip"
done
export PATH="$FF:$PATH"

# 7 browser
step 7 browser "A browser for drawing the graphics"
if [ -d "/Applications/Google Chrome.app" ] || [ -d "/Applications/Microsoft Edge.app" ]; then info "Chrome or Edge found: using it"
else info "no Chrome or Edge: downloading Chromium (~350 MB)"; run "$PY" -m playwright install chromium; fi

# 8 models
step 8 models "AI models: person cut-out (15 MB), speech-to-text (~1.6 GB)"
[ -f "$H/models/rvm_mobilenetv3_fp32.onnx" ] && info "cut-out model already present" || download "$RVM_URL" "$H/models/rvm_mobilenetv3_fp32.onnx" "$RVM_SHA"
mkdir -p "$HF_HOME"
if [ $SKIP_MODELS = 1 ]; then info "speech model skipped (--skip-models): the first transcribe downloads it"; else
  info "speech model: downloading (resumes if interrupted; the long one)"
  run "$PY" -c "from huggingface_hub import snapshot_download as s; s('$WHISPER_REPO', allow_patterns=['config.json','preprocessor_config.json','model.bin','tokenizer.json','vocabulary.*'])"
fi

# 9 sounds
step 9 sounds "Sound packs"
if [ $SKIP_SOUNDS = 1 ]; then info "skipped (--skip-sounds)"; else
  i=0
  while P="$(rel "sfx.$i.pack")" && [ -n "$P" ]; do
    MARK="$H/sfx/$P/.sha256"; WANT="$(rel "sfx.$i.sha256")"
    if [ -f "$MARK" ] && [ "$(cat "$MARK")" = "$WANT" ] && [ $UPDATE = 0 ]; then info "$P: already in place"
    else
      Z="$DL/$(rel "sfx.$i.file")"; download "$(rel "sfx.$i.url")" "$Z" "$WANT"
      mkdir -p "$H/sfx" && unzip -qo "$Z" -d "$H/sfx" || fail "could not unpack the $P sounds"
      echo "$WANT" > "$MARK"; rm -f "$Z"; info "$P: $(rel "sfx.$i.sounds") sounds"
    fi
    i=$((i + 1))
  done
fi

# 10 skills
step 10 skills "The Peet Edit skills for Claude"
mkdir -p "$H/playbooks" "$SKILLS/peet"
rsync -a --delete "$APP/plugin/" "$SKILLS/peet/" || fail "could not copy the skills"
chmod +x "$SKILLS/peet/bin/peet"
if [ "$H" != "$HOME/PeetEdit" ]; then  # the wrapper must find this home without PEET_HOME
  sed -i '' "s|^H=\"\${PEET_HOME:-\$HOME/PeetEdit}\"|H=\"\${PEET_HOME:-$H}\"|" "$SKILLS/peet/bin/peet"
fi
info "skills at $SKILLS/peet (start a new Claude session to use them)"

# 11 doctor
step 11 doctor "Putting peet on your PATH and checking everything"
mkdir -p "$H/bin" && cp "$SKILLS/peet/bin/peet" "$H/bin/peet" && chmod +x "$H/bin/peet"
LINE="export PATH=\"$H/bin:\$PATH\""
grep -qsF "$LINE" "$HOME/.zprofile" || { echo "$LINE" >> "$HOME/.zprofile"; info "added $H/bin to your PATH (new terminals know 'peet')"; }
DOC="$("$H/bin/peet" doctor 2>/dev/null | tail -1)"
rm -rf "$H/scratch"; [ -z "${PEET_UV_CACHE:-}" ] && rm -rf "$UV_CACHE_DIR"
SIZE=$(du -sm "$H" | cut -f1)
READY=$(echo "$DOC" | grep -q '"ready": true' && echo true || echo false)
finish true "\"version\": \"$VER\", \"doctor_ready\": $READY, \"doctor\": ${DOC:-null}, \"skills\": $(json_str "$SKILLS/peet"), \"size_mb\": $SIZE"
