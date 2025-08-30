# frozen_string_literal: true
require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: VivliostyleCommands
      # ------------------------------------------------------------------------------
      # book.yml の設定から vivliostyle.config.js を生成するコマンド群。
      # タイトル/著者/言語/読み進め方向/エントリー/出力PDFなどを反映し、
      # 既存ファイルがある場合はバックアップも自動で作成する。
      #
      # 備考:
      #   - -v/--verbose 指定時、ENV['VERBOSE'] = '1' をセットして詳細ログを出力。
      #   - 生成先ファイル名は設定（vivliostyle.config_file）またはデフォルトを使用。
      # ==============================================================================
      module VivliostyleCommands
        extend self
        def included(base)
          base.class_eval do
            # ルーターが受け付ける公開名（vivliostyle:config）と Thor メソッド名（vivliostyle_config）を対応付け
            map 'vivliostyle:config' => :vivliostyle_config
            desc 'vivliostyle:config', 'config/book.yml の設定から vivliostyle.config.js を生成します'
            long_desc <<~DESC
              book.yml の設定から vivliostyle.config.js を生成します。

              生成内容:
              - タイトル、著者、言語設定
              - 読み進め方向（ltr/rtl）
              - エントリーファイル（entries.js）
              - 出力PDFファイル名

              既存ファイルは自動バックアップされます。
            DESC

            # ================================================================
            # Command: vivliostyle:config（設定ファイル生成）
            # ------------------------------------------------
            # 概要:
            #   book.yml の設定をもとに vivliostyle.config.js を生成する。
            #   既存ファイルは timestamp 付きで自動バックアップ。
            # オプション:
            #   -v, --verbose  詳細ログ（ENV['VERBOSE']='1'）
            # ================================================================
            def vivliostyle_config
              ENV['VERBOSE'] = '1' if options[:verbose]

              Common.log_action("vivliostyle.config.jsを生成しています...")

              # 設定を取得
              config             = Common::CONFIG
              book_config        = config['book'] || {}
              vivliostyle_config = config['vivliostyle'] || {}
              pdf_config         = config['pdf'] || {}

              # JS 文字列に安全に埋め込むための簡易エスケープ
              esc = ->(s) { s.to_s.gsub('\\', '\\\\').gsub("'", "\\'") }

              # 設定値を取得（デフォルト値付き）
              # title が未設定の場合は main_title と subtitle を結合して使う
              combined_title = [book_config['main_title'], book_config['subtitle']].compact.join(' ').strip
              title_raw = book_config['title']
              title = (title_raw && !title_raw.to_s.strip.empty?) ? title_raw : (combined_title.empty? ? '書籍タイトル' : combined_title)
              author              = book_config['author'] || '著者名'
              language            = book_config['language'] || 'ja'
              reading_progression = vivliostyle_config['reading_progression'] || 'ltr'
              entries_file        = vivliostyle_config['entries_file'] || 'entries.js'
              output_file         = pdf_config['output_file'] || 'output.pdf'
              config_file         = vivliostyle_config['config_file'] || 'vivliostyle.config.js'

              # バックアップ処理（最新のみ保持）
              if File.exist?(config_file)
                Dir.glob("#{config_file}.backup_*").each { |f| FileUtils.rm_f(f) }
                timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
                backup_file = "#{config_file}.backup_#{timestamp}"
                FileUtils.cp(config_file, backup_file)
                Common.log_info("既存ファイルをバックアップしました: #{backup_file}")
              end

              # vivliostyle.config.jsの内容を生成
              config_content = <<~JS
                import entries from './#{esc.call(entries_file)}';

                // @ts-check
                /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
                const vivliostyleConfig = {
                  title: '#{esc.call(title)}', // 書籍のタイトル
                  author: '#{esc.call(author)}', // 著者名
                  language: '#{esc.call(language)}', // 言語設定
                  readingProgression: '#{esc.call(reading_progression)}', // 読み進め方向（ltr: 横書き, rtl: 縦書き）
                  entry: entries, // 章立て構成（#{entries_file}から読み込み）
                  output: [ // 出力ファイル設定
                    './#{esc.call(output_file)}' // PDFファイル
                  ]
                };

                export default vivliostyleConfig;
              JS

              # ファイルに書き込み
              File.write(config_file, config_content)

              Common.log_success("#{config_file} を生成しました")
              Common.log_info("タイトル: #{title}")
              Common.log_info("著者: #{author}")
              Common.log_info("言語: #{language}")
              Common.log_info("読み進め方向: #{reading_progression}")
              Common.log_info("出力ファイル: #{output_file}")
            end
          end
        end
      end
    end
  end
end
