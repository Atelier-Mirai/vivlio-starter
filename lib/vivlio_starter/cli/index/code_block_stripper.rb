# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/index/code_block_stripper.rb
# ================================================================
# 責務:
#   Markdown からコード（フェンス／インライン）を取り除く。
#   索引・用語の候補抽出で、コード例やログ出力の断片（バーグラフ
#   `[###]`、配列リテラル `[00, 90-98, 99]` など）が索引語として
#   誤検出されるのを防ぐ。
#
# 実装は CLI::Masking へ一元化済み（P1）。本モジュールは索引ドメインからの
# 呼び名を保つ薄い委譲層で、意味論（可変長・入れ子・~~~・include: 除外）は
# Masking.strip_code が唯一の原器として保証する。
# ================================================================

require_relative '../masking'

module VivlioStarter
  module CLI
    module IndexCommands
      module CodeBlockStripper
        module_function

        # フェンス・インラインコードを取り除いたテキストを返す。
        # 行数は保つ（コード行は空行に置換）ため、周辺文脈の行対応は崩れない。
        def strip(content) = Masking.strip_code(content)
      end
    end
  end
end
