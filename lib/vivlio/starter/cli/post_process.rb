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
require_relative 'post_process/heading_processor'

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

                # Step 4.1: クロスリファレンス用コードブロックをラップ
                wrap_cross_ref_code_blocks!(html_file)

                # Step 5: 見出しにクラス/data属性を付与
                begin
                  HeadingProcessor.inject_heading_markers!([html_file], max_level: 3)
                  Common.log_info("#{html_file}: 見出しメタを付与 (class=data)")
                rescue StandardError => e
                  Common.log_warn("#{html_file}: 見出しメタ付与に失敗: #{e}")
                end

                # Step 6: 見出し番号スパンを構築
                begin
                  HeadingProcessor.inject_heading_number_spans!(html_file)
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
        # クロスリファレンス用コードブロックのラップ
        # ----------------------------------------------------------------
        # pre_process で挿入した "<!--xref:ID-->" コメントを基準に、
        # 直前の <p>（キャプション）と直後の <pre>（Prism済みコード）を
        # <div id="ID" class="cross-ref-list"> で包みます。
        # 旧スタイルの <p class="code-caption" data-xref-id> にも対応します。
        # 行番号付与 (prism_lines) 後に実行します。
        # ================================================================
        def wrap_cross_ref_code_blocks!(html_file)
          content = File.read(html_file, encoding: 'utf-8')

          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(content)
                else
                  Nokogiri::HTML.parse(content, nil, 'UTF-8')
                end

          changed = false

          # パターン1: <!--xref:ID--> コメントを基準にラップ
          doc.xpath('//comment()').each do |comment|
            text = comment.text.to_s.strip
            next unless text.start_with?('xref:')

            id = text.sub(/\Axref:/, '')
            next if id.empty?

            caption = comment.previous_element
            pre = comment.next_element

            next unless caption&.name == 'p'
            next unless pre&.name == 'pre'

            # キャプションに code-caption クラスを付与（既存クラスは保持）
            existing_classes = caption['class'].to_s.split(/\s+/).reject(&:empty?)
            unless existing_classes.include?('code-caption')
              caption['class'] = (existing_classes + ['code-caption']).uniq.join(' ')
            end

            wrapper = Nokogiri::XML::Node.new('div', doc)
            wrapper['id'] = id
            wrapper['class'] = 'cross-ref-list'

            # wrapper を caption の直前に挿入し、caption と pre を移動
            caption.add_previous_sibling(wrapper)
            wrapper.add_child(caption)
            wrapper.add_child(pre)

            # マーカーコメントは削除
            comment.remove

            changed = true
          end

          # パターン2（後方互換）: <p class="code-caption" data-xref-id> + <pre>
          doc.css('p.code-caption[data-xref-id]').each do |p|
            id = p['data-xref-id'].to_s
            next if id.empty?

            node = p.next_sibling
            pre = nil
            while node
              if node.element?
                if node.name == 'pre'
                  pre = node
                end
                break
              end
              node = node.next_sibling
            end
            next unless pre

            wrapper = Nokogiri::XML::Node.new('div', doc)
            wrapper['id'] = id
            wrapper['class'] = 'cross-ref-list'

            p.remove_attribute('data-xref-id')

            p.add_previous_sibling(wrapper)
            wrapper.add_child(p)
            wrapper.add_child(pre)

            changed = true
          end

          return unless changed

          File.write(html_file, doc.to_html(encoding: 'UTF-8'))
          Common.log_success("#{html_file}: cross-ref list code blocks wrapped")
        end
        module_function :wrap_cross_ref_code_blocks!

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
      end
    end
  end
end
