# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/markdown_transformer.rb
# ================================================================
# 責務:
#   Markdown の特殊記法を変換し、コードブロックの処理を行う。
#
# 変換処理:
#   - コードインクルード: ```ruby:codes/sample.rb → ファイル内容を埋め込み
#   - book-card: :::book-card → 書籍紹介カード HTML
#   - table-rotate: :::table-rotate → 90度回転テーブル
#   - リンク脚注化: [text](url) → text[^n] + 脚注定義
#
# コードブロック:
#   - 言語指定から Prism.js クラスを生成
#   - 行番号表示用の data-line 属性を付与
#   - ファイル名表示用のヘッダーを生成
#
# 依存:
#   - Common: 設定読み込み・ログ出力
#   - MarkdownUtils: 共通ユーティリティ
#   - CrossReferenceProcessor: クロスリファレンス処理
# ================================================================

require_relative '../common'
require_relative 'markdown_utils'
require_relative 'cross_reference_processor'
require_relative 'link_image_validator'

module VivlioStarter
  module CLI
    module PreProcessCommands
      # Markdown 特殊記法変換モジュール
      module MarkdownTransformer
        module_function

        # Markdown内のリンク記法を脚注化
        def transform_links_to_footnotes(md_text)
          original = md_text.to_s
          text, code_spans = MarkdownUtils.extract_code_spans(original)

          max_n = 0
          text.scan(/\[\^url(\d+)\]:/).each do |m|
            n = m[0].to_i
            max_n = n if n > max_n
          end

          url_id = {}
          replacements = []

          replaced = text.gsub(/(?<!!)\[(.+?)\]\((https?:[^\s)]+)\)(?!\s*\[^url\d+\])/) do |_match|
            label = ::Regexp.last_match(1)
            url   = ::Regexp.last_match(2)
            id = (url_id[url] ||= begin
              max_n += 1
              "url#{max_n}"
            end)
            replacements << [id, url]
            "[#{label}](#{url}) [^#{id}]"
          end

          existing_defs = {}
          text.scan(/\[\^(url\d+)\]:\s*(\S+)/) { |id, u| existing_defs[id] = u }

          new_defs = url_id.filter_map do |u, id|
            next nil if existing_defs.key?(id)

            "[^#{id}]: #{u}"
          end

          result = if new_defs.empty?
                     replaced
                   elsif replaced.strip.end_with?("\n")
                     "#{replaced}\n#{new_defs.join("\n")}\n"
                   else
                     "#{replaced}\n\n#{new_defs.join("\n")}\n"
                   end

          MarkdownUtils.restore_code_spans(result, code_spans)
        end

        # book-card 内のMarkdownを事前整形
        def normalize_book_card_md(md_text)
          lines = md_text.to_s.split(/\r?\n/, -1)
          out = []
          lines.each_with_index do |line, i|
            out << line
            next_line = lines[i + 1]

            if line.match(/^\s*!\[[^\]]*\]\([^)]+\)\s*$/)
              out << '' if next_line && next_line.strip != ''
            elsif line.match(/^\s*\*\*[^*].*\*\*\s*$/)
              out << '' if next_line && next_line.strip != ''
            end
          end
          out.join("\n")
        end

        # <div class="book-card"> ... </div> の内側MarkdownをHTMLへ
        def convert_book_card_inner_markdown(content)
          content.gsub(%r{<div class="book-card">\n(.*?)\n</div>}m) do
            inner = ::Regexp.last_match(1)
            normalized = normalize_book_card_md(inner)
            html = MarkdownUtils.render_markdown_to_html(normalized)
            formatted = format_book_card_inner_html(html)
            "<div class=\"book-card\">\n#{formatted}\n</div>"
          end
        end

        # <div ... class="... table-rotate ..." ...> ... </div> の内側MarkdownをHTMLへ
        def convert_table_rotate_inner_markdown(content)
          convert_table_container_inner_markdown(content, 'table-rotate')
        end

        # <div ... class="... CLASS ..." ...> ... </div> の内側パイプテーブルをHTMLへ変換する汎用メソッド
        def convert_table_container_inner_markdown(content, class_name)
          content.gsub(%r{<div\s+([^>]*\bclass="[^"]*\b#{Regexp.escape(class_name)}\b[^"]*"[^>]*)>\s*(.*?)\s*</div>}m) do
            attrs = ::Regexp.last_match(1)
            inner = ::Regexp.last_match(2)

            normalized = "\n\n#{inner.to_s.strip}\n\n"
            html = MarkdownUtils.render_markdown_to_html(normalized).to_s.strip

            if !html.include?('<table') && inner.include?('|')
              table_html = MarkdownUtils.pipe_table_to_html(inner)
              html = table_html if table_html
            end

            "<div #{attrs}>\n#{html}\n</div>"
          end
        end

        # book-card の内側を整形
        def format_book_card_inner_html(inner_html)
          html = inner_html.to_s.strip

          img_match = html.match(/<img[^>]*>/i)
          return inner_html unless img_match

          img_tag = img_match[0].gsub(%r{\s*/?>}i) { '>' }

          if html.sub!(%r{<p>\s*#{Regexp.escape(img_match[0])}\s*</p>}i, '')
            # removed wrapped <p> with img
          else
            html.sub!(img_match[0], '')
          end

          title_match = html.match(%r{<p>\s*<strong>(.*?)</strong>\s*</p>}im)
          return inner_html unless title_match

          title_text = title_match[1].strip
          html.sub!(title_match[0], '')

          description_html = html.strip

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

        # ::: {.class ...} 記法で囲まれたコンテナを div に変換。
        # コードブロック内の ::: 記法は変換対象外とする。
        def convert_container_blocks(content, class_name:)
          opened_count = 0
          closed_count = 0

          # --- Phase: コードブロック退避 ---
          protected_text, spans = MarkdownUtils.extract_code_spans(content)

          pattern = /:::\s*\{\.([^}]+)\}\s*\n(.*?)\n:::\s*(?:\n|$)/m

          converted = protected_text.gsub(pattern) do
            raw_token_str = ::Regexp.last_match(1)
            inner         = ::Regexp.last_match(2)

            raw_tokens = raw_token_str.split
            first_class = raw_tokens.first
            additional_tokens = raw_tokens.drop(1)
            additional_classes = additional_tokens.select { |t| t.start_with?('.') }.map { |c| c.delete_prefix('.') }
            param_tokens = additional_tokens.reject { |t| t.start_with?('.') }

            next ::Regexp.last_match(0) unless first_class == class_name || additional_classes.include?(class_name)

            opened_count += 1
            closed_count += 1

            all_classes = [first_class] + additional_classes
            class_attr = all_classes.join(' ')

            style_parts = []
            param_tokens.each do |token|
              if (m_scale = token.match(/^scale=(.+)$/))
                raw = m_scale[1].strip
                scale_percent = raw.end_with?('%') ? raw.to_f : raw.to_f * 100.0
                scale_int = scale_percent.round
                style_parts << "--table-rotate-scale:#{scale_int}%;"
              end

              next unless (m_shift = token.match(/^shift-y=(.+)$/))

              raw = m_shift[1].strip
              shift_percent = raw.end_with?('%') ? raw.to_f : raw.to_f * 100.0
              shift_int = shift_percent.round
              sign = shift_int.negative? ? '' : '+'
              style_parts << "--table-rotate-shift-y:#{sign}#{shift_int}%;"
            end

            style_attr = style_parts.empty? ? '' : " style=\"#{style_parts.join(' ')}\""

            "<div class=\"#{class_attr}\"#{style_attr}>\n#{inner}\n</div>\n\n"
          end

          # --- Phase: コードブロック復元 ---
          converted = MarkdownUtils.restore_code_spans(converted, spans)

          [converted, opened_count, closed_count]
        end

        # 標準 Markdown（pandoc / Markdown Extra 風）の定義リスト記法を <dl> に変換する。
        #   用語           ← <dt>
        #   : 説明         ← <dd>（複数並べれば複数 <dd>）
        #     続き行       ← 直前 <dd> の続き（半角スペース字下げ）
        # VFM は定義リストに未対応なので、検出ブロックを Kramdown でレンダリングして
        # <dl class="def-list"> を生成する（class は索引/奥付の <dl> と衝突させないため）。
        # 著者は空行なしのコンパクトな形でも書け、内部でエントリ間に空行を補ってから
        # Kramdown に渡す。インラインコード `...` 等のインライン装飾は Kramdown が処理する。
        # コードフェンス（``` 可変長）内は対象外。
        def convert_definition_lists(content)
          lines = content.lines
          out = []
          i = 0
          fence_len = nil
          while i < lines.size
            line = lines[i]
            stripped = line.lstrip
            if stripped.start_with?('```')
              run = stripped[/\A`+/].length
              if fence_len.nil? then fence_len = run
              elsif run >= fence_len then fence_len = nil
              end
              out << line
              i += 1
            elsif fence_len.nil? && definition_list_start?(lines, i)
              j = definition_list_end(lines, i)
              out << render_definition_list(lines[i...j].join)
              i = j
            else
              out << line
              i += 1
            end
          end
          out.join
        end

        # 用語行: 行頭から始まる非空行で、定義行（: ）・継続行（字下げ）・他のブロック構文でないもの
        def definition_term_line?(line)
          s = line.to_s.chomp
          return false if s.strip.empty?
          return false if s.start_with?(' ', "\t") # 字下げ＝継続行
          return false if s.match?(/\A:[ \t]/)      # 定義行
          # 見出し / 引用 / 表 / コンテナ / フェンス / 生HTML / 箇条書き・番号リストは用語にしない
          return false if s.match?(%r{\A(\#|>|\||:::|```|<|[-*+][ \t]|\d+[.)][ \t])})

          true
        end

        # 定義行: 行頭が「: 」（コロン＋空白）で内容が続くもの
        def definition_def_line?(line)
          line.to_s.match?(/\A:[ \t]+\S/)
        end

        # 継続行: 字下げされた非空行（直前の定義の続き）
        def definition_continuation_line?(line)
          return false if line.to_s.strip.empty?

          line.to_s.start_with?(' ', "\t")
        end

        # 用語行の直後が定義行なら、定義リストの開始
        def definition_list_start?(lines, idx)
          return false unless definition_term_line?(lines[idx])

          definition_def_line?(lines[idx + 1])
        end

        # 定義リストブロックの終端（排他的 index）を返す。
        # 定義/継続/（定義が続く）用語/内部空行（ルーズ形式の区切り）を取り込む。
        def definition_list_end(lines, idx)
          j = idx
          while j < lines.size
            line = lines[j]
            if definition_def_line?(line) || definition_continuation_line?(line)
              j += 1
            elsif definition_term_line?(line) && definition_def_line?(lines[j + 1])
              j += 1
            elsif line.to_s.strip.empty? && definition_list_start?(lines, j + 1)
              j += 1
            else
              break
            end
          end
          j
        end

        # 定義リストブロックを Kramdown で <dl> 化する。
        # Kramdown はエントリ間に空行を要求するため、用語行の前へ空行を補ってから渡す。
        # また本書全体の hardLineBreaks: true（改行＝<br>）に揃えるため、説明（dd）内の
        # 各行末へ Markdown のハード改行（半角スペース2つ）を補い、複数行の説明が
        # <br> で改行されるようにする（空行＝エントリ区切りはそのまま残す）。
        def render_definition_list(block)
          normalized = []
          block.lines.each do |line|
            normalized << "\n" if definition_term_line?(line) && !normalized.empty? && !normalized.last.strip.empty?
            normalized << hard_break_line(line)
          end
          html = MarkdownUtils.render_markdown_to_html(normalized.join).strip
          html = html.sub(/\A<dl>/, '<dl class="def-list">')
          "#{html}\n\n"
        end

        # 非空行の末尾を Markdown のハード改行（半角スペース2つ）へ正規化する。
        # 既存の末尾空白は一度除いてから2つに揃えるため冪等。空行はそのまま返す。
        def hard_break_line(line)
          return line if line.strip.empty?

          "#{line.chomp.sub(/[ \t]+\z/, '')}  \n"
        end

        # 単独行の {.aki} / {.aki2} を縦余白マクロ @vspace に置換する。
        # {.aki} は本来「段落末に付けて段落へ class を与える」インライン記法のため、
        # それ自身だけを 1 行に書くと（付与先の本文が無いので）VFM が "{.aki}" を
        # そのまま文字として出力してしまう。空行用途（<br> のように 1 行空ける）で
        # 書かれた単独行は @vspace:1lh（aki2 は 2lh）へ置き換え、独立段落となるよう
        # 直後に空行を補う。段落末に付いた {.aki} は対象外（post_replace でクラス化）。
        # コードフェンス内は対象外。
        def convert_standalone_spacing(content)
          lines = content.lines
          fence = nil
          out = []
          lines.each_with_index do |line, i|
            stripped = line.lstrip
            if stripped.start_with?('```', '~~~')
              marker = stripped[/\A([`~]+)/, 1]
              if fence.nil? then fence = marker
              elsif stripped.start_with?(fence) then fence = nil
              end
              out << line
              next
            end
            m = fence.nil? && line.strip.match(/\A\{\.(aki2?)\}\z/)
            prev_blank = out.empty? || out.last.strip.empty?
            if m && prev_blank
              out << "@vspace:#{m[1] == 'aki2' ? 2 : 1}lh\n"
              next_line = lines[i + 1]
              out << "\n" unless next_line.nil? || next_line.strip.empty?
            else
              out << line
            end
          end
          out.join
        end

        # :::{.class} コンテナの開始行直後・終了行直前に空行を補い、開始/終了行を独立段落にする。
        # VFM は hardLineBreaks のため、空行が無いと開始 ":::{.output}" 行を直後の本文行と
        # 1 つの <p> に結合してしまう。その状態で post_replace が ":::{.class}" を <div> へ
        # 置換すると <p> が分割され、先頭の本文（クロスリファレンスのキャプション <strong> 等）が
        # コンテナ直下に取り残されて wrap されず、見出しが素の強調表示になる不具合が起きる。
        # 開始直後・終了直前に空行を挟むことで、内側の各ブロックが独立段落になり正しく整形される。
        # コードフェンス内の ::: は対象外。既に空行がある場合は二重に入れない。
        def normalize_container_fence_spacing(content)
          lines = content.lines
          fence = nil
          out = []
          lines.each_with_index do |line, i|
            stripped = line.lstrip
            if stripped.start_with?('```', '~~~')
              marker = stripped[/\A([`~]+)/, 1]
              if fence.nil? then fence = marker
              elsif stripped.start_with?(fence) then fence = nil
              end
              out << line
              next
            end

            if fence.nil? && stripped.match?(/\A:{3,}\s*\{/) # 開始 :::{.class}
              out << line
              nxt = lines[i + 1]
              out << "\n" if nxt && !nxt.strip.empty?
            elsif fence.nil? && line.strip.match?(/\A:{3,}\z/) # 終了 :::
              out << "\n" unless out.empty? || out.last.strip.empty?
              out << line
            else
              out << line
            end
          end
          out.join
        end

        # インラインコード内の HTML 予約文字をエスケープする
        def escape_inline_code_html(line)
          MarkdownUtils.escape_inline_code_html(line)
        end

        # ```include:path[:start-end]``` を検出し、codes/ または絶対パスから読込。
        # マークダウンのコードブロックおよびインラインコード内に記述された
        # include 記法は記法の説明例であるためスキップする。
        # @param content [String] 処理対象の Markdown テキスト
        # @param source_filename [String, nil] エラーメッセージに表示するソースファイル名
        # @param source_path [String, nil] 元ファイルのパス（行番号補正用）
        def process_code_include(content, source_filename: nil, source_path: nil)
          matches_found = 0
          line_number_map = build_line_number_map(content)
          occurrence = Hash.new(0)
          skippable_lines = lines_inside_code_blocks(content)
          inline_code_lines = lines_with_inline_code_include(content)
          source_line_map = build_source_include_line_map(source_path)

          content.gsub!(/```include:([^:`\s]+)(?::(\d+)-(\d+))?\s*```/) do |match|
            # 同一 include 文字列が複数回現れても行番号を取り違えないよう、出現順に
            # 対応する行番号を消費する（例: 記法説明フェンス内の例文と、:::{.output} 等に
            # 置いた本物の include が同一文字列のとき、前者の行番号で後者まで誤スキップするのを防ぐ）。
            # ln=前処理後コンテンツ内の行（スキップ判定用）、report_ln=著者向けに原稿ファイルの行を優先。
            idx = occurrence[match]
            occurrence[match] += 1
            ln = line_number_map[match][idx]
            report_ln = source_line_map[match][idx] || ln

            # コードブロック内の include 記法はスキップ（記法説明用の例文）
            next match if ln && skippable_lines.include?(ln)

            # インラインコード内の include 記法はスキップ
            # `` ```include:file.rb``` `` のようにバッククォートで囲まれた場合
            next match if ln && inline_code_lines.include?(ln)

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

              code_content =
                if start_line && end_line
                  selected_lines = extract_line_range(lines, start_line, end_line)
                  warn_prefix = "#{source_filename || '(不明)'}#{report_ln ? ":#{report_ln}" : ''} - "
                  if selected_lines.nil?
                    # 開始行がファイル末尾を超える／逆順など、救済不能な不正指定。全文取り込みへフォールバック。
                    Common.log_warn(
                      "#{warn_prefix}include の範囲指定が不正です" \
                      "（#{original_path} は #{lines.size} 行、指定は #{start_line}-#{end_line}）。全文を取り込みます。"
                    )
                    "#{source_content}\n"
                  else
                    # 開始は有効で終了だけがファイル末尾を超える場合は、末尾までにクランプして取り込む。
                    if end_line > lines.size
                      Common.log_warn(
                        "#{warn_prefix}include の終了行がファイル末尾を超えています" \
                        "（#{original_path} は #{lines.size} 行、指定は #{start_line}-#{end_line}）。" \
                        "#{start_line}-#{lines.size} 行を取り込みます。"
                      )
                    end
                    selected_lines.join
                  end
                else
                  "#{source_content}\n"
                end

              language = MarkdownUtils.detect_language(file_path)
              replacement = "```#{language}:#{original_path}\n#{code_content}```"
              Common.log_success("置換完了: #{original_path} (#{language})")

              replacement
            else
              code_name = File.basename(original_path)
              # 元ファイルの行番号があればそちらを使う
              source_ln = report_ln
              if source_filename && source_ln
                Common.log_error(
                  "#{source_filename}:#{source_ln} - ソースコード '#{code_name}' が見つかりません",
                  detail: "コードの場所: #{file_path}"
                )
                LinkImageValidator.record_code_include_error(source_filename, source_ln, code_name)
              else
                Common.log_error(
                  "ソースコード '#{code_name}' が見つかりません",
                  detail: "コードの場所: #{file_path}"
                )
                LinkImageValidator.record_code_include_error(source_filename || '(不明)', 0, code_name)
              end
              match
            end
          end

          Common.log_info("#{matches_found}個のinclude記法を処理") if matches_found.positive?
          content
        end

        # content 内の各 include 記法マッチ文字列 → 行番号のマップを構築する
        # 1 始まりの行範囲 [start_line, end_line] の行配列を返す。
        # 終了行がファイル末尾を超える場合はファイル末尾までにクランプする（開始が有効な限り取り込む）。
        # 開始行がファイル末尾を超える・開始 < 1・逆順（end < start）のように救済不能な場合は nil を返し、
        # 呼び出し側は全文取り込みへフォールバックする（lines[(s-1)..(e-1)] は範囲外で nil を返し
        # `nil.join` で落ちるため、ここで明示的に弾く）。
        def extract_line_range(lines, start_line, end_line)
          return nil if start_line < 1 || end_line < start_line
          return nil if start_line > lines.size

          effective_end = [end_line, lines.size].min
          lines[(start_line - 1)..(effective_end - 1)]
        end

        # include 文字列 → その文字列が出現する行番号の配列（出現順）。
        # 同一文字列が複数行に現れても各出現を取りこぼさないよう配列で保持する。
        def build_line_number_map(content)
          map = Hash.new { |h, k| h[k] = [] }
          content.lines.each_with_index do |line, idx|
            line.scan(/```include:[^`\s]+(?::\d+-\d+)?\s*```/) do |match|
              map[match] << (idx + 1)
            end
          end
          map
        end
        private_class_method :build_line_number_map

        # インラインコード内に include 記法を含む行番号の Set を返す。
        # `` ```include:file.rb``` `` のようにバッククォートで囲まれた場合を検出する。
        def lines_with_inline_code_include(content)
          result = Set.new
          content.lines.each_with_index do |line, idx|
            # 行がフェンス開始/終了でない場合のみチェック
            stripped = line.lstrip
            next if stripped.match?(/\A`{3,}/)

            # インラインコード内に include 記法があるか
            # `` `...```include:file.rb```...` `` のパターンを検出
            if line.match?(/`[^`]*```include:[^`\s]+(?::\d+-\d+)?\s*```[^`]*`/)
              result << (idx + 1)
            end
          end
          result
        end
        private_class_method :lines_with_inline_code_include

        # 元ファイルから include 記法のパス → 行番号のマップを構築する。
        # pre_process で行数が変わる前の正しい行番号を取得するため。
        # include 文字列 → 原稿ファイル（前処理前）での出現行番号の配列（出現順）。
        # build_line_number_map（前処理後コンテンツ）と同じフルマッチ文字列キー・全出現走査にして
        # 出現インデックスを一致させ、同一文字列・同一パスが複数回現れても取り違えないようにする。
        # 著者向けメッセージは前処理でずれる前処理後の行ではなく、この原稿ファイルの行を優先する。
        def build_source_include_line_map(source_path)
          map = Hash.new { |h, k| h[k] = [] }
          return map unless source_path && File.exist?(source_path)

          File.readlines(source_path, encoding: 'utf-8').each_with_index do |line, idx|
            line.scan(/```include:[^`\s]+(?::\d+-\d+)?\s*```/) do |match|
              map[match] << (idx + 1)
            end
          end
          map
        end
        private_class_method :build_source_include_line_map

        # マークダウンのコードブロック内にある行番号の Set を返す。
        # ```include: で始まる行はコードブロックの開閉トグルとみなさない
        # （実際の include 記法であるため）。
        def lines_inside_code_blocks(content)
          inside = Set.new
          in_code = false
          fence_marker = nil

          content.lines.each_with_index do |line, idx|
            stripped = line.lstrip
            if (m = stripped.match(/\A(`{3,})/)) && !stripped.start_with?('```include:')
              fence = m[1]
              if in_code
                if fence.length >= fence_marker.length
                  in_code = false
                  fence_marker = nil
                end
              else
                in_code = true
                fence_marker = fence
              end
              next
            end

            inside << (idx + 1) if in_code
          end

          inside
        end
        private_class_method :lines_inside_code_blocks
      end
    end
  end
end
