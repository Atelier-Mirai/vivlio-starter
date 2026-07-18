# frozen_string_literal: true

require 'nokogiri'
require_relative 'post_process/html_parser'

module VivlioStarter
  module CLI
    # ==============================================================================
    # Module: PrismLinesCommands
    # ------------------------------------------------------------------------------
    # Prism.js のコードブロック（<pre><code>）に行番号を付与するコマンド群。
    # 入力HTMLを解析し、必要なクラスと line-numbers-rows を自動追加して保存する。
    #
    # 提供コマンド:
    #   - prism:lines INPUT_FILE [OUTPUT_FILE]
    #     入力HTML内の Prism.js コードブロックに行番号を追加する。
    #
    # 備考:
    #   - -v/--verbose で詳細ログを表示（ENV には反映しません）。
    #   - OUTPUT_FILE を省略した場合、INPUT_FILE を上書きします。
    # ==============================================================================
    module PrismLinesCommands
      module_function

      PRISM_LINES_DESC = {
        short: 'HTMLファイル内のPrism.jsコードブロックに行番号を追加します',
        long: <<~DESC
          指定したHTMLファイル内のPrism.jsコードブロックに行番号を追加します。

          引数:
            INPUT_FILE     入力HTMLファイル（必須）
            OUTPUT_FILE    出力HTMLファイル（省略可、省略時は入力ファイルを上書き）

          オプション:
            -v, --verbose  詳細な処理情報を表示

          使用例:
            vs prism:lines prime.html
            vs prism:lines prime.html prime_with_lines.html
        DESC
      }.freeze

      def included(base); end

      # Samovar/直接呼び出し用エントリポイント
      def execute_prism_lines(input_file, output_file = nil)
        output_file ||= input_file

        unless File.exist?(input_file)
          Common.log_error("エラー: 入力ファイル '#{input_file}' が存在しません")
          return
        end

        add_prism_line_numbers(input_file, output_file)
      end

      # コードの行数を返す
      def line_count(pre)
        pre.text.count("\n") + 1
      end

      # Prism コメントトークンの [!] マーカーを赤強調クラスに変換する。
      # コメント記号（# / // / -- / /* / <!--）は保持し、[!] とその前後の空白 1 つを除去する。
      # 旧 post_replace_list.yml の [!] 赤強調ルール（Prism 出力狙い）をここへ移設したもの。
      ALERT_COMMENT_PATTERN = %r{\A(\#|//|--|/\*|<!--)\s*\[!\]\s?}

      # 行番号を付けない枠。実行結果（.output）・端末転写（.terminal）・
      # テキストの図/アスキーアート（.diagram）の <pre> は「コードの提示」ではないため、
      # Prism 行番号の対象外とする（後処理はコンテナ div 化の後に走るため祖先で判定できる）。
      LINE_NUMBER_EXEMPT_ANCESTORS = '.output, .terminal, .diagram'

      # Prism.jsの行番号を追加する処理
      def add_prism_line_numbers(input_file, output_file = nil)
        document = parse_html(input_file)
        highlight_alert_comments!(document)
        document.css('pre').each do |pre|
          next if line_number_exempt?(pre)

          decorate_pre_tag(pre, document)
        end
        remove_legacy_meta(document)

        target = output_file || input_file
        PostProcessCommands::HtmlParser.save_html_document(target, document)
        log_result(input_file, target)
      end

      # HTMLファイルを Nokogiri ドキュメントに変換（HtmlParser に委譲）
      def parse_html(path)
        html = File.read(path, encoding: 'UTF-8')
        PostProcessCommands::HtmlParser.parse_html_document(html)
      end

      # Prism コメントトークン内の [!] マーカーを赤強調（codered）に変換する。
      # 旧実装は Prism のエンティティ出力 &#x3C;!-- を文字列マッチしていたが、
      # Nokogiri のテキストノードではデコード済みの <!-- になるため素の <!-- で書く
      # （旧ルール 2 本＝一般コメント＋HTML コメントが 1 パターンに統合される）。
      def highlight_alert_comments!(document)
        document.css('pre span.token.comment').each do |span|
          # 記法解説用のネストコード（language-markdown の pre 内）は対象外
          next if span.ancestors('pre').any? { |pre| pre['class'].to_s.include?('language-markdown') }

          text_node = span.children.find(&:text?)
          next unless text_node
          next unless (m = text_node.text.match(ALERT_COMMENT_PATTERN))

          text_node.content = text_node.text.sub(ALERT_COMMENT_PATTERN) { "#{m[1]} " }
          span['class'] = "#{span['class']} codered"
        end
      end

      # figcaption 末尾の開始行マーカー（例: prime.rb#L22-L25）。
      # パスに # が含まれ得るため、末尾アンカーで最後のマーカーのみ解釈する。
      START_LINE_MARKER_PATTERN = /#L(\d+)(?:-L(\d+))?\z/

      # <pre> が行番号免除枠（.output / .terminal / .diagram）の中にあるか。
      def line_number_exempt?(pre)
        pre.ancestors(LINE_NUMBER_EXEMPT_ANCESTORS).any?
      end

      # <pre> 要素と内包する <code> に行番号用クラスと要素を付与
      def decorate_pre_tag(pre, document)
        consume_start_line_marker(pre)
        pre[:class] = combine_class(pre[:class], 'line-numbers')
        code = pre.at_css('code')
        return unless code

        code[:class] = combine_class(code[:class], 'line-numbers')
        code.add_child(build_line_numbers_span(document, line_count(pre)))
      end

      # figcaption 末尾の #L 開始行マーカーを消費し、行番号ガターの開始値へ変換する。
      # マーカーは pre_process の範囲 include（または著者手書きの ```ruby:foo.rb#L5）が
      # フェンス情報文字列に載せたもので、VFM を経て figcaption テキストとして届く。
      # インライン style の counter-reset は prism.css の `counter-reset: linenumber`
      # （クラスセレクタ）より優先されるため、CSS 側の変更なしで開始値が変わる。
      # 表示テキストは従来どおりパスのみへ戻す（R8）。
      def consume_start_line_marker(pre)
        figure = pre.parent
        return unless figure&.name == 'figure'

        figcaption = figure.at_css('figcaption')
        return unless figcaption
        return unless (m = figcaption.text.match(START_LINE_MARKER_PATTERN))

        figcaption.content = figcaption.text.sub(START_LINE_MARKER_PATTERN, '')
        start = m[1].to_i
        return if start < 1 # 不正な開始値はマーカー除去のみ行い従来動作（1 始まり）

        pre['data-start'] = start.to_s
        reset = "counter-reset: linenumber #{start - 1}"
        pre['style'] = [pre['style'], reset].compact.reject(&:empty?).join('; ')
      end

      # 行数分の <span> line-numbers-rows 構造を生成
      def build_line_numbers_span(document, lines)
        span = Nokogiri::XML::Node.new('span', document)
        span['aria-hidden'] = 'true'
        span['class'] = 'line-numbers-rows'

        lines.times do
          span.add_child(Nokogiri::XML::Node.new('span', document))
        end

        span
      end

      # 不要な Content-Type メタタグを除去
      def remove_legacy_meta(document)
        document.css('meta[http-equiv="Content-Type"]').each(&:remove)
      end

      # 既存クラス文字列に安全にクラスを追加
      def combine_class(original, addition)
        classes = [original, addition].compact.reject(&:empty?)
        classes.join(' ')
      end

      # 処理完了メッセージを出力
      def log_result(input_file, output_file)
        suffix = input_file == output_file ? '' : " -> #{output_file}"
        Common.log_success("行番号付与完了: #{input_file}#{suffix}")
      end
    end
  end
end
