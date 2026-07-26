# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/pre_process/issue_registry.rb
# ================================================================
# 責務:
#   前処理の各発生源（リンク・画像検証／コードインクルード／クロスリファレンス／
#   QueryStream／Guard 警告）が検出した指摘を、章単位で横断的に集計する。
#
# 設計（docs/specs/preflight-chapter-summary-spec.md §2.1）:
#   - 発生源は「章・行・重要度・カテゴリ・メッセージ」を record するだけ。
#     各発生源が持つ固有の内部構造（LinkImageValidator の ValidationReport 等）は
#     温存し、registry へのブリッジのみを足す
#   - 逐次ログ（🔴🟡）は従来どおり各発生源が出す。registry は集計専用で
#     表示を一切行わない（二重表示を避けるための責務分離）
#   - 並列前処理（ファイル単位のスレッド）から呼ばれるため Monitor で同期する
# ================================================================

require 'monitor'

module VivlioStarter
  module CLI
    module PreProcessCommands
      module IssueRegistry
        # 単一の指摘。
        # chapter は章 basename（"21-images"）。章に紐付かない横断的な指摘は nil。
        # severity は :error / :warn、category は :image / :link / :code_include /
        # :cross_reference / :query_stream / :guard など発生源の種別。
        Issue = Data.define(:chapter, :line, :severity, :category, :message)

        # 重要度別の件数。counts / summary_by_chapter の戻り値。
        Counts = Data.define(:errors, :warns) do
          def total = errors + warns
          def clean? = total.zero?
        end

        # --- グローバル蓄積用（スレッドセーフ） ---
        @monitor = Monitor.new
        @issues = []

        class << self
          # 蓄積をリセットする（preflight / build 開始時に呼ぶ）
          def reset!
            @monitor.synchronize { @issues = [] }
          end

          # 指摘を 1 件記録する。
          # @param severity [Symbol] :error または :warn
          # @param category [Symbol] 発生源の種別（:image / :link / :guard など）
          # @param message [String] 著者向けの短い説明（逐次ログとは独立）
          # @param chapter [String, nil] 章ファイル名。拡張子付き・パス付きでも可。横断的な指摘は nil
          # @param line [Integer, nil] 行番号
          # @return [Issue] 記録した指摘
          def record(severity:, category:, message:, chapter: nil, line: nil)
            issue = Issue.new(chapter: normalize_chapter(chapter), line:, severity:, category:, message:)
            @monitor.synchronize { @issues << issue }
            issue
          end

          # 蓄積された全指摘のコピーを返す（呼び出し側での絞り込み用）
          def issues = @monitor.synchronize { @issues.dup }

          # 全体の件数を返す
          # @return [Counts]
          def counts = tally(issues)

          # 章ごとの件数を返す。キーは章 basename、章に紐付かない指摘は nil キーにまとまる。
          # @return [Hash{String, nil => Counts}]
          def summary_by_chapter
            issues.group_by(&:chapter).transform_values { tally(it) }
          end

          private

          def tally(list)
            errors, warns = list.partition { it.severity == :error }
            Counts.new(errors: errors.size, warns: warns.size)
          end

          # 発生源はファイル名の形式が揃わない（"21-images.md" / "contents/21-images.md"）ため、
          # 章キーは basename かつ拡張子なしへ正規化して集計軸を 1 つに保つ。
          def normalize_chapter(chapter)
            return nil if chapter.nil?

            name = File.basename(chapter.to_s.strip)
            return nil if name.empty?

            name.sub(/\.(md|markdown)\z/i, '')
          end
        end
      end
    end
  end
end
