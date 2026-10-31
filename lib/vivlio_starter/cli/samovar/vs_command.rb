# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/vs_command.rb
# ================================================================
# 責務:
#   公開コマンドの基底クラス。引数トークンの正規化（`--opt=value` の展開と
#   オプション位置の自由化）を全公開コマンドへ配る。
#
# なぜ options を置かないか:
#   Samovar の `Table#merged` は親の行を先に並べるため、基底クラスで
#   `options do ... end` を宣言すると、子がどう宣言していても行順が
#   「Options → 位置引数」に固定される。すると各コマンドの宣言順が意味を失い、
#   usage 表示も一律に変わってしまう。本プロジェクトは宣言順を維持する方針の
#   ため、基底クラスは prepend だけを配る（cli-argument-parsing-spec.md D1・D2）。
#   共通オプション（`--log` 等）をここへ足したくなったときは、この副作用を
#   踏まえて判断すること。
#
# 適用範囲:
#   公開コマンドのみ。内部コマンド（create:titlepage /
#   create:colophon / create:legalpage）は位置引数を持たず並べ替えの余地が
#   ないため、`Samovar::Command` を直接継承したままとする。
# ================================================================

require_relative 'option_token_normalizer'

module VivlioStarter
  module CLI
    module SamovarCommands
      # 公開コマンドの基底クラス
      class VsCommand < Samovar::Command
        prepend OptionTokenNormalizer

        private

        # CLI 引数から、catalog.yml に載っている章の Entry を解決する（vs build・vs preflight）
        # @return [Array<TokenResolver::Entry>]
        def resolve_target_entries = TokenResolver::Resolver.new.resolve(targets).select(&:in_catalog?)

        # CLI の --verify-links をスレッドローカルに設定する（vs build・vs preflight）。
        # LinkImageValidator が resolve_config で参照する
        #
        # **明示された指定だけを載せる。** resolve_config は
        # `cli_opts.fetch(:verify_external_links, 設定側の既定)` の形で book.yml をフォールバックに
        # 置くため、キーを常に立てると既定値が一度も発火せず verify.external_links が
        # 丸ごと無視される（2026-08-07 修正）。
        def setup_verify_options!
          opts = {}
          opts[:verify_external_links] = true if options[:verify_links]
          Thread.current[:vs_verify_options] = opts
        end
      end
    end
  end
end
