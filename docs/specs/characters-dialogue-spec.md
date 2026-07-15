# 会話文（対話）記法の刷新と `config/characters.yml` 仕様書

> 作成日: 2026-07-12
> ステータス: **提案（未実装・レビュー待ち）** — 本仕様の確定が実装着手のブロッカー（PLANNED「記法・データモデルを練ってから着手」）
> 対象: PLANNED.md:43 [Medium]「会話文（対話）記法の刷新と `config/characters.yml` 化」。旧 `先生`/`生徒` ハードコード方式は**廃止済み**であり、後継をゼロから設計する
> 決定事項（本仕様の提案）:
> - 記法は **`:::{.talk}` ブロック内に `キー: 発話`（ローマ字キー＋半角コロン）** を主記法とする。`【表示名】発話` の全角形は**採用しない**（§1.4 に理由）
> - キャラクター定義は `config/characters.yml`。**簡易形（色だけ）と詳細形（表示名/色/アイコン/左右）の両対応**
> - レイアウトは**チャットアプリ風（左右吹き出し）を PDF/クリーン EPUB の標準**とし、**Kindle は「色帯＋実体ラベルの簡易表示」へ劣化**（CLAUDE.md の 3 点セット劣化パターンを適用）
> - アイコン画像の標準ディレクトリは **`images/characters/`**
> 関連: `lib/vivlio_starter/cli/pre_process/markdown_transformer.rb`（`:::` 記法変換の同居先）, `lib/vivlio_starter/cli/pre_process/book_settings_css.rb`（設定→生成 CSS の既存機構。characters.yml の色もこの生成ファイルに載せる）, `lib/vivlio_starter/cli/build/epub_builder.rb:1539`（`ADMONITION_LABELS`・Kindle 実体ラベル注入）, `lib/vivlio_starter/cli/guards/container_class_check.rb`（`talk` クラスの登録先）, `stylesheets/components.css`（コンポーネント CSS の置き場）, `contents/22-extentions.md`（HTML コメントアウト中の「会話文」節——確定後に書き直す）

## 0. 背景

旧方式の問題（PLANNED より）: (1) トリガー語 `先生`/`生徒` がハードコードで、著者が話者を増やすには CSS 編集が必要だった。(2) `【先生A】` の `A` がクラスとしてしか残らず、表示名は `::before` 固定で分かりにくかった。

刷新の柱は「**著者は CSS を書かない**」。話者の追加・色変え・アイコン設定をすべて `config/characters.yml` で完結させる。

## 1. 著者向け仕様

### 1.1 `config/characters.yml`

```yaml
# 簡易形: 値が文字列なら色（テーマ色名 or HEX）
yamada: "#1565c0"
hanako: teal

# 詳細形: 値がマップなら詳細指定
sensei:
  name: 山田先生          # 表示名（省略時はキーをそのまま表示）
  color: indigo           # テーマ色名 / HEX（省略時はテーマアクセント色）
  icon: sensei.webp       # images/characters/ 内のファイル名（省略可）
  side: left              # left / right（省略時は出現順に left, right, left, …と自動割当）
```

- キーは**半角英数（ローマ字）**。本文の話者指定に使う（IME 切替なしで書ける）
- 色の語彙は `theme.color` と同一（yellow〜lime の 12 色名＋HEX）。検証は既存 `ThemeValidator` の色検証を流用
- `characters.yml` は**任意ファイル**。存在しないプロジェクトでは `.talk` 記法の使用時に 🔴 で作成を促す（雛形 3 行を提示）
- 雛形（scaffold）には**コメントアウトされた記入例のみ**を置く（既定キャラクターは提供しない——旧方式の「先生/生徒の押し付け」を繰り返さない）

### 1.2 本文記法

```markdown
:::{.talk}
sensei: Vivliostyle は CSS で組版するエンジンです。
hanako: CSS だけで本が作れるんですか？
sensei: そうです。このガイドブック自体が実例ですよ。
       複数行に続けたいときは行頭をインデントします。
:::
```

- 1 行 = 1 発話。行頭の `キー: `（キー＋半角コロン＋空白）で話者を切り替える
- **継続行**: 行頭が空白（インデント）の行は直前の発話の続き。発話内では通常の Markdown インライン記法（強調・コード・リンク）が使える
- 空行は無視。`キー:` に一致しない非インデント行は 🔴 エラー（「話者キーがありません」＋修正例）
- 未定義キーは 🔴 エラーで **characters.yml への追記例（before→after）と出現箇所**を提示（warning-messages の方針）

### 1.3 表示（ターゲット別）

| ターゲット | 表示 |
|---|---|
| PDF / クリーン EPUB | チャットアプリ風。`side` に応じて吹き出しを左右に振り分け。アイコンがあれば吹き出し外側に丸抜き表示、なければ表示名だけの色付きラベル。吹き出しの枠・名前がキャラクター色 |
| Kindle (KFX) | 吹き出し・左右振り分けなし。各発話を「**太字の表示名（実体テキスト）＋左罫線（キャラクター色・リテラル値）**」の段落ブロックで縦に並べる |

### 1.4 全角形 `【山田】…` を採用しない理由（記録）

- 主記法とダブルトリガーにすると、前処理・エラーメッセージ・ドキュメントが二重化する
- `【…】` は既に Kindle 劣化ラベル（`【TIP】` 等）の視覚語彙として使われており、原稿内での役割が衝突する
- 「全角に切替えず書ける」という原案の動機は、ローマ字キー方式そのものが満たしている

## 2. データモデル・変換設計

### 2.1 読み込み

- `lib/vivlio_starter/cli/pre_process/character_registry.rb`（新規）: `config/characters.yml` を `YAML.safe_load` で読み、`Character = Data.define(:key, :name, :color, :icon, :side)` の配列＋キー引きに正規化。簡易形/詳細形の吸収・side 自動割当・色検証をここで行う
- 読み込みは前処理開始時に 1 回（`Common.reload_configuration!` とは独立。ビルド中は不変）
- `Common::REQUIRED_YAML_FILES` には**加えない**（任意ファイル）。壊れた YAML は 🔴＋行番号（既存の YAML 安全読み込みの流儀）

### 2.2 記法変換（前処理）

`MarkdownTransformer` に `.talk` ブロック変換を追加。`:::{.talk}` 内を解析し、**生 HTML** へ変換する（table-rotate / book-card と同系の「ブロック→HTML」変換）:

```html
<div class="talk">
  <div class="talk-item talk-left talk-c-sensei">
    <img class="talk-icon" src="images/characters/sensei.webp" alt="" />
    <div class="talk-body">
      <span class="talk-name">山田先生</span>
      <p>Vivliostyle は CSS で組版するエンジンです。</p>
    </div>
  </div>
  ...
</div>
```

- 発話内インライン Markdown は VFM に変換させる必要があるため、**発話テキストは Markdown のまま残せない**（生 HTML 内は VFM が処理しない）。→ 発話部分だけ `MarkdownUtils` 経由でインライン変換してから埋め込む（book-card 変換と同じ制約・同じ解法）
- キャラクター別クラスは `talk-c-<key>`。色はクラス経由で当てる（inline style は Kindle 劣化制御・テーマ差し替えを阻むため使わない）
- アイコンパス: `images/characters/<icon>` を実在確認（変種 `.webp/.png/.jpg` は `ImagePathNormalizer.image_exists_for?` と同ポリシー）。不在なら 🟡＋アイコンなし表示へフォールバック（ビルドは止めない）
- `ContainerClassCheck` の既知クラスに `talk` を登録（`PREPROCESSED_CLASSES` 側——前処理で消費されるクラスのため）

### 2.3 CSS（2 層）

1. **静的コンポーネント CSS**（`stylesheets/components.css` に追加）: 吹き出しレイアウト・左右振り分け・アイコン丸抜き等の構造。色は `var(--talk-c-<key>)` を参照
2. **生成 CSS**（`BookSettingsCss.generate!` を拡張）: `characters.yml` から

```css
:root {
  --talk-c-sensei: #3f51b5;
  --talk-c-hanako: #009688;
}
.talk-c-sensei { --talk-accent: var(--talk-c-sensei); }
```

を book-settings.css へ追記する。**ソース CSS を書き換えない**（P3「生成 1 枚がカスケードで勝つ」方式に乗る。書き換え方式へ逆行しない）

### 2.4 Kindle 劣化（CLAUDE.md 3 点セットの適用＋α）

Kindle は `::before` ラベルと `var()` を無視するため:

1. **実体ラベル注入**: `EpubBuilder` の Kindle 経路で `.talk-item` ごとに `<p class="vs-adm-label">山田先生</p>` 相当を注入——ただし admonition と違い**ラベルは話者ごとに動的**なので、`ADMONITION_LABELS`（固定表）ではなく `.talk-name` を利用する。具体的には Kindle 経路で `.talk-name`（span）を `<p class="vs-talk-label">` へ**タグ昇格**し、アイコン `<img>` を除去する変換を `decorate_admonitions_for_epub!` の並びに追加
2. **リテラル色 CSS**: `body.vs-kindle .talk-item { border-left: 3px solid <literal>; ... }` ——色がキャラクター依存のため、`chapter-common.css` の静的記述では足りない。**生成 CSS 側（book-settings.css）に `body.vs-kindle .talk-c-<key> { border-left-color: #3f51b5 }` をリテラル値で出力**する（§2.3-2 と同じ生成器で吸収。テーマ色名→HEX の解決は既存 `normalize_color_value` を流用）
3. **テスト**: `epub_kindle_layout_test` に「.talk の各発話に実体ラベルが入る・img が除去される」アサーションを追加

クリーン EPUB は PDF と同じ吹き出し表示（`vs-epub` では劣化させない）。

## 3. テスト

1. **character_registry_test**（新規）: 簡易形/詳細形の正規化・side 自動割当（left→right 交互）・色検証エラー・icon 変種解決・YAML 破損時のエラー文言
2. **markdown_transformer 追加ケース**: `.talk` ブロック→HTML 構造（クラス・左右・アイコン有無）、継続行の連結、未定義キー 🔴（characters.yml 追記例を含む）、`characters.yml` 不在時 🔴、発話内インライン Markdown（強調・コード）の変換
3. **book_settings_css 追加ケース**: `--talk-c-*` 変数と `body.vs-kindle` リテラル色が生成 CSS に載る。characters.yml 不在なら何も出力しない
4. **epub_kindle_layout_test 追加**: §2.4-3
5. **結合（任意）**: `contents/22-extentions.md` の会話文節を本記法で復活させ、`vs build` / `vs epub` / `vs kindle` で目視確認（Kindle Previewer 実測）

## 4. 手順（実装順序）

1. 本仕様のレビュー・確定（記法/YAML スキーマは後方互換の縛りが生まれるため、着手前に確定させる）
2. `character_registry.rb` ＋テスト
3. `MarkdownTransformer` の `.talk` 変換＋ `ContainerClassCheck` 登録＋テスト
4. `components.css`（吹き出しレイアウト）＋ `BookSettingsCss` 拡張＋テスト
5. Kindle 劣化（EpubBuilder＋生成 CSS＋ epub_kindle_layout_test）
6. `config/characters.yml` 雛形・`images/characters/` の `_README.md` を root に追加 → 原稿 22 章の会話文節を書き直し → `ruby copy_to_scaffold.rb`
7. `rake test` ＋ 実機 3 ターゲット確認

## 5. スコープ外・未決事項

- **`山田：「…」` / `「…」：花子` 形式の左右対話表示**（原案の記法候補の一つ）: ブロック外のフリーフォーム検出は誤爆リスクが高く不採用。`side:` 指定が同じ表現力を安全に提供する
- **アイコンのテーマ別（light/dark）バリアント**: 対象外
- **1 ブロック内での話者色の動的変更・3 人以上の左右以外の配置（中央等）**: side は left/right の 2 値のみ
- **未決**: 吹き出けの尻尾（tail）の有無・角丸の程度などの意匠詳細は実装時に PDF 実測で決める（本仕様では構造とデータモデルのみ確定）
