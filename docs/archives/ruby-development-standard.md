---
inclusion: fileMatch
fileMatchPattern: "**/*.rb"
---

# Ruby 4.0+ Modern Development Standard

## 非交渉事項（最優先）

1. **スコープ外は変更しない** — 明示されたファイル・メソッド以外を「ついで」に編集しない。
2. **バグ修正とリファクタを混ぜない** — 同一パッチに入れない。明示指示がある場合のみ許容。
3. **破壊的変更は明示指示がなければ禁止** — シグネチャ変更・ファイル移動・テスト期待値の変更等。
4. **推測で進めない** — 曖昧なら実装前に確認する。
5. **コメントは今回触ったメソッドのみ** — 未変更メソッドへのコメント追加は禁止。
6. **過剰抽象化をしない** — 中継メソッド乱立・無関係レイヤ追加を避ける。コール深度は最大3段。

---

## 1. 基本方針

- Ruby 4.0.0 以上専用。旧バージョン互換は考慮しない。レガシー構文は破壊的に置き換える。
- **後方互換性の完全排除**: 過去の実装との互換分岐やレガシーコードパスは残さない。必要なら Git で戻れば良い。
- **人間中心の可読性**: RuboCop の機械的制限より「一連の処理が物語として読める」かを優先する。
- **Living Documentation**: 「なぜこの実装か」がコード上で理解できること。

```ruby
# ❌ 互換分岐を残す
def process(data, legacy: false)
  legacy ? old_implementation(data) : new_implementation(data)
end

# ✅ 最新実装のみ
def process(data)
  new_implementation(data)
end
```

---

## 2. Ruby 4.0+ 必須イディオム

```ruby
# it パラメータ（単一ブロック引数）
users.map { it.name.upcase }

# パターンマッチング（if/case チェーンの代替）
case result
in { status: :ok, data: }    then process(data)
in { status: :error, message: } then log_error(message)
end

# Data.define（Struct は使わない）
User = Data.define(:name, :email)

# エンドレスメソッド（単行ロジック）
def full_name = "#{first_name} #{last_name}"

# ハッシュ省略記法
{ name:, email:, age: }
```

---

## 3. コーディング標準

- **行数より凝集度**: 300〜500行のメソッドでもフェーズ区切りコメントで構造化し、無理な分割で引数地獄を作らない。「1メソッド1責任」は厳守。
- **変数のバケツリレー禁止**: 引数が過剰になるくらいならメソッド内にローカル変数で閉じ込める。
- **副作用の局所化**: 状態変化が追跡可能であること。グローバル状態への依存を最小化。

**フェーズ区切りコメント（20行以上のメソッドに使用）**:
```ruby
def complex_process(data)
  # --- Phase: Validation ---
  validate_input(data)

  # --- Phase: Transformation ---
  transformed = data.map { transform(it) }

  # --- Phase: Aggregation ---
  aggregate_results(transformed)
end
```

**過度な抽象化の禁止**:
- 1回しか使わないメソッドを「将来の再利用のため」に作らない。
- 各層で1〜2行しか処理しない「中継メソッド」は不要。
- **Inline First**: 重複が3箇所以上出たら初めて抽出を検討する。

```ruby
# ✅ 良い例：フェーズが明確で追跡しやすい
def process_users(users)
  validated  = users.select { it.active? && it.email.present? }
  transformed = validated.map { normalize_user(it) }
  transformed.sort_by(&:created_at)
end

# ❌ 悪い例：中継するだけのメソッド群
def process_users(users) = filter_users(users)
def filter_users(users)  = apply_active_filter(users)
def apply_active_filter(users) = users.select { check_if_active(it) }
def check_if_active(user) = user.active?
```

---

## 4. CLI 実装（Samovar 標準）

- `Samovar::Command` を継承。`print_usage` でヘルプ統一。
- Public コマンドは `vs --help` に表示。Internal は非表示（`docs/DEVELOPER_GUIDE.md` 参照）。
- オプションは純粋な `Hash` として下層ロジックへ渡す。Thor 互換オブジェクト禁止。
- `Samovar::InvalidInputError` をキャッチして適切なヘルプを案内。

```ruby
class PublicCommand < Samovar::Command
  self.description = "User-facing command"

  def call
    BusinessLogic.new.execute(options.to_h)
  rescue Samovar::InvalidInputError => e
    print_usage
    abort "Error: #{e.message}"
  end
end
```

---

## 5. テスト（Minitest 標準）

- **DAMP > DRY**: 各テストで Arrange/Act/Assert が完結すること。
- **統合テスト重視**: 公開 API の入出力を中心に検証。内部実装の細かなステップは検証しない。
- **DI で外部依存を差し替え**: グローバル状態を書き換える Stub は避ける（Ractor 並列実行を妨げるため）。
- テストメソッド名は `test_should_...` 形式で期待される振る舞いを記述。

```ruby
def test_should_transform_and_aggregate_user_data
  input  = [{ name: "Alice", age: 30 }, { name: "Bob", age: 25 }]
  result = Processor.new.call(input)

  assert_pattern do
    result => { users: [{ name: "ALICE" }, { name: "BOB" }], count: 2 }
  end
end
```

複雑な変換プロセスを検証する場合、無理に分割して文脈を切るより、一つのメソッド内で一連のアサーションを並べる方が読みやすければそれを許容する。

---

## 6. リファクタリング戦略

**適用するのはこういうとき**:
- レガシーな `if/case` や冗長なブロック変数を最新構文へ書き換えるとき。
- 一気通貫で実行すべき処理が不必要に分割されているとき。

**「リファクタリング」の範囲**:
- 含まれる: Ruby 4.0+ イディオムへの変換、フェーズ区切りコメントの追加、不要な中継メソッドのインライン化。
- 含まれない: ロジック変更、アーキテクチャ変更、テスト追加・変更、依存ライブラリ変更、バグ修正と同時のリファクタ。

```ruby
# Before
users.each do |user|
  puts user.name.upcase
end

# After
users.each { puts it.name.upcase }
```

RuboCop の警告は「現代的な基準」で解釈し、本質的な Lint（バグの芽）の除去に集中する。プロジェクトに合わない古い規約は `# rubocop:disable` や設定変更で柔軟に対応。

---

## 7. ドキュメント

- **今回触ったメソッドのみ**コメントを追加・更新する。未変更メソッドへの一括コメント付与は禁止。
- **Why-First**: 「何をしているか」は命名で補い、「なぜこの実装か」をコメントで説明する。
- **YARD**: 複雑な引数・戻り値にのみ `@param`/`@return` を使用。自明な場合は省略。
- `CHANGELOG.md` を常に更新する。
- 実装前に `docs/specs/*.md` を整備する（仕様ドリブン）。

```ruby
# ユーザー入力を正規化する。
# 空白除去とケース統一を行う。nil の場合は空文字列を返す。
# @param input [String, nil]
# @return [String]
def normalize_input(input)
  input.to_s.strip.downcase
end
```

---

## 8. AI 協働プロトコル

### スコープ境界

変更してよいのは以下のみ:
- ユーザーが `#` で添付したファイル
- メッセージにパス・ファイル名が明示されているもの
- 「このファイルだけ」「このメソッドだけ」と範囲が明示されたもの

変更ファイルが複数に及ぶ場合は、**実装前に変更予定ファイルの一覧を提示**してから着手する。

### 実装前に確認が必要な状況

| 状況 | 確認内容 |
|------|----------|
| 指示されていないファイルに変更が生じる | 「X も変更が必要に見えますが、変更してよいですか？」 |
| 既存のメソッドシグネチャを変更する | 「呼び出し元への影響がありますが、変更範囲はここだけでよいですか？」 |
| 新しい gem の追加が必要 | 「Y を使うと実装しやすいですが、追加してよいですか？」 |
| リファクタ対象が指示範囲を超える | 「Z も同じパターンで直せますが、今回のスコープに含めますか？」 |
| 既存テストの削除・大幅書き換えが必要 | 「既存テストの構造変更を伴いますが、意図していますか？」 |

### 明示指示なしに絶対に行わないこと

- 公開メソッドのシグネチャ変更（引数の追加・削除・順序変更）
- 定数・クラス名・モジュール名の変更
- ファイルの移動・削除・分割
- 既存テストの削除または期待値の変更
- `Gemfile` / `.gemspec` への gem 追加・バージョン変更
- `.rubocop.yml` 等の設定ファイルの変更
- `CHANGELOG.md` 以外の既存ドキュメントの書き換え

ユーザーが具体的に大規模変更を指示した場合はその指示が優先。曖昧な「改善して」「きれいにして」だけでは解釈を広げず、確認する。

### 不明点の優先順位

1. このドキュメントの規約に従う
2. 既存コードのスタイルに倣う
3. 上記で判断できない場合のみ → 実装せずに質問する

### 出力フォーマット

```
## 変更内容
- <ファイル>: <変更内容と理由>

## スコープ外の気づき（変更なし）
- <ファイル/メソッド>: <気づき> — 次のタスクとして扱いますか？

## 確認事項
- <判断を委ねたい点があれば質問形式で>
```

---

## 9. 品質チェックリスト（PR前・リリース前に参照）

日常の小さなパッチでは §8 と §3 を優先する。

**構文・イディオム**
- [ ] `it` パラメータが適切に使われているか
- [ ] パターンマッチングで条件分岐が平坦化されているか
- [ ] `Data.define` が使われ、Struct が排除されているか
- [ ] エンドレスメソッドが単行ロジックに使われているか
- [ ] 最新のハッシュ省略記法が使われているか

**アーキテクチャ**
- [ ] Samovar Public/Internal の分離が守られているか
- [ ] 副作用が局所化され、追跡可能か
- [ ] Ruby 4.0 の最適化を妨げる古いイディオムがないか

**テスト**
- [ ] テストが DAMP で、DI により並列実行に耐えるか
- [ ] 統合テストで振る舞い全体が保証されているか
- [ ] パターンマッチングによる構造検証が行われているか
- [ ] エラーメッセージが修正のヒントとして親切か

**ドキュメント**
- [ ] 新規・変更メソッドに Why コメントが付いているか
- [ ] YARD が複雑な箇所に適切に配置されているか
- [ ] `docs/specs/*.md` が整備されているか
- [ ] `CHANGELOG.md` が更新されているか

**AI 協働**
- [ ] 指示されたスコープ外のファイル・メソッドに変更が及んでいないか
- [ ] 公開メソッドのシグネチャが変更されていないか
- [ ] スコープ外の気づきは変更せず報告にとどめているか
- [ ] 不明点を推測で実装せず、確認を求めているか
