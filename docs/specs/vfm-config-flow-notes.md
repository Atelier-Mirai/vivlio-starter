# VFM 設定の流れと有効範囲（技術ノート）

記録日: 2026-07-05 / 記録者: Claude (Fable 5) /
経緯: P3-4 仕様策定（[vivlioverso-p3-4-config-fullgen-spec.md](vivlioverso-p3-4-config-fullgen-spec.md)）の
調査で確定した事実の恒久記録。**V2.0 の直接ビルド（`vs build my.md --pdf`）実装時に
必ず参照すること**（§4）。

---

## 1. 結論（先出し）

「VFM 設定」と呼べる場所は **2 箇所**あり、効いているのは片方だけ:

| 場所 | 実行時効果 | 理由 |
|---|---|---|
| **book.yml の `vfm.hard_line_breaks`** | ✅ **有効**（ビルド出力を支配） | フロントマター注入経由で `vfm` CLI が解釈する（§2） |
| **vivliostyle.config.js 内の `vfm:` ブロック** | ❌ **死に設定**（一度も参照されない） | vivliostyle CLI の vfm 設定は **Markdown エントリを自前変換するときだけ**参照される。本システムの entry は全経路で変換済み HTML（§3） |

この 2 つを混同しないこと。「config.js の vfm を書き換えたのに挙動が変わらない」
「book.yml を false にしたのに config.js が true のまま」はどちらも正常
（後者はそもそも読まれないため矛盾しない）。

---

## 2. 有効な経路: book.yml → フロントマター注入 → `vfm` CLI

```
config/book.yml (vfm: hard_line_breaks: true/false)
  → Common::CONFIG.vfm.hard_line_breaks
      （未設定なら true が既定。common.rb default_vfm / 判定は
        frontmatter_generator.rb book_hard_line_breaks? = 「!= false」）
  → FrontmatterGenerator.build_base_frontmatter（frontmatter_generator.rb:130）が
    各章の前処理済み .md のフロントマターへ 'vfm' => { 'hardLineBreaks' => <bool> } を注入
  → `vfm` CLI（convert.rb:24 の `vfm "<md>" > "<html>"`）がフロントマターを読んで
    HTML 変換 ★ここで効く
  → vivliostyle CLI は完成した HTML を組版するだけ（VFM 変換は走らない）
```

- **章ごとの上書き可**: 章の .md に自分でフロントマター `vfm: hardLineBreaks: false` を
  書けば、その章だけ上書きされる（マージは既存フロントマター優先。
  `frontmatter_generator.rb` の merge 規則・archives の
  [vfm_hard_line_breaks_default.md](../archives/vfm_hard_line_breaks_default.md) §2 参照）。

### 実測（2026-07-05・`vfm` CLI 単体で検証済み）

入力（本文は同一・フロントマターのみ差）:

```markdown
---
vfm:
  hardLineBreaks: true   # ← もう一方は false
---

一行目
二行目
```

出力:

| hardLineBreaks | `<p>` の中身 |
|---|---|
| `true` | `<p>一行目<br>二行目</p>`（改行 → `<br>`） |
| `false` | `<p>一行目 二行目</p>` 相当（改行 → スペース扱い・改行したければ空行か `<br>`） |

---

## 3. 死に設定の経路: vivliostyle.config.js の `vfm:` ブロック

vivliostyle CLI の config（`VivliostyleConfigSchema`）の vfm 設定
（トップレベル / エントリーレベルとも）は、**vivliostyle CLI 自身が .md エントリを
VFM 変換するとき**にだけ参照される。本システムでは:

- パイプライン生成 config（`Build::VivliostyleConfigWriter`）: entry は HTML
- EPUB/Kindle 生成 config（`EpubBuilder.generate_epub_config!`）: entry は HTML
- 著者向け手動フロー（`vs entries` → `vs pdf`・ルート config）: `vs entries` は
  HTML からしか entries.js を作らない（`entries.rb:56-79`）→ entry は HTML

つまり **全経路で entry が変換済み HTML** のため、config の vfm 設定は一度も参照されない。
scaffold 由来のルート config に残る `vfm: { hardLineBreaks: true }` ブロック
（正規表現挿入の痕跡で整形が崩れているもの）は歴史的残骸であり、P3-4 の全文生成化で
**トップレベル vfm ブロックは廃止・エントリーレベル（`entries.map`）へ移行**する。

---

## 4. V2.0 直接ビルド（`vs build my.md --pdf`）実装時の指針 ★本ノートの主目的

直接ビルドで **.md を vivliostyle CLI に直接渡す**設計を採る場合、§3 の前提が崩れて
config の vfm 設定が**初めて実効化**する。その際:

1. **エントリーレベルで渡すこと**（Vivliostyle CLI 公式推奨・PLANNED.md 由来）。
   P3-4 実装後の生成 config が既にこの形になっている（足場）:

   ```js
   entry: entries.map((entry) => ({
     ...entry,
     vfm: { hardLineBreaks: true } // book.yml: vfm.hard_line_breaks
   })),
   ```

2. **二重変換に注意**: 直接ビルド経路では `vfm` CLI（§2）を通さないか、通すなら
   vivliostyle には HTML を渡す。「`vfm` CLI で HTML 化 → さらに vivliostyle にも
   .md を渡す」という混在は作らないこと。
3. **設定の優先順位を §2 と揃える**: 既定 true（`!= false` 判定）・book.yml で全体設定・
   フロントマターで章（ファイル）単位上書き、の 3 層を直接ビルドでも再現する。
   vivliostyle CLI 内蔵 VFM がフロントマターの `vfm:` を尊重するかは
   **実装時に必ず実測して確認する**（本システムの `vfm` CLI 単体では尊重される＝§2 実測）。
4. **hardLineBreaks 以外の VFM オプション**を将来 book.yml に足す場合も、
   snake_case（book.yml）→ camelCase（VFM）の変換規則は §2 の既存流儀
   （`hard_line_breaks` → `hardLineBreaks`）に従う。

---

## 5. 関連資料

- [vivlioverso-p3-4-config-fullgen-spec.md](vivlioverso-p3-4-config-fullgen-spec.md) §1.3・§3
  （本ノートの出自。config 全文生成化＋エントリーレベル VFM の実装仕様）
- [../archives/vfm_hard_line_breaks_default.md](../archives/vfm_hard_line_breaks_default.md)
  （hardLineBreaks 既定有効化の当初仕様。§「参考実装」にエントリーレベル方式の原型）
- PLANNED.md「VFM 設定のエントリーレベル適用」（P3-4 実装で消化予定）
- VFM 公式: https://vivliostyle.github.io/vfm/
