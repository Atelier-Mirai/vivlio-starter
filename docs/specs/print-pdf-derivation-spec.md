# print_pdf 導出化 調査報告＋実装仕様（閲覧用 PDF ＋トンボ＝入稿用 PDF・本体 MIT のみで実装）

調査日: 2026-07-05〜06 / 調査・設計: Claude (Fable 5) / 実装担当: Claude (Opus 4.8) 想定
対象: [PLANNED.md](PLANNED.md) 「print_pdf を pdf から導出して高速化」（V2.0 構想・[High]）

関連: [backlink-dedup-pdf-map-spec.md](backlink-dedup-pdf-map-spec.md)（②。§7 で本件と連動）

---

## 0. 結論（先出し）

- **導出は本体（MIT 依存のみ）で成立する。フルスケールで実証済み**（§3）。
  使うのは **qpdf**（既存必須依存・Apache-2.0 の外部コマンド。サブプロセス呼び出しであり
  ライセンス感染なし）＋ **Prawn / pdf-reader**（既存 MIT 依存）のみ。
  **`vivlio-starter-pdf`（AGPL/HexaPDF）プラグインは不要**（プラグインの役割は従来どおり
  outline 付与のみに保たれる）。
- 方式: 閲覧用中間物を qpdf 結合 → **qpdf `--update-from-json`** でページボックス・内容シフト・
  アノテーション/named destinations の座標を一括更新 → **qpdf `--overlay`** で
  トンボ（Prawn 生成）とノンブル（Prawn 生成・ページ 1:1）を重畳。
  qpdf は構造保存型なので、リンク・named destinations（`/Dests`）が壊れない。
- 実測: 406 ページ・アノテーション 8,577 件・`/Dests` 3,361 件の変換一式で **13.2 秒**。
  現行の print pdf ステップ実測 **192.5 秒 → 約 35 秒**の見込み（レンダリング 3 回が消える）。
  Ghostscript レンダ比較で**本文配置は実 vivliostyle print 出力と完全一致**。
- これにより **「pdf ＋トンボ＝ print_pdf」の単一系列**になる: 入稿用の本文は閲覧用と
  **同一レンダリング由来**となり、二系統レンダに起因するページずれ・内容差・
  入稿用レンダの flaky（body-guard リトライ）が構造的に消える。
  従来の個別レンダ経路は **`output.print_pdf.full_bleed: true`（フチなし要素のある本）専用の
  フォールバック**としてのみ残す。
- **PLANNED.md の「カバー除去」工程は不要**。print_pdf はもともとカバーを結合しない。
  最終 output.pdf ではなく**結合前の閲覧用中間物**（`_titlepage_legalpage.pdf` / `_sections.pdf` /
  `_colophon.pdf`、print pdf ステップ時点でワークスペース `pdf/` に残存・非圧縮）から導出する。
- **目次リンク不具合の真因を特定**: `PrintPdfBuilder#merge!` の qpdf 結合が `base_pdf` 未指定のため、
  先頭ファイルがベースになり本文の `/Dests` 辞書（3,361 件）が捨てられる。アノテーションは残るが
  参照先の named destination が解決できず全リンク無反応になる。
  **`base_pdf: _sections_print.pdf` を渡す 1 行で解消**（qpdf 実機確認済み・§3.5）。
  導出化と独立の即効修正（Phase 0）として先行コミット可。
- 併せて、**隠しノンブルの合成も CombinePDF から qpdf `--overlay` へ置換**する（§2.5）。
  CombinePDF は保存時に `/Dests` を全損する（§3.4）ため、現行 Standard モードのノンブル工程は
  print PDF のリンクを壊している。置換でこの潜在バグも解消し、
  ノンブルはプロバイダ非依存の MIT 共通実装になる（プロバイダ API 縮小）。

## 0.1 ライセンス整理（本件の前提）

| 部品 | ライセンス | 使い方 | 本体への影響 |
|---|---|---|---|
| qpdf | Apache-2.0 | 外部コマンド（サブプロセス）。既に結合で必須依存 | なし |
| Prawn / pdf-reader | MIT（Ruby ライブラリ） | 既存 runtime 依存 | なし |
| CombinePDF | MIT | **本件では不使用**（/Dests 全損のため。§3.4） | — |
| HexaPDF（プラグイン） | AGPL | **本件では不使用**。outline のみ従来どおり | 感染防止の建付け維持 |

---

## 1. 現状フローと実測（2026-07-05・本書 409 ページ・pdf+print_pdf ビルド）

| ステップ | 実測 | 内訳 |
|---|---:|---|
| build overall pdf（`_sections.pdf` 閲覧用本文） | 114.8s | vivliostyle build 114.4s |
| backlink dedup | 179.4s | preview+Playwright ~73s ＋ 再レンダ 106.5s（→ ②で置換） |
| build front pages and tail（閲覧用前付・奥付） | 47.2s | 26.7s + 18.0s |
| merge / outline / rename | 30.5s | qpdf 6.7s ＋ outline 23.8s |
| **print pdf（本仕様の対象）** | **192.5s** | 本文 print レンダ 112.2s ＋ 前付 31.7s ＋ 奥付 28.1s ＋ 結合・ノンブル・outline 約 20s |

### 1.1 現行の print pdf フロー（`lib/vivlio_starter/cli/build/print_pdf_builder.rb`）

1. カバー画像生成（`CoverCommands.ensure_cover_files_for_build!`）— カバーは別ファイル入稿
2. 本文を `--crop-marks --bleed 3mm` 付きで再レンダ（`_sections_print.pdf`・body-guard 付き）
3. 前付・奥付を同様に再レンダ（`_titlepage_legalpage_print.pdf` / `_colophon_print.pdf`）
4. qpdf 結合（奥付偶数ページ調整の空白ページ挿入込み）→ `output_print.pdf`
5. 隠しノンブル（`NombreStamper.stamp!` → provider）
6. アウトライン付与（`OutlineExtractor` → provider）
7. リネーム（`<書名>_print_<版>.pdf` へ）

### 1.2 実測ジオメトリ（A4・bleed 3mm）

| | 閲覧用 `_sections.pdf` | 入稿用 `_sections_print.pdf` |
|---|---|---|
| MediaBox | `[0, 0.03, 595.28, 841.92]` | `[0, 0.28, 685.98, 932.88]` |
| TrimBox | なし | `[45.35, 45.64, 640.63, 887.53]` |
| BleedBox | なし | `[36.85, 37.14, 649.13, 896.03]` |

- 余白は片側 45.35pt = **16mm = bleed 3mm ＋ crop offset 13mm**。
  crop offset は既存定数 `CROP_MARK_OFFSET_MM = 13.0`（`cover.rb:49` / `create.rb:815`）と一致。
- MediaBox 原点の 0.03〜0.28pt は Chrome 出力のジッタ。ページごとの
  `MediaBox` 原点（ox/oy）を織り込んで補正する（§3.2 実証済み）。

---

## 2. 設計

### 2.1 方式: 「原点 0 正規化」＋ qpdf 構造更新（採用）

トリムサイズ → 入稿ジオメトリの変換は、原点 0 を維持したまま
内容・アノテーション・/Dests 座標を (m, m)＝(bleed＋crop offset) シフトし、
MediaBox を拡張する（vivliostyle `--crop-marks` 出力と同じ座標規約を再現。
ノンブル・outline・下流ツールが一切無修正で済み、座標シフト漏れはテストで検出可能）。

編集手段の比較（いずれもスパイクで実測済み）:

| 手段 | /Dests | ライセンス | 判定 |
|---|---|---|---|
| CombinePDF（MIT gem） | **全損**（保存時に named destinations 辞書を再構築しない） | MIT | ✗ 不採用 |
| HexaPDF（プラグイン） | 保持（4.4s） | AGPL | ✗ 本体のみ方針により不採用（実証には使用） |
| **qpdf `--update-from-json` ＋ `--overlay`** | **保持（構造保存型）** | Apache-2.0・外部コマンド | **✓ 採用**（13.2s） |

補足（/Dests 全損の意味）: PDF のリンクは「クリック領域（アノテーション）」と
「名前→実ページの対応表（文書カタログの `/Dests` 辞書）」の 2 部品で構成される。
vivliostyle のリンクは named destination 参照（`Dest: viv-id-…#anchor`）なので、
対応表が消えるとクリック領域が残っていても全リンクが無反応になる。

### 2.2 導出フロー（新・単一系列「pdf ＋トンボ＝ print_pdf」）

```
入力: pdf/_titlepage_legalpage.pdf, pdf/_sections.pdf, pdf/_colophon.pdf（閲覧用・dedup 済み・非圧縮）
1. カバー画像生成（従来どおり・独立）
2. qpdf 結合: merge_pdfs_with_qpdf!(files, output: output_print.pdf, base_pdf: _sections.pdf)
   - 奥付偶数ページ調整（insert_blank_page_before_colophon）は共通ロジックをそのまま使用
   - base_pdf 指定により /Dests・メタデータが本文から継承される（Phase 0 と同根）
3. ジオメトリ変換（新モジュール・qpdf --update-from-json 一発）:
   - 各ページ: /Contents を [preストリーム, 元contents…, postストリーム] に差し替え
     （pre = "q 1 0 0 1 m m cm\n" / post = "\nQ" の共有ストリーム 2 本を新規オブジェクト追加）
   - 各ページ: MediaBox/TrimBox/BleedBox 再定義（ページごとの元原点 ox/oy を補正）・CropBox 削除
   - 全アノテーション: Rect（あれば QuadPoints）を (m, m) シフト
   - /Dests 辞書: XYZ/FitH/FitV/FitR 系の座標を (m, m) シフト（1 オブジェクト丸ごと更新）
4. トンボ: Prawn で大判 1 ページの marks.pdf を生成 → qpdf --overlay marks.pdf --repeat=1-z
   （幾何は既存 add_crop_marks_overlay と同一: コーナー二重 L 字＋センター丸十字・線幅 0.24pt）
5. 隠しノンブル: Prawn で全ページ分の nombre.pdf を生成（既存 StandardProvider の描画コードを流用:
   HackGen TTF サブセット・6pt・ノド側 90° 回転）→ qpdf --overlay nombre.pdf --to=1-z --from=1-z
6. アウトライン付与（従来どおり provider 経由・Enhanced のみ実施）
7. リネーム（従来どおり）
```

空白ページ（`ensure_blank_page_pdf`）はトリムサイズで結合され、手順 3 で他ページと
一緒に拡張されるため個別対応不要。

### 2.3 新モジュール構成（すべて本体・MIT）

- `Build::PrintGeometry`（仮）: 手順 3 の実装。
  - 入力構造の取得は `qpdf --json=2 --json-key=qpdf --json-key=pages --json-stream-data=none`
    （ページ object id・/Contents 参照）＋ pdf-reader（アノテーション・/Dests の値読み出し）。
  - 更新 JSON は `{"version":2,"qpdf":[header, {"obj:N 0 R": {"value"|"stream": …}}]}` 形式。
    新規オブジェクトは `maxobjectid` 超の id で追加できる（スパイク実証済み）。
    Ruby 値 → qpdf JSON 値の変換（Reference→"N G R" / Symbol→"/Name" / String→"u:…"）は
    スパイクの `to_qjson` を流用（§3.7）。
  - 適用は `qpdf in.pdf out.pdf --update-from-json=update.json`（qpdf 11+。開発機は 12.3.2。
    `vs doctor` の qpdf バージョン要件に 11 以上を明記すること）。
- `Build::CropMarksOverlay`（仮）: 手順 4。`add_crop_marks_overlay`（`create.rb:628`）の
  Prawn 描画を共通化して呼ぶ（カバー用は CombinePDF 合成のままでよい——単一ページ・リンク無しのため。
  余力があれば同様に qpdf 化して CombinePDF 依存を縮小してもよい）。
- `Build::NombreStamper`: 手順 5 として **qpdf overlay 版を正実装にする**。
  Prawn によるノンブル PDF 生成は `StandardProvider#create_nombre_pdf` の描画コード
  （HackGen TTF・回転描画・奇偶でノド側切替）を本体側へ移し、合成だけ
  CombinePDF → `qpdf --overlay --to=1-z --from=1-z` に差し替える。
  → provider の `stamp_nombre!` はパイプラインから外れる（API は当面残置・非推奨化）。
  Standard モードで CombinePDF 合成が /Dests を壊していた潜在バグもこれで解消。
  従来レンダのフォールバック経路（§2.6）も同じ新実装を使う。

### 2.4 トンボ描画

`CreateCommands.add_crop_marks_overlay` の幾何（`draw_corner_crop_mark` /
`draw_center_crop_mark`・カバーで実証済み）をそのまま使う。全ページ同一図形なので
1 ページの marks.pdf を `--repeat=1-z` で全ページへ重畳する。

### 2.5 実行条件（ハイブリッド判定）とパイプライン変更

判定はビルド開始時に一度だけ行い、ステップ表の条件列に吸収する:

```ruby
derive_print = t.print_pdf && !Common.truthy?(Common::CONFIG.output.print_pdf.full_bleed)
```

（プロバイダ能力には依存しない——MIT のみで完結するため、プラグイン有無で経路は変わらない。）

`pipeline.rb` `full_mode_step_table` の条件変更（導出時は print_pdf 単独でも閲覧用中間物が必要）:

| 行 | 現条件 | 新条件 |
|---|---|---|
| `build overall pdf` | `t.pdf` | `t.pdf \|\| derive_print` |
| `generate entries.js` | `!t.pdf && t.print_pdf` | `!t.pdf && t.print_pdf && !derive_print` |
| `build front pages and tail` | `t.pdf` | `t.pdf \|\| derive_print` |
| `build front pages html` | `!t.pdf` | `!t.pdf && !derive_print` |
| `merge all pdfs` / `apply outline` / rename 系 | `t.pdf` 系 | 変更なし（閲覧用成果物の要否は従来どおり `t.pdf`） |
| `print pdf` | `t.print_pdf` | 変更なし（Builder 内部で導出/従来を分岐） |

`derive_print` 時に `!t.pdf` でも `build overall pdf`〜`build front pages and tail` が走るが、
`merge all pdfs` 以降は走らないため閲覧用最終成果物は生まれない。
dedup の再レンダ条件も連動する（②仕様 §7）。

`PrintPdfBuilder#build!` は `derive_print` を受け取り、導出フロー（§2.2）と
従来フロー（§1.1）を切り替える。body-guard は従来フロー専用のまま残す。

### 2.6 book.yml 新設定

```yaml
output:
  print_pdf:
    bleed: 3mm         # 既存
    crop_marks: true   # 既存
    full_bleed: false  # 新設: 本文にフチなし（塗り足しまで届く）要素があるか。
                       # false（既定）= 閲覧用 PDF から高速導出 / true = 従来の個別レンダリング
```

- 命名は「導出するか」ではなく**著者が自分の本について知っている事実**（フチなし要素の有無）にする。
- 閲覧用 PDF はトリムで裁たれており塗り足しを復元できないため、`full_bleed: true` の本を
  導出すると白フチ裁ち落とし事故になる——この関係を book.yml コメントと 41-book-yml 章に明記する。
- ルート `config/book.yml` を編集後、`ruby copy_to_scaffold.rb` で雛形へ同期（CLAUDE.md）。

### 2.7 Phase 0（独立の即効修正・先行コミット可）

`PrintPdfBuilder#merge!` の結合を `base_pdf` 付きに変更:

```ruby
Build::PdfMerger.merge_pdfs_with_qpdf!(existing, output: output_print_pdf,
                                        base_pdf: pdf_path('_sections_print.pdf'))
```

これだけで従来フローの目次リンク不具合が解消する（§3.5 で qpdf 実機確認済み。
`/Dests` 1 → 3,361 に回復）。従来フローは `full_bleed: true` のフォールバックとして
残るため、Phase 0 は恒久修正として意味が残る。

---

## 3. スパイク実証結果（2026-07-05〜06）

### 3.1 導出コアの成立（フルスケール・MIT 経路）

`.cache/vs/build/pdf/_sections.pdf`（406 ページ・dedup 後・86MB）に §2.2 手順 3〜5 を適用:

- 所要 **13.2 秒**（qpdf JSON 取得＋更新 JSON 生成＋update-from-json＋トンボ・ノンブル overlay 込み。
  更新対象 8,986 オブジェクト＝ページ 406 ＋アノテーション 8,577 ＋ /Dests ＋共有ストリーム 2）
- `/Dests` 3,361 件・アノテーション 8,577 件を完全保持（座標シフト済み）
- ボックスは実 print 出力と一致（Chrome ジッタ ±0.3pt の範囲）
- Ghostscript レンダ比較（同一ページ）で**本文配置が実 vivliostyle print 出力と完全一致**
- 多ページ 1:1 の qpdf overlay（`--to=1-z --from=1-z`）によるノンブル合成も動作確認

### 3.2 ジオメトリ計算（実証済みの式）

```
m = (bleed_mm + crop_offset_mm) × 72/25.4   # 既定 (3+13)mm ≒ 45.3543pt
b = bleed_mm × 72/25.4
ページごとに ox, oy = 元 MediaBox の原点:
  MediaBox = [0, 0, w + 2m, h + 2m]
  TrimBox  = [m − ox, m − oy, m − ox + w, m − oy + h]
  BleedBox = TrimBox を b ずつ外側へ
内容      = "q 1 0 0 1 m m cm\n" ＋ 元ストリーム列 ＋ "\nQ"（共有ストリーム 2 本）
Rect / QuadPoints / XYZ 系 dest 座標 = ＋(m, m)
```

### 3.3 中間物の残存確認

pdf+print_pdf フルビルド後のワークスペース `pdf/` に閲覧用中間物（トリムサイズ・非圧縮）が
print pdf ステップ時点で残っていることを実ビルドで確認（閲覧用の圧縮は結合後の
`output.pdf` にのみかかる）。

### 3.4 CombinePDF の /Dests 全損（不採用の根拠）

`CombinePDF.load → ページボックス編集 → save` で、アノテーション 13,208 件は保持されるが
**`/Dests` は 0 件になる**（カタログの named destinations 辞書を再構築しない）。
現行 StandardProvider のノンブル合成（CombinePDF 経由）も同じ理由で print PDF のリンクを
壊している——§2.3 の qpdf overlay 置換で解消する。

### 3.5 目次リンク不具合の真因と修正確認

| PDF | links | /Dests | 状態 |
|---|---:|---:|---|
| 閲覧用最終（base=_sections.pdf で結合） | 8,577 | 3,361 | リンク正常 |
| 入稿用最終（base 未指定 → 先頭 = 前付がベース） | 8,491 | **1** | **全リンク無反応** |
| 入稿用を base=_sections_print.pdf で再結合（検証） | 8,491 | 3,361 | 回復 |

### 3.6 既知の観測事項

- 同一 HTML でも閲覧用レンダと print レンダでアノテーション数が 86 件異なる（8,577 vs 8,491）。
  レンダごとの改ページ差に由来。導出は閲覧用の値を継承する（多い側・無害）。
- ページの `/Rotate` は 0 前提（Chrome 出力は常に 0）。0 以外を検出したら導出を中止し
  従来フローへフォールバックする防御を入れる。
- 出力サイズは元とほぼ同一（86MB → 86MB）。

### 3.7 リファレンス実装（スパイクコード全文の要点）

実装の出発点。qpdf JSON v2 の値表現と新規オブジェクト追加の作法を含む:

```ruby
# 構造取得（ストリームデータなし・軽量）
full_json, = Open3.capture2('qpdf', src, '--json=2', '--json-key=qpdf', '--json-key=pages',
                            '--json-stream-data=none')
j = JSON.parse(full_json)
header, objects = j['qpdf']          # header に maxobjectid
pages = j['pages']                   # 各要素: {"object" => "46 0 R", "contents" => [...]}

# Ruby 値 → qpdf JSON 値
def to_qjson(v)
  case v
  when PDF::Reader::Reference then "#{v.id} #{v.gen} R"
  when Symbol then "/#{v}"
  when Hash   then v.to_h { |k, val| ["/#{k}", to_qjson(val)] }
  when Array  then v.map { |x| to_qjson(x) }
  when String then "u:#{v}"
  else v
  end
end

# 新規共有ストリーム（maxobjectid 超の id で追加できる）
updates["obj:#{max_id + 1} 0 R"] =
  { 'stream' => { 'dict' => {}, 'data' => Base64.strict_encode64("q 1 0 0 1 #{m} #{m} cm\n") } }
updates["obj:#{max_id + 2} 0 R"] =
  { 'stream' => { 'dict' => {}, 'data' => Base64.strict_encode64("\nQ") } }

# ページ更新は objects["obj:#{oid}"]['value'] を書き換えて updates へ（§3.2 の式）
# アノテーション・/Dests は pdf-reader で読み、シフトして to_qjson で updates へ
File.write('update.json', JSON.generate({ 'version' => 2, 'qpdf' => [header, updates] }))
system('qpdf', src, dst, '--update-from-json=update.json')

# トンボ（1 ページ・全ページへ）とノンブル（多ページ 1:1）
system('qpdf', dst, dst2, '--overlay', 'marks.pdf', '--repeat=1-z', '--')
system('qpdf', dst2, out, '--overlay', 'nombre.pdf', '--to=1-z', '--from=1-z', '--')
```

---

## 4. 実装手順（推奨順）

1. **Phase 0**: `PrintPdfBuilder#merge!` に `base_pdf:` を追加（§2.7）＋回帰テスト
   （最終 print PDF の `/Dests` が本文の named destinations を含むこと）。
2. **ノンブル qpdf 化**: `StandardProvider#create_nombre_pdf` の Prawn 描画を本体共通モジュールへ
   移し、合成を qpdf overlay に置換（§2.3）。従来フローにも適用（Standard の /Dests 破壊解消）。
3. **ジオメトリ変換モジュール**: `Build::PrintGeometry`（§2.3・§3.7）＋単体テスト。
4. **ビルダー・パイプライン**: `PrintPdfBuilder` に導出フロー追加・`derive_print` 分岐、
   `pipeline.rb` ステップ表の条件変更（§2.5）。
5. **設定**: CONFIG 既定値（`common.rb:207` 付近の `print_pdf:` に `full_bleed: nil` 追加）、
   `config/book.yml` コメント、`copy_to_scaffold.rb` 同期、原稿 41-book-yml / 44-build 章の追記、
   `vs doctor` の qpdf 要件（11 以上）明記。
6. **②との連動**（[backlink-dedup-pdf-map-spec.md](backlink-dedup-pdf-map-spec.md) §7）:
   dedup 再レンダ条件を `t.pdf || derive_print` にする。

## 5. テスト計画（すべて MIT 依存のみ: Prawn で作成 / pdf-reader で検査 / qpdf 実行）

### 5.1 単体

- `Build::PrintGeometry`: Prawn 製の小 PDF（named dest・Link アノテーション・複数 contents 付き）で
  変換 → ボックス期待値 / Rect・dest 座標シフト / /Dests・アノテーション件数の前後一致 /
  ページごとの原点ジッタ補正 / `/Rotate ≠ 0` でのフォールバック / 二重適用防止
  （TrimBox 既存なら警告スキップ）
- ノンブル qpdf 版: 合成後の `/Dests` 保持（CombinePDF 版で失われていたことの回帰テスト）・
  ページ数一致・フォントがサブセット埋め込みであること（FT-02 回帰）
- `to_qjson` 変換: Reference / Symbol / 日本語文字列 / ネスト
- Phase 0 回帰: qpdf 結合後の `/Dests` 件数がベース PDF のそれを継承すること
- ステップ表: `derive_print` 時の登録ステップ列（print_pdf 単独でも `build overall pdf` が入る等）、
  `full_bleed: true` で従来フロー

### 5.2 統合（`rake test:layout` / `test:targets` 系・実ビルド）

- 導出 print PDF: ページ数 = 閲覧用結合と同数（カバーなし・空白ページ込み）、
  TrimBox 寸法 = ページプリセット、目次リンクの dest 名が `/Dests` に解決できること（不具合の回帰）
- 従来フロー比較: 同一入力で導出版と従来版の本文ページを Ghostscript ラスタライズ比較
  — 初回実装時に手動で 1 回実施し、以後は寸法・件数アサーションで足りる

### 5.3 リリース前チェックリスト（手動）

- [ ] Acrobat / プレビューで導出 print PDF のトンボ・仕上がり線・隠しノンブルを目視
- [ ] 目次・索引・用語集リンクのクリック動作（不具合解消の確認）
- [ ] 印刷所（利用予定先）のプリフライトに導出版を通す（初回のみ）

## 6. 削減効果（実測ベース見込み）

| 経路 | 現状 | 導出後 |
|---|---:|---:|
| pdf + print_pdf フルビルドの print pdf ステップ | 192.5s | 約 35s（qpdf 結合 7s ＋変換 13s ＋ outline 約 15s） |
| print_pdf 単独ビルド | レンダ 3 回＋dedup | 閲覧用中間物の生成が入るため相殺されるが、②と併せて preview 分（~70s）短縮 |

副次効果:
- 入稿用と閲覧用の本文が**同一レンダリング由来**になり、ページずれ・内容差が構造的に消える
- 入稿用本文レンダの flaky（body-guard リトライ）消滅
- Standard モードのノンブル工程による /Dests 破壊（潜在バグ）解消
- プラグイン（AGPL）の役割が outline のみに縮小し、本体のみで入稿用 PDF が完結する
