#!/usr/bin/env bash
# Mac にバックアップした Gemma モデルを、端末のアプリ外部 files ディレクトリへ push する。
# これにより `flutter run` 後に二度とダウンロードしない（fromFile でロード）。
#
# 前提:
#   - models/gemma-4-E2B-it.litertlm が存在する（無ければ下記 curl でDL）
#   - 先に `flutter run -d <device>` でアプリを一度インストール＆起動済み
#     （files ディレクトリはアプリ自身が起動時に作る。shell の mkdir で作ると
#      所有者の違いでアプリから読めない＝fromFile が効かなくなるので注意）
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

DEST_DIR="$(dirname "$DEST")"
# ディレクトリはアプリ自身に作らせる（shell が mkdir すると所有者が shell になり
# アプリから Permission denied → fromFile が効かず再DLされてしまう）。
if ! adb_d shell "test -d '$DEST_DIR'"; then
  echo "files ディレクトリが無いのでアプリを一度起動して作らせます..."
  adb_d shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  sleep 5
  if ! adb_d shell "test -d '$DEST_DIR'"; then
    echo "ERROR: $DEST_DIR が作られませんでした。アプリを手動で起動してから再実行してください。" >&2
    exit 1
  fi
fi

echo "端末へ push: $DEST"
adb_d push "$MODEL" "$DEST"
echo "完了。アプリで『Gemma』を選ぶと fromFile でロードします（再DLなし）。"
