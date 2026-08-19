#!/bin/bash
# TalkFlow를 macOS 앱 번들로 묶고 Developer ID로 서명한다.
#
# 왜 번들이어야 하는가:
#
# Swift 패키지는 맨 실행 파일을 만든다. 맨 실행 파일은 자기 TCC 신원이 없어서
# macOS가 권한 요청을 "책임 프로세스"(그것을 실행시킨 터미널이나 에디터)에게
# 묻는다. 그래서 TalkFlow가 카카오톡 컨테이너를 읽을 때마다 엉뚱한 앱 이름으로
# 허용을 묻는 창이 뜬다. 게다가 SwiftPM의 adhoc 서명은 빌드마다 달라지므로
# 한 번 허용해도 다음 빌드에서 처음부터 다시 묻는다.
#
# Developer ID로 서명한 번들은 designated requirement가 팀 ID 기준이라
# 재빌드해도 같은 신원으로 인식된다. 허용이 한 번으로 끝난다.
#
# Usage: scripts/build-app.sh [--debug] [--install]
#   --debug    release 대신 debug 구성으로 빌드한다
#   --install  ~/Applications 로 설치한다

set -euo pipefail

APP_NAME="TalkFlow"
# 자기 도메인의 값을 넘긴다. 역DNS라 소유한 도메인이어야 하고, 예시값 그대로
# 빌드하면 남의 이름으로 서명하는 셈이 된다.
#
# 그리고 이 값을 바꾸면 권한을 다시 받아야 한다. 접근성·자동화 승인은 번들
# ID와 팀 ID에 걸려 있어서(PLATFORM-FINDINGS 8절), 다른 번들 ID로 빌드한
# 앱은 macOS 입장에서 다른 앱이다. 이미 승인을 받아 둔 맥에서는 예전 값을
# 그대로 넘겨야 그 승인이 살아 있다.
BUNDLE_ID="${TALKFLOW_BUNDLE_ID:-com.example.talkflow}"
MIN_MACOS="15.0"

CONFIG="release"
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG="debug" ;;
        --install) INSTALL=1 ;;
        *) echo "알 수 없는 인자: $arg" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_DIR=".build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"

# 서명 신원은 골라서 쓰지 않고 찾는다. 여러 개면 사람이 정해야 한다.
identities="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' || true)"
identity_count="$(printf '%s' "$identities" | grep -c . || true)"
if [ "$identity_count" -eq 0 ]; then
    echo "Developer ID Application 인증서를 찾지 못했습니다." >&2
    echo "adhoc 서명으로는 TCC 허용이 빌드마다 초기화되므로 번들을 만들 이유가 없습니다." >&2
    exit 1
fi
if [ "$identity_count" -gt 1 ]; then
    echo "Developer ID Application 인증서가 여러 개입니다. 하나만 남기거나 스크립트를 고쳐 지정하세요." >&2
    printf '%s\n' "$identities" >&2
    exit 1
fi
SIGN_ID="$(printf '%s' "$identities" | sed -n 's/.*"\(.*\)".*/\1/p')"
echo "서명 신원: ${SIGN_ID}"

echo "빌드 중 (${CONFIG})…"
swift build -c "$CONFIG" --product "$APP_NAME"
BUILT_BINARY="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"
if [ ! -x "$BUILT_BINARY" ]; then
    echo "빌드 산출물을 찾지 못했습니다: ${BUILT_BINARY}" >&2
    exit 1
fi

echo "번들 조립 중…"
rm -rf "$APP_DIR"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp "$BUILT_BINARY" "${CONTENTS}/MacOS/${APP_NAME}"

# 버전은 커밋에서 끌어온다. 손으로 관리하면 반드시 어긋난다.
SHORT_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.1")"
BUILD_VERSION="$(git rev-list --count HEAD 2>/dev/null || echo "1")"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>대기 중인 답장을 카카오톡 창에 입력하기 위해 카카오톡을 제어합니다.</string>
</dict>
</plist>
PLIST

# katok을 번들에 넣는다. KatokConnection이 Contents/Resources/katok을 가장 먼저
# 보고, 번들 안에 있으면 그 실행 파일도 이 앱의 신원 아래에서 돈다.
KATOK_SRC=""
for candidate in /opt/homebrew/bin/katok /usr/local/bin/katok; do
    [ -x "$candidate" ] && KATOK_SRC="$candidate" && break
done
if [ -n "$KATOK_SRC" ]; then
    cp "$KATOK_SRC" "${CONTENTS}/Resources/katok"
    echo "katok 포함: ${KATOK_SRC}"
else
    echo "katok을 찾지 못했습니다. 앱은 /opt/homebrew/bin 을 실행 시점에 다시 찾습니다."
fi

# Hardened runtime 아래에서 다른 앱에 Apple Event를 보내려면 이 자격이 있어야 한다.
# 샌드박스 자격은 넣지 않는다 — 카카오톡 컨테이너를 읽어야 하는 앱이다.
ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key><true/>
</dict>
</plist>
PLIST

echo "서명 중…"
# 안쪽부터 서명한다. 바깥 서명이 안쪽 내용을 봉인하므로 순서가 뒤바뀌면 깨진다.
if [ -f "${CONTENTS}/Resources/katok" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_ID" "${CONTENTS}/Resources/katok"
fi
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_ID" "$APP_DIR"

echo "검증 중…"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [ "$INSTALL" -eq 0 ]; then
    echo "완료: ${APP_DIR}"
    exit 0
fi

INSTALLED="$HOME/Applications/${APP_NAME}.app"

# 돌고 있는 앱의 번들을 갈아치우면 그 프로세스는 그대로 죽는다. 조용히
# 죽이고 끝내면 앱이 사라진 줄 모르고 답장이 멈춘 채로 남으므로, 멈춘
# 사실과 다시 띄운 사실을 둘 다 말한다.
WAS_RUNNING=0
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    WAS_RUNNING=1
    echo "실행 중인 ${APP_NAME}을 종료합니다…"
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.5
    done
    pgrep -x "$APP_NAME" >/dev/null 2>&1 && pkill -x "$APP_NAME" || true
fi

# 서명은 번들 전체를 봉인하므로 남은 파일이 있으면 검증이 깨진다. 지우고
# 새로 넣는 이유가 그것이고, 그 대가가 아래 경고다.
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED"
cp -R "$APP_DIR" "$HOME/Applications/"
echo "설치 완료: ${INSTALLED}"

if [ "$WAS_RUNNING" -eq 1 ]; then
    open "$INSTALLED"
    echo "${APP_NAME}을 다시 띄웠습니다."
fi

cat <<'NOTE'

── 권한 확인 ──────────────────────────────────────────────
번들을 교체하면 macOS가 카카오톡 데이터 접근 동의를 다시 물을 수 있습니다.
그 대화상자에 답하기 전까지 앱은 실패하지 않고 **멈춥니다** — 화면에는
"감지 중"이 그대로 켜져 있습니다.

대화상자는 최전면 앱이 있는 화면에 뜹니다. 외장 모니터를 쓰신다면 거기를
보세요.

매번 묻지 않게 하려면 전체 디스크 접근에 앱을 등록해 두는 편이 낫습니다.
  시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 → +
  경로: ~/Applications/TalkFlow.app

멈췄는지 확인:
  sample $(pgrep -x TalkFlow) 2 -f /dev/stdout | grep -c contentsOfDirectoryAtURL
  0이면 정상입니다.
───────────────────────────────────────────────────────────
NOTE
