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
            transform_book_cards!
            transform_table_rotations!
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
              context.chapter_number
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
          rescue DataRender::DataRenderError => e
            Common.log_error("QueryStream 展開エラー: #{e.message}")
            raise
          end

          # 画像パスを生成規約に従って正規化する
          def normalize_image_paths!
            context.content = ImagePathNormalizer.fix_image_paths(context.content, context.filename)
            Common.log_success("画像パスを修正しました: #{context.filename}")
          end

          # リンク・画像の自動検証を実行する
          def validate_links_and_images!
            LinkImageValidator.validate(context.content, context.filename)
          end

          # include 記法によるソースコード取り込みを実行する
          def process_code_includes!
            Common.log_action('ソースコード読み込み記法をスキャンしています…')
            context.content = MarkdownTransformer.process_code_include(context.content)
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
          def normalize_html_block_boundaries!
            html_closing_tags = %w[small div span p blockquote pre table ul ol li dl dt dd
                                   figure figcaption aside article section header footer nav main]
            closing_tag_pattern = %r{</\s*(#{html_closing_tags.join('|')})\s*>}

            # コードブロック内では変換しない
            lines = context.content.lines
            out = []
            in_code_block = false
            prev_was_html_closing = false

            lines.each do |line|
              stripped = line.lstrip

              if stripped.start_with?('```') && !stripped.start_with?('```include:')
                in_code_block = !in_code_block
                out << line
                prev_was_html_closing = false
                next
              end

              if in_code_block
                out << line
                prev_was_html_closing = false
                next
              end

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
                # 閉じタグ部分と Markdown 部分を分離
                modified = line.gsub(/(#{closing_tag_pattern})\s*(#|\*|-)/) do
                  "#{::Regexp.last_match(1)}\n\n#{::Regexp.last_match(3)}"
                end
                out << modified
                prev_was_html_closing = false
              else
                out << line
                # 現在行が HTML 閉じタグで終わっているかチェック
                prev_was_html_closing = line.strip.match?(closing_tag_pattern)
              end
            end

            context.content = out.join
          end

          # インラインコード内の HTML 予約文字をエスケープする
          # - 著者は `` `<h1>` `` のように素直に書ける
          # - 前処理後の Markdown では `&lt;h1&gt;` のようにエスケープされた形になる
          # - フェンス付きコードブロック内部はそのまま残す
          def escape_inline_code_html!
            lines = context.content.lines
            out = []
            in_code_block = false

            lines.each do |line|
              stripped = line.lstrip

              # ``` / ```lang で始まる行でコードブロックの開始・終了をトグル
              # ただし、```include:...``` のような 1 行完結の include 記法は
              # 実際のコードブロックとはみなさず、フラグを変更しない
              if stripped.start_with?('```') && !stripped.start_with?('```include:')
                in_code_block = !in_code_block
                out << line
                next
              end

              out << if in_code_block
                       line
                     else
                       MarkdownTransformer.escape_inline_code_html(line)
                     end
            end

            context.content = out.join
          end

          # 行末の `{.right}` / `{.text-right}` を VFM コンテナ `:::{.text-right}` に変換する
          # 例:
          #   **著者: Matz**{.right}
          #   ->
          #   ::: {.text-right}
          #   **著者: Matz**
          #   :::
          def transform_text_right_inlines!
            lines = context.content.lines
            out = []
            in_code_block = false

            lines.each do |line|
              stripped = line.lstrip

              if stripped.start_with?('```')
                in_code_block = !in_code_block
                out << line
                next
              end

              if !in_code_block && (m = line.match(/^(\s*)(.+)\{\.(right|text-right)\}\s*$/))
                indent = m[1]
                inner  = m[2].rstrip
                out << "#{indent}::: {.text-right}\n"
                out << "#{indent}#{inner}\n"
                out << "#{indent}:::\n"
              else
                out << line
              end
            end

            context.content = out.join
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
          # コンテナ外に非表示の参照を追加して脚注定義を生成させる
          def expose_container_footnotes!
            # コンテナ内の脚注参照を収集
            container_footnotes = []
            in_container = false

            context.content.lines.each do |line|
              if line.match?(/^:::\s*\{\.sideimage/)
                in_container = true
              elsif line.strip == ':::'
                in_container = false
              elsif in_container
                # [^urlN] または [^N] パターンを検出
                line.scan(/\[\^(url\d+|\d+)\]/).each do |match|
                  container_footnotes << match[0]
                end
              end
            end

            return if container_footnotes.empty?

            # 脚注定義の直前に非表示の参照を追加
            # これにより VFM が脚注定義を認識して <aside> を生成する
            hidden_refs = container_footnotes.uniq.map { |id| "[^#{id}]" }.join
            hidden_span = "<span class=\"footnote-anchor\" style=\"display:none\">#{hidden_refs}</span>\n\n"

            # 最初の脚注定義の直前に挿入
            return unless context.content.match?(/^\[\^url\d+\]:/m)

            context.content = context.content.sub(/^(\[\^url\d+\]:)/m, "#{hidden_span}\\1")
            Common.log_success("コンテナ内脚注参照を露出しました（#{container_footnotes.uniq.size}件）")
          end

          # HTMLコメント <!-- ... --> を削除する
          # 複数行コメントにも対応
          def strip_html_comments!
            original_length = context.content.length
            # 複数行対応のためマルチラインモードを使用
            context.content = context.content.gsub(/<!--.*?-->/m, '')
            removed_length = original_length - context.content.length
            if removed_length > 0
              Common.log_success("HTMLコメントを削除しました（#{removed_length} 文字）")
            end
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
