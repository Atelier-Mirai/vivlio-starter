# frozen_string_literal: true

# ================================================================
# Class: IndexPlanReporter
# ----------------------------------------------------------------
# 責務:
#   `vs index:plan` の画面を組み立てて表示する。語数の目安を決めるための操作盤と、
#   いまの登録の現況を示す（index-glossary-registration-spec.md §5）。
#   `vs index:auto` はこの画面を出さず、件数と次の手順だけを告げる。
#
# 報告ではなく操作盤にする（index-term-selection-spec.md §6.2）:
#   現況を並べるだけでは著者の問い——「260 語にしたい。どのキーをいくつに
#   すればよいか」——に答えられない。よって必ず次の 3 つを示す。
#     1. いまの設定と、そこから決まる目安
#     2. 設定を変えたらどうなるか（全プリセットを並べる）
#     3. 書くべき YAML そのもの
#   さらに「約 N 字に 1 語」を併記する。著者は密度で考えるのに対し設定は語数で
#   持つので、この列が両者をつなぐ橋になる。
#
# 出さないもの:
#   スコアの分布・候補の総数・提示しなかった件数。著者がスコアで判断する場面は無く、
#   抽出の内部の数は決めることにつながらない（§5.1）。
# ================================================================

require_relative '../common'
require_relative 'index_size_estimator'

module VivlioStarter
  module CLI
    module IndexCommands
      # `vs index:plan` の画面
      class IndexPlanReporter
        # いまの登録の内訳。undecided_main は主要参照が決まっていない索引語の数
        # （主要参照の機能を切った本では nil）
        Registration = Data.define(:index, :glossary, :rejected, :undecided_main)

        # 表示に必要な素材。算出はすべて呼び出し側（UnifiedIndexManager）が行い、
        # ここは組み立てと出力だけを担う（責務を混ぜない）。
        # bands は候補の抽出を切っている本（index.auto_discovery: false）では nil
        Plan = Data.define(:chapters, :prose_chars, :registration, :estimate, :all_estimates, :bands)

        # 推奨する語を画面に出す語数。全部出すのはレビューファイルの仕事。
        PREVIEW_COUNT = 5

        # 「語数を直接決める場合」の例に使う語数。現在の目安の中央に寄せると
        # 「いまと同じ値を書け」と読めてしまうので、キリのよい値へ丸める。
        def self.sample_target(estimate)
          mid = (estimate.range.begin + estimate.range.end) / 2
          [(mid / 10.0).round * 10, 10].max
        end

        def initialize(plan)
          @plan = plan
        end

        def render
          emit(volume_line)
          registration_lines.each { emit(it) }
          emit('')
          current_section.each { emit(it) }
          emit('')
          options_section.each { emit(it) }
          emit('')
          auto_section.each { emit(it) }
          emit('')
          emit('※ vs index:plan は下見です。辞書・レビューファイルは変更していません')
        end

        private

        attr_reader :plan

        def emit(line) = Common.log_always(line)

        def volume_line
          "本文の分量: #{plan.chapters.size} 章 / #{number(plan.prose_chars)} 字（コード・記法を除く地の文）"
        end

        # 主要参照の行は、決まっていない語があるときだけ出す
        def registration_lines
          reg = plan.registration
          lines = ["いまの登録: 索引 #{number(reg.index)} 語・用語集 #{number(reg.glossary)} 語・棄却 #{number(reg.rejected)} 語"]
          lines << "            主要参照が決まっていない索引語 #{number(reg.undecided_main)} 語" if reg.undecided_main.to_i.positive?
          lines
        end

        # --- ① いまの設定と、そこから決まる目安 ---

        def current_section
          est = plan.estimate
          # かっこの中にかっこを重ねない（「light（少なめ）」でなく「light ＝ 少なめ」）
          label = est.preset ? "#{est.preset} ＝ #{IndexSizeEstimator::PRESET_LABELS.fetch(est.preset)}" : est.range.begin.to_s
          ["■ いまの目安（index.target_terms: #{label}）", "    #{est} ＝ #{density_text(est)}", "    #{gap_text(est)}"]
        end

        # 現在の索引語数が目安に対してどこにいるか。数字だけでなく「どちらへ動かすか」を言う。
        def gap_text(est)
          now = plan.registration.index
          density = now.positive? ? "（約 #{number(plan.prose_chars / now)} 字に 1 語）" : ''
          if now < est.range.begin
            "現在 #{number(now)} 語は目安を #{number(est.range.begin - now)} 語下回っています#{density}"
          elsif now > est.range.end
            "現在 #{number(now)} 語は目安を #{number(now - est.range.end)} 語上回っています#{density}"
          else
            "現在 #{number(now)} 語は目安の範囲内です#{density}"
          end
        end

        # --- ② 設定を変えたらどうなるか ---

        def options_section
          lines = ['■ 設定を変えるとこうなります']
          plan.all_estimates.each do |est|
            mark = est.preset == plan.estimate.preset ? '   ← 現在' : ''
            lines << "    #{pad(IndexSizeEstimator.preset_label(est.preset), 18)}#{pad(est.to_s, 14)}#{density_text(est)}#{mark}"
          end
          lines + direct_setting_lines
        end

        # --- ③ 書くべき YAML そのもの ---

        def direct_setting_lines
          n = self.class.sample_target(plan.estimate)
          [
            '',
            '    語数を直接決める場合は config/book.yml に:',
            '      index:',
            "        target_terms: #{n}        # 約 #{number(plan.prose_chars / n)} 字に 1 語"
          ]
        end

        def density_text(est)
          r = est.chars_per_term_range
          return '' if r.end.zero?

          r.begin == r.end ? "約 #{number(r.begin)} 字に 1 語" : "約 #{number(r.begin)}〜#{number(r.end)} 字に 1 語"
        end

        # --- vs index:auto を実行するとどうなるか ---

        # 呼び名はレビューファイルの節の名前にそろえる（§3.2.2）
        def auto_section
          bands = plan.bands
          return ['■ vs index:auto を実行すると', '    候補の抽出は切ってあります（index.auto_discovery: false）。原稿に [語] と書いた語だけを登録します'] unless bands

          ['■ vs index:auto を実行すると',
           "    推奨する語 #{number(bands.recommended.size)} 語・残りの語 #{number(bands.general.size)} 語をレビューファイルに並べます",
           *preview_line(bands.recommended)]
        end

        def preview_line(entries)
          return [] if entries.empty?

          names = entries.first(PREVIEW_COUNT).map(&:term)
          more = entries.size > PREVIEW_COUNT ? " …他 #{number(entries.size - PREVIEW_COUNT)} 語" : ''
          ["    推奨する語の例: #{names.join(' / ')}#{more}"]
        end

        # 全角を 2 桁と数えて右を空白で埋める（訳語の全角で桁がずれないように）
        def pad(text, width)
          used = text.each_char.sum { it.bytesize > 1 ? 2 : 1 }
          text + (' ' * [width - used, 1].max)
        end

        def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
      end
    end
  end
end
