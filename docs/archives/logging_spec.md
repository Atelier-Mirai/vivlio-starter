# ログ出力仕様

## 概要

Vivlio Starter のログ出力メソッド群の仕様を定義する。
すべてのログ出力はこのメソッド群を経由し、`puts` の直接呼び出しは行わない。

---

## アイコン一覧

| メソッド | アイコン | コードポイント | 用途 |
|---------|---------|--------------|------|
| `log_info` | 🔵 | U+1F535 | 途中経過の情報 |
| `log_success` | ✅ | U+2705 | 途中経過の小さな成功 |
| `log_warn` | 🟡 | U+1F7E1 | 途中経過の警告 |
| `log_error` | 🔴 | U+1F534 | 途中経過のエラー |
| `log_action` | 🔧 | U+1F527 | 処理の開始・実行 |
| `log_debug` | 🧪 | U+1F9EA | デバッグ情報 |
| `log_inspection` | 🔍 | U+1F50D | 検証の詳細（verbose 時） |
| `log_summary` | 🔍 | U+1F50D | 検証サマリー（問題あり時は常に表示） |
| `log_result` | ✅/❌/📚 | — | コマンドの最終結果 |
| `log_always` | なし | — | 常に表示する素のテキスト |

アイコンはすべて U+1F*** 番台または Wide (W) 規定の文字を使用し、
ターミナル上での文字幅ずれを防ぐ。

---

## ログレベル

| レベル値 | 表示されるメソッド |
|---------|----------------|
| 0 | `log_error` `log_result` `log_summary` `log_always` |
| 1 | 上記 + `log_warn` |
| 2 | 上記 + `log_info` `log_success` `log_action` `log_inspection` |
| 3 | 上記 + `log_debug` |

---

## 出力フォーマット

### 基本形式

```
{アイコン} {msg}
```

### detail あり（2行形式）

```
{アイコン} {msg}
{アイコン} {DETAIL_INDENT}{detail 1行目}
{アイコン} {DETAIL_INDENT}{detail 2行目}
```

`DETAIL_INDENT` は半角スペース 8 文字固定とする。
`detail` が複数行の場合は `\n` で区切って渡す。

---

## 出力例

### log_warn（detail なし）

```
🔴 25-cross-reference.md:338 - ソースコード 'prime2.rb' が見つかりません
```

### log_warn（detail あり）

```
🟡 25-cross-reference.md:318 - 画像 'sample.png' が見つかりません（代替画像を使用します）
        画像の場所: images/25-cross-reference/sample.webp
```

### log_error（detail 複数行）

```
🔴 22-extentions.md:427 - 雛形ファイル '_book.full.md' が見つかりません（記法: = books | :full）
        雛形の場所: templates/_book.full.md
        ヒント: '_book.md' は存在します。スタイル名を確認してください。
```

### log_result

```
✅ Preflight 完了: 問題なし
❌ Preflight 完了: 問題あり — 詳細は上記を確認してください
📚 12-quickstart.pdf を作成しました (15.4s)
```

---

## メッセージ構成規則

### msg の構成

| 種別 | 構成 |
|------|------|
| ファイル起因の警告・エラー | `{ファイル名}:{行番号} - {問題の説明}（{補足}）` |
| システム起因のエラー | `{処理名}エラー: {問題の説明}` |
| 最終結果 | `{コマンド名} 完了: {結果の説明}` |

### detail の構成

| 行 | 内容 |
|----|------|
| 1行目 | 対象ファイルの場所（`画像の場所:` `雛形の場所:` `コードの場所:` 等） |
| 2行目 | ヒント（解決の手がかり）※ある場合のみ |

---

## メソッド定義

```ruby
DETAIL_INDENT = " " * 8

def log_info(msg)
  puts "🔵 #{msg}" if current_log_level >= 2
end

def log_success(msg)
  puts "✅ #{msg}" if current_log_level >= 2
end

def log_warn(msg, detail: nil)
  return unless current_log_level >= 1
  puts "🟡 #{msg}"
  format_detail(detail).each { |line| puts "#{DETAIL_INDENT}#{line}" }
end

def log_error(msg, detail: nil)
  puts "🔴 #{msg}"
  format_detail(detail).each { |line| puts "#{DETAIL_INDENT}#{line}" }
end

def log_action(msg)
  puts "🔧 #{msg}" if current_log_level >= 2
end

def log_debug(msg)
  puts "🧪 #{msg}" if current_log_level >= 3
end

def log_inspection(msg)
  puts "🔍 #{msg}" if current_log_level >= 2
end

def log_summary(msg)
  puts "🔍 #{msg}"
end

def log_result(msg, status:)
  icon = case status
         when :success  then "✅"
         when :failure  then "❌"
         when :artifact then "📚"
         end
  puts "#{icon} #{msg}"
end

def log_always(msg)
  puts msg
end

private

def format_detail(detail)
  return [] if detail.nil?
  detail.lines.map(&:chomp)
end
```

---

## 呼び出し例

```ruby
log_warn "25-cross-reference.md:318 - 画像 'sample.png' が見つかりません（代替画像を使用します）",
         detail: "画像の場所: images/25-cross-reference/sample.webp"

log_error "22-extentions.md:427 - 雛形ファイル '_book.full.md' が見つかりません（記法: = books | :full）",
          detail: "雛形の場所: templates/_book.full.md\nヒント: '_book.md' は存在します。スタイル名を確認してください。"

log_error "25-cross-reference.md:338 - ソースコード 'prime2.rb' が見つかりません",
          detail: "コードの場所: codes/_prime2.md"

log_result "Preflight 完了: 問題なし", status: :success
log_result "Preflight 完了: 問題あり — 詳細は上記を確認してください", status: :failure
log_result "12-quickstart.pdf を作成しました (15.4s)", status: :artifact
```

## 現状からの改善

上記で定めたログ出力仕様に基づき、それぞれの警告やエラー出力を次のように改善し、著者への提案力向上を図る。

### 画像が見つからなかった場合

**現状**
```
🟡 25-cross-reference.md:318 - 画像 'sample.png' が見つかりません（代替画像を使用します）
🟡                             画像の場所: images/25-cross-reference/sample.webp
```

**改善後**
```
🟡 25-cross-reference.md:318 - 画像 'sample.png' が見つかりません（代替画像を使用します）
        画像の場所: images/25-cross-reference/sample.webp
```

### ソースコードが見つからなかった場合

**現状**
```
🔴 25-cross-reference.md:338 - ソースコード 'prime2.rb' が見つかりません
```

**改善後**
```
🔴 25-cross-reference.md:338 - ソースコード 'prime2.rb' が見つかりません
        コードの場所: codes/_prime2.md
```

### QueryStream 展開エラー

**現状**
```
🔴 QueryStream 展開エラー: テンプレートファイルが見つかりません: templates/_book.full.md
🔴    記法: = books | :full (22-extentions.md:427)
🔴    ヒント: templates/_book.md は存在します。スタイル名を確認してください。
```

**改善後**
```
🔴 22-extentions.md:427 - 雛形ファイル '_book.full.md' が見つかりません（記法: = books | :full）
        雛形の場所: templates/_book.full.md
        ヒント: '_book.md' は存在します。スタイル名を確認してください。
```

### 裸 URL の検出

**現状**
```
🟡 94-sample.md:461 - 裸 URL を検出しました
🟡   URL: https://onlinelibrary.wiley.com/journal/15213889
```

**改善後**
```
🟡 94-sample.md:461 - 裸 URL を検出しました
        URL: https://onlinelibrary.wiley.com/journal/15213889
```

### リンク・画像検証

**現状**
```
🔍 リンク・画像検証の結果:
🔍    画像: 8 件の問題（存在しない画像: 8）
🔍    ソースコード: 6 件の問題（存在しないファイル: 6）
🔍    リンク: 3 件の問題（裸 URL: 3）
🔍    外部URL到達性チェック: スキップ（--verify-links で有効化）
```

**改善後**
```
🔍 リンク・画像検証の結果:
        画像: 8 件の問題（存在しない画像: 8）
        ソースコード: 6 件の問題（存在しないファイル: 6）
        リンク: 3 件の問題（裸 URL: 3）
        外部URL到達性チェック: スキップ（--verify-links で有効化）
```