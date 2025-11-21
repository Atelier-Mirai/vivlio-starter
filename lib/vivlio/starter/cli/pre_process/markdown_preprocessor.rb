# frozen_string_literal: true

require_relative '../common'
require_relative 'frontmatter_generator'
require_relative 'image_path_normalizer'
require_relative 'markdown_transformer'

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

          def initialize(md_file)
            filename = File.basename(md_file)
            @context = PreProcessContext.new(
              source_path: md_file,
              output_path: filename,
              filename: filename,
              file_type: Common.get_file_type(filename),
              chapter_number: Common.get_chapter_number(filename),
              content: File.read(md_file, encoding: 'utf-8')
            )
          end

          # 指定Markdownの前処理パイプラインを順次実行する
          def run
            Common.log_info("#{context.source_path} → #{context.output_path}")
            apply_frontmatter!
            normalize_image_paths!
            process_code_includes!
            escape_inline_code_html!
            transform_text_right_inlines!
            transform_book_cards!
            transform_table_rotations!
            transform_links!
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

          # 画像パスを生成規約に従って正規化する
          def normalize_image_paths!
            context.content = ImagePathNormalizer.fix_image_paths(context.content, context.filename)
            Common.log_success("画像パスを修正しました: #{context.filename}")
          end

          # include 記法によるソースコード取り込みを実行する
          def process_code_includes!
            Common.log_action('ソースコード読み込み記法をスキャンしています…')
            context.content = MarkdownTransformer.process_code_include(context.content)
            Common.log_success('ソースコード読み込み処理が完了しました')
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

              if in_code_block
                out << line
              else
                out << MarkdownTransformer.escape_inline_code_html(line)
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
