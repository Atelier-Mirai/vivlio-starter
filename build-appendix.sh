#!/usr/bin/env bash
# 簡易ビルドスクリプト（表の配置確認用）
# 使い方: プロジェクトルートで実行
#   ./build-appendix.sh [MD_ID] [HTML_FILE]
# 例:
#   ./build-appendix.sh 93-appendix-c 93-appendix.html

set -euo pipefail

MD_ID="${1:-93-appendix-c}"
HTML_FILE="${2:-93-appendix.html}"

echo "▶ 前処理: ${MD_ID}"
rake pre_process "${MD_ID}"

echo "▶ 変換: ${MD_ID}"
rake convert "${MD_ID}"

echo "▶ 後処理: ${MD_ID}"
rake post_process "${MD_ID}"

echo "▶ PDF ビルド: ${HTML_FILE}"
vivliostyle build "${HTML_FILE}"

echo "▶ 出力を開く"
rake open

echo "✅ 完了: ${MD_ID} → ${HTML_FILE}"
