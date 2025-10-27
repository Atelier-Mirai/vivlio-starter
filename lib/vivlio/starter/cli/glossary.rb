# frozen_string_literal: true

require_relative 'glossary/shared_helpers'
require_relative 'glossary/add_commands'
require_relative 'glossary/canonicalize_commands'
require_relative 'glossary/lint_commands'
require_relative 'glossary/fix_commands'

module Vivlio
  module Starter
    module CLI
      # Glossary 関連コマンドを用途別モジュールとして読み込むラッパー
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
