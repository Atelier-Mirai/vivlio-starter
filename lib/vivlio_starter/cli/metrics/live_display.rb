# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Metrics
      # 章別分量のライブ表示を制御する
      #
      # `vs metrics` の並列解析中、最初にキャッシュ由来のプレースホルダ行を
      # 一覧表示しておき、章ごとの解析が完了するたびに該当行だけを
      # ANSI エスケープで書き換える。解析の進捗が行単位で見えるため、
      # 章数が多い書籍でも「固まっている」ように見えない。
      class LiveDisplay
        # 解析完了時に placeholder → analysis へ中身を差し替えるため、
        # 不変の Data ではなく可変の Struct を使う
        Entry = Struct.new(:path, :placeholder, :analysis, keyword_init: true)

        # カーソル行全体を消去する ANSI エスケープシーケンス
        CLEAR_LINE = "\e[2K"

        # @param placeholders [Array] キャッシュ由来の章情報（解析完了までの仮表示）
        # @param formatter [Formatter] 章行の整形を委譲する
        # @param show_sections [Boolean] 節単位の内訳も表示するか
        def initialize(placeholders:, formatter:, show_sections: false)
          @formatter = formatter
          @show_sections = show_sections
          @entries = placeholders.map do |placeholder|
            Entry.new(path: placeholder.path, placeholder:, analysis: nil)
          end
          @path_index = @entries.each_with_index.to_h { |entry, index| [entry.path, index] }
          @rendered = false
          @finalized = false
          @line_count = 0
          @current_lines = []
        end

        # 全章分のプレースホルダ行を初回表示する（2回目以降の呼び出しは無視）
        def render_initial
          return if @rendered

          @current_lines = build_lines
          @line_count = @current_lines.size
          @current_lines.each { puts it }
          @rendered = true
        end

        # 1章分の解析完了を受けて該当行を確定表示に差し替える
        # 文字数の最大値が変わるとバーの縮尺も変わるため、全行を再描画する
        def update_analysis(path, analysis)
          return unless @rendered
          return if @finalized

          idx = @path_index[path]
          return unless idx

          entry = @entries[idx]
          entry.analysis = analysis
          entry.placeholder = nil
          redraw
        end

        # 全章の解析結果で表示を確定する
        # 解析対象外の章が除外されることがあるため、行の構成自体を作り直す
        def render_final(analyses)
          @finalized = true
          @entries = analyses.map do |analysis|
            Entry.new(path: analysis.chapter.path, placeholder: nil, analysis:)
          end
          @path_index = @entries.each_with_index.to_h { |entry, index| [entry.path, index] }

          if @entries.empty?
            render_empty
          elsif @rendered
            redraw
          else
            @current_lines = build_lines
            @line_count = @current_lines.size
            @current_lines.each { puts it }
            @rendered = true
          end
        end

        # 対象章ゼロの場合の表示（既存のプレースホルダ表示は消去する）
        def render_empty
          clear_block if @rendered

          puts '（対象章がありません）'
          @line_count = 1
          @rendered = true
        end

        private

        attr_reader :formatter, :show_sections, :entries, :line_count

        # 最新の entries 状態で表示ブロック全体を書き換える
        def redraw
          return unless @rendered

          @current_lines = build_lines
          refresh_block(@current_lines)
        end

        # 各章を「確定行（解析済み）」または「プレースホルダ行」として整形する
        def build_lines
          max_chars = compute_max_chars
          entries.map do |entry|
            if entry.analysis
              formatter.format_chapter_line(entry.analysis.chapter, max_chars, show_sections)
            else
              format_placeholder_line(entry.placeholder)
            end
          end
        end

        # バー表示の縮尺基準となる最大文字数を求める（ゼロ除算回避のため最低 1）
        def compute_max_chars
          values = entries.map do |entry|
            if entry.analysis
              entry.analysis.chapter.chars
            elsif entry.placeholder
              entry.placeholder.chars
            else
              0
            end
          end

          values.compact.max || 1
        end

        # 表示済みブロックの先頭までカーソルを戻し、新しい行で上書きする
        # 行数が減った場合も古い行が残らないよう、多い方の行数だけ消去する
        def refresh_block(lines)
          move_cursor_up(@line_count) if @line_count.positive?
          max_lines = [@line_count, lines.size].max

          max_lines.times do |idx|
            clear_current_line
            text = lines[idx]
            puts text || ''
          end

          @line_count = lines.size
        end

        # 表示済みブロックを空行で塗り潰して消去する
        def clear_block
          move_cursor_up(@line_count) if @line_count.positive?
          @line_count.times do
            clear_current_line
            puts ''
          end
          @line_count = 0
        end

        def move_cursor_up(lines)
          return if lines <= 0

          print "\e[#{lines}A"
        end

        def clear_current_line
          print "\r"
          print CLEAR_LINE
        end

        # 解析待ちの章を「第NN章 タイトル ... N 文字」形式で仮表示する
        def format_placeholder_line(placeholder)
          label = placeholder_label(placeholder)
          padded = pad_label(label)
          "#{padded} ... #{number_with_comma(placeholder.chars)} 文字"
        end

        def placeholder_label(placeholder)
          num = format('%02d', placeholder.chapter_num)
          "第#{num}章 #{placeholder.title}"
        end

        def pad_label(text)
          truncate_label(text).ljust(Formatter::CHAPTER_LABEL_WIDTH)
        end

        # 確定行（Formatter 側）と桁が揃うよう、長いタイトルは省略記号付きで切り詰める
        def truncate_label(text)
          width = Formatter::CHAPTER_LABEL_WIDTH
          return text if text.length <= width

          "#{text.each_char.take(width - 1).join}…"
        end

        # 3桁区切りのカンマを付与する（例: 12345 → "12,345"）
        def number_with_comma(num)
          num.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
        end
      end
    end
  end
end
