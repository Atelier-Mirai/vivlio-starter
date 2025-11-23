# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: entries（entries.js 生成）
      # ------------------------------------------------
      # - 目的: HTML から entries.js（ESM）を生成
      # - 提供コマンド: entries
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
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

        def included(base)
          base.class_eval do
            desc 'entries [TOKENS...]', ENTRIES_DESC[:short]
            long_desc ENTRIES_DESC[:long]
            # ================================================================
            # Command: entries（entries.js 生成）
            # ------------------------------------------------
            # - 概要: 指定 HTML から entries.js（ESM）を作成
            # - 入力: *.html（引数未指定時はカレント直下の *.html）
            # - 出力: entries.js
            # - オプション: --verbose (-v)
            # ================================================================
            def entries(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]

              files = Common.normalize_tokens(tokens)

              # デバッグ用にオプションを表示
              Common.log_action('entries.jsを生成しています...')

              # ベースディレクトリ（mybook 設定が有効なら mybook/ 配下）
              base_dir = '.'

              # 処理対象のHTMLファイル一覧を取得
              html_files = if files.any?
                             # 引数で指定されたファイル群のみを対象
                             files.flat_map do |f|
                               # 拡張子が.htmlで終わる場合はそのまま使用
                               if File.extname(f) == '.html'
                                 name = File.dirname(f) == '.' ? File.join(base_dir, f) : f
                                 File.exist?(name) ? [name] : []
                               else
                                 # トークン（例: 46）に対してマッチする HTMLファイルを検索
                                 # パターン: #{token}.html または #{token}-*.html
                                 pattern1 = File.join(base_dir, "#{f}.html")
                                 pattern2 = File.join(base_dir, "#{f}-*.html")
                                 candidates = Dir.glob([pattern1, pattern2])
                                 candidates.empty? ? [] : candidates
                               end
                             end
                           else
                             # カレントディレクトリの .html 全てを対象
                             Dir.glob(File.join(base_dir, '*.html'))
                           end

              # 処理対象ファイルを表示
              Common.log_info("目次作成対象ファイル: #{html_files.join(', ')}")

              # entries.jsの生成
              entries = html_files.map do |html_file|
                base_name = File.basename(html_file, '.html')
                title = base_name

                # HTMLファイルからタイトルを取得（優先）
                html_title = nil
                if File.exist?(html_file)
                  content = File.read(html_file)
                  if content =~ %r{<title>(.+?)</title>}
                    html_title = ::Regexp.last_match(1).strip
                    title = html_title unless html_title.empty?
                  end
                end

                # HTMLからタイトルが取得できなかった場合のフォールバック処理
                if (html_title.nil? || html_title.empty?) && (base_name =~ /^\d+-(.+)$/)
                  # ファイル名からタイトルを生成
                  title = ::Regexp.last_match(1)
                end

                # エントリーを生成
                { path: html_file, title: title }
              end

              # entries.jsをES Module形式で書き込み
              File.open(File.join(base_dir, 'entries.js'), 'w') do |f|
                f.puts 'export default ['
                entries.each_with_index do |entry, i|
                  f.puts '  {'
                  f.puts "    \"path\": \"#{entry[:path]}\","
                  f.puts "    \"title\": \"#{entry[:title]}\""
                  f.puts "  }#{',' if i < entries.length - 1}"
                end
                f.puts ']'
              end

              Common.log_success("entries.js生成完了: #{entries.length}件のエントリを登録")
            end
          end
        end
      end
    end
  end
end
