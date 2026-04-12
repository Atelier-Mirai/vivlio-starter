## フォント運用メモ

1. **標準フォント（ローカル常備）**
   - `stylesheets/fonts/` に標準添付フォント（Noto Serif JP / Noto Sans JP / Zen Maru Gothic / hackgen35）を配置済みとする。
   - `page-settings.css` では `@font-face` でローカルファイルを参照する。
   - `config/book.yml` の `main_text_font` などに標準名を書くだけで利用できる。

2. **利用者指定フォント（Google Fonts から取得）**
   - ビルド時、`config/book.yml` に標準名以外のフォントがあるかチェックする。
   - 未配備フォントは Google Fonts CSS（例: `https://fonts.googleapis.com/css2?family=Zen+Kurenaido&display=swap`）を取得し、参照される `woff2` などを `stylesheets/fonts/` に保存する。
   - ダウンロード済みかどうかはファイル存在で判定し、再ビルド時はネットアクセス不要とする。