# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/samovar/option_token_normalizer.rb
# ================================================================
# 責務:
#   Samovar へ渡す前に引数トークンを正規化する。
#   (1) `--opt=value` を `--opt value` へ開き、値が続かないオプションには既定値を補う
#   (2) オプション群と位置引数群を、そのコマンドの宣言順に合わせて並べ替える
#
# なぜ必要か:
#   Samovar の `Options#parse` はフラグ文字列の完全一致でしかオプションを引けず
#   （`@keyed` のハッシュ参照）、`=` を分割する処理を持たない。そのため
#   `--log=debug` は「解釈できないトークン」として弾かれる。
#   加えて `Options` は `input.first` が既知フラグである間しか消費せず、
#   `Table#parse` は各行を宣言順に 1 回ずつしか処理しないため、オプションが
#   位置引数を挟んで分かれていると必ず失敗する。コマンドごとに宣言順が違う
#   （`vs build 10 --no-clean` は通るが `vs lint 10 --fix` は通らない等）ため、
#   著者から見て規則が推測できない CLI になっていた。
#
# 並べ替えは Samovar へ渡す内部形式の話であり、著者の打ち方は制約しない。
# どちらの順で打っても同じ形へ揃うため結果が一致する。
#   vs build 10 --no-clean  →  10 --no-clean  →  targets=["10"] clean=false
#   vs build --no-clean 10  →  10 --no-clean  →  targets=["10"] clean=false
#
# 使い方:
#   公開コマンドの基底クラス `VsCommand` が prepend 済みのため、個別の指定は不要。
#   対象フラグはコマンドの options 定義から自動導出するため、オプションを
#   増やしても宣言の追加は要らない。
#
# 仕様: docs/archives/cli-argument-parsing-spec.md Part 1
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
          # options 定義に現れる全フラグ名。トークンを「オプション」と「位置引数」へ
          # 仕分けるのに使う。BooleanFlag は `alternatives` に `--no-xxx` を持つため、
          # prefix と併せて集めれば `--no-clean` のような否定形も文字列一致で拾える。
          # @return [Array<String>] `--clean` `--no-clean` `-h` のようなフラグ名
          def all_option_flags
            @all_option_flags ||= option_flag_objects.flat_map { [it.prefix, *it.alternatives] }.freeze
          end

          # options 定義から「値を取るフラグ」の名前を集める。
          # Samovar の ValueFlag は値なしフラグ（`--high` など）も表現するため、
          # 値プレースホルダを持たないもの（boolean?）を除いて判定する。
          # @return [Array<String>] `--log` `-s` のようなフラグ名（短縮形を含む）
          def value_option_flags
            @value_option_flags ||= option_flag_objects
                                    .select { it.is_a?(Samovar::ValueFlag) && !it.boolean? }
                                    .flat_map { [it.prefix, *it.alternatives] }
                                    .freeze
          end

          # オプション群を位置引数より前に並べるべきか。
          # Samovar の `Table#parse` は行を宣言順に 1 回ずつ処理し、`Options` は
          # `input.first` が既知フラグである間しか消費しない。つまりオプションは
          # 「options 行が回ってくる時点で先頭に並んでいる」必要があり、寄せる向きは
          # そのコマンドの宣言順で決まる。
          def options_declared_first?
            return @options_declared_first unless @options_declared_first.nil?

            rows = table.merged.each.to_a.select { it.respond_to?(:parse) }
            options_at = rows.index { it.is_a?(Samovar::Options) }
            argument_at = rows.index { it.is_a?(Samovar::Many) || it.is_a?(Samovar::One) }

            # 片方しか持たないコマンドは並べ替えの余地がない（どちらでも結果は同じ）
            @options_declared_first = options_at.nil? || argument_at.nil? || options_at < argument_at
          end

          private

          # 継承したオプションも拾えるよう merged 済みのテーブルを走査する
          def option_flag_objects
            table.merged.each.to_a.grep(Samovar::Options)
                 .flat_map { it.each.to_a }
                 .flat_map { it.flags.each.to_a }
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

        # `--log=debug` のような `=` 区切りを `--log debug` へ開き、オプション群と
        # 位置引数群をコマンドの宣言順に合わせて並べ替える。著者がどちらの順で打っても
        # 同じ形へ揃うため、`vs build 10 --no-clean` と `vs build --no-clean 10` が
        # 同じ結果になる。各群の内部の相対順序は保つ（`vs rename 11 12` の 11 と 12 は
        # 順序に意味がある）。
        def normalize_option_tokens(input)
          tokens = input.to_a
          all_flags = self.class.all_option_flags
          value_flags = self.class.value_option_flags
          option_tokens = []
          argument_tokens = []
          idx = 0

          while idx < tokens.length
            token = tokens[idx]
            name, inline_value = token.to_s.split('=', 2)

            # 未知のトークンと、値を取らないフラグへの `=` 付き指定（`--no-clean=1` など）は
            # 位置引数側へ送り、従来どおり Samovar に 🔴 を出させる。黙ってオプション扱いすると
            # 綴り間違いに気づけなくなる。
            if !all_flags.include?(name) || (inline_value && !value_flags.include?(name))
              argument_tokens << token
              idx += 1
              next
            end

            fallback = BARE_VALUE_DEFAULTS[name]
            following = tokens[idx + 1]
            option_tokens << name

            if inline_value # --opt=value 形式（空値は既定へ倒す）
              option_tokens << (inline_value.empty? ? fallback.to_s : inline_value)
              idx += 1
            elsif value_flags.include?(name) && following && !following.to_s.start_with?('-') # --opt value 形式
              option_tokens << following
              idx += 2
            else # 値なし（ブールフラグ・末尾・次が別オプション）
              option_tokens << fallback if fallback
              idx += 1
            end
          end

          if self.class.options_declared_first?
            option_tokens + argument_tokens
          else
            argument_tokens + option_tokens
          end
        end
      end
    end
  end
end
