# Step 8（backlink dedup）高速化 調査報告＋実装仕様（PDF named destinations 方式）

調査日: 2026-07-05 / 調査・設計: Claude (Fable 5) / 実装担当: Claude (Opus 4.8) 想定
対象: [PLANNED.md](PLANNED.md) 「Step 8（backlink dedup）の抜本的高速化」（ビルド/出力・[High]）

関連: [print-pdf-derivation-spec.md](print-pdf-derivation-spec.md)（①。§7 で連動）
前提: 用語辞書 `config/index_glossary_terms.yml` は 2026-07-05 に `vs index:auto` → `vs index:apply`
で復帰済み（155 語・うち用語集 16 語）。索引・用語集が無効な本では Step 8 自体がスキップされる。

---

## 0. 結論（先出し）

- PLANNED.md が期待した「vivliostyle CLI のページ番号 JSON 出力」は現行 11.x に存在しないが、
  **もっと良い供給源が既にある**: vivliostyle build が生成する PDF は、**id を持つ全要素の
  named destination を文書カタログの `/Dests` 辞書に書き出している**
  （本書実測: 5,372 エントリ。名前に `…00-preface.html#gls-src-00-preface-pdf-2` の形で
  **アンカー ID がそのまま埋まっている**）。
- したがって Step 7 で生成済みの `_sections.pdf` を pdf-reader（MIT・既存依存）でパースするだけで、
  dedup に必要な **anchor_id → ページ番号** マップが**決定的に**得られる。
  対応付けヒューリスティック（順序・座標マッチ）は一切不要。
- **スパイクで実証済み**（§3）: 抽出 **0.52 秒**（対 Playwright 方式 約 73 秒、409 ページ）。
  公式 Step 8 と dedup 判定を突合し、用語集 295/295・本文† 239/239 件が完全一致、
  対象 HTML 16 ファイルが**バイト一致**。索引のみ 5,761 リンク中 15 件（0.26%）が相違したが、
  これは **preview レンダと build レンダの改ページ位置が 1 ページずれる境界ケース**であり、
  実 PDF を測る新方式のほうが**正確**（§3.3）。
- 効果: Step 8 実測 179.4s → 約 107s（再レンダ 106.5s は本文が変わる以上不可避）。
  加えて **Playwright・preview サーバー・ポート 13100・`extract_page_mapping.mjs` への依存が
  丸ごと消える**（除去できる系: `page_mapping_extractor.rb` の preview/Playwright 機構一式）。

---

## 1. 現状の仕組みと置換対象

```
Step 8（BacklinkDedupOrchestrator.run!）
  Phase 1: PageMappingExtractor#extract!
           vivliostyle preview をヘッドレス起動（port 13100）
           → Playwright で全ページレンダ完了を待機（〜73s）
           → DOM から .glossary-link / .glossary-backlink / .index-term の配置ページを収集
  Phase 2: BacklinkDeduplicator#deduplicate!（HTML 浄化・Nokogiri）
  Phase 3: 変更があれば vivliostyle build で _sections.pdf を再レンダ（〜106s）
```

**Deduplicator が実際に使うのは `mappings`（gls-src-*）と `index_mappings`（idx-*）の
「anchor_id → (spine_index, page_index)」ルックアップのみ**。
`PageMapping.backlink_mappings` は収集されるが**未使用**（`backlink_deduplicator.rb` 参照。
`build_anchor_to_page_lookup` / `build_index_anchor_to_page_lookup` だけが消費者）。
また (spine_index, page_index) は**同一ページ判定のキー**としてしか使われないため、
グローバル通しページ番号 1 本で完全に等価（vivliostyle は spine 文書ごとに改ページするため、
1 ページに複数 spine が同居することはない）。

## 2. vivliostyle の /Dests 形式（実測・vivliostyle CLI 11.0.2）

- 文書カタログ直下の `/Dests` 辞書（PDF 1.1 形式。`/Names` の名前ツリーではない）。
- キー例（PDF name。`:XXXX` は UTF-16 コードユニットの 4 桁 hex エスケープ）:

  ```
  viv-id-http:003a:002f:002flocalhost:003a13000:002f…:002f00-preface:002ehtml:0023gls-src-00-preface-pdf-2
  → 復号: viv-id-http://localhost:13000/…/00-preface.html#gls-src-00-preface-pdf-2
  ```

- 値は明示 destination 配列 `[ページ参照 /XYZ x y z]`（ページ参照 → ページ番号はページツリー走査で解決）。
- **復号は「`:` ＋ hex4」を 1 コードユニットに変換**するだけ（元名前中のすべての `:` は
  エスケープされるため、区切りの取り違えは起きない）。アンカー ID は復号後の最初の `#` 以降。
  URL 部（ホスト・ポート・パス）はビルドごとに変わり得るので**プレフィックスに依存しないこと**。
- 日本語アンカー（例 `gls-src-08-web-ウェブサイト-4`）も同エスケープで格納される。BMP 外
  （サロゲートペア）は id に現れない前提でよいが、復号関数は例外時に元文字列を返す防御を入れる。

### 2.1 復号・抽出コード（スパイク検証済み・実装の出発点）

```ruby
require 'pdf-reader'

def extract_anchor_page_map(pdf_path)
  reader = PDF::Reader.new(pdf_path)
  objects = reader.objects
  root = objects.deref(objects.trailer[:Root])

  # ページ参照 oid → 通しページ番号（1..N）
  page_no = {}
  walk = lambda do |ref|
    node = objects.deref(ref)
    case node[:Type]
    when :Pages then Array(objects.deref(node[:Kids])).each { |kid| walk.call(kid) }
    when :Page  then page_no[ref.id] = page_no.size + 1
    end
  end
  walk.call(root[:Pages])

  map = {}
  Array(objects.deref(root[:Dests])).each do |name, dest|
    anchor = decode_viv_name(name).split('#', 2)[1] or next
    arr = objects.deref(dest)
    arr = objects.deref(arr[:D]) if arr.is_a?(Hash)
    page = page_no[Array(arr).first&.id] or next
    map[anchor] = page
  end
  map
end

# vivliostyle の :XXXX（UTF-16 コードユニット hex4）エスケープを復号
def decode_viv_name(sym)
  s = sym.to_s
  units = []
  i = 0
  while i < s.length
    if s[i] == ':' && s[i + 1, 4]&.match?(/\A\h{4}\z/)
      units << s[i + 1, 4].hex
      i += 5
    else
      units << s[i].ord
      i += 1
    end
  end
  units.pack('U*')
rescue StandardError
  s
end
```

## 3. スパイク実証結果（2026-07-05・409 ページ・dedup 前スナップショットで検証）

### 3.1 抽出

- `/Dests` 5,372 エントリ → anchor→page 5,320 件（gls-src: **691**＝Playwright 方式の取得数と同数 /
  idx: 4,050 / 未解決 0）
- 所要 **0.52 秒**（ページツリー走査込み）。dedup 判定＋HTML 書換まで含めても 0.8 秒。

### 3.2 公式 Step 8 との突合

同一入力（dedup 前ワークスペースのスナップショット）に対し、PDF 方式のマップで
Deduplicator と同じ判定を再現し、公式実行（Playwright 方式）の出力と比較:

| 項目 | 公式 | PDF 方式 | 一致 |
|---|---:|---:|---|
| 用語集バックリンク削除 | 295 | 295 | ✅（`_glossarypage.html` バイト一致） |
| 本文 † 削除 | 239 | 239 | ✅（対象 15 章すべてバイト一致） |
| 索引ページ番号削除 | 1,717 | 1,716 | 15 リンクで判定相違（下記） |

### 3.3 索引 15 件の相違 = 新方式のほうが正確

相違はすべて「同一用語の連続出現（`…-75` と `…-76` 等）がページ境界を挟む」ケースで、
**preview レンダ（Playwright が測る対象）と build レンダ（実際の PDF）の改ページ位置が
1 ページずれる**ことに起因する。現行方式は「preview で測って build で組む」ため
この不整合を構造的に抱えるが、新方式は **Step 7 が実際に出力した PDF そのもの**を測るため、
判定基準として正確側にある。（なお dedup 後の再レンダで最終ページはまた微動し得る——
これは現行方式も同じ、本質的な残余誤差。）

## 4. 設計

### 4.1 新クラス `Build::PdfPageMapExtractor`（`lib/vivlio_starter/cli/build/`）

- 入力: `_sections.pdf` のパス。出力: 既存の `PageMappingExtractor::PageMapping` と同形の Data
  （**Deduplicator を無修正で使い回すため**）:
  - `mappings`: `gls-src-*` の `MappingEntry(anchor_id:, href: '', page_index: 通しページ, spine_index: 0)`
  - `index_mappings`: `idx-*` の `IndexMappingEntry(anchor_id:, page_index:, spine_index: 0)`
  - `backlink_mappings`: `[]`（未使用のため空。合わせて Data 定義から削除してもよいが、
    その場合は grep で全消費者を確認すること）
  - `total_pages`: ページ数 / `extracted_at`: 現在時刻
- spine_index を 0 固定にしても、ルックアップは (spine, page) タプルの同値判定にしか
  使われないため挙動は等価（§1）。PageMapping Data 定義は新クラス側へ移設する。
- `/Dests` が無い・fragment 付きの名前が 1 件も無い場合は例外を投げる
  → orchestrator の既存 rescue（警告してdedupスキップ・ビルド続行）に乗る。
  これは vivliostyle 更新で `/Dests` 出力仕様が変わった場合の検知点になる
  （バージョン更新時チェックリストに追記）。

### 4.2 `BacklinkDedupOrchestrator` の変更

```
Phase 1（置換）:
  sections_pdf = BUILD_PDF_DIR/_sections.pdf
  1. 無ければビルドする（print_pdf 単独経路）: 既存の vivliostyle.config.sections.js を
     execute_pdf で実行（従来この経路では preview が全ページをレンダしていた。
     同等コストで実 PDF が手に入り、①導出のソースにもなる）
  2. PdfPageMapExtractor.new(sections_pdf).extract!
Phase 2（無修正）: BacklinkDeduplicator
Phase 3（条件変更）: 再レンダは「閲覧用 PDF を出す場合」または「①の導出を行う場合」のみ:
  rebuild_pdf! if result.files_modified.any? && (targets.pdf || derive_print)
  ※ 従来レンダの print_pdf 単独経路では、print レンダ自体が dedup 済み HTML を読むため
    閲覧用 _sections.pdf の再レンダは不要（現行は無条件に再レンダしており、単独経路では無駄）。
```

パイプラインからの受け渡し: `run!(entries)` に `targets`（と①実装後は `derive_print`）を
渡せるようシグネチャを拡張する（pipeline.rb のステップ表から供給）。

### 4.3 削除するもの（Phase 2 クリーンアップ・動作確認後）

- `page_mapping_extractor.rb` の preview サーバー管理・Playwright 実行系
  （`PageMapping` Data は新クラスへ移設済みのため、ファイルごと削除可能）
- `extract_page_mapping.mjs`
- Playwright / preview 関連の依存記述（`vs doctor` のチェック項目・README・原稿章に
  Playwright 言及があれば追従。`grep -rn playwright` で洗い出すこと）
- `DEFAULT_PORT = 13_100` 等のポート予約

### 4.4 削減効果（実測ベース見込み）

| | 現状 | 新方式 |
|---|---:|---:|
| Phase 1（マッピング取得） | ~73s（preview 起動＋全ページブラウザレンダ＋Playwright） | **~0.5s** |
| Phase 3（再レンダ） | 106.5s | 106.5s（不可避・pdf 出力時のみ） |
| Step 8 合計 | 179.4s | **~107s** |

## 5. テスト計画

- **復号関数の単体テスト**: ASCII / 日本語（`ウェブサイト`）/ `#` 以降なし / 不正 hex / 空。
- **抽出の単体テスト**: Prawn（MIT）で 2〜3 ページの PDF を作り
  `add_dest("viv-id-…:0023gls-src-01-test-用語-1", dest_xyz(...))` 相当の named destination を
  持たせ、anchor→page マップを検証（Prawn は `dests` へ名前登録が可能。
  だめなら HexaPDF で生成しテストは skip ガード——ただし主経路は Prawn 生成を推奨）。
- **Deduplicator 回帰**: 既存テストが PageMapping を組み立てて渡す形なら無修正で通ること。
- **統合（rake test:layout 系・索引有効プロジェクト）**: フルビルドで
  (1) Step 8 が preview を起動しないこと（ポート 13100 を listen しない）、
  (2) 削除件数が 0 より大きいこと、(3) `_glossarypage.html` / `_indexpage.html` の
  重複が実際に減っていること。
- **print_pdf 単独経路**: `_sections.pdf` 不在からの自前ビルド → 抽出 → 再レンダ省略、の分岐。

## 6. リスクと備え

| リスク | 備え |
|---|---|
| vivliostyle 更新で `/Dests` の出力形式・`viv-id-` 接頭辞が変わる | §4.1 の検知（fragment 付き名前ゼロで例外→警告スキップ）。バージョン更新チェックリストに「索引付きビルドで Step 8 の削除件数 > 0 を確認」を追加 |
| URL プレフィックスがポート・パスで変動 | 復号後「最初の `#` 以降」だけを使う（プレフィックス非依存・実装済み） |
| dedup による † 削除で本文が微小リフローし、測定済みページとずれる | 現行方式と同じ残余誤差（§3.3）。再レンダ後の PDF が最終決定 |
| 巨大 /Dests（数万エントリ）でのパース時間 | 5,372 件で 0.5s。線形なので実用域。異常肥大時も Step 8 の rescue で無害化 |

## 7. ①（print_pdf 導出）との連動

- ①導出のソースは **dedup 済みの** `_sections.pdf`。よって Phase 3 の再レンダ条件は
  `targets.pdf || derive_print`（§4.2）。
- ①＋②適用後の print_pdf 単独ビルドは「本文レンダ（マップ取得）→ dedup → 本文再レンダ
  （dedup 反映）→ 導出」となり、現行（preview ＋ 再レンダ ＋ print 3 レンダ）から
  約 100〜170 秒短縮される。
- 実装順は Phase 0（①仕様 §2.7）→ ② → ① を推奨（②が独立して完結し、①の
  パイプライン条件変更時に §4.2 の条件を同時に触るため）。
