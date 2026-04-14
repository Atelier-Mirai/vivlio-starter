# lint 出力フォーマッター改善仕様書

---

## 1. 目的

`vs lint` の出力（textlint stylish フォーマット）を、日本語話者にとって読みやすい簡潔な形式に整形する。
現状の textlint 出力はエンジニア向けの冗長な英語混じりフォーマットであり、書籍執筆者にとって視認性が低い。
本仕様では、出力を後処理で再整形し、以下の改善を実現する。

## 2. 背景

- textlint の stylish フォーマットは `行:列  ✓ error  メッセージ  ルール名` の形式で出力される。
- 列番号・`✓ error` ラベル・複数行にわたる冗長な説明文が、一覧性を著しく損なっている。
- 現在の `TextlintFormatter` は一部の英語メッセージを日本語に翻訳するのみで、構造的な整形は行っていない。
- 改善後は、行番号のみの簡潔な表示・説明文のインデント整理・英語メッセージの日本語化により、修正箇所の特定と対応判断を素早く行えるようにする。

## 3. 対象範囲

- `lib/vivlio/starter/cli/textlint_formatter.rb` の拡張（出力再整形ロジックの追加）。
- `lib/vivlio/starter/cli/lint.rb` の出力パイプライン（`TextlintFormatter` 呼び出し部分）。
- 付随するテストの追加・更新。

## 4. 現状の出力パターンと改善案

### 4.1 単純な置換提案（prh 等）

**現状:**
```
    5:4     ✓ error  サーバ => サーバー                                                                                              prh
```

**改善後:**
```
    5  サーバ => サーバー (prh)
```

- 列番号を除去し、行番号のみ表示。
- `✓ error` ラベルを除去。
- ルール名を末尾に `(ルール名)` 形式で付与。
- 余分な空白を除去。

### 4.2 置換提案＋補足説明（prh 等の複数行出力）

**現状:**
```
   12:81    ✓ error  コンピュータ => コンピューター
語尾が -er, -or, -ar で終わる語彙には長音を付けます（外来語カタカナ表記）                                       prh
```

**改善後:**
```
   12  コンピュータ => コンピューター
         語尾が -er, -or, -ar で終わる語彙には長音を付けます（外来語カタカナ表記） (prh)
```

- 1行目: 行番号＋置換提案。
- 2行目以降: インデント（9文字分のスペース）＋補足説明。ルール名は最終行末尾に `(ルール名)`。

### 4.3 助詞重複などの長文エラー（no-doubled-joshi 等）

**現状:**
```
   14:87    error    一文に二回以上利用されている助詞 "により" がみつかりました。

次の助詞が連続しているため、文を読みにくくしています。

- "により"
- "により"

同じ助詞を連続して利用しない、文の中で順番を入れ替える、文を分割するなどを検討してください。
                    ja-technical-writing/no-doubled-joshi
```

**改善後:**
```
   14  一文に二回以上利用されている助詞 "により" がみつかりました。同じ助詞を連続して利用しない、文の中で順番を入れ替える、文を分割するなどを検討してください。 (ja-technical-writing/no-doubled-joshi)
```

- 冗長な中間部分（「次の助詞が連続しているため…」「- "により"」等のリスト）を除去。
- 1行目のメッセージと最終行の改善提案を結合し、1行にまとめる。
- 空行を除去。

### 4.4 文長超過（sentence-length）

**現状:**
```
   23:630   error    Line 23 sentence length(127) exceeds the maximum sentence length of 100.
Over 27 characters                                        japanese/sentence-length
```

**改善後:**
```
   23  文の長さ (127) が最大文長の 100 を超えています。 (japanese/sentence-length)
```

- 英語メッセージを日本語に翻訳。
- 「Over N characters」の補足行を除去（文長の数値で十分伝わるため）。

### 4.5 読点過多（max-ten）

**現状:**
```
   52:155   error    一つの文で"、"を4つ以上使用しています                                                                           ja-technical-writing/max-ten
```

**改善後:**
```
   52  一つの文で"、"を4つ以上使用しています (ja-technical-writing/max-ten)
```

- 列番号・`error` ラベル除去、ルール名を括弧付きに。

### 4.6 文体混在（no-mix-dearu-desumasu）

**現状:**
```
  115:55    error    本文: "である"調 と "ですます"調 が混在
=> "ですます"調 の文体に、次の "である"調 の箇所があります: "である。"
Total:
である  : 2
ですます: 47
                                          japanese/no-mix-dearu-desumasu
```

**改善後:**
```
  115  本文: "である"調 と "ですます"調 が混在。"ですます"調 の文体に "である"調 の箇所があります: "である。" (japanese/no-mix-dearu-desumasu)
```

- 「Total:」以降の統計情報を除去（混在の指摘のみで十分）。
- `=>` 以降の説明を1行に結合。

### 4.7 冗長表現（ja-no-redundant-expression）

**現状:**
```
   63:26    error    【dict5】 "記述を行う"は冗長な表現です。"記述する"など簡潔な表現にすると文章が明瞭になります。
解説: https://github.com/textlint-ja/textlint-rule-ja-no-redundant-expression#dict5                  ja-technical-writing/ja-no-redundant-expression
```

**改善後:**
```
   63  "記述を行う"は冗長な表現です。"記述する"など簡潔な表現にすると文章が明瞭になります。 (ja-technical-writing/ja-no-redundant-expression)
```

- `【dict5】` ラベルを除去。
- `解説: https://...` の URL 行を除去。

### 4.8 スペーシング系（ja-spacing）

**現状:**
```
    5:34    ✓ error  原則として、全角文字と半角文字の間にスペースを入れません。                                                      ja-spacing/ja-space-between-half-and-full-width
```

**改善後:**
```
    5  原則として、全角文字と半角文字の間にスペースを入れません。 (ja-spacing/ja-space-between-half-and-full-width)
```

### 4.9 ファイルパスヘッダー

**現状:**
```
/Users/mirai/projects/vivlio-starter/contents/08-web.md
```

**改善後:**
```
📄 contents/08-web.md
```

- 絶対パスをプロジェクトルートからの相対パスに変換。
- アイコンを付与して視認性を向上。

## 5. 整形ルールまとめ

| 要素 | 現状 | 改善後 |
| --- | --- | --- |
| 行:列 | `5:4` | `5` （列番号除去） |
| `✓ error` / `error` | 表示 | 除去 |
| ルール名 | 行末に空白区切り | `(ルール名)` 形式で末尾に |
| 補足説明 | 同一行 or 次行にフラット | 9文字インデントで次行に |
| 冗長な中間説明 | 複数行 | 要約して1行に結合 |
| 英語メッセージ | そのまま | 日本語に翻訳 |
| 空行 | エラー間に挿入 | 除去 |
| ファイルパス | 絶対パス | 相対パス＋アイコン |
| `【dictN】` ラベル | 表示 | 除去 |
| `解説: URL` 行 | 表示 | 除去 |
| `Total:` 統計ブロック | 表示 | 除去 |
| `Over N characters` 行 | 表示 | 除去 |

## 6. 実装方針

### 6.1 アーキテクチャ

`TextlintFormatter` を拡張し、`translate_output` に加えて `reformat_output` メソッドを追加する。
処理パイプラインは以下の順序:

1. **textlint 実行** → 生の stylish 出力を取得
2. **`reformat_output`** → 構造的な再整形（本仕様のメイン処理）
3. **`translate_output`** → 個別メッセージの日本語翻訳（既存処理）
4. **`filter_textlint_summary`** → サマリー行の除去（既存処理）

### 6.2 パース戦略

textlint stylish 出力は以下の構造を持つ:

```
<ファイルパス>
    <行>:<列>  [✓] error  <メッセージ>  <ルール名>
[<継続行>...]
[<空行>]
```

パーサーは行単位でステートマシンとして動作する:

- **ファイルヘッダー行**: `/` で始まる絶対パス → 相対パス化
- **エラー開始行**: `^\s+\d+:\d+\s+` にマッチ → 新しいエラーエントリ開始
- **継続行**: エラー開始行にマッチしない非空行 → 現在のエラーエントリに追加
- **空行**: 区切り → 無視

各エラーエントリをパースした後、整形ルールに従って出力文字列を生成する。

### 6.3 エラーエントリの構造

パース結果は以下のデータ構造で保持する:

```ruby
LintEntry = Data.define(:line, :fixable, :message, :details, :rule)
```

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `line` | Integer | 行番号 |
| `fixable` | Boolean | `✓` の有無（自動修正可能か） |
| `message` | String | 主メッセージ（1行目） |
| `details` | Array<String> | 補足説明行（2行目以降） |
| `rule` | String | ルール名 |

### 6.4 整形フェーズ

1. **ルール名抽出**: 主メッセージまたは最終継続行の末尾からルール名を分離。
2. **ラベル除去**: `✓ error` / `error` を除去。
3. **列番号除去**: `行:列` → `行` に変換。
4. **冗長部分の除去**:
   - `【dictN】` プレフィクス
   - `解説: https://...` 行
   - `Total:` 以降の統計ブロック
   - `Over N characters` 行
   - 助詞リスト（`- "助詞"` 形式の行）と「次の助詞が連続しているため…」の定型文
5. **メッセージ結合**: 分離された主メッセージと有用な補足を結合。
6. **英語→日本語翻訳**: sentence-length 等の英語メッセージを日本語化。
7. **出力生成**: 整形済みエントリを文字列に変換。

### 6.5 英語メッセージの日本語翻訳（追加分）

| 英語パターン | 日本語 |
| --- | --- |
| `Line N sentence length(M) exceeds the maximum sentence length of L.` | `文の長さ (M) が最大文長の L を超えています。` |
| `Disallow to use "X"` | `「X」は使用しないでください` （既存） |

### 6.6 lint.rb の変更

`LintRunner#call` 内の出力パイプラインに `reformat_output` を挿入:

```ruby
stdout, stderr, status = Open3.capture3(*command)
raw_stdout = stdout
raw_stderr = stderr

# 構造的再整形（新規）
stdout = TextlintFormatter.reformat_output(stdout)

# サマリー行除去（既存）
stdout = filter_textlint_summary(stdout)
stderr = filter_textlint_summary(stderr)

# 個別翻訳（既存 — reformat で大部分カバーされるため将来的に統合可能）
stdout = TextlintFormatter.translate_output(stdout) unless stdout.nil? || stdout.empty?
```

## 7. テスト方針

### 7.1 単体テスト（TextlintFormatter）

`test/vivlio/starter/cli/textlint_formatter_test.rb` に以下のテストケースを追加:

- **単純置換提案**: `5:4  ✓ error  サーバ => サーバー  prh` → `5  サーバ => サーバー (prh)`
- **置換＋補足説明**: 複数行 prh 出力 → インデント付き2行出力
- **助詞重複**: 冗長な中間部分が除去され1行に結合
- **文長超過**: 英語→日本語翻訳、Over 行除去
- **文体混在**: Total ブロック除去、1行結合
- **冗長表現**: `【dictN】` と URL 行の除去
- **ファイルパスヘッダー**: 絶対パス→相対パス＋アイコン
- **複数エラーの連続処理**: 実際の textlint 出力全体を入力し、期待出力と比較

### 7.2 統合テスト

既存の `lint_commands_test.rb` で、`Open3.capture3` のスタブ出力に stylish フォーマットの生データを設定し、最終出力が整形済みであることを検証。

## 8. 検証項目

- [ ] 単純な prh 置換提案が `行  A => B (prh)` 形式で出力される。
- [ ] 補足説明付きの prh 出力がインデント付き複数行で出力される。
- [ ] 助詞重複エラーが冗長部分を除去して1行に結合される。
- [ ] sentence-length の英語メッセージが日本語に翻訳される。
- [ ] 文体混在エラーの Total ブロックが除去される。
- [ ] `【dictN】` ラベルと解説 URL が除去される。
- [ ] ファイルパスが相対パス＋アイコンで表示される。
- [ ] 列番号が全エラーで除去されている。
- [ ] `✓ error` / `error` ラベルが全エラーで除去されている。
- [ ] `--fix` オプション使用時も整形が正しく動作する。
- [ ] 既存の `filter_textlint_summary` と競合しない。
- [ ] エラーなし（textlint 成功）時に余計な出力が発生しない。

## 9. 影響範囲とリスク

- textlint のバージョンアップで stylish フォーマットが変更された場合、パーサーの更新が必要になる。
- 整形処理は textlint 出力の後処理であるため、textlint 自体の動作には影響しない。
- `--format` オプションで stylish 以外のフォーマット（json 等）を指定した場合、整形処理をスキップする必要がある。

## 10. 今後の拡張余地

- 色付き出力（ANSI カラー）による視認性向上。
- エラー種別ごとのグルーピング表示（prh / spacing / 文体 等）。
- `--format compact` のような独自フォーマットオプションの追加。
- 修正可能（✓）エラーと手動修正エラーの視覚的区別。

## 11. 参考資料

- [docs/specs/lint_token_resolver_integration_spec.md](./lint_token_resolver_integration_spec.md): lint コマンド TokenResolver 対応仕様書
- [lib/vivlio/starter/cli/textlint_formatter.rb](../../lib/vivlio/starter/cli/textlint_formatter.rb): 現行の翻訳フォーマッター
- [lib/vivlio/starter/cli/lint.rb](../../lib/vivlio/starter/cli/lint.rb): lint コマンド本体
