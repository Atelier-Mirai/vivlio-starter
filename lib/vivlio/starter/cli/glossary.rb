# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/glossary.rb
# ================================================================
# 責務:
#   glossary 系コマンドのエントリポイント。
#   用途別モジュールを読み込み、統合して提供する。
#
# 提供コマンド:
#   - glossary:add: 新規用語の追加
#   - glossary:lint: 表記揺れの検出
#   - glossary:fix: 表記揺れの自動修正
#   - glossary:canonicalize: YAML の正準化
#
# 依存モジュール:
#   - GlossarySharedHelpers: 共通ヘルパー
#   - GlossaryAddCommands: 追加コマンド
#   - GlossaryLintCommands: 検出コマンド
#   - GlossaryFixCommands: 修正コマンド
#   - GlossaryCanonicalizeCommands: 正準化コマンド
# ================================================================

require_relative 'glossary/shared_helpers'
require_relative 'glossary/add_commands'
require_relative 'glossary/canonicalize_commands'
require_relative 'glossary/lint_commands'
require_relative 'glossary/fix_commands'

module Vivlio
  module Starter
    module CLI
      # glossary コマンド統合モジュール
      module GlossaryCommands
        def self.included(base)
          base.include GlossarySharedHelpers
          base.include GlossaryAddCommands
          base.include GlossaryCanonicalizeCommands
          base.include GlossaryLintCommands
          base.include GlossaryFixCommands
        end
      end
    end
  end
end
