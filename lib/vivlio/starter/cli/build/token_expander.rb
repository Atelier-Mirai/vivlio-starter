# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/build/token_expander.rb
# ================================================================
# 責務:
#   build コマンドの引数トークンを実在する Markdown ファイル名に展開する。
#
# トークン形式:
#   - 章番号: "45" → contents/45-*.md にマッチ
#   - 範囲: "45-47" → 45〜47 の章番号を持つ全ファイル
#   - ベース名: "45-first-html" → 完全一致
#   - カンマ区切り: "45,47,49" → 複数指定
#
# 使用例:
#   expand_token_to_basenames('45')       # => ['45-first-html.md']
#   expand_token_to_basenames('45-47')    # => ['45-first-html.md', ...]
#   expand_tokens_to_targets(['45', '54-56']) # => 重複なしで展開
#
# 依存:
#   - Common::CONTENTS_DIR: 章ファイルの格納ディレクトリ
# ================================================================

module Vivlio
  module Starter
    module CLI
      module BuildCommands
        # build 引数のトークン展開モジュール
        module TokenExpander
          # contents/ 以下の全 .md ファイルのベース名を取得
          def list_contents_basenames
            Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).map { |p| File.basename(p) }
          end

          # ベース名から章番号部分だけを整数として取得する
          def chapter_number_from_basename(basename)
            (basename[/^(\d+)-/, 1] || nil)&.to_i
          end

          # 指定レンジに収まる章ベース名をフィルタリングして返す
          def find_basenames_in_range(from_num, to_num)
            a, b = [from_num.to_i, to_num.to_i].minmax
            list_contents_basenames.select do |bn|
              n = chapter_number_from_basename(bn)
              n && n >= a && n <= b
            end
          end

          # トークン1つを展開して対象ベース名の配列に変換する
          #
          # @param token [String] 章番号('45')、範囲('45-47')、ベース名('45-first-html')
          # @return [Array<String>] マッチしたベース名の配列
          def expand_token_to_basenames(token)
            t = token.to_s.strip
            return [] if t.empty?

            # 範囲指定: 45-47
            return find_basenames_in_range(::Regexp.last_match(1), ::Regexp.last_match(2)) if t =~ /(\A\d+)-(\d+\z)/

            # 章番号のみ: 45
            return list_contents_basenames.select { |bn| bn.start_with?("#{t}-") } if t =~ /\A\d+\z/

            # 明示的なベース名（contents/ プレフィックスあり/なし、.md あり/なし）
            name = t.sub(%r{\A#{Regexp.escape(Common::CONTENTS_DIR)}/}, '')
            name = "#{name}.md" unless name.end_with?('.md')
            path = File.join(Common::CONTENTS_DIR, name)
            File.exist?(path) ? [name] : []
          end

          # トークン配列を章ベース名配列として重複なく取得する
          #
          # @param tokens [Array<String>] トークンの配列
          # @return [Array<String>] ベース名の配列（重複なし）
          def expand_tokens_to_targets(tokens)
            Array(tokens).compact.flat_map { |tok| expand_token_to_basenames(tok) }.uniq
          end
        end
      end
    end
  end
end
