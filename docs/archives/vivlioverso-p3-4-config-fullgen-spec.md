# P3-4: vivliostyle.config.js 全文生成化＋VFM エントリーレベル適用 詳細仕様

調査日: 2026-07-05 / 調査者: Claude (Fable 5) / 実装担当: Opus 4.8 /
位置づけ: [vivlioverso-foundation-workplans.md](vivlioverso-foundation-workplans.md) P3-4 の
残課題（「V2.0 での config.js 全文生成化」）＋ PLANNED.md の
「VFM 設定のエントリーレベル適用」（両者は P5 依存マップで「同時が効率的」と対応付け済み）。
P4 個票 [vivlioverso-p4b-workspace-remnants-spec.md](vivlioverso-p4b-workspace-remnants-spec.md) とは独立。

> **実装者への共通指示**（workplans と同一）
> - 完了条件は「`rake test` / `rake test:standard` 緑・rubocop クリーン・
>   実プロジェクトで `vs build`（全ターゲット）実走・出力の同一性確認」＋本書固有条件。
> - 仕様と実装が食い違う場合は実装を止めて報告する。

---

## 0. 結論（先出し）

- P3 で CSS は「ソース不変＋生成ファイル 1 枚」へ移行済みだが、**ルートの
  `vivliostyle.config.js` だけが正規表現 in-place 書換（`sync_vivliostyle_config_size!` /
  `title!`）のまま残っている**。P3 と同じ思想で **book.yml からの全文生成**へ移行する。
- 生成器は P4 で新設済みの `Build::VivliostyleConfigWriter`（パイプライン用途別 config の
  生成元）に**ルート config 生成メソッドを追加**する形で寄せる。メタデータ解決
  （title/author/language/size）が 1 箇所になる。
- VFM 設定は生成時に **エントリーレベル**（`entry: entries.map(e => ({...e, vfm: …}))`・
  Vivliostyle CLI 公式推奨方式）で埋める。トップレベル `vfm:` ブロックは廃止。
- **正直な整理（§3）**: 本システムの実効的な VFM 変換は `vfm` CLI＋フロントマター注入
  （`frontmatter_generator.rb:130`）で行われており、config の vfm 設定は現状
  **どの経路でも実行時効果を持たない**（entry は全経路 HTML）。本改修の価値は
  (a) 正規表現書換という脆い機構の全廃、(b) 公式スキーマ準拠の正しい形の確立
  （V2.0「直接ビルド `vs build my.md --pdf`」で .md entry を渡す際の足場）、の 2 点。
  **フロントマター注入は現行のまま維持する**（実効機構はそちら）。
- 著者が手編集していた場合に備え、**マーカー無しファイルは一度だけ `.bak` へ退避して
  警告**したうえで生成へ移行する（§2.2）。

---

## 1. 現状（ルート config の書き手・読み手マップ）

### 1.1 書き手

| 経路 | 所在 | 実態 |
|---|---|---|
| `vs new` | `lib/project_scaffold/vivliostyle.config.js` | scaffold 同梱コピー。**copy_to_scaffold.rb の管理外**（DIRS/FILES に含まれず・`copy_to_scaffold.rb:14,60`）で、現物は別書籍の古い title を保持したまま（初回ビルドの sync で自己修復する前提） |
| 毎ビルド | `BookSettingsCss.generate!` → `sync_vivliostyle_config!`（`book_settings_css.rb:66-68, 277-282`） → `CssUpdater.sync_vivliostyle_config_size!` / `title!`（`css_updater.rb:38-103`） | size と title の 2 プロパティだけを正規表現 sub で書換（size 行が無ければ language 行の後に挿入）。'prepare theme images' ステップ経由で **full/preflight/single 全モード**で実行 |
| 手動 | 著者の直接編集 | 現行では size/title 以外の編集は保持される（暗黙の自由） |

### 1.2 読み手

| 経路 | 所在 | 実態 |
|---|---|---|
| 著者向け手動フロー | `vs entries` → `vs pdf`（`pdf.rb:177-181`・config 指定なしの `npx vivliostyle build`） | ルート config＋ルート entries.js を使用。P4 で「手動フロー用に現状維持」と確定済み |
| Guard | `Guards::VivliostyleConfigCheck`（`guards/vivliostyle_config_check.rb`） | 存在検査のみ。呼び出しは `build_command.rb:91` と `preflight_command.rb:74` の 2 箇所 |
| single-doc 判定 | `SingleDocDecider#config_allows_single_doc?`（`pdf.rb:271-283`） | config が `entries.js` を参照していれば無効化（生成 config も import を維持するため挙動不変） |
| doctor | `doctor.rb:644, 690` | プロジェクトの「目印」として存在確認のみ |
| パイプライン | **使わない**（P4 以降） | `Build::VivliostyleConfigWriter` 生成の用途別 config を `--config` で使用 |

### 1.3 VFM 設定の現行フロー

- 実効経路: `FrontmatterGenerator.build_base_frontmatter`（`frontmatter_generator.rb:130`）が
  各章フロントマターに `vfm: hardLineBreaks: <bool>` を注入 →
  `vfm` CLI（`convert.rb:24`）がそれを解釈して HTML 化。既定は
  `Common::CONFIG.vfm.hard_line_breaks != false`（`frontmatter_generator.rb:137-139`・
  既定値は `common.rb:266-270` の `default_vfm`）。
- ルート config のトップレベル `vfm: { hardLineBreaks: true }` ブロック
  （scaffold 由来・正規表現挿入の痕跡が残る崩れた整形）は、entry が HTML であるため
  **どの経路でも参照されない死に設定**。
- パイプライン生成 config（`VivliostyleConfigWriter.config_content`・
  `vivliostyle_config_writer.rb:83-108`）と EPUB 生成 config
  （`EpubBuilder.generate_epub_config!`）には vfm 記述なし（entry が HTML なので正しい）。

### 1.4 メタデータ解決の重複（統合対象）

title/author/language/size の解決規則が現在 3 箇所にある:

1. `VivliostyleConfigWriter.resolve_title/author/language`（`vivliostyle_config_writer.rb:110-130`）
   ＋ `EpubBuilder.resolve_page_size`
2. `EpubBuilder.generate_epub_config!` 内のインライン解決（writer と同一規則の重複実装）
3. `CssUpdater.sync_vivliostyle_config_size!/title!`（撤去対象）

---

## 2. 設計仕様

### 2.1 生成物

`Build::VivliostyleConfigWriter` に `write_root_config!` を新設し、以下の全文を
ルート `vivliostyle.config.js` へ書き出す:

```js
import entries from './entries.js';

// @ts-check
// 自動生成: config/book.yml のビルド設定（手編集しない）
// 生成器: VivlioStarter::CLI::Build::VivliostyleConfigWriter（毎ビルド再生成）
// 設定変更は config/book.yml を編集すること。
// このファイルは vs entries → vs pdf の著者向け手動フロー用。
// ビルドパイプラインは .cache/vs/build/ 配下の用途別 config を使う（P4 §3.2）。
/** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
const vivliostyleConfig = {
  title: '…',                    // book.yml: book.title（無ければ main_title + subtitle）
  author: '…',                   // book.yml: book.author
  language: 'ja',                // book.yml: book.language
  size: 'JIS-B5',                // book.yml: page（プリセット名 or 実寸）
  readingProgression: 'ltr',
  entry: entries.map((entry) => ({
    ...entry,
    // VFM 設定はエントリーレベルで適用（Vivliostyle CLI 公式推奨・PLANNED 対応）
    vfm: { hardLineBreaks: true } // book.yml: vfm.hard_line_breaks
  })),
  output: [
    './output.pdf'
  ]
};

export default vivliostyleConfig;
```

- **値の解決は既存 resolver を再利用**: `resolve_title` / `resolve_author` /
  `resolve_language`（§1.4-1）＋ `EpubBuilder.resolve_page_size`（プリセット名 upcase or
  `"<width> <height>"`——旧 `sync_vivliostyle_config_size!` と同一セマンティクス）。
- `hardLineBreaks` は `FrontmatterGenerator.book_hard_line_breaks?` と同じ判定
  （`CONFIG.vfm.hard_line_breaks != false`）を使う。判定メソッドの共有方法は実装判断
  （FrontmatterGenerator の公開メソッド参照で可）。
- トップレベル `vfm:` ブロックは**出力しない**（entry レベルへ一本化）。
- `workspaceDir` は**指定しない**（手動フローはルート `.vivliostyle/` の現行挙動のまま。
  clean.rb `:199-203` が掃除する既存前提を崩さない）。
- **決定的出力**（タイムスタンプ等を含めない）＋ **write-if-changed**
  （内容が同一なら書き込まない。毎ビルドの mtime 更新と無用な git 差分認識を避ける。
  旧 sync も同一時は無書込だった——`css_updater.rb:63, 97`）。

### 2.2 上書きポリシー（著者編集の保護）

生成マーカー（ヘッダの `// 自動生成:` 行）で判定する:

| 既存ファイルの状態 | 動作 |
|---|---|
| 無い | 生成する（Guard 撤去の根拠・§2.4-2） |
| マーカーあり | 内容が変わる時だけ再生成（通常運転） |
| **マーカー無し**（旧 scaffold のコピー or 著者の手編集） | **一度だけ** `vivliostyle.config.js.bak` へ退避 → 生成 → 🟡 警告 |

警告は親切に（[warning-messages-actionable] の規約: 修正案＋場所を添える）:

```
🟡 vivliostyle.config.js を config/book.yml から再生成しました
   旧ファイルは vivliostyle.config.js.bak に退避しています。
   title / author / size / VFM 設定は book.yml から自動反映されます。
   それ以外の独自カスタマイズがあった場合は .bak を確認し、必要なら
   book.yml へ移してください（今後この JS ファイルへの手編集は保持されません）。
```

- `.bak` が既に存在する場合は上書きしない（初回退避を保護）。
- `.bak` は clean 対象に**しない**（著者の判断で削除してもらう）。

### 2.3 接続と撤去

1. `BookSettingsCss.generate!` の `sync_vivliostyle_config!` 呼び出し（`book_settings_css.rb:68`）を
   `Build::VivliostyleConfigWriter.write_root_config!` へ差し替え、
   `sync_vivliostyle_config!` メソッド（`:277-282`）を削除。
   `book_settings_css.rb` に `require_relative '../build/vivliostyle_config_writer'` を追加
   （単体テストが book_settings_css.rb を個別 require しても解決できるように。
   writer 側は fileutils のみ require しており循環しない）。
2. `CssUpdater.sync_vivliostyle_config_size!` / `sync_vivliostyle_config_title!`
   （`css_updater.rb:38-103`）を削除し、ヘッダコメント（`:6-24`）から config.js 同期の
   記述を除去（CssUpdater は「値計算専業」になる）。
3. `Guards::VivliostyleConfigCheck` を `build_command.rb:91` と `preflight_command.rb:74` から
   外し、check クラス本体（`guards/vivliostyle_config_check.rb`・`guards.rb:28` の require）も
   削除する。**根拠**: 呼び出し元は build/preflight の 2 コマンドだけで、どちらも
   'prepare theme images' ステップで config を再生成する（欠落は自己修復される）。
   手動フロー `vs pdf` はもともとこの Guard を通らず、`npx vivliostyle` 自身のエラーで
   検出される（現行と同じ）。
4. `VivliostyleConfigWriter` のヘッダコメント（`vivliostyle_config_writer.rb:26-27`
   「ルートの vivliostyle.config.js …は現状維持」）を本仕様の姿へ更新。

### 2.4 旧 sync との挙動差（意図的な変更・CHANGELOG に記す）

| 項目 | 旧 sync | 全文生成 |
|---|---|---|
| title が book.yml に無い | 既存 title を温存（無書込で return） | プレースホルダ `'書籍タイトル'`（resolver の既存規則・vivliostyle 11 スキーマが 1 文字以上を要求するため） |
| size 行が無い config | language 行の後へ挿入（正規表現） | 常に完全な形で出力 |
| size/title 以外の手編集 | 温存 | 保持しない（§2.2 の退避＋警告で移行） |
| トップレベル vfm ブロック | 触らない（scaffold 由来で残存） | 出力しない（entry レベルへ） |
| ファイル欠落時 | 何もしない（Guard がエラー） | 生成する（Guard 撤去） |

### 2.5 scaffold と本リポジトリの追随

- `lib/project_scaffold/vivliostyle.config.js` を生成形（マーカー付き・中立的な
  プレースホルダ値）へ手動更新する（初回 `vs build` で book.yml の実値に再生成されるため、
  値そのものは重要でない。マーカーを持たせることが目的——**これが無いと新規プロジェクトの
  初回ビルドで無意味な .bak が生まれる**）。
- 本リポジトリのルート `vivliostyle.config.js` も生成形で**コミットし直す**
  （さもないと `workspace_structure_test` の git 無差分検査（WS-04・`GENERATED_FILES` は
  ビルド後に復元して検査する方式）で毎回差分となる。生成が決定的なら、コミット後は
  ビルドしても無差分になる）。
- copy_to_scaffold.rb は現状どおり本ファイルを管理対象外のままとする（root 側も
  scaffold 側も「生成形」で安定するため同期の必要がない）。

### 2.6 メタデータ解決の一本化（同時にやると安い・任意）

`EpubBuilder.generate_epub_config!` 内のインライン解決（§1.4-2）を
`VivliostyleConfigWriter.resolve_title/author/language` の呼び出しへ置換する
（writer のコメント「EPUB 経路と同一に保つ」`vivliostyle_config_writer.rb:81-82` が
「EPUB 経路が writer を使う」に反転し、規則の二重管理が消える）。
EPUB 側の出力バイトが不変であることをテストで確認して行うこと。見送っても本個票は成立する。

---

## 3. VFM エントリーレベル適用の効果範囲（正直な整理）

> 本節の詳細（2 経路の流れ図・`vfm` CLI 実測結果・V2.0 直接ビルド実装時の指針）は
> [vfm-config-flow-notes.md](vfm-config-flow-notes.md) に恒久記録した。

- **今日の実行時効果はゼロ**である: `vs entries` は HTML から entries.js を作り
  （`entries.rb:56-79`・.md は対象にならない）、パイプラインも全経路 HTML entry。
  Vivliostyle CLI は HTML entry に VFM を適用しない。
- それでも entry レベルで埋める理由:
  1. PLANNED.md（`:21`）が求める公式推奨スキーマへの準拠を「全文生成」のついでに
     コストほぼゼロで達成できる（正規表現 sub では entry の map 化は不可能だった——
     全文生成が前提条件だという意味で「同時が効率的」）。
  2. V2.0 の「直接ビルド（`vs build my.md --pdf`）」で .md entry を渡すとき、
     hardLineBreaks が book.yml から正しく効く足場になる。
- **実効機構（フロントマター注入）は変更しない**。著者が章単位で
  `vfm: hardLineBreaks: false` を上書きできる現行仕様（`frontmatter_generator.rb` の
  マージ規則）もそのまま。
- 実装後、PLANNED.md の該当項目（`:21`）を削除（または「対応済み」化）し、
  archives の `vfm_hard_line_breaks_default.md` の「実装ごまかし」節が指す技術的負債の
  解消として CHANGELOG に記す。

---

## 4. 段階実装（各段で独立コミット）

1. **生成器の追加（既存 sync は残す）**: `write_root_config!` 実装＋ユニットテスト
   （テンプレ全文・マーカー判定・.bak 退避・write-if-changed・エスケープ）。
   この時点では未接続＝出力不変。
2. **接続＋撤去**: `BookSettingsCss` の差し替え・CssUpdater sync 2 メソッド削除・
   Guard 撤去（§2.3）。本リポジトリの `vivliostyle.config.js` を生成形でコミット。
   検証: 実ビルド（全ターゲット）で PDF 全ページテキスト一致（title メタデータは
   同値のはず・PDF の DocInfo title も確認）・EPUB バイト同一・
   2 回目のビルドで config.js に差分/再書込が無いこと。
3. **scaffold 更新＋手動フロー実証**: scaffold config を生成形へ。
   `vs new` した一時プロジェクトで初回ビルド→ `.bak` が**生まれない**こと、
   マーカー無し config を置いた場合に `.bak`＋警告が**一度だけ**出ることを確認。
   `vs entries && vs pdf` の手動フローが従来どおり output.pdf を生成すること。
4. **EPUB メタデータ解決の一本化（§2.6・任意）**。

---

## 5. テスト

- 新設 `vivliostyle_config_writer_test`（または既存へ追加）:
  - 生成全文のスナップショット（title 合成・size プリセット名/実寸・language 既定・
    `hardLineBreaks` の true/false 反映・`'` エスケープ）
  - マーカー付き既存 → 再生成される／内容同一 → 書き込まれない（mtime 不変）
  - マーカー無し既存 → `.bak` 退避＋警告＋生成、`.bak` 既存時は退避しない
  - ファイル欠落 → 生成される
- `css_updater_test` の sync 系テストを削除（値計算テストは残す）。
- `book_settings_css_test`: `generate!` が root config 生成を呼ぶことの確認
  （sync 呼び出しアサーションの置換）。
- guard 撤去に伴う `build_command` / `preflight` 系テストの前提更新
  （config 欠落で即エラーにならず、ビルドが自己修復することの検証を 1 本）。
- レイアウト系: `rake test:layout` 全緑・`workspace_structure_test`（WS-04 git 無差分）緑。
- 原稿・ドキュメントの記述確認: `grep -rn 'vivliostyle.config.js' contents/ README.md docs/`
  で「手編集する」旨の記述が残っていないか確認し、あれば book.yml 誘導へ書き換える。

---

## 6. 完了条件（固有）

1. ビルド後の `vivliostyle.config.js` が book.yml から決定的に全文生成され、
   `sync_vivliostyle_config_size!` / `title!` と `Guards::VivliostyleConfigCheck` が
   コードベースから消えている。
2. 生成 config の entry が `entries.map` による**エントリーレベル VFM** になっており、
   トップレベル `vfm:` ブロックが無い。PLANNED.md の該当項目が消化されている。
3. book.yml の `page.size` / `book.title` / `vfm.hard_line_breaks` を変更 → 再ビルドで
   config.js に正しく反映される（正規表現時代の「行が無いと挿入位置に依存」問題が消滅）。
4. 手動フロー（`vs entries` → `vs pdf`）が従来どおり動く。
5. 出力同一性: 全ターゲットの実ビルドで移行前後の成果物一致
   （PDF テキスト＋DocInfo title・EPUB バイト・KPF 生成）。
6. `rake test:release` 全緑・rubocop クリーン・CHANGELOG 記載
   （§2.4 の挙動差と「手編集は保持されない」旨の Breaking 表記を含む）。

---

## 7. スコープ外（明示）

- 直接ビルド（`vs build my.md --pdf`）の実装（V2.0・P5。本個票はその足場まで）。
- `vs entries` の .md 対応・手動フローの workspace 化（P4 §8 で据え置き済み）。
- `default_vivliostyle`（`common.rb:254-261`）の `entries_file` / `config_file` 設定キーの
  整理（現状維持。全文生成後も参照箇所の意味は変わらない）。
- book.yml に vivliostyle 任意オプションのパススルー節を設ける案（timeout 等。
  需要が出たら別個票——生成テンプレに差し込み点を 1 つ足すだけで対応できる設計余地は
  本仕様の全文生成で確保される）。
