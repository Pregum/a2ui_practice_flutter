#!/usr/bin/env bash
# Mac にバックアップした Gemma モデルを、端末のアプリ外部 files ディレクトリへ push する。
# これにより `flutter run` 後に二度とダウンロードしない（fromFile でロード）。
#
# 前提:
#   - models/gemma-4-E2B-it.litertlm が存在する（無ければ下記 curl でDL）
#   - 先に `flutter run -d <device>` でアプリを一度インストール済み
#     （クリーン再インストールする `flutter test` ではデータが消えるので注意）
#
# 使い方: scripts/push_gemma_model.sh [device-id]
set -euo pipefail

DEVICE="${1:-}"
PKG="com.xtone.a2ui_support_demo"
MODEL="models/gemma-4-E2B-it.litertlm"
URL="https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm"
DEST="/storage/emulated/0/Android/data/${PKG}/files/gemma-4-E2B-it.litertlm"

adb_d() { if [ -n "$DEVICE" ]; then adb -s "$DEVICE" "$@"; else adb "$@"; fi; }

if [ ! -f "$MODEL" ]; then
  echo "モデルが無いのでDLします（2.4GB・認証不要）..."
  mkdir -p models
  curl -L --fail -o "$MODEL" "$URL"
fi

echo "端末へ push: $DEST"
adb_d shell mkdir -p "$(dirname "$DEST")"
adb_d push "$MODEL" "$DEST"
echo "完了。アプリで『Gemma』を選ぶと fromFile でロードします（再DLなし）。"
