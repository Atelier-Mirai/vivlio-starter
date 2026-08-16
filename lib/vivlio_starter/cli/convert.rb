# frozen_string_literal: true

require 'fileutils'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: convert（Markdown → HTML 変換）
    # ------------------------------------------------
    # - 目的: Markdown を VFM で HTML に変換するコマンド群
    # - 関連: 共通処理は `lib/vivlio_starter/cli/common.rb` を参照
    # ================================================================
    module ConvertCommands
      module_function

      def execute_convert(command_or_context, tokens_or_entries)
        ctx = normalized_context(command_or_context)
        enable_verbose(ctx)

        # 中間 .md / .html はワークスペースの html/ に置かれる（P4 §3.4-1）
        base_dir = Common::BUILD_HTML_DIR
        md_files = resolve_md_files_for_convert(tokens_or_entries, base_dir)

        failed = md_files.reject { convert_markdown!(it) }
        return report_conversion_failures(failed) unless failed.empty?

        Common.log_success('Markdown→HTML 変換が完了しました')
      end
      module_function :execute_convert

      # 1 章を VFM で HTML へ変換する。成功したら true。
      #
      # **終了コードを信用しない**のが要点（実測 2026-08-16）。VFM は読み込みに失敗しても
      # exit 0 を返し、Node のスタックトレースを標準出力へ吐く——変換はシェルの
      # リダイレクトで行うため、それがそのまま .html として保存される。コマンド自体が
      # 無い場合は 0 バイトの .html が残る。どちらも「中身のある章」として後続を素通りし、
      # 本文の代わりにエラーダンプや白紙が組み上がる。
      # 正常な出力は必ず `<!doctype html>` で始まるので、中身の頭まで見て成否を決める。
      def convert_markdown!(md)
        html = md.sub(/\.md\z/, '.html')
        ok = system(%(#{Common::VFM_COMMAND} "#{md}" > "#{html}"))
        return true if ok && html_document?(html)

        # 失敗の痕跡は残さない。後続に「欠落」として気づかせるほうが、
        # 壊れた HTML を本文と信じて組むより安い
        FileUtils.rm_f(html)
        false
      end
      module_function :convert_markdown!

      # VFM の出力が HTML 文書として始まっているか（先頭だけ読めば足りる）
      def html_document?(path)
        File.file?(path) && File.read(path, 16).to_s.lstrip.start_with?('<')
      end
      module_function :html_document?

      # 変換できなかった章を 🔴 で報告する。
      # 成功メッセージは出さない——1 章でも欠ければ、そのまま組んだ本は不完全だからである。
      def report_conversion_failures(failed)
        Common.log_error(
          "VFM の Markdown → HTML 変換に失敗しました（#{failed.size} 件）",
          detail: <<~DETAIL
            #{failed.map { "- #{File.basename(it)}" }.join("\n")}
            対処: `#{Common::VFM_COMMAND} #{File.basename(failed.first)}` を手で実行するとエラーの内容が読めます
            （壊れた HTML は残していません。そのまま進むと当該章が白紙で組み上がるためです）
          DETAIL
        )
      end
      module_function :report_conversion_failures

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
