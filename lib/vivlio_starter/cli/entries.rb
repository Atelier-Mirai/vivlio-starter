# frozen_string_literal: true

require_relative 'common'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: entries.js 生成ロジック
    # ================================================================
    # 提供機能:
    #   - HTML から entries.js（ESM）を生成
    # ================================================================
    module EntriesCommands
      module_function

      ENTRIES_DESC = {
        short: 'entries.jsを生成します',
        long: <<~DESC
          指定した HTML ファイルから entries.js を生成します。指定が無い場合はカレントディレクトリの全 .html を対象にします。

          処理内容:
          - HTMLファイルからタイトルを取得（titleタグ優先）
          - entries.js をES Module形式で生成
          - 各エントリにパスとタイトル情報を含む

          例:
            vs entries 11-install.html
            vs entries 11-install 12-tutorial
        DESC
      }.freeze

      def included(base); end

      def execute_entries(command_or_context, tokens_or_entries)
        ctx = normalized_context(command_or_context)
        enable_verbose(ctx)

        Common.log_action('entries.jsを生成しています...')

        base_dir = '.'
        html_files = resolve_html_files_for_entries(base_dir, tokens_or_entries)
        Common.log_info("目次作成対象ファイル: #{html_files.join(', ')}")

        entries = html_files.map { |html_file| build_entry(html_file) }

        write_entries(base_dir, entries)

        Common.log_success("entries.js生成完了: #{entries.length}件のエントリを登録")
      end
      module_function :execute_entries

      # Entry 配列または basename 配列から HTML ファイルパス配列を解決する
      # @param base_dir [String] ベースディレクトリ（プロジェクトルート）
      # @param entries_or_basenames [Array<TokenResolver::Entry>, Array<String>]
      # @return [Array<String>] HTML ファイルパスの配列
      def resolve_html_files_for_entries(base_dir, entries_or_basenames)
        raw = Array(entries_or_basenames).compact
        return Dir.glob(File.join(base_dir, '*.html')) if raw.empty?

        # Entry オブジェクトかどうかを判定
        if raw.first.respond_to?(:basename)
          raw.map { |entry| File.join(base_dir, "#{entry.basename}.html") }.uniq
        else
          # basename 配列: パスに変換
          raw.flat_map { |bn| resolve_token(base_dir, bn.to_s) }.uniq
        end
      end
      module_function :resolve_html_files_for_entries

      def resolve_token(base_dir, token)
        if File.extname(token) == '.html'
          path = File.dirname(token) == '.' ? File.join(base_dir, token) : token
          File.exist?(path) ? [path] : []
        else
          pattern1 = File.join(base_dir, "#{token}.html")
          pattern2 = File.join(base_dir, "#{token}-*.html")
          Dir.glob([pattern1, pattern2])
        end
      end
      module_function :resolve_token

      def build_entry(html_file)
        base_name = File.basename(html_file, '.html')
        title = base_name
        html_title = extract_html_title(html_file)

        if html_title && !html_title.empty?
          title = html_title
        elsif html_title.to_s.empty? && (base_name =~ /^\d+-(.+)$/)
          title = ::Regexp.last_match(1)
        end

        # パスを相対パス形式に正規化（./を接頭辞として付与）
        normalized_path = html_file.start_with?('./') ? html_file : "./#{html_file}"
        { path: normalized_path, title: title }
      end
      module_function :build_entry

      def extract_html_title(path)
        return unless File.exist?(path)

        content = File.read(path)
        ::Regexp.last_match(1).strip if content =~ %r{<title>(.+?)</title>}
      rescue StandardError => e
        # タイトル抽出失敗時はフォールバック名が使われるため、原因をデバッグログに残す
        Common.log_debug("[entries] #{path} のタイトル抽出に失敗: #{e.class}: #{e.message}")
        nil
      end
      module_function :extract_html_title

      def write_entries(base_dir, entries)
        File.open(File.join(base_dir, 'entries.js'), 'w') do |f|
          f.puts 'export default ['
          entries.each_with_index do |entry, i|
            f.puts '  {'
            f.puts %(    "path": "#{entry[:path]}",)
            f.puts %(    "title": "#{entry[:title]}")
            f.puts "  }#{',' if i < entries.length - 1}"
          end
          f.puts ']'
        end
      end
      module_function :write_entries

      def normalized_context(command_or_ctx)
        return command_or_ctx if command_or_ctx.is_a?(Hash)

        { options: options_of(command_or_ctx) }
      end
      module_function :normalized_context

      def enable_verbose(context)
        ENV['VERBOSE'] = '1' if options_of(context)[:verbose]
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
    end
  end
end
