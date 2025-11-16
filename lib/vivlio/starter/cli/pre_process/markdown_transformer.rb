# frozen_string_literal: true

require 'cgi'
require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PreProcessCommands
        # Markdown変換処理を担当するモジュール
        module MarkdownTransformer
          # 拡張子→言語の対応表
          EXT_TO_LANG = {
            'c' => 'c',
            'cc' => 'cpp',
            'cpp' => 'cpp',
            'cs' => 'csharp',
            'css' => 'css',
            'cxx' => 'cpp',
            'go' => 'go',
            'html' => 'html',
            'java' => 'java',
            'js' => 'javascript',
            'json' => 'json',
            'kt' => 'kotlin',
            'md' => 'markdown',
            'php' => 'php',
            'py' => 'python',
            'rb' => 'ruby',
            'rs' => 'rust',
            'scala' => 'scala',
            'scss' => 'scss',
            'sh' => 'bash',
            'sql' => 'sql',
            'swift' => 'swift',
            'ts' => 'typescript',
            'xml' => 'xml',
            'yaml' => 'yaml',
            'yml' => 'yaml'
          }.freeze

          module_function

          # 拡張子から言語名を推定
          def detect_language(file_path)
            ext = File.extname(file_path).downcase.delete_prefix('.')
            EXT_TO_LANG.fetch(ext, 'text')
          end

          # 簡易Markdown→HTML 変換
          def render_markdown_to_html(md_text)
            # まずはKramdownを試す
            require 'kramdown'
            Kramdown::Document.new(md_text).to_html
          rescue LoadError
            # フォールバック: 最小限のMarkdownをHTMLへ
            lines = md_text.to_s.split(/\r?\n/)
            html_parts = []
            in_ol = false
            buffer_p = []

            flush_p = lambda do
              unless buffer_p.empty?
                paragraph = buffer_p.join(' ').strip
                html_parts << "<p>#{paragraph}</p>" unless paragraph.empty?
                buffer_p.clear
              end
            end

            lines.each do |line|
              if line.strip.empty?
                flush_p.call
                next
              end

              # 画像
              if (m = line.match(/^\s*!\[[^\]]*\]\(([^)]+)\)\s*$/))
                flush_p.call
                src = m[1]
                html_parts << "<img src=\"#{src}\">"
                next
              end

              # 見出し相当の太字行
              if (m = line.match(/^\s*\*\*(.+?)\*\*\s*$/))
                flush_p.call
                html_parts << "<p><strong>#{m[1]}</strong></p>"
                next
              end

              # 番号リスト
              if (m = line.match(/^\s*(\d+)\.\s+(.*)$/))
                flush_p.call
                html_parts << '<ol>' unless in_ol
                in_ol = true
                html_parts << "<li>#{m[2]}</li>"
                next
              elsif in_ol
                html_parts << '</ol>'
                in_ol = false
              end

              buffer_p << line
            end

            flush_p.call
            html_parts << '</ol>' if in_ol
            html_parts.join("\n")
          end

          # Markdown内のリンク記法を脚注化
          def transform_links_to_footnotes(md_text)
            text = md_text.to_s

            # 既存の url 脚注番号の最大を取得
            max_n = 0
            text.scan(/\[\^url(\d+)\]:/).each do |m|
              n = m[0].to_i
              max_n = n if n > max_n
            end

            url_id = {}
            replacements = []

            # リンク本体を置換
            replaced = text.gsub(/(?<!!)\[(.+?)\]\((https?:[^\s)]+)\)(?!\[\^url\d+\])/) do |_match|
              label = ::Regexp.last_match(1)
              url   = ::Regexp.last_match(2)
              id = (url_id[url] ||= begin
                max_n += 1
                "url#{max_n}"
              end)
              replacements << [id, url]
              "[#{label}](#{url}) [^#{id}]"
            end

            # 追加する脚注定義を生成
            existing_defs = {}
            text.scan(/\[\^(url\d+)\]:\s*(\S+)/) { |id, u| existing_defs[id] = u }

            new_defs = url_id.map do |u, id|
              next nil if existing_defs.key?(id)

              "[^#{id}]: #{u}"
            end.compact

            return replaced if new_defs.empty?

            # 文末に空行2つを挟んで脚注定義を追記
            if replaced.strip.end_with?("\n")
              "#{replaced}\n#{new_defs.join("\n")}\n"
            else
              "#{replaced}\n\n#{new_defs.join("\n")}\n"
            end
          end

          # book-card 内のMarkdownを事前整形
          def normalize_book_card_md(md_text)
            lines = md_text.to_s.split(/\r?\n/, -1)
            out = []
            lines.each_with_index do |line, i|
              out << line
              next_line = lines[i + 1]

              # 画像のみの行の直後に空行を補う
              if line.match(/^\s*!\[[^\]]*\]\([^)]+\)\s*$/)
                out << '' if next_line && next_line.strip != ''
              # 太字のみの行の直後に空行を補う
              elsif line.match(/^\s*\*\*[^*].*\*\*\s*$/)
                out << '' if next_line && next_line.strip != ''
              end
            end
            out.join("\n")
          end

          # <div class="book-card"> ... </div> の内側MarkdownをHTMLへ
          def convert_book_card_inner_markdown(content)
            # 開始/終了タグの直後に改行が入っているテンプレ構造を前提に、内側をキャプチャ
            content.gsub(%r{<div class="book-card">\n(.*?)\n</div>}m) do
              inner = ::Regexp.last_match(1)
              normalized = normalize_book_card_md(inner)
              html = render_markdown_to_html(normalized)
              formatted = format_book_card_inner_html(html)
              "<div class=\"book-card\">\n#{formatted}\n</div>"
            end
          end

          # パイプテーブルを簡易HTML化
          def pipe_table_to_html(md_text)
            text = md_text.to_s.strip
            lines = text.split(/\r?\n/).map(&:rstrip)
            return nil if lines.size < 2

            header = lines[0]
            sep    = lines[1]
            return nil unless header.include?('|')
            return nil unless sep && sep =~ /^\s*\|?[\s:\-|]+\|?\s*$/

            rows = lines[2..] || []

            to_cells = lambda do |line|
              parts = line.split('|')
              parts.shift if parts.first&.strip == ''
              parts.pop   if parts.last&.strip  == ''
              parts.map(&:strip)
            end

            esc_code = lambda do |s|
              s.gsub(/`([^`]+)`/) { "<code>#{::Regexp.last_match(1)}</code>" }
               .gsub('&', '&amp;')
               .gsub('<', '&lt;')
               .gsub('>', '&gt;')
            end

            thead_cells = to_cells.call(header)
            tbody_rows  = rows.map { |r| to_cells.call(r) }

            html = []
            html << '<table>'
            html << '  <thead>'
            html << "    <tr>#{thead_cells.map { |c| "<th>#{esc_code.call(c)}</th>" }.join}</tr>"
            html << '  </thead>'
            if tbody_rows.any?
              html << '  <tbody>'
              tbody_rows.each do |cells|
                html << "    <tr>#{cells.map { |c| "<td>#{esc_code.call(c)}</td>" }.join}</tr>"
              end
              html << '  </tbody>'
            end
            html << '</table>'
            html.join("\n")
          end

          # <div ... class="... table-rotate ..." ...> ... </div> の内側MarkdownをHTMLへ
          # - class="table-rotate" を含む任意の属性を保持したまま変換する
          def convert_table_rotate_inner_markdown(content)
            # 例: <div class="table-rotate scale-60" style="--table-rotate-scale:0.60;"> ... </div>
            # 属性部全体（class, style 等）を attrs としてキャプチャし、そのまま再利用する
            content.gsub(%r{<div\s+([^>]*\bclass="[^"]*\btable-rotate\b[^"]*"[^>]*)>\s*(.*?)\s*</div>}m) do
              attrs = ::Regexp.last_match(1)
              inner = ::Regexp.last_match(2)

              normalized = "\n\n#{inner.to_s.strip}\n\n"
              html = render_markdown_to_html(normalized).to_s.strip

              # フォールバック: パイプテーブルらしき記号がある場合
              if !html.include?('<table') && inner.include?('|')
                table_html = pipe_table_to_html(inner)
                html = table_html if table_html
              end

              "<div #{attrs}>\n#{html}\n</div>"
            end
          end

          # book-card の内側を整形
          def format_book_card_inner_html(inner_html)
            html = inner_html.to_s.strip

            # 1) 画像タグを抽出
            img_match = html.match(/<img[^>]*>/i)
            return inner_html unless img_match

            img_tag = img_match[0]
            img_tag = img_tag.gsub(%r{\s*/?>}i) { |_m| '>' }

            # 画像のみの<p>ラッパーを除去
            if html.sub!(%r{<p>\s*#{Regexp.escape(img_match[0])}\s*</p>}i, '')
              # removed wrapped <p> with img
            else
              html.sub!(img_match[0], '')
            end

            # 2) タイトルを抽出
            title_match = html.match(%r{<p>\s*<strong>(.*?)</strong>\s*</p>}im)
            return inner_html unless title_match

            title_text = title_match[1].strip
            html.sub!(title_match[0], '')

            # 3) 残りを説明HTMLとする
            description_html = html.strip

            # 4) 目標の構造で出力
            parts = []
            parts << "  #{img_tag}"
            parts << '  <div class="book-info">'
            parts << "    <p class=\"book-title\">#{title_text}</p>"
            parts << '    <div class="book-description">'
            parts << "      #{description_html}"
            parts << '    </div>'
            parts << '  </div>'
            parts.join("\n")
          end

          # ::: {.class ...} 記法で囲まれたコンテナを div に変換して件数を返す
          # - 例: :::{.table-rotate scale:60% shift-y:20%}
          #   → <div class="table-rotate" style="--table-rotate-scale:0.60; --table-rotate-shift-y:+20%;"> ... </div>
          def convert_container_blocks(content, class_name:)
            opened_count = 0
            closed_count = 0

            # 1行形式のコンテナブロックをまとめてキャプチャする
            #  - 1行目: ::: {.class ...}
            #  - 中身:   任意行（非貪欲）
            #  - 終了行: :::
            # 行頭・行末のアンカーに依存せず、テキスト中のどこにあってもマッチするようにする
            # 終了タグの後の改行も含めてマッチさせる
            pattern = %r!:::\s*\{\.([^}]+)\}\s*\n(.*?)\n:::\s*(?:\n|$)!m

            converted = content.gsub(pattern) do
              raw_token_str = ::Regexp.last_match(1)
              inner         = ::Regexp.last_match(2)

              raw_tokens   = raw_token_str.split
              
              # 最初のトークンは必ずクラス名（既に . は除かれている）
              # その後のトークンはパラメータ（: を含む）または追加クラス（. で始まる）
              first_class = raw_tokens.first
              additional_tokens = raw_tokens.drop(1)
              
              # 追加のクラストークン（. で始まるもの）を抽出
              additional_classes = additional_tokens.select { |t| t.start_with?('.') }.map { |c| c.delete_prefix('.') }
              
              # パラメータトークン（: を含むもの）を抽出
              param_tokens = additional_tokens.reject { |t| t.start_with?('.') }

              # 対象クラスを含まない場合はそのまま返す
              unless first_class == class_name || additional_classes.include?(class_name)
                ::Regexp.last_match(0)
              else
                opened_count += 1
                closed_count += 1

                # クラス属性を構築
                all_classes = [first_class] + additional_classes
                class_attr = all_classes.join(' ')

                # table-rotate 用のパラメータトークンを style 属性へ変換
                # 両方ともパーセント形式で出力する
                style_parts = []
                param_tokens.each do |token|
                  # 例: scale:60% → 60%, scale:0.60 → 60%
                  if (m_scale = token.match(/^scale:(.+)$/))
                    raw = m_scale[1].strip
                    scale_percent = if raw.end_with?('%')
                                      raw.to_f
                                    else
                                      raw.to_f * 100.0
                                    end
                    scale_int = scale_percent.round
                    style_parts << "--table-rotate-scale:#{scale_int}%;"
                  end

                  # 例: shift-y:20% → +20%, shift-y:0.20 → +20%
                  if (m_shift = token.match(/^shift-y:(.+)$/))
                    raw = m_shift[1].strip
                    shift_percent = if raw.end_with?('%')
                                      raw.to_f
                                    else
                                      raw.to_f * 100.0
                                    end
                    shift_int = shift_percent.round
                    sign = shift_int.negative? ? '' : '+'
                    style_parts << "--table-rotate-shift-y:#{sign}#{shift_int}%;"
                  end
                end

                style_attr = style_parts.empty? ? '' : " style=\"#{style_parts.join(' ')}\""

                "<div class=\"#{class_attr}\"#{style_attr}>\n#{inner}\n</div>\n\n"
              end
            end

            [converted, opened_count, closed_count]
          end

          # ```include:path[:start-end]``` を検出し、codes/ または絶対パスから読込
          def process_code_include(content)
            matches_found = 0

            content.gsub!(/```include:([^:`\s]+)(?::(\d+)-(\d+))?\s*```/) do |match|
              matches_found += 1
              original_path = ::Regexp.last_match(1)
              start_line = ::Regexp.last_match(2)&.to_i
              end_line = ::Regexp.last_match(3)&.to_i

              Common.log_action("マッチ発見: #{match.strip}")
              Common.log_info("元のパス: #{original_path}")

              file_path = if original_path.start_with?('/')
                            original_path
                          else
                            File.join(Common::CODES_DIR, original_path)
                          end
              Common.log_info("解決されたパス: #{file_path}")

              if File.exist?(file_path)
                source_content = File.read(file_path)
                lines = source_content.lines

                code_content = if start_line && end_line
                                 # 1-origin の範囲指定を Ruby の配列スライスに合わせて 0-origin に補正（end も含む）
                                 selected_lines = lines[(start_line - 1)..(end_line - 1)]
                                 selected_lines.join
                               else
                                 # 範囲未指定時はファイル全体を取り込み
                                 "#{source_content}\n"
                               end

                language = detect_language(file_path)
                replacement = "```#{language}:#{original_path}\n#{code_content}```"
                Common.log_success("置換完了: #{original_path} (#{language})")

                replacement
              else
                Common.log_error("ファイルが見つかりません: #{file_path}")
                match
              end
            end

            Common.log_info("#{matches_found}個のinclude記法を処理") if matches_found.positive?
            content
          end

          # =====================================================================
          # クロスリファレンス（相互参照）機能
          # =====================================================================

          # ラベル定義情報を保持する構造体
          Label = Struct.new(:id, :type, :chapter, :number, :title, :source_file, :line, :auto) do
            def display_name
              case type
              when :list
                'リスト'
              when :table
                '表'
              when :fig
                '図'
              else
                '要素'
              end
            end

            def full_number
              "#{display_name} #{number}"
            end
          end

          # キャプション行のパターン（** タイトル @id ** 形式）
          CAPTION_PATTERN = /^\*\*\s*(.+?)\s+@([a-zA-Z0-9_\-]+)\s*\*\*\s*$/

          # キャプション行を検出してラベル情報を抽出
          # @param line [String] 検査対象の行
          # @return [Hash, nil] { title: String, id: String, auto: Boolean } or nil
          def extract_caption_label(line)
            match = line.match(CAPTION_PATTERN)
            return nil unless match

            title_with_id = match[1].strip
            label_id = match[2].strip

            # @auto または @omakase の場合は自動ID扱い
            auto_mode = %w[auto omakase].include?(label_id)

            { title: title_with_id, id: label_id, auto: auto_mode }
          end

          # 次の非空行を取得し、種別を判定
          # @param lines [Array<String>] 行配列
          # @param current_index [Integer] キャプション行のインデックス
          # @return [Symbol, nil] :list, :table, :fig, または nil
          def detect_block_type(lines, current_index)
            # キャプションの次の行から非空行を探す
            (current_index + 1...lines.size).each do |i|
              line = lines[i].strip
              next if line.empty?

              # コードブロック → list
              return :list if line.start_with?('```')

              # テーブル → table
              return :table if line.start_with?('|') && line.count('|') > 1

              # 画像 → fig
              return :fig if line.start_with?('![')

              # どれにも該当しない場合は nil（エラー扱い）
              return nil
            end

            nil
          end

          # 章番号を抽出（ファイル名から）
          # @param filename [String] 章ファイル名（例: "71-install.md"）
          # @return [String] 章番号（例: "71"）
          def extract_chapter_number(filename)
            basename = File.basename(filename, '.*')
            match = basename.match(/^(\d+)/)
            match ? match[1] : '0'
          end

          # 章全体をスキャンしてラベル定義を収集
          # @param content [String] 章のMarkdownテキスト
          # @param source_file [String] ソースファイル名
          # @param chapter_number [String] 章番号
          # @return [Hash] { labels: Array<Label>, errors: Array<String> }
          def collect_labels(content, source_file, chapter_number)
            lines = content.lines
            labels = []
            errors = []
            counters = { list: 0, table: 0, fig: 0 }

            # コードフェンス内の例示用キャプションはラベルとして扱わない
            in_code_block = false

            lines.each_with_index do |line, index|
              stripped = line.lstrip

              # ``` / ```lang で始まる行でコードブロックの開始・終了をトグル
              if stripped.start_with?('```')
                in_code_block = !in_code_block
                next
              end

              # コードブロック内はラベル解析の対象外
              next if in_code_block

              caption_info = extract_caption_label(line)
              next unless caption_info

              # 種別判定
              block_type = detect_block_type(lines, index)
              unless block_type
                errors << "#{source_file}:#{index + 1} - キャプション行に@idがありますが、" \
                          "直後のブロックから種別（リスト/表/図）を判定できませんでした"
                next
              end

              # 番号の採番
              counters[block_type] += 1
              number = "#{chapter_number}-#{counters[block_type]}"

              # 自動IDの場合はIDを生成
              label_id = if caption_info[:auto]
                           "#{block_type}-#{chapter_number}-#{counters[block_type]}"
                         else
                           caption_info[:id]
                         end

              # Labelオブジェクトを作成
              label = Label.new(
                label_id,
                block_type,
                chapter_number,
                number,
                caption_info[:title],
                source_file,
                index + 1,
                caption_info[:auto]
              )

              labels << label
            end

            { labels: labels, errors: errors }
          end

          # キャプション行と直後のブロックをHTML化（図・表・コード）
          # @param content [String] 章のMarkdownテキスト
          # @param filename [String] ソースファイル名（画像パス正規化用）
          # @param labels_map [Hash<String, Label>] ラベルID → Label のマップ
          # @return [String] 変換後のコンテンツ
          def transform_captioned_blocks(content, filename, labels_map)
            lines = content.lines
            output = []
            i = 0
            in_code_block = false

            # 自動IDのカウンター（章ごとに各種別をカウント）
            auto_counters = { list: 0, table: 0, fig: 0 }

            while i < lines.size
              line = lines[i]

              stripped = line.lstrip

              if stripped.start_with?('```')
                in_code_block = !in_code_block
                output << line
                i += 1
                next
              end

              if in_code_block
                output << line
                i += 1
                next
              end

              caption_info = extract_caption_label(line)

              # キャプション行でない場合はそのまま出力
              unless caption_info
                output << line
                i += 1
                next
              end

              # キャプション行の場合、種別を判定
              block_type = detect_block_type(lines, i)
              unless block_type
                # 種別が不明な場合はそのまま出力（エラーは既にcollect_labelsで記録済み）
                output << line
                i += 1
                next
              end

              # 自動IDの場合はカウンターを増やしてIDを生成
              if caption_info[:auto]
                auto_counters[block_type] += 1
                chapter_num = extract_chapter_number(filename)
                generated_id = "#{block_type}-#{chapter_num}-#{auto_counters[block_type]}"
                label = labels_map[generated_id]
              else
                label = labels_map[caption_info[:id]]
              end

              # ブロックの開始位置を探す
              block_start = i + 1
              while block_start < lines.size && lines[block_start].strip.empty?
                block_start += 1
              end

              # ブロック種別に応じて処理
              case block_type
              when :fig
                html = transform_figure_block(lines, i, block_start, caption_info, label, filename)
                output << html
                i = find_block_end(lines, block_start, :fig) + 1

              when :table
                html = transform_table_block(lines, i, block_start, caption_info, label)
                output << html
                i = find_block_end(lines, block_start, :table) + 1

              when :list
                html = transform_code_block(lines, i, block_start, caption_info, label)
                output << html
                i = find_block_end(lines, block_start, :list) + 1

              else
                output << line
                i += 1
              end
            end

            output.join
          end

          # 図ブロックのHTML変換
          def transform_figure_block(lines, caption_index, block_start, caption_info, label, filename)
            # 画像行を取得（既に画像パス正規化済み）
            img_line = lines[block_start].strip
            
            # Markdown画像記法をHTMLに変換
            align_value = nil
            img_html = if img_line =~ /!\[(.*?)\]\((.*?)\)(?:\{([^}]+)\})?/
                         alt = Regexp.last_match(1)
                         src = Regexp.last_match(2)
                         attrs = Regexp.last_match(3)

                         # 属性を処理
                         style_parts = []
                         classes = []
                         if attrs
                           attrs.scan(/width=(\d+%)/) { |w| style_parts << "width: #{w[0]}" }
                           attrs.scan(/align=(left|center|right)/) { |a| align_value ||= a[0] }
                           attrs.scan(/\.([a-z\-]+)/) { |c| classes << c[0] }
                         end

                         class_attr = classes.any? ? " class=\"#{classes.join(' ')}\"" : ''
                         style_attr = style_parts.any? ? " style=\"#{style_parts.join('; ')}\"" : ''

                         "<img src=\"#{src}\" alt=\"#{alt}\"#{class_attr}#{style_attr}>"
                       else
                         img_line
                       end
            
            # キャプションテキストを生成
            caption_text = if label
                             "#{label.full_number}: #{caption_info[:title]}"
                           else
                             caption_info[:title]
                           end
            
            # figure要素として出力
            html = []
            figure_classes = ['cross-ref-figure']
            case align_value
            when 'center'
              figure_classes << 'cross-ref-align-center'
            when 'right'
              figure_classes << 'cross-ref-align-right'
            end
            html << "<figure class=\"#{figure_classes.join(' ')}\">"
            html << "  #{img_html}"
            html << "  <figcaption>#{caption_text}</figcaption>"
            html << '</figure>'
            html << ''
            html.join("\n")
          end

          # 表ブロックのHTML変換
          def transform_table_block(lines, caption_index, block_start, caption_info, label)
            # テーブル行を収集
            table_lines = []
            i = block_start
            while i < lines.size
              line = lines[i]
              break if line.strip.empty? || !line.include?('|')
              table_lines << line
              i += 1
            end

            # Markdownテーブルを結合してKramdownで変換
            table_md = table_lines.join
            table_html = render_markdown_to_html(table_md).strip

            # キャプションテキストを生成
            caption_text = if label
                             "#{label.full_number}: #{caption_info[:title]}"
                           else
                             caption_info[:title]
                           end

            # tableタグをキャプション付きで包む
            html = []
            html << '<div class="cross-ref-table">'
            html << "  <p class=\"table-caption\">#{caption_text}</p>"
            html << "  #{table_html}"
            html << '</div>'
            html << ''
            html.join("\n")
          end

          # コードブロックのHTML変換
          def transform_code_block(lines, caption_index, block_start, caption_info, label)
            # コードブロックを収集
            i = block_start
            
            # 開始行（```）から言語を取得
            first_line = lines[i] || ''
            # ```lang や ```lang:filename のような形式を想定し、言語部分のみ抽出
            lang_match = first_line.to_s.match(/```([a-zA-Z0-9_\-]+)?/)
            language = (lang_match && lang_match[1]).to_s
            i += 1

            # コードの内容を収集（終了の```まで）
            code_content = []
            while i < lines.size
              line = lines[i]
              break if line.strip.start_with?('```')
              code_content << line
              i += 1
            end

            # コードをHTMLエスケープ
            escaped_code = code_content.join.gsub('&', '&amp;')
                                            .gsub('<', '&lt;')
                                            .gsub('>', '&gt;')

            # キャプションテキストを生成
            caption_text = if label
                             "#{label.full_number}: #{caption_info[:title]}"
                           else
                             caption_info[:title]
                           end

            # 言語クラスを設定
            lang_class = language.empty? ? '' : " class=\"language-#{language}\""

            # コードブロックをキャプション付きで包む
            html = []
            html << '<div class="cross-ref-list">'
            html << "  <p class=\"code-caption\">#{caption_text}</p>"
            html << "  <pre><code#{lang_class}>#{escaped_code}</code></pre>"
            html << '</div>'
            html << ''
            html.join("\n")
          end

          # ブロックの終了位置を探す
          def find_block_end(lines, start_index, block_type)
            case block_type
            when :fig
              # 画像は1行で終了
              start_index
            when :table
              # テーブルは | を含む行が続く限り
              i = start_index
              while i < lines.size && lines[i].include?('|')
                i += 1
              end
              i - 1
            when :list
              # コードブロックは ``` で終了
              i = start_index + 1
              while i < lines.size
                return i if lines[i].strip.start_with?('```')
                i += 1
              end
              i - 1
            else
              start_index
            end
          end

          # 本文中の @id を番号付きリンクに置換
          # @param content [String] 章のMarkdownテキスト
          # @param labels_map [Hash<String, Label>] ラベルID → Label のマップ
          # @param filename [String, nil] ログ用のファイル名
          # @return [Hash] { content: String, errors: Array<String> }
          def replace_references(content, labels_map, filename = nil)
            errors = []
            in_code_block = false

            processed_lines = []

            content.lines.each_with_index do |line, idx|
              line_number = idx + 1
              stripped = line.lstrip

              # フェンス付きコードブロック (``` ～ ``` ) 内はそのまま残す
              if stripped.start_with?('```')
                in_code_block = !in_code_block
                processed_lines << line
              elsif in_code_block
                processed_lines << line
              else
                processed_lines << replace_references_in_line(line, labels_map, errors, filename, line_number)
              end
            end

            { content: processed_lines.join, errors: errors }
          end

          # 1行分のテキストについて、インラインコード（`...` や <code>...</code>）の外側だけ @id を置換する
          def replace_references_in_line(line, labels_map, errors, filename = nil, line_number = nil)
            # まず HTML の <code>...</code> セグメントをコードとして扱い、それ以外の部分だけを処理する
            parts = line.split(/(<code[^>]*>.*?<\/code>)/)

            parts.map! do |part|
              # <code>...</code> はそのまま残す
              if part.start_with?('<code')
                next part
              end

              # `code` や ``code`` など、バッククォートで囲まれた部分を保持しつつ、それ以外だけを変換する
              segments = part.scan(/`+[^`]*`+|[^`]+/)

              segments.map! do |segment|
                # バッククォートで囲まれた部分はインラインコードとしてそのまま残す
                if segment.start_with?('`')
                  next segment
                end

                segment.gsub(/@([a-zA-Z0-9_\-]+)/) do
                  label_id = Regexp.last_match(1)
                  label = labels_map[label_id]

                  if label
                    # ラベルが存在する場合、番号付きテキストに置換
                    # 例: リスト 4-1, 表 3-2, 図 1-5
                    label.full_number
                  else
                    # 未定義の場合はエラーとして記録
                    location = if filename && line_number
                                 "#{filename}:#{line_number}"
                               elsif line_number
                                 "行#{line_number}"
                               else
                                 '(位置情報なし)'
                               end
                    errors << "#{location} - 未定義のラベルID: @#{label_id}"
                    "@#{label_id}" # そのまま残す
                  end
                end
              end

              segments.join
            end

            parts.join
          end

          # 複数章のラベルを統合し、重複チェックを行う
          # @param all_labels [Array<Label>] 全章から収集したラベルの配列
          # @return [Hash] { labels_map: Hash, duplicates: Array<String> }
          def build_labels_map_with_duplicates_check(all_labels)
            labels_map = {}
            duplicates = []

            all_labels.each do |label|
              if labels_map.key?(label.id)
                # 重複を検出
                existing = labels_map[label.id]
                duplicates << "ラベルID '@#{label.id}' が重複しています:\n" \
                              "  - #{existing.source_file}:#{existing.line}\n" \
                              "  - #{label.source_file}:#{label.line}"
              else
                labels_map[label.id] = label
              end
            end

            { labels_map: labels_map, duplicates: duplicates }
          end

          # ID一覧レポートを生成
          # @param all_labels [Array<Label>] 全ラベルの配列
          # @return [String] レポート文字列（Markdown形式）
          def generate_cross_reference_report(all_labels)
            report = ["# Cross Reference Map\n"]

            # ファイルごとにグルーピング
            labels_by_file = all_labels.group_by(&:source_file)

            labels_by_file.each do |file, labels|
              report << "\n- #{file}"
              labels.each do |label|
                mode = label.auto ? 'auto' : 'manual'
                report << "  - @#{label.id.ljust(30)} (#{label.full_number.ljust(12)}, #{mode.ljust(6)}) 「#{label.title}」"
              end
            end

            report.join("\n")
          end

          # クロスリファレンス処理のメインエントリーポイント
          # @param chapters [Hash] { filename => content } の形式
          # @return [Hash] { chapters: Hash, report: String, errors: Array<String> }
          def process_cross_references(chapters)
            all_labels = []
            all_errors = []
            processed_chapters = {}

            # Phase 1: 全章からラベル定義を収集
            Common.log_info('Phase 1: ラベル定義を収集中...')
            chapters.each do |filename, content|
              chapter_number = extract_chapter_number(filename)
              result = collect_labels(content, filename, chapter_number)

              all_labels.concat(result[:labels])
              all_errors.concat(result[:errors])

              Common.log_info("  #{filename}: #{result[:labels].size}個のラベルを検出")
            end

            # Phase 2: ラベルマップを構築し、重複をチェック
            Common.log_info('Phase 2: ラベルマップ構築と重複チェック...')
            map_result = build_labels_map_with_duplicates_check(all_labels)
            labels_map = map_result[:labels_map]
            duplicates = map_result[:duplicates]

            if duplicates.any?
              Common.log_error("ラベルIDの重複を検出しました:")
              duplicates.each { |dup| Common.log_error(dup) }
              all_errors.concat(duplicates)
            end

            # Phase 3: キャプション付きブロックをHTML化
            Common.log_info('Phase 3: キャプション付きブロックをHTML化中...')
            chapters.each do |filename, content|
              transformed = transform_captioned_blocks(content, filename, labels_map)
              processed_chapters[filename] = transformed
            end

            # Phase 4: 本文中の @id を置換
            Common.log_info('Phase 4: 本文中の @id 参照を置換中...')
            processed_chapters.each do |filename, content|
              result = replace_references(content, labels_map, filename)
              processed_chapters[filename] = result[:content]
              all_errors.concat(result[:errors])

              if result[:errors].any?
                Common.log_warn("  #{filename}: #{result[:errors].size}個の未定義参照を検出")
                result[:errors].each do |msg|
                  Common.log_warn("    - #{msg}")
                end
              end
            end

            # Phase 5: レポート生成
            report = generate_cross_reference_report(all_labels)

            # 結果を返す
            {
              chapters: processed_chapters,
              report: report,
              errors: all_errors,
              labels_count: all_labels.size
            }
          end
        end
      end
    end
  end
end
