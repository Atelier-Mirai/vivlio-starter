# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/import/re_report.rb
# ================================================================
# 責務:
#   .re 直変換で見つかった「著者に伝えるべきこと」を集め、まとめて報告する。
#
# なぜ集めてから出すのか:
#   変換は章ごとに走るので、そのつど出力すると同じ記法の警告が何十行も並ぶ。
#   記法ごとに畳んで「どの記法が何件・最初の 3 箇所はどこか」を示すほうが、
#   著者は直す順番を決められる。
#
# 3 段階（re-direct-import-spec.md §4.1）:
#   🔴 unsupported … Vivlio に対応概念が無い。著者が手で直す必要がある
#   🟡 degraded    … 変換はしたが情報が落ちた
#   🔵 note        … 見た目が変わりうるが著者の作業は不要
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module Import
      # 変換中の気づきを集めて報告する
      class ReReport
        # 1 件の気づき。同じ記法をまとめるため kind（記法名）を持つ
        Finding = Data.define(:level, :kind, :file, :line, :message, :detail)

        # 畳んだあと、各記法について何箇所まで場所を挙げるか
        SHOWN_LOCATIONS = 3

        attr_reader :findings

        def initialize
          @findings = []
          @counts = Hash.new(0)
        end

        # 🔴 対応概念が無い記法。原文はそのまま残っている前提で呼ぶ
        def unsupported(kind, file:, line:, message:, detail: nil)
          add(:unsupported, kind, file, line, message, detail)
        end

        # 🟡 変換はしたが、指定・装飾が落ちた
        def degraded(kind, file:, line:, message:, detail: nil)
          add(:degraded, kind, file, line, message, detail)
        end

        # 🔵 見た目は変わりうるが、著者の作業は要らない
        def note(kind, file:, line:, message:, detail: nil)
          add(:note, kind, file, line, message, detail)
        end

        # 変換できた記法を数える（サマリの母数になる）
        def count(category) = @counts[category] += 1

        def counted(category) = @counts[category]

        def any? = @findings.any?

        # 記法ごとに畳んでログへ流す
        def emit!
          emit_group(:unsupported) { Common.log_error(it.first, detail: it.last) }
          emit_group(:degraded) { Common.log_warn(it.first, detail: it.last) }
          emit_group(:note) { Common.log_info(it.first) }
        end

        # 「静かに終わった＝全部うまくいった」と誤解させないための総括。
        # detail は 1 本の文字列で渡す（Common#format_detail が lines で割る）
        def summary(chapters:, lines:)
          Common.log_summary("変換サマリ（#{chapters} 章 / #{lines} 行）", detail: summary_lines.join("\n"))
        end

        private

        def add(level, kind, file, line, message, detail)
          @findings << Finding.new(level:, kind:, file:, line:, message:, detail:)
        end

        # 同じ記法の指摘を 1 つにまとめ、場所を SHOWN_LOCATIONS 件だけ添える
        def emit_group(level)
          @findings.select { it.level == level }.group_by(&:kind).each_value do |group|
            head = group.first
            places = group.first(SHOWN_LOCATIONS).map { "#{it.file}:#{it.line}" }.join('、')
            more = group.size > SHOWN_LOCATIONS ? "ほか #{group.size - SHOWN_LOCATIONS} 箇所" : nil
            message = "#{[places, more].compact.join('、')}: #{head.message}"
            message = "#{message}（計 #{group.size} 箇所）" if group.size > 1
            yield [message, head.detail]
          end
        end

        def summary_lines
          lines = [
            "ブロック命令 #{@counts[:block]} 件を変換",
            "インライン命令 #{@counts[:inline]} 件を変換"
          ]
          lines << "ラベル ID #{@counts[:relabel]} 件を一意化のため改名" if @counts[:relabel].positive?
          lines << tally_line
          lines.compact
        end

        def tally_line
          tally = @findings.group_by(&:level).transform_values(&:size)
          parts = []
          parts << "🔴 #{tally[:unsupported]} 件" if tally[:unsupported]
          parts << "🟡 #{tally[:degraded]} 件" if tally[:degraded]
          return '変換できなかった記法はありません' if parts.empty?

          "#{parts.join(' / ')} — 詳細は上のログを参照してください"
        end
      end
    end
  end
end
