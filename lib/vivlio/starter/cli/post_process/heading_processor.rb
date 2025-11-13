# frozen_string_literal: true

require 'nokogiri'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PostProcessCommands
        # ================================================================
        # Module: HeadingProcessor
        # ----------------------------------------------------------------
        # 【役割】
        # - 見出し（h1..h6）にマーカーとメタデータを付与
        # - 章番号・節番号のスパンを構築
        # 
        # 【処理内容】
        # 1. 見出しマーカー付与
        #    - class: vs-h-marker
        #    - data-heading: 見出しテキスト
        #    - data-hN: レベル別見出しテキスト
        #    - data-chapter: 章トークン
        # 
        # 2. 見出し番号スパン構築
        #    - h1: <span class="chapter-number">第N章</span><span class="chapter-title">タイトル</span>
        #    - h2: <span class="section-number">N-M</span><span class="section-title">タイトル</span>
        #    - h3: <span class="subsection-marker">♣</span><span class="subsection-title">タイトル</span>
        # ================================================================
        module HeadingProcessor
          MAIN_CHAPTER_RANGE = (11..89)

          module_function

          # 見出し(h1..hN)に本文参照用のマーカー（class と data 属性）を付与
          # @param html_paths [Array<String>] HTMLファイルパスの配列
          # @param max_level [Integer] 処理する見出しの最大レベル（デフォルト: 3）
          def inject_heading_markers!(html_paths, max_level: 3)
            paths = Array(html_paths).select { |p| File.exist?(p) }
            return if paths.empty?

            max_l = [[max_level.to_i, 1].max, 6].min
            paths.each do |path|
              html = File.read(path, encoding: 'utf-8')
              doc  = if defined?(Nokogiri::HTML5)
                       Nokogiri::HTML5.parse(html)
                     else
                       Nokogiri::HTML.parse(html, nil, 'UTF-8')
                     end
              modified = false
              chapter_token = File.basename(path, File.extname(path)).to_s.strip
              chapter_token = nil if chapter_token.empty?
              
              (1..max_l).each do |lvl|
                doc.css("h#{lvl}").each do |h|
                  # 見出し要素自体に vs-h-marker クラスを付与
                  classes = (h['class'] || '').split
                  unless classes.include?('vs-h-marker')
                    classes << 'vs-h-marker'
                    h['class'] = classes.join(' ').strip
                    modified = true
                  end

                  # 見出しテキストを data 属性として付与
                  heading_text = extract_heading_core_text(h)
                  if heading_text && !heading_text.empty?
                    # data-heading（汎用）
                    if h['data-heading'] != heading_text
                      h['data-heading'] = heading_text
                      modified = true
                    end
                    # data-h{level}（レベル別）
                    lvl_key = "data-h#{lvl}"
                    if h[lvl_key] != heading_text
                      h[lvl_key] = heading_text
                      modified = true
                    end

                    # h1の場合、idも設定
                    if lvl == 1 && h['id'].to_s.strip.empty?
                      h['id'] = heading_text
                      modified = true
                    end
                  end

                  # 章トークンを付与
                  if chapter_token && h['data-chapter'] != chapter_token
                    h['data-chapter'] = chapter_token
                    modified = true
                  end
                end
              end
              
              if modified
                out = doc.respond_to?(:to_html) ? doc.to_html : doc.to_s
                File.write(path, out, encoding: 'utf-8')
              end
            rescue StandardError => e
              Common.log_warn("見出しメタ付与に失敗: #{path} (#{e})")
            end
          end

          # 見出し番号スパンを構築
          # @param html_path [String] HTMLファイルパス
          def inject_heading_number_spans!(html_path)
            return unless File.exist?(html_path)

            html = File.read(html_path, encoding: 'utf-8')
            doc = if defined?(Nokogiri::HTML5)
                    Nokogiri::HTML5.parse(html)
                  else
                    Nokogiri::HTML.parse(html, nil, 'UTF-8')
                  end

            file_type = Common.get_file_type(html_path)
            chapter_token = File.basename(html_path, File.extname(html_path))
            chapter_number = Common.get_chapter_number(chapter_token)
            chapter_number_i = chapter_number&.to_i

            chapter_display_number = resolve_main_chapter_display_number(chapter_token, chapter_number_i)
            appendix_letter = nil

            if chapter_number_i&.between?(91, 97)
              appendix_letter = Common.appendix_number_to_letter(chapter_number_i)&.upcase
            end

            process_h1 = %w[chapter appendix].include?(file_type)
            process_h2 = %w[chapter appendix].include?(file_type)
            process_h3 = %w[chapter appendix].include?(file_type)

            modified = false

            # h1 の処理
            if process_h1 && (h1 = doc.at_css('h1'))
              title_text = extract_heading_core_text(h1)
              number_text = if file_type == 'appendix'
                              appendix_letter ? "付録 #{appendix_letter}" : nil
                            elsif chapter_display_number
                              "第#{chapter_display_number}章"
                            end
              modified |= rebuild_heading_with_spans(h1, number_text, title_text, :chapter, doc)
              if number_text
                h1['data-chapter-number-display'] = number_text
              else
                h1.delete('data-chapter-number-display')
              end
              if title_text
                h1['data-chapter-title'] = title_text
              else
                h1.delete('data-chapter-title')
              end
            end

            # h2 の処理
            if process_h2
              section_index = 0
              doc.css('h2').each do |h2|
                section_index += 1
                title_text = extract_heading_core_text(h2)
                number_text = if file_type == 'appendix'
                                appendix_letter ? "#{appendix_letter}-#{section_index}" : section_index.to_s
                              elsif chapter_display_number
                                "#{chapter_display_number}-#{section_index}"
                              else
                                section_index.to_s
                              end
                modified |= rebuild_heading_with_spans(h2, number_text, title_text, :section, doc)
                h2['data-section-number-display'] = number_text if number_text
                h2['data-section-title'] = title_text if title_text
              end
            end

            # h3 の処理
            if process_h3
              marker = Common::CONFIG.dig('theme', 'markers', 'h3') || '♣'
              doc.css('h3').each do |h3|
                title_text = extract_heading_core_text(h3)
                modified |= rebuild_heading_with_spans(h3, marker, title_text, :subsection, doc)
                h3['data-subsection-title'] = title_text if title_text
              end
            end

            return unless modified

            out = doc.respond_to?(:to_html) ? doc.to_html : doc.to_s
            File.write(html_path, out, encoding: 'utf-8')
          end

          # 見出しを番号スパンとタイトルスパンで再構築
          # @param node [Nokogiri::XML::Element] 見出し要素
          # @param number_text [String] 番号テキスト
          # @param title_text [String] タイトルテキスト
          # @param kind [Symbol] 見出しの種類（:chapter, :section, :subsection）
          # @param doc [Nokogiri::HTML::Document] ドキュメント
          # @return [Boolean] 変更があったかどうか
          def rebuild_heading_with_spans(node, number_text, title_text, kind, doc)
            number_text = number_text.to_s.strip
            title_text = title_text.to_s.strip

            number_class, title_class = case kind
                                        when :chapter then %w[chapter-number chapter-title]
                                        when :section then %w[section-number section-title]
                                        when :subsection then %w[subsection-marker subsection-title]
                                        else [nil, nil]
                                        end

            current_number_span = number_class ? node.at_css("span.#{number_class}") : nil
            current_title_span  = title_class ? node.at_css("span.#{title_class}") : nil

            current_number = current_number_span&.text&.strip
            current_title  = current_title_span&.text&.strip
            current_title ||= extract_heading_core_text(current_title_span || node)

            needs_update = false
            needs_update ||= (number_text.empty? ? !current_number.to_s.empty? : current_number != number_text)
            needs_update ||= (current_title != title_text)

            return false unless needs_update

            # タイトルの元ノードを保存
            original_title_nodes = if current_title_span
                                     current_title_span.children.map(&:dup)
                                   else
                                     node.children.reject do |child|
                                       number_class && child.element? && child['class'].to_s.split.include?(number_class)
                                     end.map(&:dup)
                                   end

            node.children.remove

            # 番号スパンを追加
            if number_class && !number_text.empty?
              span = Nokogiri::XML::Node.new('span', doc)
              span['class'] = number_class
              span.content = number_text
              node.add_child(span)
            end

            # タイトルスパンを追加
            if title_class
              span = Nokogiri::XML::Node.new('span', doc)
              span['class'] = title_class
              if original_title_nodes.empty?
                span.content = title_text
              else
                original_title_nodes.each { |child| span.add_child(child) }
              end
              node.add_child(span)
            else
              node.add_child(Nokogiri::XML::Text.new(title_text, doc)) unless title_text.empty?
            end

            true
          end

          # 見出しのコアテキストを抽出
          # @param node [Nokogiri::XML::Element] 見出し要素
          # @return [String] 見出しテキスト
          def extract_heading_core_text(node)
            %w[chapter-title section-title subsection-title].each do |cls|
              span = node.at_css("span.#{cls}")
              return span.text.to_s.strip if span
            end
            node.text.to_s.strip
          end

          # メイン章の表示番号を解決
          # @param chapter_token [String] 章トークン
          # @param chapter_number_i [Integer, nil] 章番号
          # @return [Integer, nil] 表示番号
          def resolve_main_chapter_display_number(chapter_token, chapter_number_i = nil)
            return nil if chapter_token.nil? || chapter_token.empty?

            chapter_number_i ||= Common.get_chapter_number(chapter_token)&.to_i
            return nil unless chapter_number_i && MAIN_CHAPTER_RANGE.include?(chapter_number_i)

            order = main_chapter_order
            if (idx = order.index(chapter_token))
              return idx + 1
            end

            chapter_number_i - 10
          end

          # メイン章の順序を取得
          # @return [Array<String>] 章トークンの配列
          def main_chapter_order
            @main_chapter_order ||= begin
              configured = configured_main_chapter_tokens
              tokens = configured&.any? ? configured : discovered_main_chapter_tokens
              tokens
            end
          end

          # 設定ファイルから章トークンを取得
          # @return [Array<String>, nil] 章トークンの配列
          def configured_main_chapter_tokens
            cfg = Common::CONFIG['chapters']
            raw_list = case cfg
                       when nil
                         nil
                       when String
                         str = cfg.to_s
                         return nil if str.strip.casecmp('all').zero?

                         str.lines.map(&:strip).reject(&:empty?)
                       when Array
                         cfg.map { |s| s.to_s.strip }.reject(&:empty?)
                       end
            return nil unless raw_list&.any?

            normalize_and_filter_tokens(raw_list)
          end

          # 発見されたHTMLファイルから章トークンを取得
          # @return [Array<String>] 章トークンの配列
          def discovered_main_chapter_tokens
            html_tokens = Dir.glob(File.join('.', '*.html')).map { |path| File.basename(path, '.html') }
            normalize_and_filter_tokens(html_tokens).sort_by { |token| Common.get_chapter_number(token).to_i }
          end

          # トークンリストを正規化してフィルタ
          # @param list [Array] トークンリスト
          # @return [Array<String>] 正規化された章トークンの配列
          def normalize_and_filter_tokens(list)
            seen = {}
            Array(list).each_with_object([]) do |entry, acc|
              token = normalize_chapter_token(entry)
              next unless token
              next unless main_chapter_token?(token)
              next if seen[token]

              seen[token] = true
              acc << token
            end
          end

          # 章トークンを正規化
          # @param entry [String] エントリ
          # @return [String, nil] 正規化されたトークン
          def normalize_chapter_token(entry)
            s = entry.to_s.strip
            return nil if s.empty?

            s = s.sub(%r{\A\./}, '')
            s = s.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}i, '')
            s = s.sub(/\.(html|md)\z/i, '')
            s = s.sub(/\.(html|md)\z/i, '')
            s = s.strip
            return nil if s.empty?

            s
          end

          # メイン章トークンかどうか判定
          # @param token [String] トークン
          # @return [Boolean] メイン章トークンの場合true
          def main_chapter_token?(token)
            num = Common.get_chapter_number(token)
            num && MAIN_CHAPTER_RANGE.include?(num.to_i)
          end
        end
      end
    end
  end
end
