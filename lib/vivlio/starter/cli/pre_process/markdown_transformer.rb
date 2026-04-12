# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/markdown_transformer.rb
# ================================================================
# 責務:
#   Markdown の特殊記法を変換し、コードブロックの処理を行う。
#
# 変換処理:
#   - コードインクルード: ```ruby:codes/sample.rb → ファイル内容を埋め込み
#   - book-card: :::book-card → 書籍紹介カード HTML
#   - table-rotate: :::table-rotate → 90度回転テーブル
#   - リンク脚注化: [text](url) → text[^n] + 脚注定義
#
# コードブロック:
#   - 言語指定から Prism.js クラスを生成
#   - 行番号表示用の data-line 属性を付与
#   - ファイル名表示用のヘッダーを生成
#
# 依存:
#   - Common: 設定読み込み・ログ出力
#   - MarkdownUtils: 共通ユーティリティ
#   - CrossReferenceProcessor: クロスリファレンス処理
# ================================================================

require_relative '../common'
require_relative 'markdown_utils'
require_relative 'cross_reference_processor'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # Markdown 特殊記法変換モジュール
        module MarkdownTransformer
          module_function

          # Markdown内のリンク記法を脚注化
          def transform_links_to_footnotes(md_text)
            original = md_text.to_s
            text, code_spans = MarkdownUtils.extract_code_spans(original)

            max_n = 0
            text.scan(/\[\^url(\d+)\]:/).each do |m|
              n = m[0].to_i
              max_n = n if n > max_n
            end

            url_id = {}
            replacements = []

            replaced = text.gsub(/(?<!!)\[(.+?)\]\((https?:[^\s)]+)\)(?!\s*\[^url\d+\])/) do |_match|
              label = ::Regexp.last_match(1)
              url   = ::Regexp.last_match(2)
              id = (url_id[url] ||= begin
                max_n += 1
                "url#{max_n}"
              end)
              replacements << [id, url]
              "[#{label}](#{url}) [^#{id}]"
            end

            existing_defs = {}
            text.scan(/\[\^(url\d+)\]:\s*(\S+)/) { |id, u| existing_defs[id] = u }

            new_defs = url_id.filter_map do |u, id|
              next nil if existing_defs.key?(id)

              "[^#{id}]: #{u}"
            end

            result = if new_defs.empty?
                       replaced
                     elsif replaced.strip.end_with?("\n")
                       "#{replaced}\n#{new_defs.join("\n")}\n"
                     else
                       "#{replaced}\n\n#{new_defs.join("\n")}\n"
                     end

            MarkdownUtils.restore_code_spans(result, code_spans)
          end

          # book-card 内のMarkdownを事前整形
          def normalize_book_card_md(md_text)
            lines = md_text.to_s.split(/\r?\n/, -1)
            out = []
            lines.each_with_index do |line, i|
              out << line
              next_line = lines[i + 1]

              if line.match(/^\s*!\[[^\]]*\]\([^)]+\)\s*$/)
                out << '' if next_line && next_line.strip != ''
              elsif line.match(/^\s*\*\*[^*].*\*\*\s*$/)
                out << '' if next_line && next_line.strip != ''
              end
            end
            out.join("\n")
          end

          # <div class="book-card"> ... </div> の内側MarkdownをHTMLへ
          def convert_book_card_inner_markdown(content)
            content.gsub(%r{<div class="book-card">\n(.*?)\n</div>}m) do
              inner = ::Regexp.last_match(1)
              normalized = normalize_book_card_md(inner)
              html = MarkdownUtils.render_markdown_to_html(normalized)
              formatted = format_book_card_inner_html(html)
              "<div class=\"book-card\">\n#{formatted}\n</div>"
            end
          end

          # <div ... class="... table-rotate ..." ...> ... </div> の内側MarkdownをHTMLへ
          def convert_table_rotate_inner_markdown(content)
            content.gsub(%r{<div\s+([^>]*\bclass="[^"]*\btable-rotate\b[^"]*"[^>]*)>\s*(.*?)\s*</div>}m) do
              attrs = ::Regexp.last_match(1)
              inner = ::Regexp.last_match(2)

              normalized = "\n\n#{inner.to_s.strip}\n\n"
              html = MarkdownUtils.render_markdown_to_html(normalized).to_s.strip

              if !html.include?('<table') && inner.include?('|')
                table_html = MarkdownUtils.pipe_table_to_html(inner)
                html = table_html if table_html
              end

              "<div #{attrs}>\n#{html}\n</div>"
            end
          end

          # book-card の内側を整形
          def format_book_card_inner_html(inner_html)
            html = inner_html.to_s.strip

            img_match = html.match(/<img[^>]*>/i)
            return inner_html unless img_match

            img_tag = img_match[0].gsub(%r{\s*/?>}i) { '>' }

            if html.sub!(%r{<p>\s*#{Regexp.escape(img_match[0])}\s*</p>}i, '')
              # removed wrapped <p> with img
            else
              html.sub!(img_match[0], '')
            end

            title_match = html.match(%r{<p>\s*<strong>(.*?)</strong>\s*</p>}im)
            return inner_html unless title_match

            title_text = title_match[1].strip
            html.sub!(title_match[0], '')

            description_html = html.strip

            parts = []
            parts << "  #{img_tag}"
            parts << '  <div class="book-info">'
            parts << "    <p class=\"book-title\">#{title_text}</p>"
            parts << '    <div class="book-description">'
            parts << "      #{description_html}"
            parts << '    </div>'
            parts << '  </div>'
            parts.join("\n")
          end

          # ::: {.class ...} 記法で囲まれたコンテナを div に変換
          def convert_container_blocks(content, class_name:)
            opened_count = 0
            closed_count = 0

            pattern = /:::\s*\{\.([^}]+)\}\s*\n(.*?)\n:::\s*(?:\n|$)/m

            converted = content.gsub(pattern) do
              raw_token_str = ::Regexp.last_match(1)
              inner         = ::Regexp.last_match(2)

              raw_tokens = raw_token_str.split
              first_class = raw_tokens.first
              additional_tokens = raw_tokens.drop(1)
              additional_classes = additional_tokens.select { |t| t.start_with?('.') }.map { |c| c.delete_prefix('.') }
              param_tokens = additional_tokens.reject { |t| t.start_with?('.') }

              next ::Regexp.last_match(0) unless first_class == class_name || additional_classes.include?(class_name)

              opened_count += 1
              closed_count += 1

              all_classes = [first_class] + additional_classes
              class_attr = all_classes.join(' ')

              style_parts = []
              param_tokens.each do |token|
                if (m_scale = token.match(/^scale=(.+)$/))
                  raw = m_scale[1].strip
                  scale_percent = raw.end_with?('%') ? raw.to_f : raw.to_f * 100.0
                  scale_int = scale_percent.round
                  style_parts << "--table-rotate-scale:#{scale_int}%;"
                end

                next unless (m_shift = token.match(/^shift-y=(.+)$/))

                raw = m_shift[1].strip
                shift_percent = raw.end_with?('%') ? raw.to_f : raw.to_f * 100.0
                shift_int = shift_percent.round
                sign = shift_int.negative? ? '' : '+'
                style_parts << "--table-rotate-shift-y:#{sign}#{shift_int}%;"
              end

              style_attr = style_parts.empty? ? '' : " style=\"#{style_parts.join(' ')}\""

              "<div class=\"#{class_attr}\"#{style_attr}>\n#{inner}\n</div>\n\n"
            end

            [converted, opened_count, closed_count]
          end

          # インラインコード内の HTML 予約文字をエスケープする
          def escape_inline_code_html(line)
            MarkdownUtils.escape_inline_code_html(line)
          end

          # ```include:path[:start-end]``` を検出し、codes/ または絶対パスから読込
          def process_code_include(content)
            matches_found = 0

            content.gsub!(/```include:([^:`\s]+)(?::(\d+)-(\d+))?\s*```/) do |match|
              matches_found += 1
              original_path = ::Regexp.last_match(1)
              start_line = ::Regexp.last_match(2)&.to_i
              end_line = ::Regexp.last_match(3)&.to_i

              Common.log_action("マッチ発見: #{match.strip}")
              Common.log_info("元のパス: #{original_path}")

              file_path = if original_path.start_with?('/')
                            original_path
                          else
                            File.join(Common::CODES_DIR, original_path)
                          end
              Common.log_info("解決されたパス: #{file_path}")

              if File.exist?(file_path)
                source_content = File.read(file_path)
                lines = source_content.lines

                code_content = if start_line && end_line
                                 selected_lines = lines[(start_line - 1)..(end_line - 1)]
                                 selected_lines.join
                               else
                                 "#{source_content}\n"
                               end

                language = MarkdownUtils.detect_language(file_path)
                replacement = "```#{language}:#{original_path}\n#{code_content}```"
                Common.log_success("置換完了: #{original_path} (#{language})")

                replacement
              else
                Common.log_error("ファイルが見つかりません: #{file_path}")
                match
              end
            end

            Common.log_info("#{matches_found}個のinclude記法を処理") if matches_found.positive?
            content
          end
        end
      end
    end
  end
end
