# frozen_string_literal: true

# Samovar ベース CLI への移行に伴い、このファイルは互換レイヤーのみを提供します。
# 既存コードで `require 'vivlio/starter/cli'` が使われていても、
# 実際の CLI 実装は `lib/vivlio/starter/cli/samovar` 側に存在します。

require_relative 'cli/common'
require_relative 'cli/create'
require_relative 'cli/delete'
require_relative 'cli/doctor'
require_relative 'cli/entries'
require_relative 'cli/glossary'
require_relative 'cli/help'
require_relative 'cli/new'
require_relative 'cli/pdf'
require_relative 'cli/post_process'
require_relative 'cli/pre_process'
require_relative 'cli/rename'
require_relative 'cli/renumber'
require_relative 'cli/text_lint'
require_relative 'cli/text_metrics'

require_relative 'cli/samovar'

module Vivlio
  module Starter
    module CLI
      # Thor 実装は削除済み。ここでは Samovar コマンド群を読み込むだけ。
    end
  end
end
