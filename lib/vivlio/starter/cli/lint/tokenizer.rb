# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      module Lint
        # Markdownファイルから英単語トークンを抽出する
        module Tokenizer
          module_function

          INLINE_IGNORE_MD = /<!--\s*spellcheck:ignore\s*-->/
          INLINE_IGNORE_RE = /#@#\s*spellcheck:ignore/
          FENCE_PATTERN    = /^```/
          FRONTMATTER_SEP  = /^---\s*$/

          # @param content [String] Markdownファイル全体の内容
          # @param check_code_blocks [Boolean] コードブロック内もチェックするか
          # @return [Array<[String, Integer]>] [word, line_no] のペア配列
          def tokenize(content, check_code_blocks: false)
            tokens           = []
            in_code_fence    = false
            in_frontmatter   = false
            line_no          = 0

            content.each_line do |line|
              line_no += 1

              # YAMLフロントマター（先頭 --- 〜 --- ）をスキップ
              if line_no == 1 && line.match?(FRONTMATTER_SEP)
                in_frontmatter = true
                next
              end

              if in_frontmatter
                in_frontmatter = false if line.match?(FRONTMATTER_SEP)
                next
              end

              # コードフェンスのトグル
              if line.match?(FENCE_PATTERN)
                in_code_fence = !in_code_fence
                next
              end

              # コードブロック内のスキップ
              next if in_code_fence && !check_code_blocks

              # spellcheck:ignore 行のスキップ
              next if line.match?(INLINE_IGNORE_MD) || line.match?(INLINE_IGNORE_RE)

              extract_words(line).each { |word| tokens << [word, line_no] }
            end

            tokens
          end

          # @param line [String] 1行のMarkdownテキスト
          # @return [Array<String>] 抽出された英単語の配列
          def extract_words(line)
            cleaned = line.dup
            cleaned.gsub!(/`[^`]*`/, ' ')                          # インラインコードを除去
            cleaned.gsub!(/<[^>]+>/, ' ')                          # HTMLタグを除去
            cleaned.gsub!(/\{[^}]*\}/, ' ')                        # Vivliostyle拡張記法 {.aki} 等
            cleaned.gsub!(/!?\[([^\]]*)\]\([^\)]*\)/, '\1')        # Markdownリンク・画像
            cleaned.gsub!(/!?\[([^\]]*)\]\[[^\]]*\]/, '\1')        # 参照リンク
            cleaned.gsub!(%r{https?://\S+}, ' ')                   # URLを除去
            cleaned.gsub!(/^#+\s*/, '')                            # 見出し記号を除去

            cleaned.scan(/[a-zA-Z]+(?:-[a-zA-Z]+)*/).select { _1.length >= 2 }
          end
        end
      end
    end
  end
end
