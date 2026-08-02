# frozen_string_literal: true

# ================================================================
# Class: IndexPlanReporter
# ----------------------------------------------------------------
# 責務:
#   索引の「現況と計画」を組み立てて表示する。
#   - 本文の分量（章数・地の文の文字数）
#   - 索引語の登録状況
#   - 候補のスコア分布
#
# なぜ切り出すか:
#   `vs index:plan`（下見）と `vs index:auto`（本番）で**同じ画面**を出すため。
#   見え方が実行ごとに変わると、著者は「下見で見た内容と本番が違うのでは」と
#   疑うことになる。両者の違いは末尾の案内と、辞書・レビューファイルを書くか
#   どうかだけにする（index-term-selection-spec.md §6.2）。
#
# 表示の作法:
#   割合（「上位 60%」）は出さない。決まるのは語数と順位なので、順位と件数で言う。
#   帯の名前はレビューファイルで既に使っている語（推奨候補・一般候補）に揃え、
#   新しい語彙を持ち込まない（同 §6.3）。
# ================================================================

require_relative '../common'
require_relative '../metrics/analyzer'
require_relative 'review_markdown_generator' # 末尾の案内でレビューファイル名を使う

module VivlioStarter
  module CLI
    module IndexCommands
      # 索引の現況と計画を表示する
      class IndexPlanReporter
        # 表示に必要な素材。算出はすべて呼び出し側（UnifiedIndexManager）が行い、
        # ここは組み立てと出力だけを担う（責務を混ぜない）。
        Plan = Data.define(:chapters, :prose_chars, :registered_terms, :candidate_scores)

        # 章の本文から地の文の文字数を数える。
        # 計数の実装は `Metrics::Analyzer` が唯一の正典——ここで除去処理を書き直すと
        # `vs metrics` の表示と黙ってずれる（§3.3）。
        # @param chapters [Array<String>] 章のベースネームまたはパス
        # @return [Integer] 地の文の文字数（空白を除く）
        def self.prose_chars_of(chapters)
          chapters.sum do |chapter|
            path = resolve_path(chapter)
            path ? Metrics::Analyzer.prose_length(File.read(path, encoding: 'utf-8')) : 0
          end
        end

        # 章名からファイルパスを解決する（contents/ を優先）
        def self.resolve_path(chapter)
          return chapter if File.exist?(chapter.to_s)

          candidates = [
            File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
            File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")
          ]
          candidates.find { File.exist?(it) }
        end
        private_class_method :resolve_path

        def initialize(plan)
          @plan = plan
        end

        # 画面へ出力する。
        # @param dry_run [Boolean] true なら「書き換えていない」旨を末尾に添える
        def render(dry_run: false)
          Common.log_always(volume_line)
          Common.log_always(registration_line)
          Common.log_always(candidate_line)
          Common.log_always(score_distribution_line) if scores.any?
          Common.log_always('')
          Common.log_always(footer(dry_run:))
        end

        private

        attr_reader :plan

        def scores = @scores ||= plan.candidate_scores.compact.sort

        def volume_line
          "本文の分量: #{plan.chapters.size} 章 / #{number(plan.prose_chars)} 字（コード・記法を除く地の文）"
        end

        def registration_line = "索引語の登録: #{number(plan.registered_terms)} 語"

        def candidate_line = "候補抽出: #{number(scores.size)} 件"

        # 分布は五数要約で示す。平均は外れ値に引きずられて実感と合わない。
        def score_distribution_line
          q = ->(ratio) { scores[[(scores.size * ratio).to_i, scores.size - 1].min].round }
          "  スコア分布: 最小 #{q[0.0]} / 下位 25% #{q[0.25]} / 中央 #{q[0.5]} / " \
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
