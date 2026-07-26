# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/option_token_normalizer.rb
# ================================================================
# 責務:
#   Samovar が解さない `--opt=value` 記法を `--opt value` へ開き、
#   値が続かないオプションには既定値を補う。
#
# なぜ必要か:
#   Samovar の `Options#parse` はフラグ文字列の完全一致でしか
#   オプションを引けず（`@keyed` のハッシュ参照）、`=` を分割する処理を
#   持たない。そのため `--log=debug` は「解釈できないトークン」として
#   弾かれ、CLI が 🟡 とともに --help を表示して終わってしまう。
#   加えて `ValueFlag#parse` は次のトークンを無条件に値とみなすため、
#   値を伴わない `--log` の直後に別オプションが並ぶと誤読する。
#
# 使い方:
#   値を取るオプションを持つ Samovar::Command で prepend する。
#     prepend OptionTokenNormalizer
#   対象フラグはコマンドの options 定義から自動導出するため、
#   オプションを増やしても宣言の追加は不要。
# ================================================================

module VivlioStarter
  module CLI
    module SamovarCommands
      # `--opt=value` 記法を Samovar が解せる形へ正規化する
      module OptionTokenNormalizer
        # 値が省略されたときに補う既定値。
        # `--log` だけは bare 指定に意味を持たせ（`--log` = info 相当）、
        # それ以外は値必須として補完せず Samovar の検証に委ねる。
        BARE_VALUE_DEFAULTS = { '--log' => 'info' }.freeze

        # prepend 先のクラスへ値フラグの導出機能を配る
        def self.prepended(base) = base.extend(ClassMethods)

        # コマンドクラス側に生えるヘルパー
        module ClassMethods
          # options 定義から「値を取るフラグ」の名前を集める。
          # Samovar の ValueFlag は値なしフラグ（`--high` など）も表現するため、
          # 値プレースホルダを持たないもの（boolean?）を除いて判定する。
          # 継承したオプションも拾えるよう merged 済みのテーブルを走査する。
          # @return [Array<String>] `--log` `-s` のようなフラグ名（短縮形を含む）
          def value_option_flags
            @value_option_flags ||= table.merged.each.to_a.grep(Samovar::Options)
                                         .flat_map { it.each.to_a }
                                         .flat_map { it.flags.each.to_a }
                                         .select { it.is_a?(Samovar::ValueFlag) && !it.boolean? }
                                         .flat_map { [it.prefix, *it.alternatives] }
                                         .freeze
          end
        end

        def initialize(input = nil, **)
          super(input ? normalized_input(input) : input, **)
        end

        private

        # Samovar の `Command#parse` は「渡された配列が空になったか」で未解釈トークンを
        # 検出し、`Nested#parse` は親と同じ配列オブジェクトをそのまま子へ渡す。
        # 正規化結果を新しい配列で返すと親側の配列が消費されないまま残り、親が
        # InvalidInputError を上げてしまうため、元の配列を書き換えて返す。
        def normalized_input(input)
          normalized = normalize_option_tokens(input)
          return normalized unless input.respond_to?(:replace)

          input.replace(normalized)
        end

        # `--log=debug` / `--theme=blue` のような `=` 区切りを `--log debug` 形式へ開く。
        # 値が続かないときは既定値のあるオプションだけ補い、無いものはそのまま渡して
        # Samovar の検証に委ねる。対象外のトークンは順序を保って素通しする。
        def normalize_option_tokens(input)
          tokens = input.to_a
          value_flags = self.class.value_option_flags
          normalized = []
          idx = 0

          while idx < tokens.length
            name, inline_value = tokens[idx].to_s.split('=', 2)

            unless value_flags.include?(name)
              normalized << tokens[idx]
              idx += 1
              next
            end

            fallback = BARE_VALUE_DEFAULTS[name]
            following = tokens[idx + 1]
            normalized << name

            if inline_value # --opt=value 形式（空値は既定へ倒す）
              normalized << (inline_value.empty? ? fallback.to_s : inline_value)
              idx += 1
            elsif following && !following.to_s.start_with?('-') # --opt value 形式
              normalized << following
              idx += 2
            else # 値なし（末尾・次が別オプション）
              normalized << fallback if fallback
              idx += 1
            end
          end

          normalized
        end
      end
    end
  end
end
