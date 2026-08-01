# ビルドをターゲット別に並列化する（PDF 枝 ∥ EPUB/Kindle 枝）仕様書

調査日: 2026-08-01 / 調査・設計・実装: Claude (Opus 5)
状態: **実装済み**（2026-08-01。実測 535.51s → 359.55s・−32.9%。→ §9 実装記録）
対象: `PLANNED.md` 「ビルド / 出力」— ビルド時間の短縮

関連:
`front-back-matter-single-render-spec.md`（**前提工程**。§3.3 の共有状態を解消する）、
`kindle-rotate-table-image-spec.md`（実装すると枝間に依存が生まれる。§6 で調整）、
`vivlioverso-p4-investigation.md`（消費者 dir 分離。本仕様が乗る土台）

---

## 0. 背景・効果

### 0.1 実測の枝分け

A5・515 ページ・`targets: pdf, epub, kindle` のフルビルド（2026-08-01 実測・TOTAL 553.25s）を、
共有前段・PDF 枝・EPUB 枝に分けて足すと次のようになる。

| 相 | ステップ | 実測 |
|---|---|---|
| 共通 | clean / optimize images / prepare theme images / preprocess sections / index scan and build / convert sections html / generate part title pages / techbook post-process / generate toc html | **16.19s** |
| PDF 枝 | build overall pdf 148.06 + backlink dedup 153.43 + build front and back matter 71.10 + merge all pdfs 2.98 + apply outline 30.91 + compress and rename 0.06 | **406.54s** |
| EPUB 枝 | generate epub（EPUB＋Kindle＋KPF 変換） | **130.52s** |
| 合流 | final clean | 0.00s |
| | 逐次合計 | **553.25s**（実測と一致） |

```
並列後 = 16.19 + max(406.54, 130.52) + 0.00 = 422.73s
削減   = 130.52s（23.6%）
```

**EPUB 枝がまるごと PDF 枝の陰に隠れる。**

### 0.2 分岐は 2 本でよい

`html → pdf` / `html → epub` / `html → kindle` の 3 本に割る案も考えられるが、**壁時計は 1 秒も縮まない**。
PDF 枝が EPUB 枝の 3.1 倍あり、そこが臨界経路だからである。EPUB と Kindle を割っても
両方とも PDF 枝より短いまま終わる。

分けるのは **`PDF`（`print_pdf` の導出を含む） ∥ `EPUB → Kindle`（枝の中は逐次）** の 2 本。
枝を増やさないぶん、共有状態の洗い出し（§3）も 1 組で済む。

なお EPUB 枝内の EPUB / Kindle の内訳は未計測である（KPF 変換が支配的と見られる）。
**設計はこの内訳に依存しない**——枝全体が PDF 枝より短ければ、内訳がどうであれ結論は変わらない。

### 0.3 他の高速化との合成

`front-back-matter-single-render-spec.md`（前付・奥付を本文と 1 回で組む・−68.05s）と
本仕様は独立に効く。両方入れると:

| | 共通前段 | PDF 枝 | EPUB 枝 | 合計 |
|---|---|---|---|---|
| 現状 | 16.2s | 406.5s | 130.5s | **553.25s** |
| 前付・奥付のみ | 19.2s | 約 337s | 130.5s | **約 487s** |
| 前付・奥付＋並列化 | 19.2s | 約 337s | （隠れる） | **約 356s** |

**553 秒 → 約 356 秒（−36%）。** しかも前者は本仕様の依存 §3.3 を副産物として解消するので、
**前付・奥付 → 並列化の順**で実装するのが素直である。

---

## 1. 方針

### 1.1 ステップ表に「相」を持たせる

`pipeline.rb` の `full_mode_step_table` は「1 枚の宣言的ステップ表を上から評価する」設計で、
これは分岐爆発を潰すために意図して選ばれた形（`register_full_mode_steps` のコメント「課題 A」）。
**この性質を壊さない。** 各行に第 4 要素として相（phase）を足すだけにする。

```ruby
# 各行 = [ラベル, ハンドラ, 実行条件, 相]
# 相は :shared → (:pdf ∥ :epub) → :join の順に評価される
['generate toc html',   -> { … }, true,              :shared],
['build overall pdf',   -> { … }, need_viewing_pdf,  :pdf],
['generate epub',       -> { epub_flow.run! }, t.epub_or_kindle?, :epub],
['final clean',         -> { run_final_clean }, …,   :join],
```

実行側は相ごとに刈り取って走らせる。

```ruby
def run
  ensure_entry_files_exist!
  Common.ensure_build_workspace!
  Common.reset_vivliostyle_build_timings
  run_phase(:shared)
  if fork_branches?
    run_branches_in_parallel
  else
    run_phase(:pdf)
    run_phase(:epub)
  end
  run_phase(:join)
  timings
end

# 両枝に実際の仕事があるときだけ分岐する。
# pdf 単独・epub 単独のビルドでは分岐しない（スレッドを起こす意味がない）。
def fork_branches? = parallel_enabled? && phase_steps(:pdf).any? && phase_steps(:epub).any?
```

`:single` / `:preflight` モードは相を持たない（すべて `:shared` 扱い）。

### 1.2 逐次へ戻せること

`VIVLIO_BUILD_PARALLEL=0` で分岐を無効化し、現行と同じ逐次実行に落とせるようにする。
章単位の並列度を持つ既存の `VIVLIO_BUILD_CONCURRENCY`（`section_builder.rb:198`）と
同じ流儀の環境変数にそろえる。**`book.yml` には出さない**——これは著者の本の性質ではなく、
実行機と切り分け作業の都合だからである。

逐次へ戻せることは性能の保険ではなく**切り分けの道具**である。並列化後に出た不具合が
並列由来かどうかを、1 コマンドで判定できる状態を保つ。

---

## 2. 枝の切り分け

| ステップ | 相 | 根拠 |
|---|---|---|
| clean / optimize images / prepare theme images | `:shared` | 生成資産キャッシュを両枝が読む |
| preprocess sections / index scan and build | `:shared` | `html/` の原本を作る |
| convert sections html / generate part title pages | `:shared` | 〃 |
| techbook post-process / generate toc html | `:shared` | 〃 |
| **（新）特殊ページ HTML 生成** | `:shared` | §3.3。`front-back-matter-single-render-spec.md` §2.1 が移す |
| **（新）カバー資産生成** | `:shared` | §3.2 |
| build overall pdf | `:pdf` | |
| generate entries.js | `:pdf` | |
| backlink dedup | `:pdf` | 書き換えは `pdf/` に閉じる（P4 §3.4-3） |
| build front and back matter | `:pdf` | レンダのみ残る（HTML 生成は `:shared` へ） |
| merge all pdfs / apply outline | `:pdf` | |
| compress and rename | `:pdf` | |
| print pdf | `:pdf` | 閲覧用 PDF から導出するため（`print-pdf-derivation-spec.md`） |
| generate epub | `:epub` | |
| final clean | `:join` | ワークスペースを消すので両枝の完了後 |

**臨界経路である PDF 枝をメインスレッドで走らせ、EPUB 枝を子スレッドへ出す。**
こうすると進捗表示（§3.4）と `Interrupt`（§3.6）がどちらも自然な側に付く。

---

## 3. 解消すべき共有状態

以下はすべて**実物を見て確認した**もので、推測ではない。

### 3.1 `workspaceDir` を 5 つの config が共有している【必須】

`vivliostyle.config.{sections,front,colophon}.js` と EPUB / Kindle の config が、
そろって `workspaceDir: '.cache/vs/build/.vivliostyle'` を指している
（`vivliostyle_config_writer.rb:104` と `epub_builder.rb:374` の 2 箇所が出所）。

このディレクトリの中身を数えたところ **15,263 ファイル**あり、`covers/` `docs/` `images/`
`lib/` `stylesheets/` `test/` とプロジェクトの木がまるごと写されている。さらに直下に
**`publication.json` が 1 個**あり、これは各ビルドが自分のエントリ一覧で上書きするものである。

**2 つの vivliostyle が同時に走れば確実に踏み合う。** 分岐前に必ず分ける。

分け方には落とし穴がある。`common.rb:59` が
**「4 消費者 dir は同一深度（ルートから 4 階層）にすることが仕様の要」**（P4 §3.1）と書いており、
資産への相対プレフィックスがこの深度に依存している。したがって

- ❌ `.cache/vs/build/.vivliostyle/pdf`（5 階層になる）
- ✅ `.cache/vs/build/.vivliostyle-pdf` / `.vivliostyle-epub`（現行と同じ 4 階層）

を採る。`clean` は `BUILD_DIR` を `rm_rf` するので掃除は自動で追従する
（`BUILD_DIR` を glob して中身を列挙している箇所は無いことを確認済み）。

### 3.2 カバー生成を両枝が呼ぶ【必須】

**両枝がまったく同じ `CoverCommands.ensure_cover_files_for_build!` を呼ぶ。**

- PDF 枝: `PdfMerger.ensure_cover_assets_for_page_size!`（`pdf_merger.rb:88`）→ `merge all pdfs` の中
- EPUB 枝: `EpubFlow#generate_cover_if_needed`（`epub_flow.rb:104`）

この関数は `.cache/vs/covers/` へ `frontcover_master_a5_rgb.pdf` / `backcover_master_a5_rgb.pdf` /
`cover_master.jpg` を `magick` と `rsvg-convert` で書き出す。今は PDF 枝が先に走り、
EPUB 枝は「既に存在します」でスキップしているだけ（デバッグログで確認）。

**依存ではなく競合である。** 並列化すると同じファイルへ 2 つの `magick` が同時に書き、
半端なファイルを他方が読む窓が開く。PdfMerger 側の `cover_generation_attempts` メモは
インスタンス内でしか効かず、EpubFlow とは調停しない。

**カバー生成は本文レンダに一切依存しない**ので、`:shared` 相へ引き上げて両枝の呼び出しを
削るのが正解。引き上げ先は `prepare theme images` の隣が自然（同じ「資産の事前生成」）。

### 3.3 `html/` への書き込みが PDF 枝に残っている【2026-08-01 解消済み】

EPUB のスパイン 36 件の末尾は `./_colophon.html` である（`entries.epub.js` を実見）。
`EpubBuilder.stage_consumer_htmls!`（`epub_builder.rb:110`）が `html/` から読んで消費者 dir へ写す。

ところが `_colophon.html` を **`html/` へ書くのは PDF 枝の
`PdfBuilder.build_front_pages_and_tail!`**（`pdf_builder.rb:167`）である。
つまり今のままでは **EPUB 枝が読む最中に PDF 枝が書く**。

`front-back-matter-single-render-spec.md` §2.1 がこの生成を共通前段へ前倒しした
（`generate front and back matter html` ステップ）。**2026-08-01 の実装で本項は解消済み**で、
`:pdf` 相に `html/` へ書くステップはもう無い。§7 の回帰テストでその状態を固定する。

### 3.4 進捗表示（Spinner）が TTY を奪い合う

`Spinner.while(label)` は呼び出しごとに新しいインスタンスを作り、それぞれが自前の
`Mutex` と `Thread` で `$stdout` へ書く（`spinner.rb:42, 52, 90`）。**互いの排他は取れていない。**
2 枝が同時に回せば行が混ざる。

**採る方針: 子枝（EPUB）のログをバッファし、合流時にまとめて吐く。**

- TTY の奪い合いが構造的に起きない（書き手が常に 1 つ）
- ログの読み順が「共通前段 → PDF 枝 → EPUB 枝」と安定し、ビルドログの diff が取れる
- 実装が小さい（`Common.emit` に差し替え可能な出力先を 1 つ足すだけ）

EPUB 枝は PDF 枝より先に終わるので、著者から見れば「合流時に EPUB のログがまとめて出る」
という体験になる。分岐の直後に 1 行だけ予告を出す。

```
🔧 [parallel] EPUB/Kindle を並行生成しています（ログは完了時にまとめて出ます）
```

スピナーは PDF 枝＝臨界経路が持ち続けるので、進捗の見え方は現行とほぼ変わらない。

### 3.5 計時レポートはスレッドローカル

`Common` の vivliostyle 計時と現ステップラベルは、既に `Thread.current[]` で
スレッドローカルになっている（`common.rb:800-828`）。**競合はしないが、
親スレッドの `consume_vivliostyle_build_timings` は子枝の内訳を見られない。**

子枝の中で `reset_vivliostyle_build_timings` → 実行 → `consume_vivliostyle_build_timings` し、
戻り値として親へ返して合流時にマージする。`--log=debug` のステップ別テーブル
（`output_helpers.rb:32`）には相を示す印を足し、**逐次合計と壁時計の両方**を出す。

```
  - generate epub                       130.52s   [epub 枝・PDF 枝と並行]
  = TOTAL（逐次合計）                   553.25s
  = WALL（実測）                        422.73s
```

逐次合計を残すのは、並列化後も「どのステップが重いか」を比較できるようにするため。
壁時計だけにすると、隠れた枝の劣化に気付けなくなる。

### 3.6 中断（Ctrl+C）と片枝の失敗

**Ctrl+C は問題にならない。** 端末はフォアグラウンドプロセスグループ全体へ SIGINT を送るので、
子スレッドが `system()` で起こした `npx vivliostyle` も一緒に死ぬ。孤児は残らない。

**問題は 2 つある。**

1. **Ruby の `Interrupt` はメインスレッドにしか上がらない。** 子枝は `system()` が false を
   返しただけと解釈し、次のステップへ進んでしまう。ステップ間で参照する中断フラグを
   1 つ置き、`run_phase` のループ先頭で見る。
2. **片枝が例外で死んだとき、もう片方の外部プロセスを始末できない。** 現行は
   `system(build_command)`（`pdf.rb:129`）で pid を握っていない。
   - 第 1 段階: 子枝は `Thread#value` で例外を親へ伝える。親（PDF 枝）が先に死んだ場合は
     **子枝の完了を待ってから**終了する（外部プロセスを殺さない代わりに、宙ぶらりんの
     Chromium を残さない）。待ちは最長でも EPUB 枝の残り時間。
   - 第 2 段階（任意）: `Process.spawn` + `Process.wait` へ移し、pid を枝ごとに登録して
     中断時に `Process.kill` する。**本仕様の必須要件にはしない**——`vs build` の外部
     コマンド呼び出しは広範囲にあり、pid 管理の導入は独立した仕事にすべきである。

`test/vivlio_starter/robustness/interrupt_handling_test.rb` に既存の契約があるので、
並列時も同じ終了コード（130）とメッセージになることをテストで固定する。

---

## 4. 資源競合の実測（実装と同時に必ず行う）

**並列化は合計 CPU 時間を減らさない。** 枝どうしが食い合えば、見かけの利得は目減りする。
実装したら必ず測り、想定と合わなければ設計へ戻ること。

### 4.1 実測結果（2026-08-01・実装後）

同一コード・同一原稿（A5・515 ページ・`targets: pdf, epub, kindle`・`--no-clean`）で、
`VIVLIO_BUILD_PARALLEL=0` と既定（並列）を続けて測った。

| ステップ | 逐次 | 並列 | 差 |
|---|---|---|---|
| build overall pdf | 142.36s | 165.50s | +23.14 |
| backlink dedup | 155.53s | 140.77s | −14.76 |
| **PDF 枝 合計** | **333.31s** | **341.91s** | **+8.60（+2.6%）** |
| generate epub（EPUB＋Kindle＋KPF） | 184.46s | 203.72s | +19.26（+10.4%） |
| 共通前段 | 17.75s | 17.64s | −0.11 |
| **壁時計** | **535.51s** | **359.55s** | **−175.96s（−32.9%）** |

**競合は穏当だった。** PDF 枝の内訳で増減が割れているのは、EPUB 枝（203.72s）が
`build overall pdf` を丸ごと覆い、`backlink dedup` には 38 秒しか重ならなかったため。
**枝全体で見るのが正しい読み方**で、ステップ単位の比較は重なり具合に引きずられる。

壁時計は 17.64 + max(341.91, 203.72) = 359.55 と実測に一致した（EPUB 枝は完全に隠れた）。
`user 591.13s → 642.31s`・`real 537.11s → 360.95s` で、並列度は約 1.78。
10 コア機で CPU は飽和していない。

### 4.2 §0.1 の予測との差

§0.1 は壁時計 422.73s を見込んでいたが、実測は 359.55s とそれより良い。
間に `front-back-matter-single-render-spec.md`（−71s）が入ったためで、
予測の誤りではない。

一方で §0.1 の枝別内訳（EPUB 枝 130.52s）は、**その後の原稿・実装の変化で
184.46s まで伸びている**。並列化の効果を測るときは、必ず**同一コードで
`VIVLIO_BUILD_PARALLEL=0` と比べる**こと——日をまたいだ数字と比べると、
競合の大きさを 4 倍以上に見誤る（実際に一度誤った）。

### 4.3 索引・用語集を切ると臨界経路が入れ替わる（2026-08-01 実測）

`index_glossary.enabled: false` にすると `BacklinkDedupOrchestrator` が
`_glossarypage.html` / `_indexpage.html` の不在で即座に抜け、**本文の 2 回目のレンダが
まるごと消える**。PDF 枝が半分以下になり、**EPUB 枝のほうが長くなる**。

| 相 | 索引あり | 索引なし |
|---|---|---|
| 共通前段 | 17.8s | 16.9s |
| PDF 枝 | 343.4s | **153.2s** |
| EPUB 枝 | 272.1s | **238.1s** ← 臨界経路 |
| 壁時計 | 361.2s | **255.0s** |
| PDF ページ数 | 515 | 499（索引・用語集の 16 ページぶん） |

**どちらが長くても正しく動く。** `join_epub_branch` の `Thread#join` は無条件で待ち、
`final clean` は `:join` 相にある。設計が「PDF のほうが長い」に依存しているのは
§0.1 の見積もりだけである。

ただし 2 つ、この構成でだけ表面化するものがある。

1. **子枝の完了待ちにスピナーが無かった**（`a1222459` で修正）。PDF 枝が先に終わると、
   子枝のログはバッファ済みなので端末が無反応になる。並列化前は `generate epub` が
   本流のステップとしてスピナーを持っていたため、これは潜在的な退行だった。
2. **回転テーブルの待ちがそのまま壁時計に乗る**（実測 57.80s ＝全体の 23%）。
   索引ありの構成では PDF 枝の陰に隠れて 1 秒も現れない。同じ機能が構成次第で
   見え方が正反対になるので、待ち時間は必ずログへ出すこと
   （`RotateTableImages.wait_until_ready!` が計測する）。

なお **この組み合わせは自己限定的**である。待ちは `build overall pdf` に律速されるので
本が薄ければ待ちも縮み、逆に厚い本ほど索引が欲しくなる。「499 ページなのに索引が無い」は
実運用ではあまり成立しない。

### 4.4 残る宿題

同時に走る重量プロセスは Chromium 2 つ＋Kindle Previewer（JVM）で最大 3。
開発機（10 コア・32GB）では上記のとおり余裕があったが、
**コア数の少ない機械（4 コア級）では測っていない**。必要なら
`fork_branches?` にコア数の下限を入れる。

章単位の既存並列（`SectionBuilder.parallel_each`・並列度 `min(cores, 4)`）は
**共通前段の中**で完結し、分岐とは時間帯が重ならない。掛け算にはならない。

---

## 5. 実装の順序

すべて 2026-08-01 に完了した（各行末はコミット）。

1. ~~`front-back-matter-single-render-spec.md` を実装する（§3.3 が消える）~~ — `7a7c4df6`
2. ~~カバー生成を `:shared` へ引き上げる（§3.2）~~ — `6a2138cd`
3. ~~`workspaceDir` を枝ごとに分ける（§3.1）~~ — `46d14cc0`
4. ~~ステップ表へ相を足し、逐次のまま相ごとに実行する形へ組み替える（§1.1）~~ — `abe1d397`
5. ~~ログのバッファリングと計時のマージを入れる（§3.4 / §3.5）~~ — `ce2614b9`
6. ~~分岐を有効化し、`VIVLIO_BUILD_PARALLEL=0` で戻せることを確認する（§1.2）~~ — `cc98378c`
7. ~~資源競合を測る（§4）~~ — §4.1

4 と 6 を分けるのが要点だった。**「相への組み替え」と「実際に並列にすること」を
別のコミットにする**と、不具合が出たときにどちらが原因かを二分できる。
実際には 6 の実ビルドで §9.2 の共有状態が 2 つ出たので、この切り分けが効いた。

---

## 6. `kindle-rotate-table-image-spec.md` との関係

あちらの案 A は「生成済み PDF の該当ページを `pdftoppm` で切り出す」方式である。
実装すると **Kindle が PDF 枝の成果物に依存する**——枝の独立性が崩れる。

ただし壁時計への影響は、**どちらのレンダを使うかで大きく変わる**。

| 切り出し元 | Kindle 枝が待つ時刻 | 影響 |
|---|---|---|
| dedup 後の `_sections.pdf` | 16.19 + 148.06 + 153.43 = **317.7s** | Kindle の 100 秒級の作業がここから始まり、PDF 枝（422.7s）と競る |
| **1 回目の `build overall pdf` の出力** | 16.19 + 148.06 = **164.3s** | 余裕を持って PDF 枝の陰に収まる |

**1 回目のレンダを使うべきである。** dedup が消すのは用語集・索引のバックリンクと
本文の † マークで、**回転テーブルの中身は 1 文字も変わらない**。変わるのはページ番号だけだが、
「id → ページ番号」を引くのと「そのページを切り出す」のを**同じ PDF に対して**行う限り、
ずれようがない。

したがって `kindle-rotate-table-image-spec.md` 側に次を追記する（§7 で実施済み）。

- 切り出し元は **dedup 前の 1 回目のレンダ出力**とする
- 引きと切り出しは必ず同一の PDF に対して行う
- 並列化後は、Kindle 枝がこの PDF の生成完了を待つラッチを持つ

順序としては **本仕様を先に入れてから回転テーブルを実装する**ほうが安全である。
逆順だと、依存を後から並列構造へねじ込むことになる。

---

## 7. テスト

- **相の分類**（ユニット）: `full_mode_step_table` の全行が相を持つこと。
  `:pdf` 相に `html/` へ書くステップが無いこと（§3.3 の回帰固定）
- **分岐条件**（ユニット）: `targets: pdf` 単独・`targets: epub` 単独では分岐しないこと
- **逐次等価**（統合・`rake test:layout`）: `VIVLIO_BUILD_PARALLEL=0` と既定（並列）で、
  **生成される PDF / EPUB / KPF のページ数とファイルサイズが一致**すること。
  ビルドの決定性は `test-targets-flaky-issues` の調査で実証済みなので、この比較は成立する
- **カバー競合**（ユニット）: `:shared` 相でカバーが生成され、PdfMerger と EpubFlow の
  どちらからも再生成が呼ばれないこと
- **workspaceDir**（ユニット）: PDF 用と EPUB 用の生成 config が**別**の `workspaceDir` を
  指すこと・両者が 4 階層であること
- **中断**（robustness）: 並列時の Ctrl+C で終了コード 130 になること・
  子枝が次のステップへ進まないこと
- **ログ**: 子枝のログが合流後にまとめて出ること・行が混ざらないこと

---

## 8. スコープ外

- **EPUB と Kindle をさらに分けること**。§0.2 のとおり壁時計が縮まない。
  加えて両フレーバは `HeadingImageComposer` の生成資産キャッシュを共有して書くため、
  分けると新しい競合を作ることになる
- **章単位の並列度の調整**。`VIVLIO_BUILD_CONCURRENCY` は既存であり本仕様は触らない
- **`Process.spawn` への全面移行と pid 管理**。§3.6 のとおり独立した仕事
- **プロセス分割（fork/子プロセス）での並列化**。スレッドで足りる——重い処理はすべて
  外部プロセスで、Ruby 側は待っているだけなので GVL は問題にならない

---

## 9. 実装記録（2026-08-01）

### 9.1 結果

**535.51s → 359.55s（−175.96s・−32.9%）。** 内訳と資源競合は §4.1。
成果物は逐次と等価だった。

| 成果物 | 逐次 | 並列 | 判定 |
|---|---|---|---|
| PDF | 515 ページ / 101,128,935 B | 515 ページ / 101,128,930 B | ページ数一致・5 B 差は生成時刻 |
| EPUB | 32,209,635 B | 32,209,635 B | **バイト一致** |
| KPF | 50,109,839 B | 50,108,798 B | 1,041 B 差は Kindle Previewer が埋める UUID/時刻 |

### 9.2 仕様書に無かった共有状態が 2 つあった

§3 は「実物を見て確認した」共有状態を 3 つ挙げたが、**取りこぼしが 2 つ**あった。
どちらも「grep で `Common::` や `.cache/` を追う」だけでは出てこない種類のもので、
**プロセス全体に効く API**を探すべきだったという教訓が残る。

1. **`Dir.chdir` がプロセス全体の cwd を動かす**（`epub_builder.rb` の zip 書き戻し 3 箇所）。
   `Dir.chdir(tmpdir) { system('zip', …) }` という書き方で、EPUB を展開した一時
   ディレクトリへ降りてから zip を呼んでいた。並列にすると **PDF 枝が起こす
   `npx vivliostyle` がその一時ディレクトリを cwd として継ぐ**——しかも起こる確率は
   タイミング次第なので、再現しない壊れ方をする。子プロセスの cwd だけを変える
   `system(…, chdir:)` へ寄せて解消した（`EpubBuilder.zip_into`）。
2. **スピナーは `Common.emit` を経由せず `$stdout` へ直に書く**。§3.4 でログの出力先を
   差し替える方針を決めたが、スピナーはその出口を通らないため素通りしてしまい、
   2 本のスピナーが同じ TTY を奪い合う。`Spinner#enabled?` に
   「出力先が差し替えられているスレッドでは回さない」を足した。**出力先の差し替えを
   知っている場所が 1 つ増える**のは避けられないが、判定を 1 箇所に閉じてある。

### 9.3 `:pdf` 相の中で「どのステップと重なるか」は制御していない

EPUB 枝は PDF 枝の**どの部分と重なるかを選べない**。今回は `build overall pdf` を
丸ごと覆い `backlink dedup` には 38 秒しか重ならなかったが、原稿が変われば配分は動く。
そのため**ステップ単位の前後比較には意味が薄く**、枝の合計で見る必要がある（§4.1）。
将来ここを詰めるなら、枝内の実行順ではなく「EPUB 枝をいつ起こすか」を動かすことになる。

### 9.4 逐次へ戻す道具は実際に役立った

`VIVLIO_BUILD_PARALLEL=0` は性能の保険ではなく切り分けの道具、と §1.2 に書いたとおり、
実測の対照群としてそのまま使えた。**同一コードで並列と逐次を続けて測れる**ことが、
§4.2 の「日をまたいだ数字と比べて競合を 4 倍に見誤る」事故から復帰する唯一の手段だった。

### 9.5 実測は他の作業と同じディレクトリで走らせないこと

対照ビルドの最中に `rake test` を回してしまい、テストが走らせる clean 系が
ビルドのワークスペースを消して**計測が丸ごと無効になった**（`generate epub 0.00s`・
`apply outline 0.00s` が残る）。終了コードは 0 のままなので、
**表の数字を読むまで気付けない**。実ビルドの計測中はリポジトリに触らないこと。
