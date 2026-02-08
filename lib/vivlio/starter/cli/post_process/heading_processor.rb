# frozen_string_literal: true

require 'nokogiri'
require_relative '../common'
require_relative 'html_parser'

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
          MAIN_CHAPTER_RANGE = (1..89)

          module_function

          # 一時的な章トークンの並びを外部から指定するためのオーバーライド
          # 例: vs build 54-56 のような単章/範囲ビルド時に、
          #     そのビルド対象だけを 1,2,3... の順番で扱いたい場合に使用する。
          #
          # - nil または空配列の場合はオーバーライドなし（従来どおり CONFIG['chapters'] や HTML から自動検出）
          # - 設定された場合は、その並びを優先的に main_chapter_order の候補として利用する
          def chapter_tokens_override=(tokens)
            @chapter_tokens_override = Array(tokens).compact.map(&:to_s)
            # 章並びを再計算させるためキャッシュを無効化
            @main_chapter_order = nil
          end

          def chapter_tokens_override
            @chapter_tokens_override || []
          end

          # 見出し(h1..hN)に本文参照用のマーカー（class と data 属性）を付与
          # @param html_paths [Array<String>] HTMLファイルパスの配列
          # @param max_level [Integer] 処理する見出しの最大レベル（デフォルト: 3）
          def inject_heading_markers!(html_paths, max_level: 3)
            paths = Array(html_paths).select { |p| File.exist?(p) }
            return if paths.empty?

            max_l = max_level.to_i.clamp(1, 6)
            paths.each do |path|
              process_heading_markers_for_file(path, max_l)
            rescue StandardError => e
              Common.log_warn("見出しメタ付与に失敗: #{path} (#{e})")
            end
          end

          # 単一ファイルの見出しマーカー処理
          def process_heading_markers_for_file(path, max_level)
            html = File.read(path, encoding: 'utf-8')
            doc = parse_html_document(html)
            chapter_token = extract_chapter_token(path)

            modified = false
            (1..max_level).each do |lvl|
              doc.css("h#{lvl}").each do |h|
                modified |= apply_marker_to_heading(h, lvl, chapter_token)
              end
            end

            save_html_document(path, doc) if modified
          end

          # 見出し要素にマーカーを適用
          def apply_marker_to_heading(heading, level, chapter_token)
            modified = add_marker_class(heading)
            modified |= add_heading_data_attributes(heading, level)
            modified |= add_chapter_token(heading, chapter_token)
            modified
          end

          # vs-h-marker クラスを追加
          def add_marker_class(heading)
            classes = (heading['class'] || '').split
            return false if classes.include?('vs-h-marker')

            classes << 'vs-h-marker'
            heading['class'] = classes.join(' ').strip
            true
          end

          # 見出しテキストの data 属性を追加
          def add_heading_data_attributes(heading, level)
            text = extract_heading_core_text(heading)
            return false if text.nil? || text.empty?

            modified = false
            modified |= set_attr_if_changed(heading, 'data-heading', text)
            modified |= set_attr_if_changed(heading, "data-h#{level}", text)
            modified |= set_h1_id(heading, text) if level == 1
            modified
          end

          # 属性値が変わった場合のみ設定
          def set_attr_if_changed(node, attr, value)
            return false if node[attr] == value

            node[attr] = value
            true
          end

          # h1 に id を設定
          def set_h1_id(heading, text)
            return false unless heading['id'].to_s.strip.empty?

            heading['id'] = text
            true
          end

          # 章トークンを追加
          def add_chapter_token(heading, chapter_token)
            return false unless chapter_token
            return false if heading['data-chapter'] == chapter_token

            heading['data-chapter'] = chapter_token
            true
          end

          # ファイルパスから章トークンを抽出
          def extract_chapter_token(path)
            token = File.basename(path, File.extname(path)).to_s.strip
            token.empty? ? nil : token
          end

          # 見出し番号スパンを構築
          # @param html_path [String] HTMLファイルパス
          # @param entry [TokenResolver::Entry] 章情報を持つ Entry オブジェクト
          def inject_heading_number_spans!(html_path, entry)
            return unless File.exist?(html_path)

            html = File.read(html_path, encoding: 'utf-8')
            doc = parse_html_document(html)
            context = build_heading_context(html_path, entry)
            return unless context[:process_headings]

            modified = process_h1_spans(doc, context)
            modified |= process_h2_spans(doc, context)
            modified |= process_h3_spans(doc)

            save_html_document(html_path, doc) if modified
          end

          # 見出し処理のコンテキストを構築
          # @param html_path [String] HTML ファイルパス
          # @param entry [TokenResolver::Entry] 章情報を持つ Entry オブジェクト
          def build_heading_context(html_path, entry)
            chapter_token = File.basename(html_path, File.extname(html_path))
            chapter_number_i = entry.number&.to_i

            {
              file_type: entry.kind.to_s,
              chapter_display_number: chapter_number_i ? resolve_main_chapter_display_number(chapter_token, chapter_number_i) : nil,
              appendix_letter: chapter_number_i&.between?(91, 97) ? Common.appendix_number_to_letter(chapter_number_i)&.upcase : nil,
              process_headings: %i[chapter appendix].include?(entry.kind)
            }
          end

          # h1 のスパン処理
          def process_h1_spans(doc, context)
            h1 = doc.at_css('h1')
            return false unless h1

            title_text = extract_heading_core_text(h1)
            number_text = build_h1_number_text(context)
            modified = rebuild_heading_with_spans(h1, number_text, title_text, :chapter, doc)
            update_h1_data_attributes(h1, number_text, title_text)
            modified
          end

          # h1 の番号テキストを構築
          def build_h1_number_text(context)
            return "付録 #{context[:appendix_letter]}" if context[:file_type] == 'appendix' && context[:appendix_letter]
            return "第#{context[:chapter_display_number]}章" if context[:chapter_display_number]

            nil
          end

          # h1 の data 属性を更新
          def update_h1_data_attributes(h1, number_text, title_text)
            number_text ? h1['data-chapter-number-display'] = number_text : h1.delete('data-chapter-number-display')
            title_text ? h1['data-chapter-title'] = title_text : h1.delete('data-chapter-title')
          end

          # h2 のスパン処理
          def process_h2_spans(doc, context)
            modified = false
            doc.css('h2').each_with_index do |h2, idx|
              section_index = idx + 1
              title_text = extract_heading_core_text(h2)
              number_text = build_h2_number_text(context, section_index)
              modified |= rebuild_heading_with_spans(h2, number_text, title_text, :section, doc)
              h2['data-section-number-display'] = number_text if number_text
              h2['data-section-title'] = title_text if title_text
            end
            modified
          end

          # h2 の番号テキストを構築
          def build_h2_number_text(context, section_index)
            if context[:file_type] == 'appendix'
              context[:appendix_letter] ? "#{context[:appendix_letter]}-#{section_index}" : section_index.to_s
            elsif context[:chapter_display_number]
              "#{context[:chapter_display_number]}-#{section_index}"
            else
              section_index.to_s
            end
          end

          # h3 のスパン処理
          def process_h3_spans(doc)
            marker = Common::CONFIG.dig('theme', 'markers', 'h3') || '♣'
            modified = false
            doc.css('h3').each do |h3|
              title_text = extract_heading_core_text(h3)
              modified |= rebuild_heading_with_spans(h3, marker, title_text, :subsection, doc)
              h3['data-subsection-title'] = title_text if title_text
            end
            modified
          end

          # HTMLドキュメントをパース（HtmlParser に委譲）
          def parse_html_document(html)
            HtmlParser.parse_html_document(html)
          end

          # HTMLドキュメントを保存（HtmlParser に委譲）
          def save_html_document(path, doc)
            HtmlParser.save_html_document(path, doc)
          end

          # 見出しを番号スパンとタイトルスパンで再構築
          def rebuild_heading_with_spans(node, number_text, title_text, kind, doc)
            number_text = number_text.to_s.strip
            title_text = title_text.to_s.strip
            number_class, title_class = heading_span_classes(kind)

            return false unless needs_heading_update?(node, number_text, title_text, number_class, title_class)

            original_title_nodes = extract_original_title_nodes(node, number_class, title_class)
            node.children.remove
            add_number_span(node, number_class, number_text, doc)
            add_title_span(node, title_class, title_text, original_title_nodes, doc)
            true
          end

          # 見出し種別に応じたクラス名を取得
          def heading_span_classes(kind)
            case kind
            when :chapter then %w[chapter-number chapter-title]
            when :section then %w[section-number section-title]
            when :subsection then %w[subsection-marker subsection-title]
            else [nil, nil]
            end
          end

          # 見出しの更新が必要か判定
          def needs_heading_update?(node, number_text, title_text, number_class, title_class)
            current_number = number_class ? node.at_css("span.#{number_class}")&.text&.strip : nil
            current_title_span = title_class ? node.at_css("span.#{title_class}") : nil
            current_title = current_title_span&.text&.strip || extract_heading_core_text(current_title_span || node)

            number_changed = number_text.empty? ? !current_number.to_s.empty? : current_number != number_text
            title_changed = current_title != title_text
            number_changed || title_changed
          end

          # 元のタイトルノードを抽出
          def extract_original_title_nodes(node, number_class, title_class)
            title_span = title_class ? node.at_css("span.#{title_class}") : nil
            if title_span
              title_span.children.map(&:dup)
            else
              node.children.reject do |child|
                number_class && child.element? && child['class'].to_s.split.include?(number_class)
              end.map(&:dup)
            end
          end

          # 番号スパンを追加
          def add_number_span(node, number_class, number_text, doc)
            return unless number_class && !number_text.empty?

            span = Nokogiri::XML::Node.new('span', doc)
            span['class'] = number_class
            span.content = number_text
            node.add_child(span)
          end

          # タイトルスパンを追加
          def add_title_span(node, title_class, title_text, original_nodes, doc)
            if title_class
              span = Nokogiri::XML::Node.new('span', doc)
              span['class'] = title_class
              original_nodes.empty? ? span.content = title_text : original_nodes.each { |c| span.add_child(c) }
              node.add_child(span)
            elsif !title_text.empty?
              node.add_child(Nokogiri::XML::Text.new(title_text, doc))
            end
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

            chapter_number_i ||= TokenResolver::Resolver.new.resolve_file(chapter_token).number&.to_i
            return nil unless chapter_number_i && MAIN_CHAPTER_RANGE.include?(chapter_number_i)

            order = main_chapter_order
            if (idx = order.index(chapter_token))
              return idx + 1
            end

            chapter_number_i
          end

          # メイン章の順序を取得
          # @return [Array<String>] 章トークンの配列
          def main_chapter_order
            return @main_chapter_order if @main_chapter_order

            # ビルドコマンド等から一時的な章リストが与えられている場合はそれを優先
            override = chapter_tokens_override
            if override && !override.empty?
              tokens = normalize_and_filter_tokens(override)
              if tokens && !tokens.empty?
                @main_chapter_order = tokens
                return @main_chapter_order
              end
            end

            configured = configured_main_chapter_tokens
            tokens = configured&.any? ? configured : discovered_main_chapter_tokens
            @main_chapter_order = tokens
          end

          # 設定ファイルから章トークンを取得
          # @return [Array<String>, nil] 章トークンの配列
          #
          # 対応形式（config/book.yml の chapters キー）:
          #   - nil / 'all'        → フルビルド（nil を返す）
          #   - "54-56"            → 章番号指定（11..89 の範囲）
          #   - "02, 11-13, 91"   → カンマ区切り + 範囲指定
          #   - [54, 55, 56]       → 章番号配列
          #   - "11-install\n12-tutorial" → ファイルベース名（行ごと）
          #   - ["11-install", "12-tutorial"] → ファイルベース名配列
          def configured_main_chapter_tokens
            cfg = Common::CONFIG['chapters']

            case cfg
            when nil
              nil
            when String
              str = cfg.to_s
              return nil if str.strip.casecmp('all').zero?

              # 数字/レンジ指定（例: "54-56" や "11, 12-13"）として解釈できる場合
              if chapter_number_string?(str)
                numbers = parse_chapter_numbers_from_string(str)
                return tokens_from_chapter_numbers(numbers) if numbers && !numbers.empty?

                return nil
              end

              # それ以外は、行ごとのトークン（ファイルベース名）として扱う
              raw_list = str.lines.map(&:strip).reject(&:empty?)
              return nil if raw_list.empty?

              normalize_and_filter_tokens(raw_list)
            when Array
              arr = cfg.map { |s| s.to_s.strip }.reject(&:empty?)
              return nil if arr.empty?

              # 全要素が整数として解釈できる場合は章番号配列
              if all_integer_strings?(arr)
                numbers = arr.map(&:to_i).uniq.sort
                return tokens_from_chapter_numbers(numbers)
              end

              # それ以外はトークン配列として扱う
              normalize_and_filter_tokens(arr)
            end
          end

          # 文字列が「章番号/範囲」のみで構成されているか判定
          # 例: "11, 12-13" → true / "11-install" → false
          def chapter_number_string?(str)
            parts = str.to_s.split(',').map(&:strip).reject(&:empty?)
            return false if parts.empty?

            parts.all? do |part|
              part.match?(/\A\d+\z/) || part.match?(/\A\d+-\d+\z/)
            end
          end

          # 配列の全要素が整数文字列かどうか
          def all_integer_strings?(arr)
            Array(arr).all? { |s| s.to_s.strip.match?(/\A\d+\z/) }
          end

          # カンマ区切り + 範囲指定文字列から章番号配列を抽出
          # 例: "02, 11-13, 91" → [2, 11, 12, 13, 91]
          def parse_chapter_numbers_from_string(str)
            parts = str.to_s.split(',').map(&:strip).reject(&:empty?)
            numbers = []

            parts.each do |part|
              if (m = part.match(/\A(\d+)-(\d+)\z/))
                start_num = m[1].to_i
                end_num   = m[2].to_i
                next if start_num > end_num

                numbers.concat((start_num..end_num).to_a)
              elsif part.match?(/\A\d+\z/)
                numbers << part.to_i
              else
                # 数字以外が混在している場合は番号指定としては扱わない
                return nil
              end
            end

            numbers.uniq.sort
          rescue StandardError
            nil
          end

          # 章番号配列からメイン章トークンの配列を生成
          # 対象は contents/*.md のうち MAIN_CHAPTER_RANGE に入る章
          def tokens_from_chapter_numbers(numbers)
            return nil unless numbers&.any?

            allowed = numbers.map(&:to_i).uniq
            resolver = TokenResolver::Resolver.new

            md_tokens = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |p| File.basename(p, '.md') }
            candidates = normalize_and_filter_tokens(md_tokens)

            candidates.select do |token|
              entry = resolver.resolve_file(token)
              entry.number && allowed.include?(entry.number.to_i)
            end
          end

          # 発見されたHTMLファイルから章トークンを取得
          # @return [Array<String>] 章トークンの配列
          def discovered_main_chapter_tokens
            resolver = TokenResolver::Resolver.new
            html_tokens = Dir.glob(File.join('.', '*.html')).map { |path| File.basename(path, '.html') }
            normalize_and_filter_tokens(html_tokens).sort_by { |token| resolver.resolve_file(token).number&.to_i || 0 }
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
            entry = TokenResolver::Resolver.new.resolve_file(token)
            entry.number && MAIN_CHAPTER_RANGE.include?(entry.number.to_i)
          end
        end
      end
    end
  end
end
