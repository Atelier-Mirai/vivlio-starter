#!/usr/bin/env bash
# Type 3 フォント回帰の高速検証ループ（~10秒）。
#
# フル `vs build`（数分）を回さずに、フォント埋め込み層だけを素早く検査する。
# type3-check.html を vivliostyle で直接ビルドし、pdffonts で Type 3 を数える。
#
# リポジトリ root には vivliostyle.config.js があり単一 HTML ビルドの邪魔になるため、
# 一時ディレクトリへ HTML をコピーし、フォント参照を絶対パス化してからビルドする。
#
# 使い方:  test/vivlio_starter/fixtures/type3/verify.sh
# 前提:    リポジトリ root に node_modules（vivliostyle）と poppler の pdffonts。
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../../.." && pwd)"
viv="$root/node_modules/.bin/vivliostyle"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Chrome は絶対パスの @font-face url() を読み込まないため、フォントを作業ディレクトリへ
# 複製し相対参照のまま使う。あわせて vivliostyle.config.js の無い一時ディレクトリで
# ビルドし、リポジトリの config を拾わせない。
mkdir -p "$work/stylesheets"
cp -R "$root/stylesheets/fonts" "$work/stylesheets/fonts"
sed "s#\.\./\.\./\.\./\.\./stylesheets#stylesheets#g" \
  "$here/type3-check.html" > "$work/index.html"

( cd "$work" && "$viv" build "index.html" -o "out.pdf" --log-level silent )

echo "=== pdffonts ==="
pdffonts "$work/out.pdf"
n=$(pdffonts "$work/out.pdf" | grep -c "Type 3" || true)
echo
echo ">>> Type 3 フォント数: $n"
[ "$n" -eq 0 ] && echo "✅ Type 3 なし" || { echo "❌ Type 3 検出"; exit 1; }
