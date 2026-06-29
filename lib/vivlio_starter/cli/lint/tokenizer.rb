# frozen_string_literal: true

module VivlioStarter
  module CLI
    module Lint
      # Markdownファイルから英単語トークンを抽出する
      module Tokenizer
        module_function

        FENCE_PATTERN    = /^```/
        FRONTMATTER_SEP  = /^---\s*$/

        # vs-lint コメント記法の定義
        VS_LINT_DISABLE           = /^\s*<!--\s*vs-lint-disable\s*-->\s*$/
        VS_LINT_ENABLE            = /^\s*<!--\s*vs-lint-enable\s*-->\s*$/
        VS_LINT_DISABLE_NEXT_LINE = /^\s*<!--\s*vs-lint-disable-next-line\s*-->\s*$/

        # @param content [String] Markdownファイル全体の内容
        # @param check_code_blocks [Boolean] コードブロック内もチェックするか
        # @param path [String, nil] 警告メッセージに含めるファイルパス（省略可）
        # @return [Array<[String, Integer]>] [word, line_no] のペア配列
        def tokenize(content, check_code_blocks: false, path: nil)
          tokens           = []
          in_code_fence    = false
          in_frontmatter   = false
          line_no          = 0

          # vs-lint コメントによる除外行番号セットを構築
          excluded_lines, unclosed_disable_at = build_excluded_lines(content)
          warn_unclosed_disable(path, unclosed_disable_at) if unclosed_disable_at

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

            # vs-lint コメントによる除外
            next if excluded_lines.include?(line_no)

            extract_words(line).each { |word| tokens << [word, line_no] }
          end

          tokens
        end

        # vs-lint コメントに基づいて除外すべき行番号のセットを構築する
        # @param content [String] Markdownファイル全体の内容
        # @return [Array(Set<Integer>, Integer?)] 除外行番号セットと、
        #   未クローズ disable ブロックの開始行番号（クローズ済みなら nil）
        def build_excluded_lines(content)
          excluded_lines = Set.new
          disable_opened_at = nil
          line_no = 0

          content.each_line do |line|
            line_no += 1

            # vs-lint-disable コメント行自体を除外
            if line.match?(VS_LINT_DISABLE)
              disable_opened_at ||= line_no
              excluded_lines.add(line_no)
              next
            end

            # vs-lint-enable コメント行自体を除外
            if line.match?(VS_LINT_ENABLE)
              disable_opened_at = nil
              excluded_lines.add(line_no)
              next
            end

            # vs-lint-disable-next-line コメント行自体を除外し、次の行も除外
            if line.match?(VS_LINT_DISABLE_NEXT_LINE)
              excluded_lines.add(line_no)
              excluded_lines.add(line_no + 1)
              next
            end

            # disable ブロック内の行を除外
            excluded_lines.add(line_no) if disable_opened_at
          end

          [excluded_lines, disable_opened_at]
        end

        # vs-lint-disable が閉じられないままファイル末尾に達した場合に警告を出す。
        # 著者が誤って enable を書き忘れたケースを検知するためのガード。
        # @param path [String, nil] ファイルパス（警告メッセージ用）
        # @param opened_at [Integer] disable が開始された行番号
        def warn_unclosed_disable(path, opened_at)
          location = path ? "#{path}:#{opened_at}" : "line #{opened_at}"
          warn "[vs-lint] 警告: #{location} の <!-- vs-lint-disable --> が " \
               '<!-- vs-lint-enable --> で閉じられていません。ファイル末尾まで lint が無効化されます。'
        end

        # @param line [String] 1行のMarkdownテキスト
        # @return [Array<String>] 抽出された英単語の配列
        def extract_words(line)
          cleaned = line.dup
          cleaned.gsub!(/`[^`]*`/, ' ')                          # インラインコードを除去
          cleaned.gsub!(/<[^>]+>/, ' ')                          # HTMLタグを除去
          cleaned.gsub!(/\{[^}]*\}/, ' ')                        # Vivliostyle拡張記法 {.aki} 等
          cleaned.gsub!(/(?<![A-Za-z0-9_])@[A-Za-z][A-Za-z0-9-]*/, ' ') # 相互参照ラベル @id（メールは除外）
          cleaned.gsub!(/!?\[([^\]]*)\]\([^)]*\)/, '\1') # Markdownリンク・画像
          cleaned.gsub!(/!?\[([^\]]*)\]\[[^\]]*\]/, '\1')        # 参照リンク
          cleaned.gsub!(%r{https?://\S+}, ' ')                   # URLを除去
          cleaned.gsub!(/^#+\s*/, '')                            # 見出し記号を除去

          cleaned.scan(/[a-zA-Z]+(?:-[a-zA-Z]+)*/).select { it.length >= 2 }
        end
      end
    end
  end
end
