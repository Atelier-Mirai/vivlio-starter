# vs-lint コメント記法統一 改修仕様書

## 概要

`vs lint` コマンドは textlint（日本語校正）と spellcheck（英語スペルチェック）の2つのチェックを実行する。
現行実装ではそれぞれのチェックが異なる除外記法を持っており、利用者の利便性を損なっている。

本仕様書は、両チェックの除外記法を `vs-lint` プレフィックスに統一し、
一行除外・複数行除外の両機能を textlint・spellcheck の双方で機能させるための改修を定める。

---

## 現行の問題点

### textlint 側の実装

| 機能 | 記法 |
|---|---|
| 複数行除外（開始） | `<!-- textlint-disable -->` |
| 複数行除外（終了） | `<!-- textlint-enable -->` |
| 次の行のみ除外 | `<!-- textlint-disable-next-line -->` |
| 特定ルールのみ除外 | `<!-- textlint-disable prh -->` |

textlint 本体の filter-rule-comments プラグインが `textlint-disable` 系コメントをネイティブに解釈する。
Vivlio Starter 独自の制御ではなく、textlint の標準機能に依存している。

### spellcheck 側の実装

| 機能 | 記法 |
|---|---|
| 一行除外（行末） | `<!-- spellcheck:ignore -->` |
| 複数行除外 | **未実装** |

spellcheck は Vivlio Starter が独自実装したチェック機構であり、
HTMLコメントを行ごとにスキャンして `spellcheck:ignore` を検出する。

---

## 新記法の定義

### コメント一覧

| 記法 | 配置 | 効果 |
|---|---|---|
| `<!-- vs-lint-disable -->` | 除外したい範囲の直前の行 | 対応する `enable` までの全行を除外 |
| `<!-- vs-lint-enable -->` | 除外したい範囲の直後の行 | 除外範囲を終了する |
| `<!-- vs-lint-disable-next-line -->` | 除外したい行の直前の行 | 次の1行のみを除外 |

### 適用対象

- textlint（日本語校正）
- spellcheck（英語スペルチェック）

の両方に対して同一の記法が機能する。

### 記法の詳細ルール

#### `<!-- vs-lint-disable -->`

- コメントは単独の行に記述する。
- このコメント行自体は除外範囲に含まれない（次の行から除外が始まる）。
- 対応する `<!-- vs-lint-enable -->` が存在しない場合、ファイル末尾まで除外する。

#### `<!-- vs-lint-enable -->`

- コメントは単独の行に記述する。
- このコメント行自体は除外範囲に含まれない（前の行まで除外が終わる）。
- 対応する `<!-- vs-lint-disable -->` が存在しない場合は無視する。

#### `<!-- vs-lint-disable-next-line -->`

- コメントは単独の行に記述する。
- 直後の1行のみが除外対象となる。
- `<!-- vs-lint-disable -->` の範囲内で使用した場合、すでに範囲除外が効いているため
  実質的な意味を持たないが、エラーとはしない。

---

## 改修対象と方針

### 1. textlint チェック

#### 現状

textlint は `textlint-filter-rule-comments` プラグインを通じて
`<!-- textlint-disable -->` 系コメントをネイティブに解釈している。

#### 改修方針

**textlint プラグインをそのまま維持し、前処理で変換する。**

`vs lint` コマンドが textlint を呼び出す前に、対象 `.md` ファイルをメモリ上（または一時ファイル）に展開し、
以下の変換を施したうえで textlint に渡す。

| 変換前（新記法） | 変換後（textlint ネイティブ記法） |
|---|---|
| `<!-- vs-lint-disable -->` | `<!-- textlint-disable -->` |
| `<!-- vs-lint-enable -->` | `<!-- textlint-enable -->` |
| `<!-- vs-lint-disable-next-line -->` | `<!-- textlint-disable-next-line -->` |

変換はファイルを書き換えず、標準入力またはテンポラリファイルで行う。
textlint のエラー出力に含まれる行番号は変換前ファイルと一致するため、
ユーザーへの表示に補正は不要。

#### 実装箇所

`lib/vivlio_starter/commands/lint_command.rb`（または相当するクラス）内の
textlint 呼び出しロジック。

```ruby
# 変換例（概念コード）
def rewrite_comments(source)
  source
    .gsub("<!-- vs-lint-disable-next-line -->", "<!-- textlint-disable-next-line -->")
    .gsub(/<!--\s*vs-lint-disable\s*-->/, "<!-- textlint-disable -->")
    .gsub(/<!--\s*vs-lint-enable\s*-->/, "<!-- textlint-enable -->")
end
```

`disable-next-line` を先に置換することで、`disable` への誤マッチを防ぐ。

---

### 2. spellcheck チェック

#### 現状

spellcheck は `contents/` 配下の `.md` ファイルを1行ずつスキャンし、
行末の `<!-- spellcheck:ignore -->` を検出してその行を除外している。

複数行除外機能は未実装。

#### 改修方針

**spellcheck 本体のコメント解析ロジックを全面的に置き換える。**

ファイルを事前にスキャンして除外行番号のセットを構築し、
チェック本体では行番号を参照して除外判定を行う。

#### 除外行番号セット構築アルゴリズム

```ruby
excluded_lines = Set.new
in_disable_block = false
lines.each_with_index do |line, index|
  line_number = index + 1  # 1-origin
  stripped = line.strip

  if stripped == "<!-- vs-lint-disable -->"
    in_disable_block = true
    next
  end

  if stripped == "<!-- vs-lint-enable -->"
    in_disable_block = false
    next
  end

  if stripped == "<!-- vs-lint-disable-next-line -->"
    excluded_lines.add(line_number + 1)
    next
  end

  excluded_lines.add(line_number) if in_disable_block
end
```

#### コメント行自体の扱い

`<!-- vs-lint-disable -->` `<!-- vs-lint-enable -->` `<!-- vs-lint-disable-next-line -->`
の各コメント行自体は、スペルチェック対象外とする（英単語を含まないため実害はないが、
明示的に除外しておくことで挙動を明確にする）。

#### 実装箇所

`lib/vivlio_starter/spellcheck/` 配下のファイルスキャン・行フィルタリングロジック。
既存の `spellcheck:ignore` 検出ロジックを削除し、上記アルゴリズムで置き換える。

---

## 後方互換性

### 旧記法の扱い

旧記法は**サポートしない（削除する）**。

| 旧記法 | 新記法 | 対応 |
|---|---|---|
| `<!-- textlint-disable -->` | `<!-- vs-lint-disable -->` | 非対応（削除） |
| `<!-- textlint-enable -->` | `<!-- vs-lint-enable -->` | 非対応（削除） |
| `<!-- textlint-disable-next-line -->` | `<!-- vs-lint-disable-next-line -->` | 非対応（削除） |
| `<!-- textlint-disable prh -->` | `<!-- vs-lint-disable -->` | 非対応（削除） |
| `<!-- spellcheck:ignore -->` (行末) | `<!-- vs-lint-disable-next-line -->` | 非対応（削除） |

#### 理由

- 旧記法を混在サポートすると、著者の混乱を招き統一の目的が失われる。
- Vivlio Starter は 現在開発中であるため、後方互換性は不要である。

---

## テスト仕様

### textlint 除外テスト

| ケース | 入力 | 期待結果 |
|---|---|---|
| disable〜enable 内の行 | `<!-- vs-lint-disable -->` 〜 `<!-- vs-lint-enable -->` で囲まれた行 | textlint エラーなし |
| disable-next-line の次行 | `<!-- vs-lint-disable-next-line -->` の直後の行 | textlint エラーなし |
| disable-next-line の次々行 | `<!-- vs-lint-disable-next-line -->` の2行後の行 | textlint エラーあり（除外されない） |
| enable のない disable | ファイル末尾まで disable | ファイル末尾まで除外 |

### spellcheck 除外テスト

| ケース | 入力 | 期待結果 |
|---|---|---|
| disable〜enable 内の行 | `<!-- vs-lint-disable -->` 〜 `<!-- vs-lint-enable -->` で囲まれた行 | spellcheck エラーなし |
| disable-next-line の次行 | `<!-- vs-lint-disable-next-line -->` の直後の行 | spellcheck エラーなし |
| disable-next-line の次々行 | `<!-- vs-lint-disable-next-line -->` の2行後の行 | spellcheck エラーあり（除外されない） |
| コメント行自体 | `<!-- vs-lint-disable -->` の行 | spellcheck 対象外 |
| 旧記法 `spellcheck:ignore` | 行末に旧記法を持つ行 | **除外されない**（旧記法は非対応） |

---

## 変更ファイル一覧（予定）

| ファイル | 変更内容 |
|---|---|
| `lib/vivlio_starter/commands/lint_command.rb` | textlint 呼び出し前の `vs-lint` → `textlint` コメント変換処理を追加 |
| `lib/vivlio_starter/spellcheck/checker.rb`（相当） | `spellcheck:ignore` 検出ロジックを削除し、`vs-lint` 記法による除外行セット構築ロジックに置換 |
| `contents/` 配下の全 `.md` ファイル | 旧記法を新記法に一括変換（移行作業） |
| `config/.textlintrc.yml` | 変更なし（textlint プラグイン設定はそのまま維持） |

---

## 備考

- textlint プラグイン（`textlint-filter-rule-comments`）の `textlint-disable` 対応はそのまま利用する。
  Vivlio Starter 独自の記法は前処理変換で吸収するため、プラグイン設定の変更は不要。
- `<!-- vs-lint-disable prh -->` のような**特定ルール指定は実装しない**。
  textlint・spellcheck ともにルール単位の除外ニーズは低く、シンプルさを優先する。
