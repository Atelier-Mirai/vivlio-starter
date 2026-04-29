Vivlio Verso — 「verso」はラテン語で「裏のページ」「左ページ」。本の製版用語でありながら「ver.2」の音も重なります。そして「裏側を作り直す」という再設計の含意が、リファクタリングの意図と綺麗に重なります。

vs build
🟡 PDF しおり（アウトライン）の付与は Standard モード(MIT) ではサポートされていません。
索引語辞書(config/index_glossary_terms.yml)が見つかりませんでした
⚠️  原稿に [用語|読み] という書き方で手動登録した語のみが索引に載ります
⚠️  自動索引機能を有効にするには: vs index:auto -> vs index:apply

変更内容
1. 
pdf.rb
 — preflight press-ready 対応
PdfCommandRunner#build_command に --preflight press-ready オプションを追加
book.yml の output.pdf.preflight で制御（press-ready / true で有効、未設定で無効）
Ghostscript が PDF を後処理し、Type 3 フォント（カラー絵文字含む）を CID フォントに正規化
2. 
css_updater.rb
 — タイトル同期
sync_vivliostyle_config_title! メソッドを追加
ビルド前処理で vivliostyle.config.js の title を book.yml の main_title + subtitle に自動同期
update_page_settings_css から呼び出し
3. 
book.yml
 — preflight 設定追加
output.pdf.preflight: press-ready を追加
4. 
page-settings.css
 / 
page-settings.css
本文フォントを BIZ UDMincho（静的 TTF）に差し替え
見出しフォントを BIZ UDGothic（静的 TTF）に差し替え
font-family 名は "Noto Serif JP" / "Noto Sans JP" を維持（CSS 変数の変更不要）
5. 
chapter-common.css
 — generic family 排除
sans-serif → var(--font-header) に変更（3 箇所）
keyfont, monospace → keyfont, var(--font-code) に変更
6. 
prism.css
 — generic family 排除
Consolas, Monaco, ... → var(--font-code), monospace に変更
7. フォントファイル追加
stylesheets/fonts/BIZ_UDMincho/ — Regular, Bold
stylesheets/fonts/BIZ_UDGothic/ — Regular, Bold
scaffold 側にも同一ファイルを配置