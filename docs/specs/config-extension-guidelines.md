# 新コマンド・機能追加時における設定（CONFIG）拡張およびテスト実装指針

対象: `lib/` への機能追加、新コマンド実装、`book.yml` への新しい設定キー追加を行う全開発者
策定日: 2026-07-02 / 準拠仕様: `config-access-unification-spec.md`

---

## 概要

本プロジェクトでは、`config/book.yml` から読み込まれた設定はすべて再帰的な不変 Data オブジェクトである `Common::CONFIG` を通じてアクセスします。
新しいコマンドや機能（例: `vs furigana` など）を追加し、新しい設定キー（セクション）を導入する場合は、本指針に定義された**「3つのステップ（スキーマ定義・正規アクセス・消費テスト）」**を必ず遵守してください。

ハッシュ感覚での場当たり的な実装は、過去に発生した「7種類の記法混在カオス」を再発させるため厳禁とします。

---

## 1. 既定値スキーマへの登録（`lib/vivlio_starter/cli/common.rb`）

新しい設定セクション（例: `furigana`）を追加する場合、ユーザーが `book.yml` にそのセクションを**書かなかったとしても安全にドット記法でアクセスできるよう**、必ず既定値スキーマに登録します。

### 編集ファイル: `lib/vivlio_starter/cli/common.rb`

スキーマは `default_config_schema` メソッドが返す Hash として定義されています。
新セクションの構造と初期値をここに追加してください。

```ruby
# lib/vivlio_starter/cli/common.rb の default_config_schema 内（例）
def default_config_schema
  {
    # ... 既存の 16 セクション ...

    # ✅ 新設セクションの定義を追加
    furigana: {
      level: 0,            # 0: 小学生, 1: 中学生, 2: 高校生, 3: 全般
      style: "ruby",       # ruby: 通常ルビ, tatechuyu: 縦中留め
      targets: []          # 特例でルビを振る単語リスト
    }
  }
end
```

マージは `merge_hardcoded_defaults` が deep merge で行い、「ユーザーがキーだけ書いて
値を空欄にした場合（nil）」は既定値を採用、`false` は明示設定として尊重されます。

スキーマ定義のルール
第1階層（セクション名）: 必ずスネークケース（/\A[a-z_][a-zA-Z0-9_]*\z/）で定義します。

第2階層（キー名）: コード側からドット記法で参照する可能性のあるキーは、値が未定であっても nil や空配列（[]）として明示的に列挙してください。これにより、ユーザーの環境でキーが未定義の場合でも NoMethodError を防げます。

## 2. ロジック側での設定値アクセス（The One Way）
コマンドの実装ロジック内では、config-access-unification-spec.md で定められた正規記法のみを使用します。

❌ 禁止されるアンチパターン
❌ 禁止: 文字列キーによるブラケット・dig アクセス
CONFIG['furigana']['level']
CONFIG.dig('furigana', 'level')

❌ 禁止: 旧互換メソッドや冗長なガード（スキーマが保証されているため不要）
CONFIG.fetch('furigana', {})
CONFIG.furigana&.level if CONFIG.respond_to?(:furigana)
CONFIG.furigana.level || 0  # スキーマに既定値 0 があるため || フォールバックはデッドコード

✅ 推奨される正規パターン
キーが静的に決まっている場合は、ぼっち演算子（&.）なしのドット記法が原則です。
```ruby
# ✅ 正解: 静的なキーはドット記法でスマートに
if Common::CONFIG.furigana.level == 0
  apply_elementary_furigana!
end
```

✅ 正解: 動的なアクセス（キーが変数などの場合）はシンボル dig
```ruby
key_to_read = :level
Common::CONFIG.furigana.dig(key_to_read)
```

✅ 正解: パターンマッチによる安全な分解（シンボルキー）
```ruby 
case Common::CONFIG.furigana
in { level: 0..1, style: "ruby" }
  setup_school_ruby_processor
else
  setup_standard_processor
end
```

注意 (ivar メモ化の禁止):
拡張性を考慮し、@furigana_cfg = Common::CONFIG.furigana のようにインスタンス変数へ設定オブジェクトを長期保持（メモ化）しないでください。設定リロード（reload_configuration!）時に古い Data オブジェクト（stale）を参照し続ける原因になります。メソッド内のローカル変数への代入は問題ありません。

## 3. 消費テストの実装
新設した設定キーが正しく機能し、将来の統合を破壊しないよう、必ず以下の2つの観点から回帰テストを追加してください。

テストファイル: test/vivlio_starter/cli/common_config_loading_test.rb
このファイル（またはコマンド個別テスト）に、以下のパターンを網羅するテストケースを追加します。

### 3.1 最小構成（設定欠落）時のデフォルト値保証テスト
ユーザーが book.yml に新設定を一切書かなかった場合に、スキーマの既定値が適用され、ドット参照でクラッシュしないかを検証します。

**重要**: `wrap_config` 単体では既定値は適用されません。本番と同じ経路
（既定値マージ → Data ラップ）を再現するため、必ず `merge_hardcoded_defaults` を通します。

```ruby
def test_furigana_defaults_with_empty_config
  # 空の設定（または新セクションが欠落した設定）を、本番と同じ経路で読み込ませる
  stub_config = Common.wrap_config(Common.merge_hardcoded_defaults({}))

  # 欠落していても NoMethodError にならず、既定値が引けること
  assert_equal 0, stub_config.furigana.level
  assert_equal "ruby", stub_config.furigana.style
  assert_equal [], stub_config.furigana.targets
end
```

### 3.2 ユーザーオーバーライド（値の消費）テスト
ユーザーが明示的に設定を指定した場合に、正しく値が上書きされてロジックに消費されるかを検証します。
```ruby
def test_furigana_custom_config_override
  # ユーザー入力を模したハッシュ
  user_input = {
    furigana: {
      level: 2,
      style: "tatechuyu"
    }
  }

  # 既定値マージ → wrap_config で擬似設定 Data オブジェクトを生成
  config = Common.wrap_config(Common.merge_hardcoded_defaults(user_input))

  # 値がユーザー指定のものに上書きされていること
  assert_equal 2, config.furigana.level
  assert_equal "tatechuyu", config.furigana.style

  # スキーマに定義されているがユーザーが書かなかったキーは、既定値が維持されていること
  # （deep merge により部分指定でも兄弟キーが消えない）
  assert_equal [], config.furigana.targets
end
```

テスト時における偽装（Mock/Stub）の注意点:
テスト内で設定を偽装する場合は、生の Hash を直接ロジックに渡してはいけません。必ず Common.wrap_config(hash) を経由させて、本番環境と同じ Data オブジェクトの挙動（StringキーのSymbol正規化、メンバー限定アクセス等）を再現した状態のオブジェクトを流し込んでください。

### 3.3 消費保証テスト（自動検査）

`test/vivlio_starter/cli/book_yml_consumption_test.rb` が、**scaffold の book.yml に
定義された全キーが lib コードから参照されていること**を自動検査します。
新しい設定キーを scaffold の book.yml（＝ルートの `config/book.yml` を編集して
`ruby copy_to_scaffold.rb` で同期）に追加したのに実装が消費していない場合、
このテストが失敗します。「book.yml にキーを書いたが実装はハードコーディングのまま」
という消費漏れはここで検出されるため、キー追加とロジック実装は必ずセットで行ってください。
（`metrics.use` の値として動的参照されるプリセット名のような例外は、
テスト内の `ALLOWED_UNREFERENCED` に理由つきで登録します）
