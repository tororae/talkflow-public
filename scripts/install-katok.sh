#!/bin/bash
# Installs the katok CLI that TalkFlow reads KakaoTalk through.
#
# katok publishes signed release archives but no Homebrew tap, so this script
# downloads a pinned release, verifies its published SHA-256, and installs the
# binary where TalkFlow looks for it.
#
# Usage: scripts/install-katok.sh [install-dir]

set -euo pipefail

KATOK_VERSION="0.3.0"
REPO="NomaDamas/katok"
INSTALL_DIR="${1:-/opt/homebrew/bin}"

case "$(uname -m)" in
    arm64) TARGET="aarch64-apple-darwin" ;;
    x86_64) TARGET="x86_64-apple-darwin" ;;
    *) echo "지원하지 않는 아키텍처입니다: $(uname -m)" >&2; exit 1 ;;
esac

ARCHIVE="katok-${KATOK_VERSION}-${TARGET}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/v${KATOK_VERSION}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "katok ${KATOK_VERSION} (${TARGET}) 내려받는 중…"
curl -fsSL "${BASE_URL}/${ARCHIVE}" -o "${WORK_DIR}/${ARCHIVE}"
curl -fsSL "${BASE_URL}/${ARCHIVE}.sha256" -o "${WORK_DIR}/${ARCHIVE}.sha256"

# The published checksum file names the archive under its build directory, so
# compare the digests directly instead of relying on shasum -c resolving paths.
expected="$(awk '{print $1}' "${WORK_DIR}/${ARCHIVE}.sha256")"
actual="$(shasum -a 256 "${WORK_DIR}/${ARCHIVE}" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
    echo "SHA-256 검증 실패. 설치를 중단합니다." >&2
    echo "  기대값: $expected" >&2
    echo "  실제값: $actual" >&2
    exit 1
fi
echo "SHA-256 검증 통과."

tar -xzf "${WORK_DIR}/${ARCHIVE}" -C "$WORK_DIR"
binary="$(find "$WORK_DIR" -type f -name katok -perm -u+x | head -1)"
if [ -z "$binary" ]; then
    echo "받은 아카이브에서 katok 실행 파일을 찾지 못했습니다." >&2
    exit 1
fi

if [ ! -w "$INSTALL_DIR" ]; then
    echo "${INSTALL_DIR}에 쓸 권한이 없습니다. 다른 경로를 인자로 넘기거나 sudo로 실행하세요." >&2
    exit 1
fi

install -m 755 "$binary" "${INSTALL_DIR}/katok"
echo "설치 완료: ${INSTALL_DIR}/katok"
"${INSTALL_DIR}/katok" doctor --json >/dev/null && echo "katok doctor 통과."
