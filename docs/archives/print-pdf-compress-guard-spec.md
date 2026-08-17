# 入稿用 PDF を圧縮しようとしたら引き止める

> 作成日: 2026-08-16
> ステータス: **実装待ち**
> 対象: `lib/vivlio_starter/cli/pdf.rb`（`PdfCompressor`）
> 関連: `image-format-per-target-spec.md`（PDF が重い根本原因の側）

## 0. なぜこの仕様書があるか

入稿用 PDF を圧縮すると印刷所に出せなくなる。Ghostscript の `/ebook` は**画像を 150 dpi へダウンサンプルし、全画像を JPEG へ再エンコードする**ためで、一般に求められる 300〜350 dpi を大きく下回る（実測 2026-08-16: 本書 97.2 MB → 10.6 MB・中央値 564 ppi → 150 ppi）。

原稿はこの危険を**文章で**塞いでいる。

> `contents/45-utility.md` L57
> 印刷所に提出する「入稿用データ」には、このコマンドを使用しないでください。

文章で書いてあるということは、**機械は止めていない**ということである。

## 1. ビルド経路は既に守られている（変更不要）

先に確認しておく。`vs build` の側は三重に守られていて、手を入れる必要がない（2026-08-16 実装確認）。

| # | 仕組み | 効果 |
|---|---|---|
| 1 | `PdfFinalizer#compress_pdf!` の対象は `pdf/output.pdf`（**閲覧用の結合済み PDF**）だけ | 入稿用 `output_print.pdf` は最初から対象外 |
| 2 | 圧縮ステップの条件が 2 行とも **`t.pdf &&`** で始まる | `targets: print_pdf` 単独では**ステップ自体が立たない**（`--compress` を付けても走らない） |
| 3 | 入稿用の導出元は `.cache/vs/build/pdf/_sections.pdf`（**中間生成物**） | 圧縮後の成果物を読まないので、`targets: pdf, print_pdf` ＋ `compress: true` でも入稿用は無傷 |

3 が効いていて、`targets: pdf, print_pdf` では**閲覧用だけ軽くなり、入稿用はフル解像度のまま**という望ましい挙動になる。ステップ順は `compress and rename` → `print pdf` で圧縮が先だが、圧縮されるのは別ファイルなので影響しない。

**したがって本仕様が塞ぐのは、手動コマンドの経路だけである。**

## 2. 残る穴

```bash
vs pdf:compress vivlio_starter_print_v1.0.0.pdf   # いまは黙って圧縮する
```

`determine_paths` の 3 形態のうち、危険なのは**入力を明示したとき**だけである。

| 呼び方 | 入力 | 危険度 |
|---|---|---|
| 引数なし | `book.yml` から解決した閲覧用 PDF | 安全（入稿用を選びようがない） |
| `vs pdf:compress <file>` | 指定ファイル（出力は `_compressed` 付き） | **ここ** |
| `vs pdf:compress <in> <out>` | 指定ファイル | **ここ** |

なお**上書きはしない**（`default_compressed_name` が `_compressed` を付ける）。元の入稿用 PDF は残るので、事故は「圧縮版を入稿してしまう」ことであって、原本の破壊ではない。この差が §4 の強さを決める。

## 3. 入稿用かどうかの判定

2 つの手掛かりを OR で見る。どちらか一方では取りこぼす。

### 3.1 ファイル名

**`generate_print_pdf_filename` の戻り値と厳密一致させてはならない。** 入稿用 PDF の名前は設定で変わるうえ、手元には過去にビルドしたものも残るためである。

| 場面 | 名前 |
|---|---|
| `include_version: true` | `vivlio_starter_print_v1.0.0.pdf` |
| **`include_version: false`** | **`vivlio_starter_print.pdf`**（`_v` が入らない） |
| **過去のバージョンでビルドした残り** | `vivlio_starter_print_v0.9.0.pdf` |

`generate_output_filename` は `filename += '_print' if target == 'print_pdf'` と付けてから、`include_version && !blank?(project_version)` のときだけ `_v#{version}` を足す。**バージョンは付いたり付かなかったりするが、`_print` は必ず付く。**

したがって判定は **`"#{project.name}_print"` で始まるか**（前方一致）とする。これなら 3 つの場面すべてを拾える。著者が `myproject_print_draft.pdf` のような接尾辞を付けた場合も拾えるが、それは入稿用である可能性が高いので拾ってよい。

**著者がリネームしていると外れる**のは変わらない。そこは §3.2 が受け持つ。

### 3.2 ページボックス

入稿用 PDF は塗り足しぶん MediaBox が広く、TrimBox が仕上がり線を指す。**MediaBox ≠ TrimBox なら入稿用**と判定できる。

ただし `crop_marks: false` の本は `PrintPdfBuilder#build_by_derivation!` がジオメトリ拡張をせず、`finalize_print_boxes!` も `crop_marks?` で早期 return するため、**MediaBox = TrimBox のまま**になる。この場合はこの手掛かりが効かない。

### 3.3 限界を認める

**`crop_marks: false` かつリネーム済みの入稿用 PDF は検出できない。** 両方の手掛かりが外れるためで、これは仕様上の限界として受け入れる。検出できないケースのために判定を緩めると、閲覧用 PDF にまで警告が出て狼少年になる。

## 4. どう引き止めるか

**止めない。尋ねる。**

上書きしない以上、実害は「圧縮版ができる」ことだけであり、ビルドを中断させるほどではない。また入稿用と判定した PDF を著者が意図して圧縮したい場面（入稿以外の用途で配りたい等）もありうる。

```
🟡 入稿用の PDF を圧縮しようとしています: vivlio_starter_print_v1.0.0.pdf
        圧縮すると画像が 150 dpi まで落ち、印刷所の基準（300〜350 dpi）を下回ります
        入稿には圧縮していない PDF を使ってください
        続けますか？ [y/N]
```

- 対話（tty）なら確認を求め、既定は **No**
- 非対話・`--yes` 指定時は 🟡 を出して続行する（既存の `Common.confirm?` の流儀に合わせる）

**警告文には理由と数値を入れる。**「使わないでください」だけでは、なぜ駄目なのかが分からず、著者は次も同じことをする。

## 5. 実装

`PdfCompressor#call` の冒頭、`determine_paths` の直後に判定を挟む。引数なしの呼び出しでは判定自体を行わない（§2 のとおり安全なため）。

判定は純粋関数に切り出す（`print_pdf_input?(path)`）。ページボックスの読み取りは `Pdf.provider` を経由せず `pdfinfo -box` で足りる——入稿用かどうかを知るだけなら、プロバイダの重い依存を持ち込む必要がない。

## 6. 検証

1. **入稿用 PDF を明示指定** → 🟡 が出て、既定 No で中止すること
2. **閲覧用 PDF を明示指定** → 警告が出ないこと（誤検知しない）
3. **引数なし** → 従来どおり黙って圧縮すること
4. **`crop_marks: false` の入稿用** → ファイル名で拾えること（ボックスでは拾えないため）
5. **リネームした入稿用** → ボックスで拾えること
6. **`include_version: false`**（`vivlio_starter_print.pdf`）→ 拾えること。`_v` の有無に依存しないことを固定する
7. **過去バージョンの残り**（`vivlio_starter_print_v0.9.0.pdf`）→ 拾えること。現在の `project.version` と一致しなくても入稿用は入稿用である

## 7. 実装記録（2026-08-17 完了）

実装して 3 つ分かった。

**`Common.confirm?` は非対話で「No」を返す。** §4 に「非対話・`--yes` 指定時は 🟡 を出して続行する（既存の `Common.confirm?` の流儀に合わせる）」と書いたが、あれの実装は `input.gets` が nil のとき `default`（既定 false）を返すので、パイプや CI では**中止**になる。本仕様の原則は「止めない。尋ねる」なので、`$stdin.tty?` を自分で見て、非対話では警告だけ出して続行するようにした。`--yes` オプションは `vs pdf:compress` に存在せず、追加もしていない。

**判定はプロジェクト名を引数で受ける形にした。** §5 の「純粋関数に切り出す」を素直にやると `Common::CONFIG` を読むことになり、テストのたびに `book.yml` / `page_presets.yml` / `catalog.yml` を書いて `reload_configuration!` する羽目になる。`print_pdf_input?(path, project_name = configured_project_name)` としたことで、名前の判定 5 ケースが設定なしで書けるようになった。

**Prawn で TrimBox を作れる。** ボックス判定のテストには MediaBox ≠ TrimBox の PDF が要るが、Prawn に専用の API は無い。`pdf.state.page.dictionary.data[:TrimBox] = [9, 9, 603, 783]` で直接置ける（`pdfinfo -box` が読めることを実測で確認）。本体リポジトリのテストは AGPL の HexaPDF に依存できないので、この手が要る。

検証は §6 の 7 項目を 12 のテストで固めた。実動作も確認済み——入稿用を明示指定すると 🟡 が理由と数値つきで 3 行出て、閲覧用（`vivlio_starter_v0.0.1.pdf`）では 1 行も出ない。

## 8. やらないこと

- **ビルド経路への変更**（§1 のとおり既に守られている）
- **`45-utility.md` L57 の注意書きの削除。** 機械が尋ねるようになっても、なぜ駄目かを説明する文章は本の側に要る
- **圧縮そのものの禁止。** 入稿用 PDF を圧縮したい正当な場面はありうる
