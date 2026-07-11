# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/post_process/html_replacer.rb
# ================================================================
# 責務:
#   ReplacementRules の組み込み置換ルールを HTML に適用するエンジン。
#
# ルール形式（ReplacementRules::Rule）:
#   - pattern      … 検索パターン（Regexp リテラル・/m 付き）
#   - replacement  … 置換文字列（$1〜$9 でキャプチャ参照）
#   - mode         … 保護モード（:text_only / :tag_aware）
#
# 用途:
#   - :::{.class} → <div> 化、p/div のねじれ修正、空段落除去
#   - クラス追加（例: <hr> → <hr class="pagebreak">）
#   - マクロ展開（@vspace など）
# ================================================================

require_relative '../common'

module VivlioStarter
  module CLI
    module PostProcessCommands
      # 組み込み置換ルール適用エンジン
      module HtmlReplacer
        module_function

        # 退避プレースホルダのマーカー。Unicode 制御文字 (U+0000) を両端に置くので
        # 原稿内やルールパターンに出現することはない。
        PRE_PLACEHOLDER_PREFIX  = "\u0000__VS_PRE__"
        CODE_PLACEHOLDER_PREFIX = "\u0000__VS_CODE__"
        TAG_PLACEHOLDER_PREFIX  = "\u0000__VS_TAG__"
        PLACEHOLDER_SUFFIX      = "__\u0000"

        # ReplacementRules::Rule の配列を適用して HTML ファイルを更新
        def process_html_file(html_file, replace_rules)
          return { changed: false, replacements: 0 } unless replace_rules&.any?

          content = File.read(html_file, encoding: 'utf-8')
          replacements = 0

          replace_rules.each do |rule|
            content, applied = apply_rule(content, rule)
            replacements += applied
          end

          if replacements.positive?
            File.write(html_file, content, encoding: 'utf-8')
            { changed: true, replacements: replacements }
          else
            { changed: false, replacements: 0 }
          end
        rescue StandardError => e
          Common.log_error("置換処理に失敗: #{html_file} - #{e.message}")
          { changed: false, replacements: 0 }
        end

        # 単一のルールを適用する。rule.mode で対象領域を絞り込んでから gsub を実行する。
        #
        # モード:
        # - :text_only    … HTML 構造（<pre>/<code> の本体、および全てのタグ定義
        #                   `<...>`）を退避し、テキストノード部分だけに適用する。
        #                   これにより `@vspace` などのマクロが `data-heading="..."` の
        #                   ような属性値の中で置換されて HTML が壊れる事故を防ぐ。
        # - :tag_aware    … `<p>` `<li ...>` `<span ...>` など HTML 構造を対象にする
        #                   ルール。<pre>/<code> 内にはそもそもこれらのリテラルタグが
        #                   存在しない（実体参照化される）ため、<pre> ブロックのみ退避
        #                   して全体に適用する。
        def apply_rule(content, rule)
          case rule.mode
          when :text_only
            with_text_scope_protected(content) do |stashed|
              replace_with_captures(stashed, rule.pattern, rule.replacement)
            end
          else # :tag_aware
            # <pre> ブロック内のテキストは置換対象外とする
            # コードブロック内の ::: 等が <div> に変換されるのを防ぐ
            pre_blocks = []
            protected = content.gsub(%r{<pre\b[^>]*>.*?</pre>}m) do |block|
              pre_blocks << block
              "#{PRE_PLACEHOLDER_PREFIX}TA#{pre_blocks.size - 1}#{PLACEHOLDER_SUFFIX}"
            end

            result, applied = replace_with_captures(protected, rule.pattern, rule.replacement)

            result = result.gsub(/#{Regexp.escape(PRE_PLACEHOLDER_PREFIX)}TA(\d+)#{Regexp.escape(PLACEHOLDER_SUFFIX)}/) do
              pre_blocks[Regexp.last_match(1).to_i]
            end
            [result, applied]
          end
        end

        # テキスト専用ルール向けに、HTML 構造を全て退避したビューをブロックへ渡す。
        # 以下の順で退避する（後続のマッチが先のプレースホルダを巻き込まないよう
        # 大きい構造から順に退避）:
        #   1. <pre>...</pre>             （フェンス付きコードブロック全体）
        #   2. <code>...</code>           （インラインコード／pre 内に残存するものも含む）
        #   3. <...>                      （開始・終了タグ、自己閉じタグ、コメント）
        # 終了後は逆順で復元する。
        def with_text_scope_protected(content)
          pre_blocks  = []
          code_blocks = []
          tags        = []

          stashed = content.gsub(%r{<pre\b[^>]*>.*?</pre>}m) do |block|
            pre_blocks << block
            "#{PRE_PLACEHOLDER_PREFIX}#{pre_blocks.size - 1}#{PLACEHOLDER_SUFFIX}"
          end
          stashed = stashed.gsub(%r{<code\b[^>]*>.*?</code>}m) do |block|
            code_blocks << block
            "#{CODE_PLACEHOLDER_PREFIX}#{code_blocks.size - 1}#{PLACEHOLDER_SUFFIX}"
          end
          stashed = stashed.gsub(/<[^>]*>/m) do |tag|
            tags << tag
            "#{TAG_PLACEHOLDER_PREFIX}#{tags.size - 1}#{PLACEHOLDER_SUFFIX}"
          end

          result, applied = yield(stashed)

          result = result.gsub(/#{Regexp.escape(TAG_PLACEHOLDER_PREFIX)}(\d+)#{Regexp.escape(PLACEHOLDER_SUFFIX)}/) do
            tags[Regexp.last_match(1).to_i]
          end
          result = result.gsub(/#{Regexp.escape(CODE_PLACEHOLDER_PREFIX)}(\d+)#{Regexp.escape(PLACEHOLDER_SUFFIX)}/) do
            code_blocks[Regexp.last_match(1).to_i]
          end
          result = result.gsub(/#{Regexp.escape(PRE_PLACEHOLDER_PREFIX)}(\d+)#{Regexp.escape(PLACEHOLDER_SUFFIX)}/) do
            pre_blocks[Regexp.last_match(1).to_i]
          end

          [result, applied]
        end

        def replace_with_captures(content, regex, replacement_str)
          applied = 0
          new_content = content.gsub(regex) do
            match_data = ::Regexp.last_match
            result = replacement_str.dup
            (1..9).each { |i| result.gsub!("$#{i}", match_data[i].to_s) }
            applied += 1
            result
          end
          [new_content, applied]
        end
      end
    end
  end
end
