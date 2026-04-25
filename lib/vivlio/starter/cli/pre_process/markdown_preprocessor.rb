# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/pre_process/markdown_preprocessor.rb
# ================================================================
# 責務:
#   Markdown ファイルの前処理パイプラインを実行する。
#   contents/ から展開した Markdown を変換可能な状態に整える。
#
# パイプライン処理:
#   1. フロントマター生成・更新
#   2. 画像パスの正規化（相対パス → 絶対パス）
#   3. コードインクルード展開
#   4. book-card / table-rotate 変換
#   5. リンクの脚注化
#
# コンテキスト:
#   PreProcessContext で処理対象の状態を管理
#   - source_path: 元ファイルパス
#   - output_path: 出力先パス
#   - file_type: chapter/appendix/titlepage 等
#   - chapter_number: 章番号
#   - content: 処理中の内容
# ================================================================

require_relative '../common'
require_relative 'frontmatter_generator'
require_relative 'data_render'
require_relative 'image_path_normalizer'
require_relative 'markdown_transformer'
require_relative 'markdown_utils'
require_relative 'link_image_validator'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # 前処理パイプラインのコンテキスト
        PreProcessContext = Struct.new(
          :source_path,
          :output_path,
          :filename,
          :file_type,
          :chapter_number,
          :content,
          keyword_init: true
        )

        # Markdown 前処理を段階的に実行するクラス
        class MarkdownPreprocessor
          attr_reader :context

          # @param md_file [String] Markdown ファイルパス
          # @param entry [TokenResolver::Entry] 章情報を持つ Entry オブジェクト
          def initialize(md_file, entry)
            filename = File.basename(md_file)
            @context = PreProcessContext.new(
              source_path: md_file,
              output_path: filename,
              filename: filename,
              file_type: entry.kind.to_s,
              chapter_number: entry.number,
              content: File.read(md_file, encoding: 'utf-8')
            )
          end

          # 指定Markdownの前処理パイプラインを順次実行する
          def run
            Common.log_info("#{context.source_path} → #{context.output_path}")
            apply_frontmatter!
            strip_html_comments!
            process_data_streams!
            normalize_image_paths!
            validate_links_and_images!
            process_code_includes!
            normalize_html_block_boundaries!
            escape_inline_code_html!
            transform_text_right_inlines!
            transform_text_align_containers!
            transform_book_cards!
            transform_table_rotations!
            transform_table_containers!
            transform_links!
            expose_container_footnotes!
            write_output!
          end

          private

          # フロントマターを生成または併合して更新する
          def apply_frontmatter!
            context.content = FrontmatterGenerator.apply_frontmatter(
              context.content,
              context.file_type,
              context.chapter_number,
              path: context.source_path
            )
          end

          # QueryStream 記法（= books | tags=ruby 等）をデータ展開する
          def process_data_streams!
            Common.log_action('QueryStream 記法をスキャンしています…')
            before = context.content.dup
            context.content = DataRender.process(
              context.content,
              source_filename: context.filename
            )
            if context.content == before
              Common.log_info('QueryStream 記法はありません')
            else
              Common.log_success('QueryStream 記法を展開しました')
            end
          end

          # 画像パスを生成規約に従って正規化する
          def normalize_image_paths!
            context.content = ImagePathNormalizer.fix_image_paths(
              context.content, context.filename, source_path: context.source_path
            )
            Common.log_success("画像パスを修正しました: #{context.filename}")
          end

          # リンク・画像の自動検証を実行する
          def validate_links_and_images!
            LinkImageValidator.validate(context.content, context.filename, source_path: context.source_path)
          end

          # include 記法によるソースコード取り込みを実行する
          def process_code_includes!
            Common.log_action('ソースコード読み込み記法をスキャンしています…')
            context.content = MarkdownTransformer.process_code_include(
              context.content, source_filename: context.filename, source_path: context.source_path
            )
            Common.log_success('ソースコード読み込み処理が完了しました')
          end

          # HTML ブロック終了タグの直後に Markdown 記法が続く場合、空行を挿入する
          # VFM/CommonMark では、HTML ブロックの直後に空行がないと
          # Markdown として解釈されないため、この正規化が必要
          # 例:
          #   </small>## 見出し
          #   ->
          #   </small>
          #
          #   ## 見出し
          #
          # また、</small> の後に空白のみの行がある場合も真の空行に置換する
          # コードブロック・インラインコードは extract_code_spans で退避して除外する
          def normalize_html_block_boundaries!
            html_closing_tags = %w[small div span p blockquote pre table ul ol li dl dt dd
                                   figure figcaption aside article section header footer nav main]
            closing_tag_pattern = %r{</\s*(#{html_closing_tags.join('|')})\s*>}

            protected_text, spans = MarkdownUtils.extract_code_spans(context.content)

            lines = protected_text.lines
            out = []
            prev_was_html_closing = false

            lines.each do |line|
              # 前の行が HTML 閉じタグで、現在行が空白のみまたは Markdown 記法で始まる場合
              # 真の空行を挿入して Markdown として解釈されるようにする
              if prev_was_html_closing
                if line.strip.empty?
                  # 空白のみの行を真の空行に置換
                  out << "\n"
                  prev_was_html_closing = false
                  next
                elsif line.match?(/^\s*(#|\*|-|\d+\.)/)
                  # Markdown 記法で始まる行の前に空行を追加
                  out << "\n"
                end
              end

              # HTML 閉じタグの直後に Markdown 見出し(#)や段落が続く場合、空行を挿入
              # 例: </small>## 見出し → </small>\n\n## 見出し
              if line.match?(/#{closing_tag_pattern}\s*(#|\*|-)/)
                modified = line.gsub(/(#{closing_tag_pattern})\s*(#|\*|-)/) do
                  "#{::Regexp.last_match(1)}\n\n#{::Regexp.last_match(3)}"
                end
                out << modified
                prev_was_html_closing = false
              else
                out << line
                prev_was_html_closing = line.strip.match?(closing_tag_pattern)
              end
            end

            context.content = MarkdownUtils.restore_code_spans(out.join, spans)
          end

          # インラインコード内の HTML 予約文字をエスケープする
          # - 著者は `` `<h1>` `` のように素直に書ける
          # - 前処理後の Markdown では `&lt;h1&gt;` のようにエスケープされた形になる
          # - フェンス付きコードブロック内部はそのまま残す
          #
          # コードブロック・インラインコードは extract_code_spans で退避してから処理し、
          # 最後に復元する。退避後の本文（コード外）に対してのみ変換を適用する。
          def escape_inline_code_html!
            protected_text, spans = MarkdownUtils.extract_code_spans(context.content)
            transformed = protected_text.lines.map { MarkdownTransformer.escape_inline_code_html(it) }.join
            context.content = MarkdownUtils.restore_code_spans(transformed, spans)
          end

          # 行末の `{.right}` / `{.text-right}` を VFM コンテナ `:::{.text-right}` に変換する
          # 例:
          #   **著者: Matz**{.right}
          #   ->
          #   ::: {.text-right}
          #   **著者: Matz**
          #   :::
          # コードブロック・インラインコードは extract_code_spans で退避して除外する。
          # 行末の `{.right}` / `{.text-right}` / `{.text-center}` / `{.text-left}` を
          # VFM コンテナ `:::{.text-*}` に変換する
          # 例:
          #   **著者: Matz**{.right}
          #   ->
          #   ::: {.text-right}
          #   **著者: Matz**
          #   :::
          # コードブロック・インラインコードは extract_code_spans で退避して除外する。
          def transform_text_right_inlines!
            protected_text, spans = MarkdownUtils.extract_code_spans(context.content)

            transformed = protected_text.lines.map do |line|
              if (m = line.match(/^(\s*)(.+)\{\.(right|text-right|text-center|text-left)\}\s*$/)) &&
                 !line.lstrip.start_with?(':::')
                indent = m[1]
                inner  = m[2].rstrip
                klass  = m[3] == 'right' ? 'text-right' : m[3]
                "#{indent}:::{.#{klass}}\n#{indent}#{inner}\n#{indent}:::\n"
              else
                line
              end
            end.join

            context.content = MarkdownUtils.restore_code_spans(transformed, spans)
          end

          # :::{.text-right} / :::{.text-center} / :::{.text-left} コンテナを div に変換し、
          # 内側の Markdown を HTML に変換する
          def transform_text_align_containers!
            %w[text-right text-center text-left].each do |klass|
              context.content, = MarkdownTransformer.convert_container_blocks(
                context.content,
                class_name: klass
              )
            end

            # 変換後の <div class="text-*"> 内の Markdown を HTML に変換する
            context.content = context.content.gsub(%r{(<div class="text-(?:right|center|left)"[^>]*>)\n(.*?)\n(</div>)}m) do
              open_tag = ::Regexp.last_match(1)
              inner    = ::Regexp.last_match(2)
              close_tag = ::Regexp.last_match(3)
              html = MarkdownUtils.render_markdown_to_html(inner).strip
              "#{open_tag}\n#{html}\n#{close_tag}"
            end
          end

          # book-card 記法をHTMLに変換し、内部Markdownを整形する
          def transform_book_cards!
            context.content, opened, closed = MarkdownTransformer.convert_container_blocks(
              context.content,
              class_name: 'book-card'
            )
            Common.log_success("book-cardブロックの事前変換が完了しました（開始:#{opened}件 終了:#{closed}件）")

            Common.log_action('book-card内のMarkdownをHTMLへ変換しています…')
            context.content = MarkdownTransformer.convert_book_card_inner_markdown(context.content)
            Common.log_success('book-card内のMarkdownをHTMLへ変換しました')
          end

          # table-rotate 記法をHTMLに変換し、内部Markdownを整形する
          def transform_table_rotations!
            context.content, opened, closed = MarkdownTransformer.convert_container_blocks(
              context.content,
              class_name: 'table-rotate'
            )
            Common.log_success("table-rotateブロックの事前変換が完了しました（開始:#{opened}件 終了:#{closed}件）")

            Common.log_action('table-rotate内のMarkdownをHTMLへ変換しています…')
            context.content = MarkdownTransformer.convert_table_rotate_inner_markdown(context.content)
            Common.log_success('table-rotate内のMarkdownをHTMLへ変換しました')
          end

          # long-table / table-scroll 記法をHTMLに変換し、内部Markdownを整形する
          def transform_table_containers!
            %w[long-table table-scroll].each do |klass|
              context.content, opened, closed = MarkdownTransformer.convert_container_blocks(
                context.content,
                class_name: klass
              )
              next unless opened.positive?

              Common.log_success("#{klass}ブロックの事前変換が完了しました（開始:#{opened}件 終了:#{closed}件）")
              context.content = MarkdownTransformer.convert_table_container_inner_markdown(context.content, klass)
            end
          end

          # 外部リンクを脚注化して本文を整える
          def transform_links!
            Common.log_action('リンク記法を脚注化しています…')
            before = context.content.dup
            context.content = MarkdownTransformer.transform_links_to_footnotes(context.content)
            if context.content == before
              Common.log_info('脚注化の対象リンクはありません')
            else
              Common.log_success('リンクの脚注化を適用しました')
            end
          end

          # sideimage などのコンテナ内の脚注参照を VFM が認識できるように露出する
          # VFM は :::{.class} コンテナ内の [^id] を認識しないため、
          # コンテナ外に非表示の <span> を追加して脚注定義を生成させる。
          # 脚注定義の直前に一括挿入し、番号の整合は後処理の
          # renumber_footnotes_by_document_order! に委ねる。
          def expose_container_footnotes!
            container_footnotes = []
            in_container = false

            context.content.lines.each do |line|
              if line.match?(/^:::\s*\{\.sideimage/)
                in_container = true
              elsif line.strip == ':::'
                in_container = false
              elsif in_container
                line.scan(/\[\^(url\d+|\d+)\]/).each do |match|
                  container_footnotes << match[0]
                end
              end
            end

            return if container_footnotes.empty?

            hidden_refs = container_footnotes.uniq.map { |id| "[^#{id}]" }.join
            hidden_span = "<span class=\"footnote-anchor\" style=\"display:none\">#{hidden_refs}</span>\n\n"

            return unless context.content.match?(/^\[\^url\d+\]:/m)

            context.content = context.content.sub(/^(\[\^url\d+\]:)/m, "#{hidden_span}\\1")
            Common.log_success("コンテナ内脚注参照を露出しました（#{container_footnotes.uniq.size}件）")
          end

          # HTMLコメント <!-- ... --> を削除する
          # 複数行コメントにも対応。ただしフェンス付きコードブロック（``` ... ```）と
          # インラインコード（`...`）の中身はそのまま残す。
          def strip_html_comments!
            original_length = context.content.length

            # 1) フェンス付きコードブロックを退避
            fences = []
            content = context.content.gsub(/^([ \t]*)(`{3,}|~{3,})[^\n]*\n.*?\n\1\2[^\n]*$/m) do |block|
              fences << block
              "\u0000FENCE#{fences.size - 1}\u0000"
            end

            # 2) インラインコード `...` を退避
            inlines = []
            content = content.gsub(/`[^`\n]+`/) do |code|
              inlines << code
              "\u0000INLINE#{inlines.size - 1}\u0000"
            end

            # 3) 残りからHTMLコメントを除去
            content = content.gsub(/<!--.*?-->/m, '')

            # 4) インラインコード復元
            content = content.gsub(/\u0000INLINE(\d+)\u0000/) { inlines[Regexp.last_match(1).to_i] }

            # 5) フェンス付きコードブロック復元
            content = content.gsub(/\u0000FENCE(\d+)\u0000/) { fences[Regexp.last_match(1).to_i] }

            context.content = content
            removed_length = original_length - context.content.length
            return unless removed_length.positive?

            Common.log_success("HTMLコメントを削除しました（#{removed_length} 文字）")
          end

          # 加工済みコンテンツを書き戻す
          def write_output!
            File.write(context.output_path, context.content, encoding: 'utf-8')
            Common.log_success('保存が完了しました')
          end
        end
      end
    end
  end
end
