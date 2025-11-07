# frozen_string_literal: true

require 'fileutils'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: CleanCommands
      # ------------------------------------------------------------------------------
      # ビルド生成物や中間ファイルを安全にクリーンアップするコマンド群。
      # .vivliostyle ディレクトリ、生成された *.html や 03-toc.md、entries.js、
      # 一時/中間PDF を削除し、最終成果物（output.pdf, output_compressed.pdf）は保持する。
      #
      # 主な削除対象:
      #   - ディレクトリ: .vivliostyle
      #   - 生成ファイル: *.html, 03-toc.md, entries.js
      #   - 中間PDF: titlepage/frontmatter/chapters_appendices 等の作業用PDF
      # 主な保持対象:
      #   - 最終PDF: output.pdf, output_compressed.pdf（configにより名称可変）
      #   - 既知のMarkdown: README.md, ROADMAP.md, CONTENT-LICENSE.md,
      #                      THIRD-PARTY-LICENSES.md, CHANGELOG.md
      # 備考:
      #   - 保持対象 PDF 名は config の pdf.output_file / pdf.output_file_compressed を優先
      # ==============================================================================
      module CleanCommands
        module_function

        CLEAN_DESC = {
          short: '不要ファイルやキャッシュを削除します',
          long: <<~DESC
            生成物（HTML/中間PDF など）を削除する標準クリーンに加えて、
            各オプションで特定のファイルのみを削除できます。
            - `vs clean`            : 生成物（HTML / 中間PDF 等）を削除（最終PDFは保持）
            - `vs clean --purge`    : 最終PDFも含めてすべて削除
            - `vs clean --cache`    : キャッシュディレクトリのみ削除（生成物は保持）
            - `vs clean --cover`    : 生成されたカバー画像のみを削除（マスターは保持）
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'clean', CLEAN_DESC[:short]
            long_desc CLEAN_DESC[:long]
            method_option :purge, type: :boolean, aliases: '-P', desc: '生成物（PDF含む）をすべて削除します'
            method_option :cache, type: :boolean, aliases: '-C', desc: 'キャッシュ(.cache/vs 既定)のみを削除します'
            method_option :cover, type: :boolean, desc: '生成されたカバー画像のみを削除します（マスターは保持）'
            # ================================================================
            # Command: clean（生成物のクリーンアップ）
            # ------------------------------------------------
            # - 削除: .vivliostyle, *.html, 03-toc.md, entries.js, 一時/中間PDF
            # - 保持: 最終成果物の PDF（output.pdf, output_compressed.pdf）
            # - 既知の保持対象MD: README.md, ROADMAP.md, CONTENT-LICENSE.md,
            #   THIRD-PARTY-LICENSES.md, CHANGELOG.md
            # ================================================================
            def clean
              # --cover オプション: 生成されたカバー画像を削除
              CleanCommands.clean_cover_files if options[:cover]

              if options[:cache]
                begin
                  dir = begin
                    Common.cache_dir
                  rescue StandardError
                    '.cache/vs'
                  end
                  if dir.nil? || dir.to_s.strip.empty?
                    Common.log_warn('キャッシュディレクトリが不明のため中止します')
                    return
                  end
                  if File.directory?(dir)
                    Common.log_action("キャッシュディレクトリを削除中: #{dir}")
                    FileUtils.rm_rf(dir)
                    Common.log_success('キャッシュ削除が完了しました')
                  else
                    Common.log_info("キャッシュディレクトリは存在しません: #{dir}")
                  end

                  if File.directory?('.vivliostyle')
                    Common.log_action('.vivliostyle ディレクトリを削除中...')
                    FileUtils.rm_rf('.vivliostyle')
                    Common.log_info('.vivliostyle ディレクトリを削除しました')
                  else
                    Common.log_info('.vivliostyle ディレクトリは存在しません')
                  end
                rescue StandardError => e
                  Common.log_warn("clean --cache 実行中にエラー: #{e}")
                end
              end

              # --cache または --cover のみが指定された場合は通常のクリーン処理をスキップ
              # --purge が指定されている、またはオプションなしの場合は通常のクリーン処理を実行
              if (options[:cache] || options[:cover]) && !options[:purge]
                # --cache または --cover のみの場合はここで終了
                return
              end

              # BuildHelpers.clean_generated_files! と等価の処理をここに実装
              Common.log_action('.vivliostyle ディレクトリを削除中...')
              FileUtils.rm_rf('.vivliostyle')

              Common.log_action('生成ファイルを削除中...')
              cleanup_patterns = [
                # HTML/JS 中間生成物
                '*.html',
                # 付録ガードHTML（明示指定; パターン変更時の保険）
                '90-appendices-guard.html',
                'entries.js',
                # 生成される一時/補助的な Markdown（任意）
                '03-toc.md',
                # pre_process によりプロジェクトルートへ展開される章系の Markdown のみ削除対象に限定
                # 例: 11-install.md など（任意の *.md やドキュメントは削除しない）
                '[0-9][0-9]-*.md',
                # フロント/テイル系の生成MD（存在時のみ）
                '00-titlepage.md', '01-legalpage.md', '98-postface.md', '99-colophon.md'
              ]

              intermediate_pdfs = [
                '00-titlepage.pdf', '01-legalpage.pdf', '02-preface.pdf', '03-toc.pdf',
                '00-01-front.pdf', '99-colophon.pdf',
                '02-03-front.pdf', '11-98-sections.pdf',
                'blank_page.pdf', 'blank_frontmatter_insert.pdf',
                'output_tmp*.pdf'
              ]
              cleanup_patterns.concat(intermediate_pdfs)

              final_pdfs = [
                Common::CONFIG.dig('pdf', 'output_file') || 'output.pdf',
                Common::CONFIG.dig('pdf', 'output_file_compressed') || 'output_compressed.pdf'
              ].uniq

              # --purge 指定時は最終PDFも削除対象に含める
              if options[:purge]
                cleanup_patterns.concat(final_pdfs)
                # 単章PDF（例: 11-install.pdf, 81-install.pdf など）も削除
                # 既に個別に列挙している中間PDFと重複しても問題ない
                cleanup_patterns << '[0-9][0-9]-*.pdf'
              end

              cleanup_patterns.each do |pattern|
                Dir.glob(pattern).each do |file|
                  next if File.directory?(file)

                  FileUtils.rm_f(file)
                  Common.log_info("#{file} を削除しました")
                end
              end
              Common.log_success('不要ファイルの削除が完了しました')
            end
          end
        end

        # 生成されたカバー画像を削除（マスターは保持）
        def clean_cover_files
          config = Common.load_config
          covers_dir = config.dig('directories', 'covers') || 'covers'

          unless File.directory?(covers_dir)
            Common.log_info("カバーディレクトリが存在しません: #{covers_dir}")
            return
          end

          Common.log_action('生成されたカバー画像を削除中...')

          # book.yml の設定から削除対象ファイルを収集
          cover_files = []
          
          # PDF用カバー（RGB版）
          if (front = config.dig('output', 'pdf', 'cover', 'front'))
            cover_files << front
          end
          if (back = config.dig('output', 'pdf', 'cover', 'back'))
            cover_files << back
          end
          
          # 印刷用PDF（CMYK版）
          if (front = config.dig('output', 'print_pdf', 'cover', 'front'))
            cover_files << front
          end
          if (back = config.dig('output', 'print_pdf', 'cover', 'back'))
            cover_files << back
          end
          
          # EPUB用カバー
          if (cover = config.dig('output', 'epub', 'cover'))
            cover_files << cover
          end
          
          # 重複を削除
          cover_files.uniq!
          
          if cover_files.empty?
            Common.log_info('book.yml にカバー画像の設定が見つかりませんでした')
            return
          end

          deleted_count = 0
          cover_files.each do |filename|
            # ファイル名のみを抽出（パスが含まれている場合に対応）
            basename = File.basename(filename)
            file_path = File.join(covers_dir, basename)
            
            if File.exist?(file_path)
              FileUtils.rm_f(file_path)
              Common.log_info("#{file_path} を削除しました")
              deleted_count += 1
            end
          end

          if deleted_count.zero?
            Common.log_info('削除対象のカバー画像はありませんでした')
          else
            Common.log_success("カバー画像を削除しました（#{deleted_count}ファイル）")
          end
        end
      end
    end
  end
end
