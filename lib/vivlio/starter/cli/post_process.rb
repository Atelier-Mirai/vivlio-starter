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
require_relative 'prism_lines'

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

        def included(base); end

        # Samovar/直接呼び出し用エントリポイント
        def execute_post_process(context_or_options, tokens = [])
          opts = normalize_options(context_or_options)
          ENV['VERBOSE'] = '1' if opts[:verbose]

          files = Common.normalize_tokens(tokens)
          base_dir = '.'

          html_files = if files.any?
                         files.map do |f|
                           name = f.end_with?('.html') ? f : "#{f}.html"
                           File.dirname(name) == '.' ? File.join(base_dir, name) : name
                         end.uniq
                       else
                         Dir.glob(File.join(base_dir, '*.html'))
                       end

          html_files.each do |html_file|
            BodyClassInjector.inject_body_class(html_file)
          end

          replace_rules = load_replace_rules
          total_replacements = 0

          html_files.each do |html_file|
            Common.log_action("処理中: #{html_file}")

            result = HtmlReplacer.process_html_file(html_file, replace_rules)
            if result[:changed]
              total_replacements += result[:replacements]
              Common.log_success("#{html_file}: #{result[:replacements]}個の置換を反映")
            else
              Common.log_info("#{html_file}: 変更なし")
            end

            begin
              content_before = File.read(html_file, encoding: 'utf-8')
              content_after  = SectionWrapper.wrap_h2_with_article_if_image_style!(content_before)
              if content_after != content_before
                File.write(html_file, content_after, encoding: 'utf-8')
                Common.log_success("#{html_file}: h2を<article.section-topic>でラップ（theme.style=image）")
                result2 = HtmlReplacer.process_html_file(html_file, replace_rules)
                if result2[:changed]
                  Common.log_success("#{html_file}: ラップ後の不要な空段落をクリーンアップ (#{result2[:replacements]}件)")
                end
              end
            rescue StandardError => e
              Common.log_error("#{html_file}: section-topicラップ中にエラー: #{e.message}")
            end

            begin
              wrap_sideimage_blocks!(html_file)
            rescue StandardError => e
              Common.log_error("#{html_file}: sideimage ラップ中にエラー: #{e.message}")
            end

            begin
              process_image_groups!(html_file)
            rescue StandardError => e
              Common.log_error("#{html_file}: image-group 処理中にエラー: #{e.message}")
            end

            content = File.read(html_file, encoding: 'utf-8')
            converted = FootnoteConverter.convert_endnotes_to_page_footnotes!(content)
            if converted != content
              File.write(html_file, converted, encoding: 'utf-8')
              Common.log_success("#{html_file}: 章末脚注をページ脚注に変換")
            end

            begin
              process_sideimage_footnotes!(html_file)
            rescue StandardError => e
              Common.log_error("#{html_file}: sideimage 脚注処理中にエラー: #{e.message}")
            end

            begin
              renumber_footnotes_by_document_order!(html_file)
            rescue StandardError => e
              Common.log_error("#{html_file}: 脚注再番号付け中にエラー: #{e.message}")
            end

            # Prism.js 行番号付与（直接呼び出し）
            PrismLinesCommands.execute_prism_lines(html_file)

            wrap_cross_ref_code_blocks!(html_file)

            begin
              HeadingProcessor.inject_heading_markers!([html_file], max_level: 3)
              Common.log_info("#{html_file}: 見出しメタを付与 (class=data)")
            rescue StandardError => e
              Common.log_warn("#{html_file}: 見出しメタ付与に失敗: #{e}")
            end

            begin
              HeadingProcessor.inject_heading_number_spans!(html_file)
              Common.log_info("#{html_file}: 見出し番号スパンを構築")
            rescue StandardError => e
              Common.log_warn("#{html_file}: 見出し番号スパン構築に失敗: #{e}")
            end
          end

          Common.log_success("ポスト置換処理完了 (合計: #{total_replacements}個の置換)")
        end
        module_function :execute_post_process

        # オプションを正規化
        def normalize_options(context_or_options)
          if context_or_options.is_a?(Hash)
            context_or_options[:options] || context_or_options
          elsif context_or_options.respond_to?(:options)
            context_or_options.options || {}
          else
            {}
          end
        end
        module_function :normalize_options

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
            block = comment.next_element

            next unless caption&.name == 'p'
            next unless block

            # 直後が <pre> 単体、または <figure> 内に <pre> を含むパターンの両方に対応
            if block.name == 'pre'
              code_container = block
            elsif block.name == 'figure' && block.at_css('pre')
              code_container = block
            else
              next
            end

            # キャプションに code-caption クラスを付与（既存クラスは保持）
            existing_classes = caption['class'].to_s.split(/\s+/).reject(&:empty?)
            unless existing_classes.include?('code-caption')
              caption['class'] = (existing_classes + ['code-caption']).uniq.join(' ')
            end

            wrapper = Nokogiri::XML::Node.new('div', doc)
            wrapper['id'] = id
            wrapper['class'] = 'cross-ref-list'

            # wrapper を caption の直前に挿入し、caption とコードブロック要素を移動
            caption.add_previous_sibling(wrapper)
            wrapper.add_child(caption)
            wrapper.add_child(code_container)

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
        # sideimage コンテナ内テキストのラップ
        # ----------------------------------------------------------------
        # Vivliostyle/VFM が出力する
        #   <div class="sideimage-right">
        #     <figure>…</figure>本文テキスト…
        #   </div>
        # のような構造では、figure 以外がテキストノードとなり
        # CSS Grid の .sideimage-right > :not(figure) セレクタでは拾えない。
        # そこで、figure 以外の子ノードを <div class="sideimage-body"> で
        # まとめて包み、常に
        #   <div class="sideimage-right">
        #     <figure>…</figure>
        #     <div class="sideimage-body">本文…</div>
        #   </div>
        # という 2 要素構造に正規化する。
        # ================================================================
        def wrap_sideimage_blocks!(html_file)
          content = File.read(html_file, encoding: 'utf-8')

          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(content)
                else
                  Nokogiri::HTML.parse(content, nil, 'UTF-8')
                end

          changed = false

          doc.css('div.sideimage-right, div.sideimage-left').each do |container|
            figure = container.at_css('> figure')
            next unless figure

            # 画像幅指定（width=50% など）から列比率を推定し、CSS変数として埋め込む
            if (fraction = extract_sideimage_width_fraction(figure))
              text_fr = (1.0 - fraction).round(3)
              img_fr  = fraction.round(3)

              existing_style = container['style'].to_s
              # 既存の sideimage 用変数定義を一度取り除く
              cleaned_style = existing_style
                               .gsub(/--sideimage-text-fr:[^;]+;?/, '')
                               .gsub(/--sideimage-img-fr:[^;]+;?/, '')
                               .strip

              var_style = "--sideimage-text-fr: #{text_fr}fr; --sideimage-img-fr: #{img_fr}fr"

              container['style'] = if cleaned_style.empty?
                                     var_style
                                   else
                                     "#{cleaned_style.chomp(';')}; #{var_style}"
                                   end

              normalize_sideimage_figure_width!(figure)

              changed = true
            end

            children = container.children

            body_nodes = children.reject do |node|
              node == figure || (node.text? && node.text.strip.empty?)
            end

            # すでに sideimage-body がひとつだけある場合は何もしない
            if body_nodes.size == 1 && body_nodes.first.element? &&
               body_nodes.first['class'].to_s.split.include?('sideimage-body')
              next
            end

            next if body_nodes.empty?

            body_wrapper = Nokogiri::XML::Node.new('div', doc)
            body_wrapper['class'] = 'sideimage-body'

            first_body = body_nodes.first
            first_body.add_previous_sibling(body_wrapper)

            body_nodes.each do |node|
              body_wrapper.add_child(node)
            end

            changed = true
          end

          # sideimage-body 内に残っているバッククォート付きコードを <code> 要素に変換
          doc.css('div.sideimage-body').each do |body|
            body.traverse do |node|
              next unless node.text?

              text = node.text
              next unless text.include?('`')

              segments = text.split(/(`[^`]*`)/)
              next if segments.length == 1

              # 元のテキストノードの直前に、新しいノードを順番に挿入していく
              segments.each do |seg|
                if seg.start_with?('`') && seg.end_with?('`') && seg.length >= 2
                  inner = seg[1..-2]
                  code = Nokogiri::XML::Node.new('code', doc)
                  code.content = inner
                  node.add_previous_sibling(code)
                else
                  node.add_previous_sibling(Nokogiri::XML::Text.new(seg, doc))
                end
              end

              # 役目を終えた元のテキストノードは削除する
              node.remove
              changed = true
            end
          end

          # sideimage-body 内のマークダウンリンクを <a> タグに変換
          # [テキスト](URL) → <a href="URL">テキスト</a>
          # 脚注参照 [^urlN] は一旦そのまま残す（後で process_sideimage_footnotes! で処理）
          doc.css('div.sideimage-body').each do |body|
            body.traverse do |node|
              next unless node.text?

              text = node.text
              next unless text.match?(/\[.+?\]\(.+?\)/)

              # マークダウンリンクと脚注参照を分割（脚注参照は後で処理するので残す）
              pattern = /(\[[^\]]+\]\([^)]+\))/
              segments = text.split(pattern)
              next if segments.length == 1

              segments.each do |seg|
                if (m = seg.match(/^\[([^\]]+)\]\(([^)]+)\)$/))
                  # マークダウンリンク: [text](url) → <a>text</a>
                  link_text = m[1]
                  link_url = m[2]
                  anchor = Nokogiri::XML::Node.new('a', doc)
                  anchor['href'] = link_url
                  anchor.content = link_text
                  node.add_previous_sibling(anchor)
                else
                  # 通常テキスト（脚注参照 [^urlN] も含む）
                  node.add_previous_sibling(Nokogiri::XML::Text.new(seg, doc))
                end
              end

              node.remove
              changed = true
            end
          end

          return unless changed

          File.write(html_file, doc.to_html(encoding: 'UTF-8'))
          Common.log_success("#{html_file}: sideimage コンテナを正規化しました")
        end
        module_function :wrap_sideimage_blocks!

        # ================================================================
        # image-group コンテナの列比率設定
        # ----------------------------------------------------------------
        # VFM が出力する
        #   <div class="image-group">
        #     <figure><img width="30%">...</figure>
        #     <figure><img>...</figure>
        #   </div>
        # のような構造で、先頭画像の width 指定を検出し、
        # CSS 変数 --image-group-col1, --image-group-col2 として
        # コンテナの style 属性に埋め込む。
        # ================================================================
        def process_image_groups!(html_file)
          content = File.read(html_file, encoding: 'utf-8')

          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(content)
                else
                  Nokogiri::HTML.parse(content, nil, 'UTF-8')
                end

          changed = false

          doc.css('div.image-group').each do |container|
            # 先頭の figure または img を取得
            first_figure = container.at_css('> figure')
            first_img = first_figure&.at_css('img') || container.at_css('> img')

            next unless first_img || first_figure

            # 先頭画像の width 指定を取得
            fraction = extract_image_group_width_fraction(first_figure, first_img)
            next unless fraction

            col1_fr = fraction.round(3)
            col2_fr = (1.0 - fraction).round(3)

            existing_style = container['style'].to_s
            # 既存の image-group 用変数定義を一度取り除く
            cleaned_style = existing_style
                             .gsub(/--image-group-col1:[^;]+;?/, '')
                             .gsub(/--image-group-col2:[^;]+;?/, '')
                             .strip

            var_style = "--image-group-col1: #{col1_fr}fr; --image-group-col2: #{col2_fr}fr"

            container['style'] = if cleaned_style.empty?
                                   var_style
                                 else
                                   "#{cleaned_style.chomp(';')}; #{var_style}"
                                 end

            # 画像側の width 指定を削除（グリッド列幅で制御）
            normalize_image_group_width!(first_figure, first_img)

            changed = true
          end

          return unless changed

          File.write(html_file, doc.to_html(encoding: 'UTF-8'))
          Common.log_success("#{html_file}: image-group コンテナの列比率を設定しました")
        end
        module_function :process_image_groups!

        # image-group 内の先頭画像から width 指定（%）を取り出し、
        # 0.0〜1.0 の範囲の比率として返す
        def extract_image_group_width_fraction(figure, img)
          width_attr = ''
          width_attr = figure['width'].to_s if figure
          width_attr = img['width'].to_s if width_attr.empty? && img

          if (m = width_attr.match(/([0-9]+(?:\.[0-9]+)?)\s*%/))
            return sanitize_image_group_fraction(m[1].to_f / 100.0)
          end

          style_sources = []
          style_sources << figure['style'].to_s if figure
          style_sources << img['style'].to_s if img

          style_sources.compact.each do |style|
            if (m = style.match(/width\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*%/))
              return sanitize_image_group_fraction(m[1].to_f / 100.0)
            end
          end

          nil
        end
        module_function :extract_image_group_width_fraction

        # パーセンテージから得た比率を安全な範囲に丸める
        def sanitize_image_group_fraction(raw)
          return nil unless raw.positive?

          # 極端な比率を避けるため、5%〜95% にクランプ
          [[raw, 0.05].max, 0.95].min
        end
        module_function :sanitize_image_group_fraction

        # 列幅でレイアウトを制御するため、figure/img 側の width 指定は取り除く
        def normalize_image_group_width!(figure, img)
          [figure, img].compact.each do |node|
            node.remove_attribute('width')

            style = node['style'].to_s
            next if style.empty?

            cleaned = style.gsub(/width\s*:\s*[^;]+;?/, '').strip
            if cleaned.empty?
              node.remove_attribute('style')
            else
              node['style'] = cleaned
            end
          end
        end
        module_function :normalize_image_group_width!

        # ================================================================
        # sideimage 内の脚注参照を処理
        # ----------------------------------------------------------------
        # Step 4 で page-footnote-print が生成された後に呼び出され、
        # sideimage-body 内の [^urlN] を <sup><a href="#fnN">N</a></sup> に変換する。
        # 印刷読者のために、リンクのURLを脚注として表示する。
        # ================================================================
        def process_sideimage_footnotes!(html_file)
          content = File.read(html_file, encoding: 'utf-8')

          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(content)
                else
                  Nokogiri::HTML.parse(content, nil, 'UTF-8')
                end

          changed = false

          # URLと脚注番号のマッピングを構築
          url_to_footnote = {}
          doc.css('aside.page-footnote-print').each do |aside|
            fn_num = aside['data-footnote-number']
            next unless fn_num

            link = aside.at_css('a')
            if link && link['href']
              url_to_footnote[link['href']] = fn_num
            end
          end

          return if url_to_footnote.empty?

          # sideimage-body 内の <a> タグの直後にある [^urlN] を処理
          doc.css('div.sideimage-body').each do |body|
            body.css('a').each do |link_elem|
              next_node = link_elem.next_sibling
              next unless next_node&.text?

              text = next_node.text
              # [^urlN] または [^N] パターンを検出
              next unless text.match?(/^\s*\[\^(?:url)?\d+\]/)

              # リンクのURLから脚注番号を取得
              target_url = link_elem['href']
              fn_num = url_to_footnote[target_url]

              if fn_num
                # 脚注参照をスーパースクリプトリンクに置換
                modified = text.sub(/^\s*\[\^(?:url)?\d+\]/, '')

                # スーパースクリプトリンクを生成
                sup = Nokogiri::XML::Node.new('sup', doc)
                anchor = Nokogiri::XML::Node.new('a', doc)
                anchor['href'] = "#fn#{fn_num}"
                anchor['class'] = 'footnote-ref'
                anchor['role'] = 'doc-noteref'
                anchor.content = fn_num
                sup.add_child(anchor)

                # <a>タグの直後にスーパースクリプトを挿入
                link_elem.add_next_sibling(sup)

                # 残りのテキストを更新
                if modified.strip.empty?
                  next_node.remove
                else
                  next_node.content = modified
                end

                changed = true
              else
                # 対応する脚注が見つからない場合は参照を削除
                cleaned = text.gsub(/\s*\[\^(?:url)?\d+\]/, '')
                if cleaned.empty?
                  next_node.remove
                else
                  next_node.content = cleaned
                end
                changed = true
              end
            end
          end

          return unless changed

          File.write(html_file, doc.to_html(encoding: 'UTF-8'))
          Common.log_success("#{html_file}: sideimage 脚注参照を変換しました")
        end
        module_function :process_sideimage_footnotes!

        # ================================================================
        # 脚注をドキュメント出現順に再番号付け
        # ----------------------------------------------------------------
        # sideimage 内の脚注と本文の脚注が混在する場合、処理順序により
        # 番号が出現順にならないことがある。この関数で修正する。
        # ================================================================
        def renumber_footnotes_by_document_order!(html_file)
          content = File.read(html_file, encoding: 'utf-8')

          doc = if defined?(Nokogiri::HTML5)
                  Nokogiri::HTML5.parse(content)
                else
                  Nokogiri::HTML.parse(content, nil, 'UTF-8')
                end

          # ドキュメント内のすべての脚注参照を出現順に収集
          # footnote-ref クラスを持つ <a> タグ、または <sup> 内の <a> タグ
          footnote_refs = []
          doc.traverse do |node|
            next unless node.element?

            # <a class="footnote-ref"> または <sup><a class="footnote-ref">
            if node.name == 'a' && node['class']&.include?('footnote-ref') && node['href']&.start_with?('#fn')
              # 非表示の脚注アンカー（footnote-anchor）はスキップ
              parent = node.parent
              next if parent&.name == 'span' && parent['class']&.include?('footnote-anchor')

              footnote_refs << node
            end
          end

          return if footnote_refs.empty?

          # 現在の脚注番号と新しい番号のマッピングを作成
          # old_fn_id => new_number
          renumber_map = {}
          footnote_refs.each_with_index do |ref, idx|
            new_number = idx + 1
            old_fn_id = ref['href'].sub('#', '') # "fn5" -> "fn5"
            renumber_map[old_fn_id] = new_number
          end

          # 既に正しい順序なら何もしない
          needs_renumber = renumber_map.any? do |old_id, new_num|
            old_num = old_id.sub('fn', '').to_i
            old_num != new_num
          end
          return unless needs_renumber

          # 脚注参照を更新
          footnote_refs.each_with_index do |ref, idx|
            new_number = idx + 1
            old_href = ref['href']
            old_fn_id = old_href.sub('#', '')

            # href と id を更新
            ref['href'] = "#fn#{new_number}"
            ref['id'] = "fnref#{new_number}" if ref['id']

            # 表示テキストを更新（<sup> 内か直接かを考慮）
            if ref.parent&.name == 'sup'
              ref.content = new_number.to_s
            elsif ref.at_css('sup')
              ref.at_css('sup').content = new_number.to_s
            else
              ref.content = new_number.to_s
            end
          end

          # 脚注定義（aside と span）を更新
          renumber_map.each do |old_fn_id, new_number|
            # aside.page-footnote-print
            aside = doc.at_css("aside##{old_fn_id}")
            if aside
              aside['id'] = "fn#{new_number}"
              aside['data-footnote-number'] = new_number.to_s
            end

            # span.page-footnote-inline
            inline = doc.at_css("span##{old_fn_id}")
            if inline
              inline['id'] = "fn#{new_number}"
            end

            # fnref も更新
            old_fnref_id = old_fn_id.sub('fn', 'fnref')
            fnref = doc.at_css("a##{old_fnref_id}")
            if fnref
              fnref['id'] = "fnref#{new_number}"
            end
          end

          # 不要になった footnote-anchor 要素を削除
          doc.css('span.footnote-anchor').each do |anchor|
            parent = anchor.parent
            anchor.remove
            # 親が空の <p> になった場合は削除
            parent.remove if parent&.name == 'p' && parent.content.strip.empty?
          end

          # 脚注定義を番号順にソート
          # 各セクション内の aside.page-footnote-print を番号順に並び替える
          doc.css('section').each do |section|
            asides = section.css('> aside.page-footnote-print').to_a
            next if asides.size < 2

            # 番号順にソート
            sorted_asides = asides.sort_by do |aside|
              aside['data-footnote-number'].to_i
            end

            # 既にソート済みならスキップ
            next if asides.map { |a| a['data-footnote-number'] } == sorted_asides.map { |a| a['data-footnote-number'] }

            # 最初の aside の直前にマーカーを挿入
            marker = Nokogiri::XML::Comment.new(doc, 'footnote-sort-marker')
            asides.first.add_previous_sibling(marker)

            # 元の aside を全て削除
            asides.each(&:remove)

            # マーカーの後にソート順に挿入
            sorted_asides.reverse_each do |aside|
              marker.add_next_sibling(aside)
            end

            # マーカーを削除
            marker.remove
          end

          File.write(html_file, doc.to_html(encoding: 'UTF-8'))
          Common.log_success("#{html_file}: 脚注を出現順に再番号付けしました")
        end
        module_function :renumber_footnotes_by_document_order!

        # sideimage コンテナ内の figure/img から width 指定（%）を取り出し、
        # 0.0〜1.0 の範囲の比率として返す
        def extract_sideimage_width_fraction(figure)
          # figure 要素・子 img 要素の両方を対象とする
          img = figure.at_css('img')

          width_attr = figure['width'].to_s
          width_attr = img['width'].to_s if width_attr.empty? && img

          if (m = width_attr.match(/([0-9]+(?:\.[0-9]+)?)\s*%/))
            return sanitize_sideimage_fraction(m[1].to_f / 100.0)
          end

          style_sources = []
          style_sources << figure['style'].to_s
          style_sources << img['style'].to_s if img

          style_sources.compact.each do |style|
            if (m = style.match(/width\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*%/))
              return sanitize_sideimage_fraction(m[1].to_f / 100.0)
            end
          end

          nil
        end

        # パーセンテージから得た比率を安全な範囲に丸める
        def sanitize_sideimage_fraction(raw)
          return nil unless raw.positive?

          # 極端な比率を避けるため、5%〜95% にクランプ
          [[raw, 0.05].max, 0.95].min
        end

        # 列幅でレイアウトを制御するため、figure/img 側の width 指定は取り除く
        def normalize_sideimage_figure_width!(figure)
          img = figure.at_css('img')

          [figure, img].compact.each do |node|
            node.remove_attribute('width')

            style = node['style'].to_s
            next if style.empty?

            cleaned = style.gsub(/width\s*:\s*[^;]+;?/, '').strip
            if cleaned.empty?
              node.remove_attribute('style')
            else
              node['style'] = cleaned
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
      end
    end
  end
end
