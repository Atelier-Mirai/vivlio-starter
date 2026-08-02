# frozen_string_literal: true

# ================================================================
# Class: IndexSizeEstimator
# ----------------------------------------------------------------
# 責務:
#   本文の分量から「この本にふさわしい索引語数」の目安を算出する。
#
# なぜ文字数か（ページ数ではない理由）:
#   同じ原稿が A5 で 500 ページ、A4 で 350 ページになっても、索引語の適正数は
#   同じであるべきである。ページ数を基準にすると判型を変えただけで目安が
#   1.4 倍動く。索引は本の中身の性質であって、紙の都合ではない。
#   （版面からのページ推定も実測で 2.2 倍外れた）
#
# なぜ比例ではないか:
#   索引語は分量に比例せず逓減する。原稿が増えても既出語の再出現が多く、
#   新語の登場は鈍る（Heaps 則 V = K × N^β）。
#
# 較正:
#   BETA と BASE_TERMS は刊行済み技術書 10 冊の実測による。
#   生データ・計測方法・限界は index-size-calibration-data.md を参照。
#   **書籍タイプ（入門書／一般技術書）では索引語数を予測できない**ことが
#   実測で分かったので、区分は「索引の密度＝編集方針」で持つ。
#
# 仕様: index-term-selection-spec.md §3
# ================================================================

require_relative '../common'
require_relative '../metrics/analyzer'

module VivlioStarter
  module CLI
    module IndexCommands
      # 索引語数の目安を算出する
      class IndexSizeEstimator
        # Heaps 則の指数。10 冊の log-log 回帰による実測値（地の文基準）。
        # 3 倍の分量でも索引語は約 2.3 倍にしかならない。
        BETA = 0.749

        # 5 万字時点の語数。10 冊の実測を密度で 3 群に分けたもの。
        #   65, 88 ┊ 118, 151, 151, 167, 171, 173 ┊ 226, 228
        # thorough の幅が狭いのは実測が 2 冊しかないためで、
        # その帯が本当に狭いことを意味しない。
        BASE_TERMS = {
          light: (65..90),      # 控えめ: 主要な語だけを拾う
          standard: (120..175), # 標準（既定）
          thorough: (225..230)  # 丁寧: 初学者向けに広く拾う
        }.freeze

        DEFAULT_PRESET = :standard

        # 基準となる分量（BASE_TERMS はこの字数時点の語数）
        BASE_CHARS = 50_000.0

        # 算出結果。range は目安語数の幅（整数指定なら 1 点の範囲になる）。
        Estimate = Data.define(:preset, :range, :chars) do
          # 「約 N 字に 1 語」。著者は密度で考えるので、語数と密度を併記するための値。
          # 語数が多いほど 1 語あたりの字数は小さくなるので、上下が入れ替わる。
          def chars_per_term_range
            return (0..0) if range.end.zero?

            ((chars / range.end)..(chars / [range.begin, 1].max))
          end

          def to_s = range.begin == range.end ? "#{range.begin} 語" : "#{range.begin}〜#{range.end} 語"
        end

        # 章の本文から地の文の文字数を数える。
        # 計数の実装は Metrics::Analyzer が唯一の正典——ここで除去処理を書き直すと
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

          [File.join(Common::CONTENTS_DIR, "#{chapter}.md"),
           File.join(Common::BUILD_HTML_DIR, "#{chapter}.md")].find { File.exist?(it) }
        end
        private_class_method :resolve_path

        # @param chars [Integer] 地の文の文字数
        def initialize(chars)
          @chars = chars
        end

        # `book.yml` の `index.target_terms` を解釈して目安を返す。
        # プリセット名なら Heaps 則で幅を、整数ならその語数を 1 点として返す。
        # @param setting [String, Symbol, Integer, nil] target_terms の値
        # @return [Estimate]
        def estimate(setting)
          case normalize(setting)
          in Integer => n then Estimate.new(preset: nil, range: (n..n), chars: @chars)
          in Symbol => preset then Estimate.new(preset:, range: range_for(preset), chars: @chars)
          end
        end

        # 全プリセットの目安。操作盤の「設定を変えるとこうなります」に使う。
        # @return [Array<Estimate>]
        def all_presets = BASE_TERMS.keys.map { estimate(it) }

        private

        # 設定値を Symbol（プリセット）か Integer（語数）へ寄せる。
        # 未知の値は既定のプリセットへ落とし、著者へ知らせる。
        def normalize(setting)
          return DEFAULT_PRESET if setting.nil?
          return setting.to_i if setting.is_a?(Integer) || setting.to_s.match?(/\A\d+\z/)

          key = setting.to_s.strip.downcase.to_sym
          return key if BASE_TERMS.key?(key)

          Common.log_warn(
            "index.target_terms の値 '#{setting}' は解釈できません（#{DEFAULT_PRESET} として扱います）",
            detail: "指定できるのは #{BASE_TERMS.keys.join(' / ')} か、語数を表す整数（例: 260）です"
          )
          DEFAULT_PRESET
        end

        # Heaps 則で 5 万字時点の語数を今の分量へ引き伸ばす
        def range_for(preset)
          base = BASE_TERMS.fetch(preset)
          factor = (@chars / BASE_CHARS)**BETA
          ((base.begin * factor).round..(base.end * factor).round)
        end
      end
    end
  end
end
