vs clean --all
vs build --no-clean
🟡 生成対象がありませんでした (pdf/print_pdf ターゲットが無効化されている可能性があります)
🔍 [KPF] 変換ログ: Error=0 / Warning=1（2 CSV）
📚 vivlio_starter_v1.0.0.epub を作成しました (83.6s)

> 🟡 生成対象がありませんでした (pdf/print_pdf ターゲットが無効化されている可能性があります)
=>
これは、targetsにepub, kindleのみを指定している為、出力不要。

> 🔍 [KPF] 変換ログ: Error=0 / Warning=1（2 CSV）
=>
変換ログでのwarning=1が気になる。どのような内容か？

> 📚 vivlio_starter_v1.0.0.epub を作成しました (83.6s)
=>
targets: epub, kindleの場合には、
vivlio_starter_v1.0.0.kpf も作成したので、メッセージに追記を。

epub:
    embed: true # 表紙画像を EPUB に埋め込むか（true: 楽天/Apple向け、false: Kindle向け）
=>
epubに表紙が組み込まれていない。

book.ymlには
# ----------------------------
# EPUB設定
# ----------------------------
epub:
  embed: true # 表紙画像を EPUB に埋め込むか（true: 楽天/Apple向け、false: Kindle向け）
  layout: reflowable # reflowable（リフロー型） / fixed（固定レイアウト型）
  # 注: メタデータ（title, author, language, isbn, publisher）は
  #     book セクションから自動的に流用される
と書いてあるのみなので、今後の分かりやすさの為にも、
# ----------------------------
# Kindle設定
# ----------------------------
kindle:
  embed: false # 表紙画像を EPUB に埋め込むか（true: 楽天/Apple向け、false: Kindle向け）
  layout: reflowable # reflowable（リフロー型） / fixed（固定レイアウト型）
を追加することとしたいがどうか？


epub_codes.pngを参照してください
Apple Books アプリを 特定の大きさにした場合に、ソースコードの出力が消える。
全文出力できるようにしたいが、どのようにすれば良いか？
（ウィンドウの大きさを変えると全てのソースコードの表示はされますが、利用者にそれを強いるのは不本意）

kindle_appendix_chapter_section.pngを参照してください。
「付録A 挑戦することの贈り物」ですが、これは付録章用の装飾が施されるべき。
「言葉の遅い少年」も同様に、付録節用の装飾が施されるべき。

kindle_section.pngを参照してください。
「1-1 全体の流れ」が、ページ途中に出現している。
ページ先頭から始まるべき。（この場合には改ページして次ページの行頭から始まるべき）

kindle_tip_memo_column.pngを参照してください。
期待値
-----------------------
|【TIP】               |
|                     |
-----------------------
(空行)
-----------------------
|【MEMO】              |
|                     |
-----------------------
（空行）
-----------------------
|【COLUMN】            |
|                     |
-----------------------
です。

TIP
【TIP】
=>
【TIP】にしてください。

また、それぞれborder枠が表示されるようにしてください。
