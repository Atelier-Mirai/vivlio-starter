# S8c `vs furigana` と S8b くるみ表紙の仕様の本文（Fable への相談）

> 作成日: 2026-11-17
> ステータス: **相談中**（Fable へ渡す）
> 出自: 2026-11-17 に、小説の答え（`v2-s8-novel-consultation.md` §4.9・§4.10）から `furigana-spec.md` と `cover-spread-spec.md` を骨格だけで書いた。本文は「S8c・S8b の最初に書き足す」としたが、そのままでは Fable の後に Opus が一人で決めることになる。著者から見える名前とファイルの形が多いので、Fable が使える今日のうちに本文を頼む（2026-11-17 ユーザー決定。Fable が使えるのは 11/17 の 17 時まで。優先は `vs furigana`）

Fable のセッションに、次の「---」より下をそのまま渡す。

---

今日の小説の答え（`v2-s8-novel-consultation.md` §4.9・§4.10）で、`vs furigana`（段階 S8c）と背表紙・くるみ表紙（段階 S8b）は別の仕様書に分けることになり、骨格（決定の表）だけを `furigana-spec.md`・`cover-spread-spec.md` に置きました。本文（範囲・コマンドとファイルの形・組み方・小段階）は空のままです。

お願いは、**二つの仕様書の本文を、Opus がそのまま節へ移せる形で書くこと**です。時間が足りなければ、**`vs furigana` を先に**してください（著者から見える名前とファイルの形が多く、読みの誤りの扱いの判断が難しいため）。

設計のやり直しではありません。骨格の表の決定は前提にしてください。変えるべきだと判断した点は、理由を添えて、ユーザーが選べる形で示してください。

コードの書き換えはしないでください。読む資料は次のとおりです。

1. `furigana-spec.md`・`cover-spread-spec.md`（骨格。§0 の表が前提）
2. `v2-s8-novel-consultation.md` §4.9・§4.10（骨格の出どころ）・§4.7（投稿サイトの記法）
3. `furigana-level-spec.md`（対象の水準 L0〜L4・学年。§3 が `vs furigana` への含意）
4. `PLANNED.md` の「`vs furigana`（半自動ルビ付与）」の項（MeCab の限界・交ぜ書き辞書から取れる表外漢字の読み 125 字・安全性）
5. `v2-migration-plan.md` §4.1 の「判断の線」（決めたことの扱いを三つに分ける表）
6. 表紙の今の仕様: `cover_spec.md`・`cover_auto_generation_spec.md`・`cover-cmyk-color-management-spec.md`・`multivolume-spec.md`（巻ごとの表紙）
7. 実物（`vs furigana`）: `lib/vivlio_starter/cli/index/review_markdown_generator.rb`・`term_line.rb`・`review_queue_manager.rb`（`vs index:auto` のレビューのファイル `_index_glossary_review.md`）・`yomi_inferrer.rb`・`yomi_overrides.rb`（MeCab で読みを推す・natto）・`lib/vivlio_starter/cli/metrics/kanji_levels.rb`（学年の表）・`lib/vivlio_starter/cli/lint/` の交ぜ書き辞書（`mazegaki_dictionary.rb`）・`lib/vivlio_starter/cli/masking.rb`
8. 実物（くるみ表紙）: `lib/vivlio_starter/cli/cover.rb`・`cover/svg_cover.rb`・`build/print_pdf_builder.rb`・`build/print_geometry.rb`・`build/crop_marks_overlay.rb`・`build/cmyk_converter.rb`・`config/book.yml` の `book.cover` と `output.print_pdf` の節・`covers/`

## 1. 今の状態

### 1.1 骨格で決まっていること（蒸し返さない）

**`vs furigana`（`furigana-spec.md` §0）**

- `vs furigana:auto [章]` が候補を調べてレビューのファイルを書き、著者が直して、`vs furigana:apply` が原稿に書き込む。ビルドの段にはしない。
- `furigana.level`（`grade1`〜`grade6`・`junior`・`non_joyo`。既定値なし。無ければ 🔴。`--level` で 1 回だけ変えられる）と `furigana.repeat`（`chapter`・`all`。`novel` は `chapter`、`picture_book` は `all`）。
- 単位は語（形態素）。送り仮名は外に出す（`{食|た}べる`）。字ごとに分けない。
- 読みの出どころは、著者の辞書（`config/furigana.yml`）→ 補助辞書（`MazegakiDictionary.readings`）→ MeCab の順。
- 自動で振らないもの（未知語・読みの候補が複数・補助辞書と MeCab の食い違い・固有名詞）は、レビューのファイルに「読みを書いてください」として場所つきで並べる。
- 既にルビのある箇所・コード・URL・数式には触れない。`apply` は置き換える行を全部見せてから確認し、`.vs-backup/furigana/` へ退避する。2 回走らせても増えない。

**くるみ表紙（`cover-spread-spec.md` §0）**

- `print_pdf` の表紙の形を選ぶキーを 1 つ足す（既定は今のまま＝表 1 と表 4 を別々に。値「くるみ」）。閲覧用の `pdf`・`epub`・`kindle` の表紙は変えない。
- 生成物は `cover_spread_<テーマ>_<判型>_cmyk.pdf`（塗り足しとトンボつき）。くるみのときは別々の入稿用の表紙を作らない。
- 並びは、左綴じが表 4・背・表 1、右綴じが表 1・背・表 4（`traits.binding`）。
- 背幅は、直接の指定（mm）が先で、無ければ「本文のページ数 ÷ 2 × 本文の紙の厚さ ＋ 表紙の紙の厚さ × 2」。どちらも無ければ 🔴。
- 段は `build cover spread`（結合の後）。背の中身は書名と著者名を縦に組む。地は表 1 の端の色か `covers/spine_<テーマ>.*`。背幅が 3mm 未満なら字を入れず 💡。分冊は巻ごと。

### 1.2 実物について分かっていること

- **`vs index:auto` のレビューのファイル**は、本の直下の `_index_glossary_review.md`（Markdown。用語行を `TermLine` が読み書きする）。`vs index:apply` がそれを読んで原稿へ書き込む。ユーザーがレビューのファイルを確認・編集している最中に `vs index:auto` を走らせ直して、編集を上書きした事故があった（2026-10-02）。
- **読みの推定**は、索引の `YomiInferrer` が natto（MeCab）で行い、MeCab が無ければ元の文字を返す。読みの上書きの表（`yomi_overrides.rb`）がある。MeCab は今の `vs` で必須ではない（索引の読みに使う）。
- **学年の表**は `KanjiLevels`（`vs metrics` の漢字の水準）にある。`grade_of` で字の学年を引ける（`furigana-level-spec.md` §3.2）。
- **交ぜ書き辞書**（`mazegaki_dictionary.rb`）から表外漢字の読みが取れることは確かめてあるが、抽出のコード（`MazegakiDictionary.readings`）はまだ無い（`PLANNED.md`）。
- **今の表紙**: 入稿用は `<side>cover_<テーマ>_<判型>_cmyk.pdf`（塗り足し＋トンボ・PDF/X-1a）を表と裏で 1 枚ずつ。テーマは同梱の SVG のひな形（`light`・`dark`・`guide`）か、著者の画像（`master`。`covers/frontcover_master.png` など）。SVG は塗り足しの分だけ viewBox を広げて組み、画像は `cover_bleed: scale`（拡大して流用）か `keep`、`*_bleed.png` があればそれを使う。CMYK への変換は `cmyk_converter.rb`（ICC は `output.print_pdf.icc_profile`）。分冊では巻ごとに表紙を作る。

### 1.3 決まっていない点・気づいた点

`vs furigana`:

1. レビューのファイルの名前・置き場・形（索引と同じ Markdown の行か、別の形か）。1 行に何を載せるか（語・読み・出どころ・場所・前後の文）。著者が「振らない」「この読みで」を書く書き方。
2. 著者がレビューのファイルを編集している最中に `vs furigana:auto` をもう一度走らせたときの扱い（上の事故）。
3. `apply` が書き込む位置。`repeat: chapter` の「章ごとの初出」の数え方（見出し・図のキャプション・脚注・目次に出る語を数えるか。既にルビのある箇所を初出と数えるか）。2 回目以降の `auto` が、前回書き込んだルビをどう見るか。
4. 送り仮名の分け方（MeCab の読みと表層から、語幹の漢字の部分だけに読みを当てる方法。「お茶」「御手洗」のような接頭辞）。熟字訓（「今日」）と当て字の扱い。
5. `config/furigana.yml` の書式（語 → 読み、と「振らない語」）。索引の読みの上書き（`yomi_overrides.rb`）と共有するか。
6. MeCab が無い環境での振る舞い（🔴 で止めるか、著者の辞書と補助辞書だけで進むか）。`vs doctor` に載せるか。
7. 投稿サイトの記法で書き込むか（骨格の論点 1。`notation.web_novel` の本）。
8. 索引の印 `[用語]`・相互参照・行内の属性 `[文字]{.class}` の中の語の扱い。
9. `vs lint`・`vs metrics` の「ルビ候補」との関係（同じ判定を使うか、数が食い違わないか）。
10. 小段階の分け方と確かめ（本書の出力に触れない。どの本で誤りを数えるか）。

くるみ表紙:

11. 表紙の形を選ぶキーの名前と値。紙の厚さのキーの名前と単位（1 枚あたりの mm か、印刷所が示す「連量」「斤量」か）と置き場（`output.print_pdf` の節か、`book` の節か）。背幅を直接書くキー。
12. 本文のページ数の数え方（入稿用 PDF のページ数か。前付・後付・白ページを含むか。分冊の巻ごと）。
13. 表 1 と表 4 が SVG のひな形のとき・著者の画像のときの組み方。背の地の色を「表 1 の端の色」から取る方法（画像の端を読む・SVG の地の色を読む）と、色が合わないときの手。`covers/spine_<テーマ>.*` の寸法の決まり（背幅が本ごとに違う）。
14. 背の文字の組み方（書体・字の大きさを背幅から決める・はみ出すときの手・巻の番号）。左綴じの技術書で背の文字の向き。
15. 帯・袖（カバーの折り返し）は扱うか。
16. KDP のペーパーバックの表紙（表 4・背・表 1 の 1 枚の PDF を求め、背幅の計算式が決まっている）を範囲に入れるか。入れるなら入稿先の違いをどう持つか。
17. 小段階の分け方と確かめ（`pdfinfo`・`pdftotext -bbox`・画素）。

## 2. 問い

### 2.1 `vs furigana`（優先）

`furigana-spec.md` の §1〜§4 の本文を書いてください。§1.3 の 1〜10 に答えを含めてください。とくに次の三つは、著者が直接触る形なので、例を添えてください。

1. レビューのファイルの実例（3〜5 語ぶん。自動で振った語・読みを書いてほしい語・振らない語を含む）と、著者が直した後の形。
2. `config/furigana.yml` の実例。
3. `vs furigana:auto`・`vs furigana:apply` の端末の出力の実例（`terminal-output-notes.md` の決まり。🔴・🟡・💡 の使い分けは「原稿の場所を指す指摘は 🟡」）。

### 2.2 くるみ表紙

`cover-spread-spec.md` の §1〜§3 の本文を書いてください。§1.3 の 11〜17 に答えを含めてください。`book.yml` に足すキーは、雛形に書く形（コメントつき）で示してください。

### 2.3 共通

1. それぞれの小段階の表（「小段階・作るもの・確かめ」の 3 列。`novel-vertical-spec.md` §8.1 と同じ形）。どちらも本書の出力に触れないはずなので、本書の出力を守る確かめをどこで行うかも書いてください。
2. 決めたことのうち、`v2-migration-plan.md` §4.1 の「決めて進め、了承は後で得る」に当たるもの（著者から見える名前など）と、Opus が実装の中で決めてよいもの（判断の軸を添えて）を分けてください。

## 3. 答えの形

- この文書の末尾に「4. 答え」の節として書く。前例は `v2-s8-novel-consultation.md` §4。
- 二つの仕様書の本文を、節の番号つきでそのまま移せる形にする（`furigana-spec.md` の §1〜§4、`cover-spread-spec.md` の §1〜§3。§5・§6 の論点の表も直す）。
- 確かめが要る点（MeCab の送り仮名の分け方が実際の作品でどれだけ当たるか、など）は、Fable が scratchpad で確かめてよい。確かめられなかった点は、確かめる内容と、結果ごとの手を書く。
- 移す先（二つの仕様書のほか、`v2-architecture-spec.md` §7.1・`PLANNED.md` など）を最後に挙げる。移すのは Opus が行う。
