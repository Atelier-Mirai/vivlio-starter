# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/markdown_converter.rb
# ================================================================
# 責務:
#   Re:VIEW Starter から生成された Markdown ファイルを
#   vivlio-starter 用に変換する追従変換処理を担当。
#
# 変換内容:
#   - <img> タグ → Markdown 画像記法（WebP）
#   - フェンス記法の変換（[abstract], [tip], [note] 等）
#   - [column], [quote] ブロックの変換
#   - コードブロックキャプションの変換
#   - dl/dt/dd → Markdown 箇条書き
#   - HTML テーブル → Markdown テーブル
#   - ルビ記法の変換
#   - コードブロック言語の自動推定（Rouge）
#   - HTML 文字実体参照のデコード
#
# 依存:
#   - Rouge: コードブロック言語推定
#   - CGI: HTML エンティティデコード
# ================================================================

require 'cgi'

module VivlioStarter
  module CLI
    module Import
      # Markdown 追従変換モジュール
      module MarkdownConverter
        module_function

        # Markdown ファイルを vivlio-starter 用に変換する
        #
        # @param temp_dir [String] 変換対象の Markdown ファイルが格納されたディレクトリ
        # @return [void]
        def process!(temp_dir)
          Common.log_info('  追従変換を実行中...')

          Dir.glob(File.join(temp_dir, '*.md')).each do |md_path|
            markdown = File.read(md_path)
            fixed = transform(markdown)
            File.write(md_path, fixed) if fixed != markdown
          end
        end

        # Markdown テキストを変換する（テスト用に公開）
        #
        # @param markdown [String] 変換対象の Markdown テキスト
        # @return [String] 変換後の Markdown テキスト
        def transform(markdown)
          fixed = markdown.dup

          # --- phase: HTML img タグの変換 ---
          fixed = convert_img_tags(fixed)

          # --- phase: フェンス記法の変換 ---
          fixed = convert_fence_blocks(fixed)

          # --- phase: quote ブロックの変換 ---
          fixed = convert_quote_blocks(fixed)

          # --- phase: br タグ → .aki ---
          fixed.gsub!(/^\s*<br>\s*$/, '{.aki}')

          # --- phase: コードブロックキャプションの変換 ---
          fixed = convert_code_captions(fixed)

          # --- phase: Markdown 画像パスの正規化 ---
          fixed = normalize_image_paths(fixed)

          # --- phase: dl/dt/dd タグの変換 ---
          fixed = convert_definition_lists(fixed)

          # --- phase: HTML テーブルの変換 ---
          fixed = convert_html_tables(fixed)

          # --- phase: ルビ記法の変換 ---
          fixed = convert_ruby_notation(fixed)

          # --- phase: コードブロック言語の自動推定 ---
          fixed = detect_code_block_languages(fixed)

          # --- phase: HTML 文字実体参照のデコード ---
          CGI.unescapeHTML(fixed)
        end

        # <img> タグを Markdown 画像記法に変換
        def convert_img_tags(text)
          text.gsub(%r{<img src=".*/([^/]+)\.(?:png|jpg|jpeg|gif)">}i) do
            file_name_no_ext = Regexp.last_match(1)
            "![](#{file_name_no_ext}.webp)"
          end
        end

        FENCE_BLOCK_DEFINITIONS = {
          'abstract' => { klass: 'chapter-lead' },
          'tip' => { klass: 'tip' },
          'note' => { klass: 'note' },
          'notice' => { klass: 'notice' },
          'centering' => { klass: 'centering' },
          'flushright' => { klass: 'text-right' },
          'column' => { klass: 'column', separator: "\n" }
        }.freeze

        # フェンス記法（[abstract], [tip], [note], [column] 等）を変換
        def convert_fence_blocks(text)
          result = text.dup
          FENCE_BLOCK_DEFINITIONS.each do |tag, config|
            loop do
              updated = convert_block(result, tag, config)
              break if updated == result

              result = updated
            end
          end
          result
        end

        # 与えられたタグ設定に従って単一種類のフェンスブロックを Markdown 化する
        def convert_block(text, tag, config)
          klass = config.fetch(:klass)
          separator = config.fetch(:separator, "\n\n")

          pattern = %r{
            ^[ \t]*\[#{tag}\](?:[ \t]+(?<title>[^\r\n]+?))?[ \t]*\r?\n
            (?<body>.*?)
            \r?\n[ \t]*\[/#{tag}\][ \t]*$
          }mix

          text.gsub(pattern) do
            match = Regexp.last_match
            title = emphasize_title(extract_inline_title(match[:title]))
            body  = match[:body].strip
            content = [title, body].reject(&:empty?).join(separator)
            ":::{.#{klass}}\n#{content}\n:::\n"
          end
        end

        # インラインに付与されたタグを除去してタイトル文字列だけを返す
        def extract_inline_title(raw)
          raw.to_s.strip.gsub(%r{</?[^>]+>}, '').strip
        end

        # 既に強調済みのタイトルはそのまま残し、未強調なら **...** を付与する
        def emphasize_title(title)
          normalized = title.to_s.strip
          return '' if normalized.empty?

          normalized.match?(/\A\*\*.*\*\*\z/) ? normalized : "**#{normalized}**"
        end

        # [quote] ブロックの変換
        def convert_quote_blocks(text)
          text.gsub(%r{^\[quote\][^\n]*\n(.*?)^\[/quote\]\s*$}m) do
            inner = Regexp.last_match(1).gsub(/\A\n+|\n+\z/, '')
            inner.lines.map { |l| "> #{l.rstrip}".strip }.join("\n") + "\n\n"
          end
        end

        # コードブロックキャプションの変換
        def convert_code_captions(text)
          text.gsub(%r{<span class="caption">▼([^<]+)</span>\s*\n```}i) do
            caption = Regexp.last_match(1).strip
            ext = File.extname(caption).delete('.').downcase
            ext = 'text' if ext.empty?
            "```#{ext}:#{caption}"
          end
        end

        # Markdown 画像パスの正規化
        def normalize_image_paths(text)
          text.gsub(%r{!\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\./images/[^)]+/([^/]+)\.(?:png|jpg|jpeg|gif)\)}i) do
            alt = Regexp.last_match(1)
            filename = Regexp.last_match(2)
            "![#{alt}](#{filename}.webp)"
          end
        end

        # dl/dt/dd タグを Markdown 箇条書きに変換
        def convert_definition_lists(text)
          text.gsub(%r{<dl>\s*(.*?)\s*</dl>}m) do
            dl_content = Regexp.last_match(1)
            items = []
            dl_content.scan(%r{<dt>([^<]*)</dt>\s*<dd>\s*(.*?)\s*</dd>}m) do |dt, dd|
              term = dt.strip
              desc = dd.strip.gsub(/\n\s*/, "\n    ")
              if desc.include?("\n")
                lines = desc.split("\n")
                desc = lines.map.with_index { |l, i| i == lines.size - 1 ? l : "#{l}  " }.join("\n")
              end
              items << "- **#{term}**\n    #{desc}"
            end
            "#{items.join("\n\n")}\n"
          end
        end

        # HTML テーブルを Markdown テーブルに変換
        def convert_html_tables(text)
          text.gsub(%r{<div class="table[^"]*">\s*(?:<p class="caption">([^<]*)</p>)?\s*<table>(.*?)</table>\s*</div>}m) do
            caption = Regexp.last_match(1)
            table_html = Regexp.last_match(2)

            rows = []
            table_html.scan(%r{<tr[^>]*>(.*?)</tr>}m) do |row_content|
              row = row_content[0]
              cells = row.scan(%r{<t[hd][^>]*>(.*?)</t[hd]>}m).map { |c| c[0].strip }
              rows << cells
            end

            next '' if rows.empty?

            md_table = []
            md_table << "**#{caption}**\n" if caption && !caption.strip.empty?
            md_table << "| #{rows[0].join(' | ')} |"
            md_table << "| #{rows[0].map { '---' }.join(' | ')} |"
            rows[1..].each { |row| md_table << "| #{row.join(' | ')} |" }

            "#{md_table.join("\n")}\n"
          end
        end

        # ルビ記法の変換: 漢字（よみ）→ {漢字|よみ}
        def convert_ruby_notation(text)
          text.gsub(/([一-龯々]+)（([ぁ-んァ-ヶー]+)）/) do
            kanji = Regexp.last_match(1)
            reading = Regexp.last_match(2)
            "{#{kanji}|#{reading}}"
          end
        end

        # コードブロック言語の自動推定（Rouge を使用）
        #
        # 言語指定のないコードブロックに対して、内容から言語を推定して付与する
        def detect_code_block_languages(text)
          text.gsub(/^```\s*\n(.*?)^```/m) do
            code = Regexp.last_match(1)
            lang = detect_lang(code)
            "```#{lang}\n#{code}```"
          end
        end

        # コード内容から言語を推定する
        #
        # @param code [String] コードブロックの内容
        # @return [String] 推定された言語タグ
        def detect_lang(code)
          # シェルコマンドの判定（$ や % で始まる行があれば zsh）
          return 'zsh' if code.match?(/^[ \t]*[$%][ \t]+/)

          begin
            require 'rouge'
            lexer = Rouge::Lexer.guess(source: code)
            tag = lexer.tag

            # Markdown で一般的に使われる短いタグ名に変換
            mapping = {
              'javascript' => 'js',
              'typescript' => 'ts',
              'markdown' => 'md',
              'plaintext' => 'text',
              'bash' => 'zsh',
              'shell' => 'zsh'
            }

            mapping.fetch(tag, tag)
          rescue LoadError
            # Rouge がない場合は text をデフォルトにする
            Common.log_warn('  Rouge gem が見つかりません。コードブロック言語推定をスキップします。')
            'text'
          rescue StandardError
            # Lexer.guess が失敗した場合も text
            'text'
          end
        end
      end
    end
  end
end
