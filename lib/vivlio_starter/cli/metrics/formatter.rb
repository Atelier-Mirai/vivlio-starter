# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/metrics/formatter.rb
# ================================================================
# 責務:
#   メトリクス分析結果を仕様に沿った形式で出力する。
#
# 機能:
#   - 基本統計・詳細分析・章別分量のフォーマット
#   - 棒グラフの描画
#   - 警告ラベルの付与
# ================================================================

module VivlioStarter
  module CLI
    module Metrics
      # メトリクス出力フォーマッタ
      class Formatter
        BAR_WIDTH = 12
        BAR_CHAR = '#'
        BAR_EMPTY_CHAR = '.'
        CHAPTER_LABEL_WIDTH = 30
        SECTION_LABEL_WIDTH = 36
        CHAR_COUNT_WIDTH = 6

        # 「表現が単調」と評価する MATTR の上限（この値以下が単調帯）。
        # 詳細分析の表示（#mattr_evaluation）と章別リストの品質警告
        # （WarningChecker#quality_warnings）が同じ値を参照することで、
        # 「詳細では単調と出るのに警告は出ない」という乖離を構造的に防ぐ。
        MATTR_MONOTONOUS_MAX = 0.5

        def initialize(config_loader)
          @config = config_loader
          @vocabulary = config_loader.vocabulary_thresholds
          @labels = config_loader.labels
        end

        # 章別リスト直後の集計行（合計章数・平均文字数）を生成する。
        def format_chapter_count_summary(count, total_chars)
          avg = count.positive? ? (total_chars.to_f / count).round : 0
          "📚 合計 #{count} 章 ／ 平均 #{number_with_comma(avg)} 文字"
        end

        # 基本情報セクションを生成する。
        # 主役は本文で、コードと記法は外数としてカッコ内に添える
        # （`chapter-volume-calibration-data.md` §7.1）。文章が主でコード・記法は従、
        # という位置づけによる。本文は語彙分析の分母と同じ値なので vocab から採る。
        def format_basic_info(basic, vocab)
          <<~OUTPUT.chomp
            📊 文章統計 — 基本情報
            - 文字数: #{number_with_comma(vocab.total_char_count)} 文字#{char_breakdown(basic)}
            - 行数: #{number_with_comma(basic.lines)} 行
          OUTPUT
        end

        # 文構造セクションを生成する
        def format_sentence_structure(basic)
          <<~OUTPUT.chomp
            📊 文章統計 — 文構造
            - 文の数: #{basic.sentences} 文（平均 #{basic.avg_sentence_len.round(1)} 文字/文）
            - 節の数: #{basic.clauses} 節（平均 #{basic.avg_clause_len.round(1)} 文字/節）
            - 読点数: #{basic.commas} 個
          OUTPUT
        end

        # 詳細分析セクションを生成する
        def format_detailed_analysis(vocab, readability)
          kanji = @vocabulary[:kanji_ratio]
          word = @vocabulary[:word_length]
          <<~OUTPUT.chomp
            📈 詳細分析

            【語彙難度】
            - 漢字比率: #{difficulty_evaluation(vocab.kanji_ratio, kanji)}（#{vocab.kanji_ratio.round(1)}%） — 理想的な範囲 #{kanji[:ideal_min]}〜#{kanji[:ideal_max]}%
            - 平均語長: #{difficulty_evaluation(vocab.avg_word_length, word)}（#{vocab.avg_word_length.round(1)} 文字） — 理想的な範囲 #{word[:ideal_min]}〜#{word[:ideal_max]} 文字
            - 文字種構成: #{character_composition(vocab)}

            【語彙多様度】
            - 使用語彙数: #{number_with_comma(vocab.unique_tokens)} 語（異なり語）／ 総語数 #{number_with_comma(vocab.total_tokens)} 語
            - 語彙の豊かさ: #{mattr_evaluation(vocab.mattr)}（MATTR: #{vocab.mattr.round(2)}）
              - 評価基準: 0.7 以上=非常に豊富、0.6〜0.7=豊富、0.5〜0.6=標準的、0.5 未満=単調

            【読解難度】
            - 評価: #{readability.label}（#{readability_description(readability.label)}）
            - スコア: #{readability.score.round(1)} 点
          OUTPUT
        end

        SNIPPET_LIMIT = 24

        # 「見直したい長い文」セクションを生成する。
        # 章番号・行番号・字数は右詰めで桁をそろえ、縦に位置が揃うようにする。
        def format_long_sentences(sentences)
          num_w = column_width(sentences, &:chapter_num)
          line_w = column_width(sentences, &:line)
          len_w = column_width(sentences, &:length)

          lines = ["📝 見直したい長い文（ワースト#{sentences.size}）", '']
          sentences.each_with_index do |s, index|
            location = "第#{s.chapter_num.to_s.rjust(num_w)}章 L#{s.line.to_s.rjust(line_w)}（#{s.length.to_s.rjust(len_w)}字）"
            lines << "#{index + 1}. #{location}: #{snippet(s.text)}"
          end
          lines.join("\n")
        end

        KANJI_LIST_TOP = 15

        # 漢字レベル（ルビ候補）セクションを生成する。
        def format_kanji_levels(report)
          lines = ['🈂 漢字レベル（ルビ候補）', '']
          lines << "- レベル内訳: #{report.ratios.map { |label, pct| "#{label} #{pct}%" }.join(' ／ ')}"
          KanjiLevels::LIST_LABELS.each do |key, title|
            list = report.lists[key]
            lines << kanji_list_line(title, list) unless list.empty?
          end
          lines.concat(kanji_location_lines(report.locations))
          lines.join("\n")
        end

        # 頻出内容語セクションを生成する。語・品詞は表示幅（全角=2）でそろえる。
        def format_content_words(words)
          word_w = words.map { display_width(it.word) }.max
          pos_w = words.map { display_width(it.pos) }.max
          count_w = words.map { it.count.to_s.length }.max

          lines = ["🔤 よく使う言葉（内容語 上位#{words.size}）", '']
          words.each_with_index do |w, index|
            rank = (index + 1).to_s.rjust(2)
            lines << "#{rank}. #{pad_to_width(w.word, word_w)}  #{pad_to_width(w.pos, pos_w)}  #{w.count.to_s.rjust(count_w)}回"
          end
          lines.join("\n")
        end

        RHYTHM_RUN_LIMIT = 5

        # 文末表現のリズムセクションを生成する。連続箇所は 1 件ずつ別行で示す。
        def format_sentence_rhythm(distribution, runs)
          lines = ['🎶 文末表現のリズム', '']
          lines << "- 文末の内訳: #{distribution.map { |category, pct| "#{category} #{pct}%" }.join('／')}"
          lines << format_monotone_runs(runs)
          lines.join("\n")
        end

        # 章間のばらつきセクションを生成する。高め／低めは別行（二段）で示す。
        def format_consistency(metrics)
          lines = ['📐 章間のばらつき（本文の章のみ）', '']
          metrics.each do |m|
            lines << "- #{m.label}: 平均 #{format_metric_value(m.mean, m.unit)} ／ ばらつき ±#{m.stdev.round(1)}"
            lines << "  #{m.high_label}: #{format_outliers(m.high, m.unit)}"
            lines << "  #{m.low_label}: #{format_outliers(m.low, m.unit)}"
          end
          lines.join("\n")
        end

        # 章行をフォーマットする（公開メソッド）。
        # extra_warnings は分量以外の指摘（文章の質）。分量とは算出タイミングが異なり
        # 章構造体に入っていないため、ここで受け取って 1 行に組み立てる
        # （metrics-quality-warnings-spec.md §2.2）。記号は系統ごとに分ける。
        # excluded は分量判定の対象外の章（前書き・付録・後書き）。✅ も出さない。
        def format_chapter_line(chapter, max_chars, show_sections, extra_warnings: [], excluded: false)
          bar = render_bar(chapter.chars, max_chars)
          warning = format_advice(chapter.warning, extra_warnings) +
                    ideal_mark(chapter.chars, thresholds[:chapter], excluded:)

          if show_sections && chapter.sections.any?
            format_chapter_with_sections(chapter, bar, warning, max_chars, excluded:)
          else
            label = padded_label(chapter_label(chapter))
            char_count = format_char_count(chapter.chars)
            "#{label} #{bar} #{char_count}#{warning}"
          end
        end

        private

        attr_reader :config, :labels

        # 相対モードでは基準（本の章の中央値）が事前スキャンの後に決まるので、
        # 値を抱え込まず毎回 ConfigLoader へ問い合わせる（あちらで memo 化済み）。
        def thresholds = config.volume_thresholds

        # 分量の指摘（💡）と文章の質の指摘（🤔）を、系統ごとの記号を付けて 1 行にまとめる。
        # 分量は「加筆をおすすめします」という提案であって直すべき欠陥ではないため、
        # 警告色の 🟡 から提案の 💡 へ移し、質の指摘とも記号を分けた
        # （`chapter-volume-calibration-data.md` §7.3）。どちらの記号も単一コードポイント・
        # EAW=W で、`terminal-output-notes.md` §1 の桁揃えの規則を満たす。
        # @return [String] 行末に足す表示片（先頭に空白を含む）。指摘が無ければ空文字列
        def format_advice(volume, quality = [])
          marks = []
          marks << "💡 #{volume}" if volume
          marks << "🤔 #{quality.join('・')}" if quality.any?
          marks.empty? ? '' : " #{marks.join(' ／ ')}"
        end

        # 分量が ideal 帯に収まっているときに付ける ✅。
        # 「足りない／多すぎる」だけを伝えると、直すところが無い章に何の反応も返らず
        # 判定されたのかどうかが分からない。**ちょうどよい**ことも伝える
        # （`chapter-volume-calibration-data.md` §7.1）。文言を添えないのは、
        # 💡 と 🤔 が「何を検討するか」を言う必要があるのに対し、✅ は
        # 「することが無い」を意味するだけで語を要さないため。
        # @param excluded [Boolean] 分量判定の対象外の章なら ✅ も出さない
        def ideal_mark(chars, threshold, excluded: false)
          return '' if excluded
          return '' unless chars.between?(threshold[:ideal_min], threshold[:ideal_max])

          ' ✅'
        end

        # 節付きで章をフォーマットする
        def format_chapter_with_sections(chapter, _bar, warning, max_chars, excluded: false)
          header = truncate_label(chapter_label(chapter))
          lines = ["#{header} (#{number_with_comma(chapter.chars)} 文字)#{warning}"]

          chapter.sections.each_with_index do |sec, idx|
            prefix = idx == chapter.sections.size - 1 ? '  └' : '  ├'
            sec_bar = render_bar(sec.chars, max_chars)
            sec_warning = format_advice(sec.warning) +
                          ideal_mark(sec.chars, thresholds[:section], excluded:)
            sec_title = padded_section_title(sec.title)
            char_count = format_char_count(sec.chars)
            lines << "#{prefix} #{sec_title} #{sec_bar} #{char_count}#{sec_warning}"
          end

          lines.join("\n")
        end

        def chapter_label(chapter)
          num = format('%02d', chapter.chapter_num)
          "第#{num}章 #{chapter.title}"
        end

        def padded_label(text)
          pad_to_width(truncate_label(text), CHAPTER_LABEL_WIDTH)
        end

        def truncate_label(text)
          truncate_to_width(text, CHAPTER_LABEL_WIDTH)
        end

        def padded_section_title(text)
          pad_to_width(truncate_section_title(text), SECTION_LABEL_WIDTH)
        end

        def truncate_section_title(text)
          truncate_to_width(text, SECTION_LABEL_WIDTH)
        end

        def truncate_to_width(text, width)
          return text if display_width(text) <= width

          result = +''
          current_width = 0

          text.each_char do |char|
            char_width = display_width(char)
            break if current_width + char_width > width - 1

            result << char
            current_width += char_width
          end

          result << '…'
        end

        def pad_to_width(text, width)
          pad = width - display_width(text)
          return text if pad <= 0

          text + (' ' * pad)
        end

        def display_width(text)
          text.each_char.sum { display_width_for_char(it) }
        end

        def display_width_for_char(char)
          fullwidth_char?(char) ? 2 : 1
        end

        def fullwidth_char?(char)
          !char.ascii_only?
        end

        # 棒グラフを描画する
        def render_bar(value, max_value)
          return "[#{BAR_EMPTY_CHAR * BAR_WIDTH}]" if max_value.zero?

          filled = [(value.to_f / max_value * BAR_WIDTH).round, BAR_WIDTH].min
          empty = BAR_WIDTH - filled
          "[#{BAR_CHAR * filled}#{BAR_EMPTY_CHAR * empty}]"
        end

        # 数値をカンマ区切りにする
        def number_with_comma(num) = num.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')

        # 本文に添える内訳（コード・記法）を外数で組み立てる。
        # コードも記法も無い原稿（小説など）では内訳を省き、行を短く保つ。
        def char_breakdown(basic)
          extras = []
          extras << "コード #{number_with_comma(basic.code_chars)} 文字" if basic.code_chars.positive?
          extras << "記法 #{number_with_comma(basic.notation_chars)} 文字" if basic.notation_chars.positive?
          return '（本文）' if extras.empty?

          "（本文。ほかに #{extras.join('、')}）"
        end

        def format_char_count(num)
          formatted = number_with_comma(num)
          "#{formatted.rjust(CHAR_COUNT_WIDTH)} 文字"
        end

        # 文字種構成比（本文＝コード除去後）。その他は数字・記号・句読点。
        # 分母は漢字比率と同じ total_char_count にそろえ、漢字%が一致するようにする。
        def character_composition(vocab)
          total = vocab.total_char_count
          return '本文なし' if total.zero?

          other = [total - vocab.kanji_char_count - vocab.hira_char_count -
                   vocab.kata_char_count - vocab.alpha_char_count, 0].max
          {
            '漢字' => vocab.kanji_char_count, 'ひらがな' => vocab.hira_char_count,
            'カタカナ' => vocab.kata_char_count, '英字' => vocab.alpha_char_count, 'その他' => other
          }.map { |label, count| "#{label} #{(count.to_f / total * 100).round(1)}%" }.join(' ／ ')
        end

        # 同一文末の連続箇所を 1 件ずつ別行で並べる（章・行は右詰めで桁そろえ）。
        def format_monotone_runs(runs)
          return '- 同じ文末の連続（5 つ以上）: 見当たりません' if runs.empty?

          shown = runs.first(RHYTHM_RUN_LIMIT)
          num_w = column_width(shown, &:chapter_num)
          line_w = column_width(shown, &:line)

          rows = shown.map do |r|
            "    第#{r.chapter_num.to_s.rjust(num_w)}章 L#{r.line.to_s.rjust(line_w)} 付近（#{r.label}が#{r.count}連続）"
          end
          rows << "    （ほか #{runs.size - RHYTHM_RUN_LIMIT} 箇所）" if runs.size > RHYTHM_RUN_LIMIT
          (['- 同じ文末の連続（5 つ以上、多い順）:'] + rows).join("\n")
        end

        # 漢字レベル一覧の 1 行（多い順、上限超は「ほか N 字」）。
        def kanji_list_line(title, list)
          shown = list.first(KANJI_LIST_TOP).map { |char, count| "#{char}(#{count})" }.join(' ')
          shown += "（ほか #{list.size - KANJI_LIST_TOP} 字）" if list.size > KANJI_LIST_TOP
          "- #{title}（多い順）: #{shown}"
        end

        # 一般・専門漢字の出現箇所（無ければ空配列）。
        def kanji_location_lines(locations)
          return [] if locations.empty?

          ['- 一般・専門漢字の出現箇所:'] + locations.map { |char, places| "    #{char} → #{format_kanji_places(places)}" }
        end

        # [章番号, 行] の並びを章ごとにまとめる（同じ章が続けば「第NN章 L1, L2」）。
        def format_kanji_places(places)
          places.slice_when { |prev, curr| prev.first != curr.first }
                .map { |group| "第#{format('%02d', group.first.first)}章 #{group.map { "L#{it.last}" }.join(', ')}" }
                .join(', ')
        end

        # 桁そろえ用に、対象フィールドの最大桁数を求める。
        def column_width(items) = items.map { yield(it).to_s.length }.max

        # 文頭の抜粋（長い文は必ず省略記号付き）。
        def snippet(text)
          body = text.strip
          body.length > SNIPPET_LIMIT ? "#{body[0, SNIPPET_LIMIT]}…" : body
        end

        # ばらつきの外れ章リストを「第NN章 値」形式で連結する。
        def format_outliers(entries, unit)
          return 'なし' if entries.empty?

          entries.map { |label, value| "#{label} #{format_metric_value(value, unit)}" }.join('、')
        end

        def format_metric_value(value, unit) = "#{value.round(1)}#{unit}"

        # 語彙難度（漢字比率・平均語長）を book.yml の閾値で 5 段階評価する。
        # 帯は ConfigLoader#vocabulary_thresholds（min/ideal/max）に由来するため、
        # 著者が対象読者に合わせて基準をカスタムできる（ハードコードだった帯を設定化）。
        def difficulty_evaluation(value, threshold)
          return '平易' if value < threshold[:min]
          return 'やや平易' if value < threshold[:ideal_min]
          return '適切' if value <= threshold[:ideal_max]
          return 'やや難解' if value <= threshold[:max]

          '難解'
        end

        # 語彙多様度（MATTR）の評価。窓付き移動平均のため、生 TTR より高め・
        # 安定した値域になる。バンドは実用書原稿の実測分布で較正した目安。
        # 単調帯の境界だけは品質警告と共有するため定数を参照する
        # （範囲パターン `in ..CONST` は書けないため case/when を使う）。
        def mattr_evaluation(mattr)
          case mattr
          when ..MATTR_MONOTONOUS_MAX then @labels[:monotonous]
          when ..0.6 then '標準的'
          when ..0.7 then '豊富'
          else '非常に豊富'
          end
        end

        # 読解難度の説明。難解側（Professional）の文言は book.yml の
        # labels.too_complex に由来するため、著者が対象読者に合わせて変えられる。
        def readability_description(label)
          case label
          in 'Easy' then '小中学生向け'
          in 'Standard' then '一般的なビジネス・実用書'
          in 'Professional' then @labels[:too_complex]
          else label
          end
        end
      end

      # 章・節の警告判定
      class WarningChecker
        # 読解難度（RS）を警告に使うために必要な最小文数。数文しかない章の RS は
        # 平均文長・連長のブレが大きく、難解判定が偶然で振れるため判定しない。
        MIN_SENTENCES_FOR_COMPLEXITY = 10

        # 建石式 RS の最難バンド（metrics.readability.standard 未満）のラベル。
        PROFESSIONAL_LABEL = 'Professional'

        def initialize(config_loader)
          @config = config_loader
          @labels = config_loader.labels
          @exclude = config_loader.exclude_chapters
          @mattr_window = config_loader.mattr_window
        end

        # 章の警告を判定する
        def chapter_warning(chapter_num, chars)
          return nil if excluded?(chapter_num)

          check_volume(chars, thresholds[:chapter])
        end

        # 節の警告を判定する
        def section_warning(chars, chapter_num: nil)
          return nil if excluded?(chapter_num)

          check_volume(chars, thresholds[:section])
        end

        # 品質警告（語彙多様度・読解難度）を判定する。分量警告と違い
        # ChapterAnalysis（vocab / readability）が要るため章構造体には持たせず、
        # 表示時に毎回導出する（しきい値・ラベルの変更が再解析なしで効く）。
        # 発火条件は詳細分析の評価バンドと完全に同一
        # （metrics-quality-warnings-spec.md §1.1）。
        # @param analysis [Runner::ChapterAnalysis]
        # @return [Array<String>] 該当ラベルの配列（該当なし・除外章は空）
        def quality_warnings(analysis)
          return [] if excluded?(analysis.chapter.chapter_num)

          warnings = []
          warnings << labels[:monotonous] if monotonous?(analysis.vocab)
          warnings << labels[:too_complex] if too_complex?(analysis.readability)
          warnings
        end

        # 警告がある章かどうか。analysis を渡すと品質警告も対象に含める
        # （--warn で「単調・難解と評価された章だけを見る」ため）。
        def has_warning?(chapter_num, chars, sections, analysis: nil)
          return true if chapter_warning(chapter_num, chars)
          return true if analysis && quality_warnings(analysis).any?

          sections.any? { section_warning(it.chars, chapter_num:) }
        end

        def excluded_chapter?(chapter_num)
          excluded?(chapter_num)
        end

        private

        attr_reader :config, :labels, :exclude, :mattr_window

        # Formatter と同じ理由で毎回問い合わせる（相対モードの基準は後から決まる）。
        def thresholds = config.volume_thresholds

        # MATTR が「表現が単調」帯（詳細分析の表示と同一バンド）。
        # 総語数が窓幅に満たない章は MATTR 自体が不安定なため判定しない。
        def monotonous?(vocab)
          vocab.total_tokens >= mattr_window && vocab.mattr <= Formatter::MATTR_MONOTONOUS_MAX
        end

        # 建石式 RS が最難バンド（Professional）。RS の母数である文数
        # （features.sentence_count）が少ない章は不安定なため判定しない。
        def too_complex?(readability)
          readability.features.sentence_count >= MIN_SENTENCES_FOR_COMPLEXITY &&
            readability.label == PROFESSIONAL_LABEL
        end

        # 除外対象か判定する
        def excluded?(chapter_num)
          return false unless chapter_num

          exclude.include?(format('%02d', chapter_num.to_i))
        end

        # 分量チェック
        def check_volume(chars, threshold)
          if chars < threshold[:min]
            labels[:too_short]
          elsif chars > threshold[:max]
            labels[:too_long]
          end
        end
      end
    end
  end
end
