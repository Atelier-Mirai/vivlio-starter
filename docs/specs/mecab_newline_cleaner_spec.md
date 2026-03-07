# MeCab を用いた不要な改行文字削除 仕様書

**対象 gem**: `vivlio-starter`  
**バージョン**: 1.0.0  
**作成日**: 2026-03-03

---

## 1. 目的

日本語テキストにおける「行幅による折り返し改行（ソフト改行）」を検出・削除し、自然な段落構造を持つテキストに整形する。本機能は `vivlio-starter` gem に組み込むモジュールとして実装する。

---

## 2. 背景と課題

PDF・書籍・資料などからコピーした日本語テキストには、印刷レイアウト上の都合で挿入された不要な改行が混入することがある。

```
# 例：不要な改行が含まれた入力テキスト
この三つの要素、主題・文法・道具は、それぞれ独立して学ぶものではありません。実際の学
習では、これらを織り交ぜながら進めていきます。
```

```
# 期待する出力テキスト
この三つの要素、主題・文法・道具は、それぞれ独立して学ぶものではありません。実際の学習では、これらを織り交ぜながら進めていきます。
```

単純な句点・記号マッチングでは以下のケースで誤判定が生じるため、MeCab による形態素解析を用いた精密な判定を採用する。

| 誤判定ケース | 説明 |
|---|---|
| 括弧内の助動詞終わり | `〜だ」` の `だ` を文末と誤判定 |
| URL中のドット | `.com` の `.` を句点と誤判定 |
| 引用符内の `？` `！` | 文中疑問を文末と誤判定 |
| 次行が接続助詞で始まる | 前行が句点でも文が続く場合がある |

---

## 3. 動作環境

| 項目 | 要件 |
|---|---|
| Ruby | 4.0 以上 |
| MeCab | インストール済み・`mecab` コマンドが PATH に存在すること |
| MeCab 辞書 | ipadic（デフォルト設定で動作すること） |
| 動作確認方法 | `echo "テスト" \| mecab` が正常に出力されること |

辞書パスの明示指定は原則不要とする。`/etc/mecabrc` または `~/.mecabrc` に設定されたデフォルト辞書を使用する。

### MeCab 出力フォーマットの確認

```bash
$ echo "テスト" | mecab
テスト  名詞,サ変接続,*,*,*,*,テスト,テスト,テスト
EOS
```

タブ区切りで以下の構造になっている：

| フィールド | 値 | 意味 |
|---|---|---|
| 表層形 | テスト | 入力文字列 |
| 品詞 | 名詞 | |
| 品詞細分類1 | サ変接続 | 「テストする」と使える名詞 |
| 読み | テスト | |
| 発音 | テスト | |

---

## 4. 入出力仕様

### 4.1 入力

| 項目 | 仕様 |
|---|---|
| 形式 | UTF-8 文字列（呼び出し元から渡される） |
| 改行コード | LF（`\n`）を基本とする |
| 段落区切り | 空行（`\n\n` 以上）で区切られた段落構造を前提とする |

### 4.2 出力

| 項目 | 仕様 |
|---|---|
| 形式 | UTF-8 文字列（呼び出し元に返す） |
| 段落区切り | 入力の段落構造を保持する |
| 文末改行 | 文末記号で終わる行の後の改行は保持する |

---

## 5. 処理仕様

### 5.1 処理フロー

```
入力テキスト（文字列）
    │
    ▼
[Step 1] 段落分割
    空行（2個以上の連続改行）を区切りとして段落に分割する
    │
    ▼
[Step 2] 段落内の行ごとに改行要否を判定
    各行末について「文末か否か」をMeCabで判定する
    │
    ▼
[Step 3] 改行の保持 or 削除
    文末と判定 → 改行を保持
    文末でないと判定 → 改行を削除し次の行と結合
    │
    ▼
[Step 4] 段落を空行で再結合
    │
    ▼
出力テキスト（文字列）
```

### 5.2 文末判定ロジック

以下のいずれかを満たす場合、**文末**と判定し改行を保持する。

| 優先度 | 条件 | 判定方法 |
|---|---|---|
| 1 | 行末が句点・感嘆符・疑問符（`。．！？`）で終わる | 正規表現 |
| 2 | 行末トークンが終助詞（`助詞-終助詞`） | MeCab品詞情報 |
| 3 | 行末トークンが文末と見なせる助動詞（`です` `ます` `だ` 等）**かつ**次行の先頭トークンが接続助詞・読点でない | MeCab品詞情報 |
| 4 | 次行の先頭トークンが接続助詞（`が` `て` `と` `ので` 等）である | MeCab品詞情報（次行先頭を解析） |

条件4は前行の状態に関わらず、**次行が接続助詞で始まる場合は強制的に改行削除**とする。

### 5.3 改行を**削除しない**条件（保持条件）

以下の場合は改行を必ず保持する。

- 空行（段落区切り）
- 行末が `。` `．` `！` `？` である
- 行がリスト記号（`-` `*` `・` `1.` 等）で始まる
- 行が見出し記号（`#`）で始まる（Markdown見出し）

### 5.4 MeCab 呼び出し仕様

```
mecab コマンドを Open3.capture2 経由で呼び出す。
入力：解析対象の1行文字列（UTF-8）
出力：MeCab の標準出力（タブ区切り形式）

出力フォーマット：
  表層形\t品詞,品詞細分類1,品詞細分類2,品詞細分類3,活用型,活用形,原形,読み,発音
  EOS
```

---

## 6. エラーハンドリング

| ケース | 対応 |
|---|---|
| `mecab` コマンドが見つからない | 標準エラーに警告を出力し、句点判定のみのフォールバックモードで処理を継続する |
| MeCab の出力が空または不正 | 当該行の改行は**保持**（安全側に倒す） |
| 入力エンコーディングが UTF-8 でない | 標準エラーに警告を出力し処理を中断する |

---

## 7. テストケース

### TC-01: 基本的な折り返し改行の削除

**入力**:
```
それぞれ独立して学ぶものではありません。実際の学
習では、これらを織り交ぜながら進めていきます。
```

**期待出力**:
```
それぞれ独立して学ぶものではありません。実際の学習では、これらを織り交ぜながら進めていきます。
```

---

### TC-02: 文末句点後の改行は保持

**入力**:
```
最初の文です。
次の文です。
```

**期待出力**:
```
最初の文です。
次の文です。
```

---

### TC-03: 次行が接続助詞で始まる場合

**入力**:
```
「本当に？」と思いながらも彼は
前に進んだ。
```

**期待出力**:
```
「本当に？」と思いながらも彼は前に進んだ。
```

---

### TC-04: URL中のドットを誤検知しない

**入力**:
```
詳細はhttps://example.com
を参照してください。
```

**期待出力**:
```
詳細はhttps://example.comを参照してください。
```

---

### TC-05: 段落区切りは保持

**入力**:
```
第一段落の文章です。

第二段落の文章です。
```

**期待出力**:
```
第一段落の文章です。

第二段落の文章です。
```

---

### TC-06: 括弧内の助動詞終わりを文末と誤判定しない

**入力**:
```
彼は「今日は晴れだ
と思った」と言った。
```

**期待出力**:
```
彼は「今日は晴れだと思った」と言った。
```

---

## 8. サンプルコード

### 8.1 句点判定のみを用いたシンプルな実装

MeCab を使わずに句点・記号のみで改行を判定する実装。TC-03・TC-04・TC-06 では誤判定の可能性があるが、軽量なフォールバックとして利用できる。

```ruby
def remove_soft_newlines(text)
  paragraphs = text.split(/\n{2,}/)

  paragraphs.map do |para|
    lines = para.split("\n").map(&:strip).reject(&:empty?)
    join_lines(lines)
  end.join("\n\n")
end

def join_lines(lines)
  result = ""
  lines.each_with_index do |line, i|
    if i == 0
      result += line
    elsif result.split("\n").last&.match?(/[。．！？」』】\.\!\?]$/)
      result += "\n" + line
    else
      result += line
    end
  end
  result
end
```

---

### 8.2 MeCab を用いた文末判定

`Open3.capture2` で `mecab` コマンドを呼び出し、行末トークンの品詞情報を取得する。

```ruby
require 'open3'

def sentence_end?(line)
  return false if line.strip.empty?

  stdout, = Open3.capture2("mecab", stdin_data: line.strip)
  tokens = stdout.lines.reject { |l| l.start_with?("EOS") || l.strip.empty? }
  return false if tokens.empty?

  last_token = tokens.last
  surface, features = last_token.split("\t")
  pos_info = features&.split(",") || []

  # 句点・記号・文末助詞・助動詞などで終わっていれば文末と判定
  surface&.match?(/[。．！？]/) ||
    (pos_info[0] == "助詞" && pos_info[1] == "終助詞") ||
    (pos_info[0] == "記号" && surface&.match?(/[）\)」』】]/))
end
```

---

### 8.3 MeCab を用いた改行削除の完全実装

```ruby
require 'open3'

def remove_soft_newlines_with_mecab(text)
  paragraphs = text.split(/\n{2,}/)

  paragraphs.map do |para|
    lines = para.split("\n").map(&:strip).reject(&:empty?)
    join_lines_mecab(lines)
  end.join("\n\n")
end

def join_lines_mecab(lines)
  result = ""
  lines.each_with_index do |line, i|
    if i == 0
      result += line
    elsif sentence_end?(result.split("\n").last || result)
      result += "\n" + line
    else
      result += line
    end
  end
  result
end

def sentence_end?(line)
  return false if line.strip.empty?

  stdout, = Open3.capture2("mecab", stdin_data: line.strip)
  tokens = stdout.lines.reject { |l| l.start_with?("EOS") || l.strip.empty? }
  return false if tokens.empty?

  last_token = tokens.last
  surface, features = last_token.split("\t")
  pos_info = features&.split(",") || []

  surface&.match?(/[。．！？]/) ||
    (pos_info[0] == "助詞" && pos_info[1] == "終助詞") ||
    (pos_info[0] == "記号" && surface&.match?(/[）\)」』】]/))
end
```

---

### 8.4 MeCab の利用可否に応じたフォールバック

`mecab` コマンドが存在しない環境では句点判定のみのモードに自動切替する。

```ruby
require 'open3'

def mecab_available?
  system("which mecab > /dev/null 2>&1")
end

def clean_newlines(text)
  if mecab_available?
    remove_soft_newlines_with_mecab(text)
  else
    warn "[vivlio-starter] MeCab not found. Falling back to punctuation-only mode."
    remove_soft_newlines(text)
  end
end
```

---

*以上*
