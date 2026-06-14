# EPUB の Kindle / Amazon KDP 対応 調査報告書

> 作成日: 2026-06-14
> ステータス: **調査報告（仕様未決・後日決定用の資料）**
> 関連: `docs/specs/build-output-bugfix-spec.md`（③-a 扉絵 / ④-A 数式）

EPUB の「扉絵（frontispiece/ornament）が表示されない」「数式が生 LaTeX で露出する」の
恒久対応にあたり、**Kindle / Amazon KDP での見え方と技術的制約**を調査した。
著者は Kindle のシェアが大きいことから **Kindle での確実な表示・出稿**を優先したい意向であり、
本書はその観点で選択肢と課題を整理する。実装方針は本書を踏まえて後日決定する。

---

## 1. 前提: 対象リーダーと優先度

- **最優先: Kindle（Amazon KDP 出稿）**。シェアが大きい。
- 次点: Apple Books / Kobo / Thorium 等（EPUB3 の CSS・MathML サポートが厚い）。
- 方針: 「Apple Books 等で綺麗」よりも「**Kindle で崩れず確実に出る**」を優先する。

リフロー型（reflowable）EPUB を対象とする。固定レイアウト（FXL）は §5 で別途検討。

---

## 2. Amazon KDP への出稿可否

- **出稿は可能**。KDP はリフロー型 EPUB のアップロードを受け付ける
  （旧 `.mobi` は廃止済み。現在は EPUB 入稿が標準）。
- KDP はアップロードされた EPUB を **Kindle 独自形式（KFX）へ内部変換**する。
  このため、**EPUB 側の CSS がそのまま反映されるとは限らない**（変換で落ちる/上書きされる）。
- 入稿前提として **epubcheck が通る**ことが重要。本 gem の EPUB は
  既に epubcheck ERROR 0 を達成済み（`epub-pipeline-fix-spec.md`）で、この要件は満たす。
- 検証は **Kindle Previewer**（Amazon 公式）で実機相当の確認が可能。最終判断は実機確認を要する。

---

## 3. Kindle のリフロー CSS サポートの制約

Kindle（KFX / Enhanced Typesetting）のリフロー表示は、EPUB3 標準の一部しかサポートせず、
他リーダー（Apple Books 等）より大幅に狭い。今回の扉絵・数式に関係する主な制約:

| 機能 | Apple Books / Kobo / Thorium | **Kindle（リフロー）** |
| --- | --- | --- |
| インライン `<img>` | ✅ | ✅ 確実に表示される |
| `position: absolute/fixed`（画像に見出しを重ねる） | ✅ | ❌ ほぼ非対応（重ならない） |
| ビューポート単位 `vh` / `vw`（全面サイズ指定） | ✅ | ⚠️ 不安定（1 画面にならない） |
| ブロック要素の `background-image`（背景に絵） | ✅ | ⚠️ 無視されることが多い |
| `object-fit` / 高度な配置 | ✅ | ⚠️ 限定的 |
| 埋め込みフォント `@font-face` | ✅ | ⚠️ 端末/設定で上書きされ得る |

→ **結論**: Kindle では「画像を背景に敷き、その上に見出しを重ねる」「`vh` で全面を埋める」は
**いずれも信頼できない**。Kindle で確実なのは **インライン `<img>` を本文フローに置く**こと。

---

## 4. 扉絵（frontispiece / ornament）の選択肢と Kindle 互換性

現状の実装は CSS 背景（`background-image: var(--frontispiece-image)` + `background-attachment: fixed`）で、
固定ページ寸法（PDF の @page）を前提とする。リフロー EPUB では `fixed` が非対応のため**表示されない**
（画像実体は EPUB に同梱済み: `stylesheets/images/bundled/sakura_portrait.webp` 等）。

著者の希望デザイン: **h1 = 1 ページ全面の扉絵（見出しを重ねる）／ h2 = 上部 1/4 を飾り画像の背景に**。

| 方式 | Apple Books 等 | **Kindle** | 備考 |
| --- | --- | --- | --- |
| (A) 背景CSS（fixed 除去 + `min-height:100vh`） | ◎ 全面＋重ね | ✗ 背景無視・vh 不安定 | 実装は軽いが Kindle で出ない恐れ |
| (B) インライン img・**重ね合わせ**（position） | ◎ 背景に絵＋見出し | △ 重ならず上下に分離へ劣化 | 主要リーダーは希望どおり／Kindle は劣化 |
| (C) インライン img・**上下に並べる** | ○ 画像＋見出し | ◎ 確実に表示 | 全リーダーで同じ・最も堅牢。背景表現は不可 |
| (D) 固定レイアウト(FXL)の扉ページ | ◎ 全面 | ◎ 全面（§5） | 本文リフローと混在の複雑さ大 |

- **Kindle 優先なら (C)** が現実解。扉絵・飾りが**確実に表示**され「淋しさ」は解消するが、
  「背景に絵＋見出しを重ねる」表現にはならない（画像と見出しが上下に並ぶ）。
- (B) は主要リーダーで希望どおりだが、**Kindle で自動的に (C) 相当へ劣化**する
  （重ね合わせが効かないため。画像自体は出る）。
- 「全面の扉絵」を Kindle でも確実に出すには **(D) FXL** が必要だが、本文との混在が重い（§5）。

---

## 5. 固定レイアウト（FXL）EPUB の検討

- FXL は 1 ページ = 1 固定キャンバスで、**全面画像・厳密な配置が可能**。Kindle も対応（絵本・コミック向け）。
- ただし FXL は**リフローを無効化**するため、文字主体の技術書本文には不適
  （文字サイズ変更・折返しができず可読性が大きく落ちる）。
- 「扉ページだけ FXL、本文はリフロー」の**混在**は EPUB 仕様上は可能だが、
  Vivliostyle の EPUB 生成パイプラインはリフロー前提であり、混在対応は**大きな追加実装**を要する。
- 現実的には RC スコープ外。将来、扉絵を最重視する場合の選択肢として記録に留める。

---

## 6. 数式（LaTeX）の Kindle 互換性

VFM は数式を `<span class="math" data-math-typeset>` の生 LaTeX（`\(...\)` / `$$...$$`）として出力し、
**Vivliostyle の MathJax がレンダリング時に組版**する設計。PDF は描画されるが、EPUB 出力には
MathJax の結果が焼き込まれず、生 LaTeX が露出する。

| 数式の表現方法 | Apple Books / Kobo / Thorium | **Kindle** | 備考 |
| --- | --- | --- | --- |
| 生 LaTeX のまま（現状） | ✗ 露出 | ✗ 露出 | 不可 |
| **MathML**（temml 等で変換） | ◎ 描画 | △ 端末差・崩れ得る | KF は MathML サブセット対応だが不安定 |
| **画像化（SVG / PNG）** | ◎ | ◎ 確実 | STEM 書籍の定番。実装規模大 |

- temml（軽量・純 JS・LaTeX→MathML）で **MathML 化**すれば、Apple Books / Kobo / Thorium では綺麗に出る。
  **Kindle は MathML サポートが不安定**で、端末・アプリにより崩れる可能性がある。
- Kindle でも確実にするには **数式の画像化（SVG が望ましい）** が定番だが、
  変換・配置・代替テキスト付与など実装規模が大きい。
- 補足: 本文中のインライン数式（`\(...\)`）と独立数式（`$$...$$`）に加え、
  **GFM テーブルセル内の `$...$` は VFM が数式 span 化しない**別問題があり、PDF でも未描画
  （`build-output-bugfix-spec.md` ④-B。サンプル原稿は Unicode 表記へ置換して回避済み）。

---

## 7. 推奨と未決事項（後日決定用）

### 推奨（Kindle 優先の場合）

- **扉絵**: (C) インライン img・上下並べ を基準にする。全リーダー（Kindle 含む）で確実に表示でき、
  「淋しさ」は解消。背景＋重ね合わせは Kindle 非対応のため採らない。
  - 主要リーダー向けに (B) の重ね合わせを「対応リーダーのみ強化（progressive enhancement）」として
    上積みする折衷案も可能（Kindle は (C) に自然劣化）。実装はやや増える。
- **数式**: 一次対応として temml で **MathML 化**（主要リーダーで綺麗）。
  Kindle での確実描画が必須要件になった段階で **画像化（SVG）** を別タスクとして検討。

### 未決事項

1. 扉絵を **(C) 一本化**するか、**(B)+(C) の折衷（リーダー判定での上積み）**にするか。
2. 数式を **MathML のみ**で出すか、**Kindle 向けに画像化**まで踏み込むか。
3. h2（節）の飾りを **上部バナー img** で表すか、CSS 背景（Kindle で消える）を許容するか。
4. 将来的に **扉ページのみ FXL** を採用する価値があるか（規模大）。

### 検証手段

- **Kindle Previewer**（Amazon 公式）で実機相当の表示確認を行ってから方式を確定する。
- Apple Books / Kobo / Thorium でも併せて確認し、リーダー間差を把握する。

---

## 8. 付記: 現状の実装

- 扉絵 CSS: `stylesheets/image-header.css`（`background-image: var(--frontispiece-image)` +
  `background-attachment: fixed` + `--frontispiece-background-size`）。`fixed` が EPUB 非対応で未表示。
- 画像実体は EPUB に同梱される（`copyAsset.excludes` は `stylesheets/images` を除外していない）。
- 数式: `vfm` が `data-math-typeset` span を生成、Vivliostyle CLI（内蔵 MathJax）が PDF で組版。
  EPUB では未焼込。

本書は調査時点のスナップショットであり、方式確定時に Kindle Previewer 実機確認で再検証する。
