# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: convert（Markdown → HTML 変換）
      # ------------------------------------------------
      # - 目的: Markdown を VFM で HTML に変換するコマンド群
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb` を参照
      # ================================================================
      module ConvertCommands
        module_function

        def execute_convert(command_or_context, tokens_or_entries)
          ctx = normalized_context(command_or_context)
          enable_verbose(ctx)

          base_dir = '.'
          md_files = resolve_md_files_for_convert(tokens_or_entries, base_dir)

          md_files.each do |md|
            html = md.sub(/\.md\z/, '.html')
            cmd  = %(#{Common::VFM_COMMAND} "#{md}" > "#{html}")
            ok = system(cmd)
            Common.log_warn("VFM の変換に失敗しました: #{md}") unless ok
          end

          Common.log_success('Markdown→HTML 変換が完了しました')
        end
        module_function :execute_convert

        def normalized_context(command_or_ctx)
          return command_or_ctx if command_or_ctx.is_a?(Hash)

          { options: options_of(command_or_ctx) }
        end
        module_function :normalized_context

        def enable_verbose(command_or_ctx)
          ENV['VERBOSE'] = '1' if options_of(command_or_ctx)[:verbose]
        end
        module_function :enable_verbose

        def options_of(command_or_ctx)
          if command_or_ctx.is_a?(Hash)
            command_or_ctx[:options] || {}
          elsif command_or_ctx.respond_to?(:options)
            command_or_ctx.options || {}
          else
            {}
          end
        end
        module_function :options_of

        # Entry 配列または basename 配列から Markdown ファイルパス配列を解決する
        # @param entries_or_basenames [Array<TokenResolver::Entry>, Array<String>]
        # @param base_dir [String] ベースディレクトリ（プロジェクトルート）
        # @return [Array<String>] Markdown ファイルパスの配列
        def resolve_md_files_for_convert(entries_or_basenames, base_dir)
          raw = Array(entries_or_basenames).compact

          if raw.empty?
            return Dir.glob(File.join(base_dir, '*.md')).reject { |f| File.basename(f) =~ /\A(README|ROADMAP)\.md\z/ }
          end

          # Entry オブジェクトかどうかを判定
          if raw.first.respond_to?(:basename)
            raw.map { |entry| File.join(base_dir, "#{entry.basename}.md") }.uniq
          else
            # basename 配列: パスに変換
            raw.map do |bn|
              name = bn.to_s.sub(/\.md\z/, '')
              File.join(base_dir, "#{name}.md")
            end.uniq
          end
        end
        module_function :resolve_md_files_for_convert
      end
    end
  end
end
