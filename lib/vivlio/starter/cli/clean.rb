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
        extend self
        def included(base)
          base.class_eval do
            desc 'clean', '不要ファイルを削除します'
            long_desc <<~DESC
              生成物（HTML/中間PDF など）を削除します。最終成果物の PDF は保持します。
              - ディレクトリ: .vivliostyle を削除
              - 生成ファイル: *.html, 03-toc.md, entries.js など
              - 中間PDF: titlepage/frontmatter などの作業用 PDF（保持対象外）
              ※ 完全に一掃する場合は --purge（PDF含む）をご利用ください。
            DESC
            method_option :purge, type: :boolean, aliases: '-P', desc: '生成物（PDF含む）をすべて削除します'
            # ================================================================
            # Command: clean（生成物のクリーンアップ）
            # ------------------------------------------------
            # - 削除: .vivliostyle, *.html, 03-toc.md, entries.js, 一時/中間PDF
            # - 保持: 最終成果物の PDF（output.pdf, output_compressed.pdf）
            # - 既知の保持対象MD: README.md, ROADMAP.md, CONTENT-LICENSE.md,
            #   THIRD-PARTY-LICENSES.md, CHANGELOG.md
            # ================================================================
            def clean
              # BuildHelpers.clean_generated_files! と等価の処理をここに実装
              Common.log_action('.vivliostyle ディレクトリを削除中...')
              FileUtils.rm_rf('.vivliostyle')

              Common.log_action('生成ファイルを削除中...')
              cleanup_patterns = [
                '*.html',
                '03-toc.md',
                'entries.js',
              ]

              keep_files = ['README.md', 'ROADMAP.md', 'CONTENT-LICENSE.md', 'THIRD-PARTY-LICENSES.md', 'CHANGELOG.md']
              Dir.glob('*.md').each do |file|
                next if keep_files.include?(file)
                cleanup_patterns << file
              end

              intermediate_pdfs = [
                '00-titlepage.pdf', '01-legalpage.pdf', '02-preface.pdf', '03-toc.pdf',
                'frontmatter.pdf', 'chapters_appendices.pdf', '98-postface.pdf', '99-colophon.pdf',
                'blank_page.pdf', 'blank_frontmatter_insert.pdf'
              ]
              cleanup_patterns.concat(intermediate_pdfs)

              final_pdfs = [
                (Common::CONFIG.dig('pdf', 'output_file') || 'output.pdf'),
                (Common::CONFIG.dig('pdf', 'output_file_compressed') || 'output_compressed.pdf')
              ].uniq

              # --purge 指定時は最終PDFも削除対象に含める
              if options[:purge]
                cleanup_patterns.concat(final_pdfs)
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
      end
    end
  end
end
