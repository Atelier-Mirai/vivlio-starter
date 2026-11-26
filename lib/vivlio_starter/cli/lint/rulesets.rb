# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/lint/rulesets.rb
# ================================================================
# 責務:
#   文章の校正の規則の組（lint.ruleset。v2-architecture-spec.md §6）
#
# 組は「technical（今の一組）から切る規則の名前」で書く。名前の読み方は lint.disabled_rules と
# 同じで、textlint のプリセットの名前（preset-ja-technical-writing）を書けばプリセットごと切れる。
# 入れる規則の一覧で書かないのは、textlint のプリセットの中身が著者の .textlintrc.yml で
# 増減し、vs の側で数え上げられないためである。lint.disabled_rules は、選んだ組から
# さらに外す指定として今と同じに働く（二つを合わせたものが切る規則になる）。
# ================================================================

require_relative 'novel_checker'

module VivlioStarter
  module CLI
    module Lint
      # 規則の組の名前 → technical から切る規則の名前
      module Rulesets
        # 文体・文の長さ・空きの規則。誤字と表記の揺れの規則（prh・spellcheck-tech-word・
        # mazegaki・kanji-lookalike・kansuji-counter-suffix・語の間の空きの取り違え）と、
        # 記法の取り違えの規則（indented-code-block など。紙面が壊れる）は残す
        STYLE_RULES = %w[
          preset-ja-technical-writing
          preset-ja-spacing
          ambiguous-comparison
          slash-between-japanese
          space-around-brackets
          long-parenthetical
          missing-period
          sentence-length
          max-ten
          ja-no-weak-phrase
        ].freeze

        # 小説の原稿の書き方の決まり（novel-vertical-spec.md §6.2）。小説の組のほかは切る
        NOVEL_RULES = NovelChecker::RULES

        TABLE = {
          # 技術書向け。今の一組（小説の規則のほかは何も切らない）
          technical: NOVEL_RULES,
          # 誤字と表記の揺れだけ（絵本の既定）
          minimal: (STYLE_RULES + NOVEL_RULES).freeze,
          # 小説向け。minimal に小説の規則を足したもの
          novel: STYLE_RULES
        }.freeze

        module_function

        # 組の名前の一覧（著者への案内に使う）
        def names = TABLE.keys

        # 組が切る規則の名前
        # @param name [String, Symbol, nil] lint.ruleset に書いた値（書かなければ technical）
        # @return [Array<String>]
        # @raise [KeyError] 知らない組の名前
        def disabled_by(name)
          key = name.to_s.strip
          key = 'technical' if key.empty?
          TABLE.fetch(key.to_sym) do
            raise KeyError, "config/book.yml の lint.ruleset に、知らない規則の組が書かれています: #{key}"
          end
        end
      end
    end
  end
end
