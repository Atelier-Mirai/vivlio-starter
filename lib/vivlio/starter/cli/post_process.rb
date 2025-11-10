# frozen_string_literal: true

# ================================================================
# Module: HTML後処理オーケストレーター
# ----------------------------------------------------------------
# 【役割】
# - 生成されたHTMLファイルの後処理パイプラインを統括
# - 各処理モジュールを読み込み、Thorコマンドとして公開
#
# 【処理の流れ】
# 1. 引数からHTMLファイルを解決
# 2. 各HTMLファイルに対して以下の処理を実行:
#    - <body> タグにファイルタイプクラスを付与
#    - YAML置換ルールを適用
#    - h2を<article.section-topic>でラップ（theme.style=imageの場合）
#    - 章末脚注→ページ脚注変換
#    - Prism.js行番号付与
#    - 見出しマーカー/番号スパンの付与
#
# 【依存モジュール】
# - BodyClassInjector: <body>タグへのクラス付与
# - HtmlReplacer: YAML置換ルール適用
# - SectionWrapper: h2を<article.section-topic>でラップ
# - FootnoteConverter: 章末脚注→ページ脚注変換
# - HeadingProcessor: 見出しマーカー/番号スパンの付与（後で作成）
# ================================================================

require 'json'
require 'yaml'
require 'nokogiri'
require_relative 'common'
require_relative 'post_process/body_class_injector'
require_relative 'post_process/html_replacer'
require_relative 'post_process/section_wrapper'
require_relative 'post_process/footnote_converter'

module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: PostProcessCommands
      # ----------------------------------------------------------------
      # HTML後処理のThorコマンド群とヘルパーメソッドを提供
      # ================================================================
      module PostProcessCommands
        module_function

        POST_PROCESS_DESC = {
          short: 'HTMLファイルのポスト置換処理を行います',
          long: <<~DESC
            指定した HTML ファイルの後処理を行います。指定が無い場合はプロジェクトルートの全 .html を対象にします。

            処理内容:
            - <body> タグにファイルタイプクラスを付与
            - book.yml の files.post_replace で指定された YAML に基づく置換処理
            - 章末脚注をページ脚注に変換
            - ソースコードに行番号を追加（Prism.js対応）

            例:
              vs post_process 11-install
              vs post_process 11-install.html 12-tutorial
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'post_process [TOKENS...]', POST_PROCESS_DESC[:short]
            long_desc POST_PROCESS_DESC[:long]
            
            # ================================================================
            # Command: post_process（HTML 後処理）
            # ----------------------------------------------------------------
            # 概要: HTML に各種後処理を適用
            # 入力: *.html（引数未指定時はカレント直下の *.html）
            # 出力: 上書き保存
            # ================================================================
            def post_process(*tokens)
              ENV['VERBOSE'] = '1' if options[:verbose]

              files = Common.normalize_tokens(tokens)
              base_dir = '.'

              # HTMLファイルを解決
              html_files = if files.any?
                             files.map do |f|
                               name = f.end_with?('.html') ? f : "#{f}.html"
                               File.dirname(name) == '.' ? File.join(base_dir, name) : name
                             end.uniq
                           else
                             Dir.glob(File.join(base_dir, '*.html'))
                           end

              # Step 1: <body> タグにファイルタイプクラスを付与
              html_files.each do |html_file|
                BodyClassInjector.inject_body_class(html_file)
              end

              # Step 2: 置換ルールの読み込みと適用
              replace_rules = load_replace_rules
              total_replacements = 0

              html_files.each do |html_file|
                Common.log_action("処理中: #{html_file}")
                
                # Step 2.1: YAML置換ルールを適用
                result = HtmlReplacer.process_html_file(html_file, replace_rules)
                if result[:changed]
                  total_replacements += result[:replacements]
                  Common.log_success("#{html_file}: #{result[:replacements]}個の置換を反映")
                else
                  Common.log_info("#{html_file}: 変更なし")
                end

                # Step 2.2: h2をarticle.section-topicでラップ（theme.style=imageの場合）
                begin
                  content_before = File.read(html_file, encoding: 'utf-8')
                  content_after  = SectionWrapper.wrap_h2_with_article_if_image_style!(content_before)
                  if content_after != content_before
                    File.write(html_file, content_after, encoding: 'utf-8')
                    Common.log_success("#{html_file}: h2を<article.section-topic>でラップ（theme.style=image）")
                    # ラップ後のクリーンアップ
                    result2 = HtmlReplacer.process_html_file(html_file, replace_rules)
                    if result2[:changed]
                      Common.log_success("#{html_file}: ラップ後の不要な空段落をクリーンアップ (#{result2[:replacements]}件)")
                    end
                  end
                rescue StandardError => e
                  Common.log_error("#{html_file}: section-topicラップ中にエラー: #{e.message}")
                end

                # Step 3: 章末脚注→ページ脚注変換
                content = File.read(html_file, encoding: 'utf-8')
                converted = FootnoteConverter.convert_endnotes_to_page_footnotes!(content)
                if converted != content
                  File.write(html_file, converted, encoding: 'utf-8')
                  Common.log_success("#{html_file}: 章末脚注をページ脚注に変換")
                end

                # Step 4: 行番号を追加(Prism.js対応)
                Vivlio::Starter::ThorCLI.start(['prism_lines', html_file])

                # Step 5: 見出しにクラス/data属性を付与（将来的にHeadingProcessorに移行）
                # TODO: HeadingProcessorモジュールへの移行
                begin
                  inject_heading_markers!([html_file], max_level: 3)
                  Common.log_info("#{html_file}: 見出しメタを付与 (class=data)")
                rescue StandardError => e
                  Common.log_warn("#{html_file}: 見出しメタ付与に失敗: #{e}")
                end

                # Step 6: 見出し番号スパンを構築
                begin
                  inject_heading_number_spans!(html_file)
                  Common.log_info("#{html_file}: 見出し番号スパンを構築")
                rescue StandardError => e
                  Common.log_warn("#{html_file}: 見出し番号スパン構築に失敗: #{e}")
                end
              end

              Common.log_success("ポスト置換処理完了 (合計: #{total_replacements}個の置換)")
            end
          end
        end

        # ================================================================
        # 置換ルールの読み込み
        # ----------------------------------------------------------------
        # book.ymlのfiles.post_replaceで指定されたYAMLファイルから
        # 置換ルールを読み込みます。
        # ================================================================
        def load_replace_rules
          target_yml = Common.post_replace_file_path
          display_yml = target_yml && Common.relative_path_from_root(target_yml)

          if target_yml && File.exist?(target_yml)
            begin
              yml_content = File.read(target_yml, encoding: 'utf-8')
              parsed = YAML.safe_load(yml_content, permitted_classes: [], aliases: true)
              replace_rules = parsed.is_a?(Array) ? parsed : nil
              Common.log_error('エラー: YAMLファイルは置換オブジェクト配列である必要があります') unless replace_rules
              Common.log_info("置換ルール: #{display_yml || target_yml} を使用")
              replace_rules
            rescue StandardError => e
              Common.log_error("YAMLの読み込みに失敗: #{e.message}")
              nil
            end
          else
            missing_label = if display_yml
                              display_yml
                            elsif target_yml
                              target_yml
                            elsif Common::POST_REPLACE_FILE
                              Common::POST_REPLACE_FILE
                            else
                              '(未設定)'
                            end
            Common.log_error("置換ルールYAMLが見つかりません: #{missing_label}")
            nil
          end
        end
        module_function :load_replace_rules

        # ================================================================
        # 【TODO】以下のメソッドは将来HeadingProcessorモジュールへ移行
        # 一時的に元のコードを直接実装しています
        # ================================================================

        MAIN_CHAPTER_RANGE = (11..89)

        # 見出し(h1..hN)に本文参照用のマーカー（class と data 属性）を付与
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
                classes = (h['class'] || '').split
                unless classes.include?('vs-h-marker')
                  classes << 'vs-h-marker'
                  h['class'] = classes.join(' ').strip
                  modified = true
                end

                heading_text = extract_heading_core_text(h)
                if heading_text && !heading_text.empty?
                  if h['data-heading'] != heading_text
                    h['data-heading'] = heading_text
                    modified = true
                  end
                  lvl_key = "data-h#{lvl}"
                  if h[lvl_key] != heading_text
                    h[lvl_key] = heading_text
                    modified = true
                  end

                  if lvl == 1 && h['id'].to_s.strip.empty?
                    h['id'] = heading_text
                    modified = true
                  end
                end

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
        module_function :inject_heading_markers!

        # 見出し番号スパンを構築
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
        module_function :inject_heading_number_spans!

        # ヘルパーメソッド
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

          original_title_nodes = if current_title_span
                                   current_title_span.children.map(&:dup)
                                 else
                                   node.children.reject do |child|
                                     number_class && child.element? && child['class'].to_s.split.include?(number_class)
                                   end.map(&:dup)
                                 end

          node.children.remove

          if number_class && !number_text.empty?
            span = Nokogiri::XML::Node.new('span', doc)
            span['class'] = number_class
            span.content = number_text
            node.add_child(span)
          end

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
        module_function :rebuild_heading_with_spans

        def extract_heading_core_text(node)
          %w[chapter-title section-title subsection-title].each do |cls|
            span = node.at_css("span.#{cls}")
            return span.text.to_s.strip if span
          end
          node.text.to_s.strip
        end
        module_function :extract_heading_core_text

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
        module_function :resolve_main_chapter_display_number

        def main_chapter_order
          @main_chapter_order ||= begin
            configured = configured_main_chapter_tokens
            tokens = configured&.any? ? configured : discovered_main_chapter_tokens
            tokens
          end
        end
        module_function :main_chapter_order

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
        module_function :configured_main_chapter_tokens

        def discovered_main_chapter_tokens
          html_tokens = Dir.glob(File.join('.', '*.html')).map { |path| File.basename(path, '.html') }
          normalize_and_filter_tokens(html_tokens).sort_by { |token| Common.get_chapter_number(token).to_i }
        end
        module_function :discovered_main_chapter_tokens

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
        module_function :normalize_and_filter_tokens

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
        module_function :normalize_chapter_token

        def main_chapter_token?(token)
          num = Common.get_chapter_number(token)
          num && MAIN_CHAPTER_RANGE.include?(num.to_i)
        end
        module_function :main_chapter_token?
      end
    end
  end
end
