# Specification: PDF Plugin Integration and Mode Switching

## 1. 背景と目的 (Background & Objective)

`vs build` コマンド実行時、拡張プラグインである `vivlio-starter-pdf` がインストールされている場合、PDF生成モードが自動的に `standard` から `enhanced` へ切り替わり、HexaPDF を用いたアウトライン（目次構造）付与等の高度な機能が有効化される仕様である。

しかし、本体側で行われた名前空間のリファクタリング（`lib/vivlio/starter/...` から `lib/vivlio_starter/...` への変更）に伴い、プラグイン側の配置や参照パスとの乖離が発生し、プラグインが常時検出されない（常に `standard` モードのままになる）不具合が発生している。

本仕様では、以下の4点を実施し、プラグインによる `enhanced` モードの自動切り替えとアウトライン機能の正常化を保証する。
1. プラグイン側の名前空間およびファイル配置を `lib/vivlio_starter/` へリファクタリング（旧互換コードは完全排除）
2. プラグイン側 Minitest コードの追従リファクタリング
3. 本体側でのプラグイン自動検出・モード切り替えロジックの改良（Ruby 4.0+ 構文・パターンマッチング活用）
4. モード切り替えを厳密に検証する統合テストスイートの拡充

---

## 2. プラグイン側のリファクタリング (Plugin Refactoring)

### 2.1. ディレクトリ構造の変更
後方互換性は一切考慮せず、古い `liv/vivlio/starter` ディレクトリ構造は破壊的に置き換える。

```text
# 変更前 (Before)
vivlio-starter-pdf/
└── lib/
        └── vivlio/
            └── starter/
                ├── pdf.rb
                └── pdf/
```

# 変更後 (After)
```text
vivlio-starter-pdf/
└── lib/
        └── vivlio_starter/
            ├── pdf.rb
            └── pdf/
```

### 2.2. コードレベルの名前空間修正
定数定義およびローダーのパスを、新しい名前空間へ一斉置換する。

```ruby
# frozen_string_literal: true

# リファクタリングの例
module VivlioStarter
  module Pdf
    VERSION = "1.1.0" # リファクタリングに伴うアップデート

    # 拡張モードで利用する HexaPDF 機能のフック
    def self.enhance_pdf(pdf_path, options = {})
      # --- Phase: Load HexaPDF Outline Processor ---
      # アウトライン付与ロジックの実装（省略）
    end
  end
end
```

### 3. プラグイン側テストコードのリファクタリング (Plugin Test Refactoring)
Minitest によるテストコードを新しい定数・パス構造に追従させる。
並列実行（Ractor等）を妨げないよう、グローバルなスタブは避け、DIまたは局所的なオブジェクト検証を行う。

### 4. 本体側の改良: プラグイン自動検出とモード切り替え (Core Implementation)
#### 4.1. 検出ロジックの実装方針
本体の vivlio_starter/cli またはビルドマネージャー側で、プラグインのロード可能性を安全に検証する。
begin ... rescue LoadError の結果をシンボルまたはパターンマッチングで評価し、条件分岐を平坦化する。


### 5. モード切り替え検証テスト（統合テストスイート） (Integration Test Suite)
本体側のテストスイート（Minitest）に、プラグインの有無によって挙動（モード）が動的に切り替わることを保証するテストケースを追加する。

### 6. 品質チェックリスト (Quality Checklist)
開発完了時に、本仕様を満たしているか以下の項目を確認すること。

[ ] vivlio/starter の古いディレクトリ・ファイルが完全に削除されているか（後方互換コードの完全排除）

[ ] 全ての新規・修正ファイル先頭に # frozen_string_literal: true が付与されているか

[ ] プラグイン検出の条件分岐にレガシーな if/else チェーンではなく、パターンマッチングやシンボルによる平坦化が使われているか

[ ] テストコードは DAMP（各ケース内で独立・完結）を維持し、並列実行を阻害するグローバルスタブを排除しているか
