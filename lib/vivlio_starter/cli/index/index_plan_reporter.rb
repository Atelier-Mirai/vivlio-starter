# frozen_string_literal: true

# ================================================================
# Class: IndexPlanReporter
# ----------------------------------------------------------------
# 責務:
#   索引の「現況と計画」を組み立てて表示する。
#
# なぜ切り出すか:
#   `vs index:plan`（下見）と `vs index:auto`（本番）で**同じ画面**を出すため。
#   見え方が実行ごとに変わると、著者は「下見で見た内容と本番が違うのでは」と
#   疑うことになる。両者の違いは末尾の案内と、辞書・レビューファイルを書くか
#   どうかだけにする（index-term-selection-spec.md §6.3）。
#
# 報告ではなく操作盤にする（§6.2）:
#   現況を並べるだけでは著者の問い——「260 語にしたい。どのキーをいくつに
#   すればよいか」——に答えられない。よって必ず次の 3 つを示す。
#     1. いまの設定と、そこから決まる目安
#     2. 設定を変えたらどうなるか（全プリセットを並べる）
#     3. 書くべき YAML そのもの
#   さらに「約 N 字に 1 語」を併記する。著者は密度で考えるのに対し設定は語数で
#   持つので、この列が両者をつなぐ橋になる。
#
# 表示の作法:
#   割合（「上位 60%」）は出さない。決まるのは語数と順位なので、順位と件数で言う。
#   帯の名前はレビューファイルで既に使っている語（推奨候補・一般候補）に揃え、
#   新しい語彙を持ち込まない（同 §6.4）。
# ================================================================

require_relative '../common'
require_relative 'index_size_estimator'
require_relative 'review_markdown_generator' # 末尾の案内でレビューファイル名を使う

module VivlioStarter
  module CLI
    module IndexCommands
      # 索引の現況と計画を表示する
      class IndexPlanReporter
        # 表示に必要な素材。算出はすべて呼び出し側（UnifiedIndexManager）が行い、
        # ここは組み立てと出力だけを担う（責務を混ぜない）。
        Plan = Data.define(:chapters, :prose_chars, :registered_terms, :candidate_scores,
                           :estimate, :all_estimates)

        # 「語数を直接決める場合」の例に使う語数。現在の目安の中央に寄せると
        # 「いまと同じ値を書け」と読めてしまうので、キリのよい値へ丸める。
        def self.sample_target(estimate)
          mid = (estimate.range.begin + estimate.range.end) / 2
          [(mid / 10.0).round * 10, 10].max
        end

        def initialize(plan)
          @plan = plan
        end

        # 画面へ出力する。
        # @param dry_run [Boolean] true なら「書き換えていない」旨を末尾に添える
        def render(dry_run: false)
          emit(volume_line)
          emit(registration_line)
          emit('')
          current_section.each { emit(it) }
          emit('')
          options_section.each { emit(it) }
          emit('')
          candidate_section.each { emit(it) }
          emit('')
          emit(footer(dry_run:))
        end

        private

        attr_reader :plan

        def emit(line) = Common.log_always(line)

        def scores = @scores ||= plan.candidate_scores.compact.sort

        def volume_line
          "本文の分量: #{plan.chapters.size} 章 / #{number(plan.prose_chars)} 字（コード・記法を除く地の文）"
        end

        def registration_line = "索引語の登録: #{number(plan.registered_terms)} 語"

        # --- ① いまの設定と、そこから決まる目安 ---

        def current_section
          est = plan.estimate
          label = est.preset ? "index.target_terms: #{est.preset}" : "index.target_terms: #{est.range.begin}"
          lines = ["■ いまの目安（#{label}）", "    #{est} ＝ #{density_text(est)}"]
          lines << "    #{gap_text(est)}"
          lines
        end

        # 現在の登録語数が目安に対してどこにいるか。数字だけでなく「どちらへ動かすか」を言う。
        def gap_text(est)
          now = plan.registered_terms
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
            lines << format('    %-10s %-14s %s%s', est.preset, est.to_s, density_text(est), mark)
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

        # --- 候補 ---

        def candidate_section
          lines = ["■ 候補: #{number(scores.size)} 件"]
          lines << "    #{score_distribution_line}" if scores.any?
          lines
        end

        # 分布は五数要約で示す。平均は外れ値に引きずられて実感と合わない。
        def score_distribution_line
          q = ->(ratio) { scores[[(scores.size * ratio).to_i, scores.size - 1].min].round }
          "スコア分布: 最小 #{q[0.0]} / 下位 25% #{q[0.25]} / 中央 #{q[0.5]} / " \
            "上位 25% #{q[0.75]} / 最大 #{scores.last.round}"
        end

        def footer(dry_run:)
          return '※ vs index:plan は下見です。辞書・レビューファイルは変更していません' if dry_run

          "#{ReviewMarkdownGenerator::REVIEW_FILE} を編集後、vs index:apply を実行してください"
        end

        def number(value) = value.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
      end
    end
  end
end
