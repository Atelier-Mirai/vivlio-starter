# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/post_process/html_replacer.rb
# ================================================================
# 責務:
#   config/post_replace_list.yml の置換ルールを HTML に適用する。
#
# 置換ルール形式:
#   - f: 検索パターン（正規表現）
#   - r: 置換文字列（$1〜$9 でキャプチャ参照）
#
# 用途:
#   - 特殊文字の変換（例: 〈〉→《》）
#   - クラス追加（例: <p> に特定クラスを付与）
#   - カスタム記法の展開
# ================================================================

require_relative '../common'

module Vivlio
  module Starter
    module CLI
      module PostProcessCommands
        # YAML 置換ルール適用モジュール
        module HtmlReplacer
          module_function

          # Prism ハイライト済みコードブロック内に適用したいルールの目印。
          # パターン文字列に `class="token` を含むルールのみ、<pre>...</pre>
          # の内側も対象とする（C 言語の `/*← */` や HTML コメント強調など）。
          CODE_AWARE_PATTERN_MARKER = 'class="token'

          # 退避プレースホルダのマーカー。Unicode 制御文字 (U+0000) を両端に置くので
          # 原稿内やルールパターンに出現することはない。
          PRE_PLACEHOLDER_PREFIX  = "\u0000__VS_PRE__"
          CODE_PLACEHOLDER_PREFIX = "\u0000__VS_CODE__"
          TAG_PLACEHOLDER_PREFIX  = "\u0000__VS_TAG__"
          PLACEHOLDER_SUFFIX      = "__\u0000"

          # YAML置換ルールを適用してHTMLファイルを更新
          def process_html_file(html_file, replace_rules)
            return { changed: false, replacements: 0 } unless replace_rules&.any?

            content = File.read(html_file, encoding: 'utf-8')
            replacements = 0

            replace_rules.each do |rule|
              pattern_str = rule['f']
              replacement_str = rule['r']
              next unless pattern_str && replacement_str

              begin
                regex = Regexp.new(pattern_str, Regexp::MULTILINE)
                content, applied = apply_rule(content, regex, replacement_str, pattern_str)
                replacements += applied
              rescue RegexpError => e
                Common.log_warn("不正な正規表現: #{pattern_str} - #{e.message}")
              end
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

          # 単一のルールを適用する。ルールのパターン文字列からモードを判定し、
          # 対象領域を絞り込んでから gsub を実行する。
          #
          # モード:
          # - :code_aware   … パターンに `class="token` を含む。<pre> 内も含めて全体に適用
          #                   （Prism ハイライト強調ルールを意図）。
          # - :text_only    … パターンに `<` を含まない。HTML 構造（<pre>/<code> の本体、
          #                   および全てのタグ定義 `<...>`）を退避し、テキストノード部分
          #                   だけに適用する。これにより `@clear` などのマクロが
          #                   `data-heading="..."` のような属性値の中で置換されて
          #                   HTML が壊れる事故を防ぐ。
          # - :tag_aware    … 上記以外。`<p>` `<li ...>` `<span ...>` など HTML 構造を
          #                   対象にするルール。<pre>/<code> 内にはそもそもこれらの
          #                   リテラルタグが存在しない（実体参照化される）ため、
          #                   追加の保護なしで全体に適用する。
          def apply_rule(content, regex, replacement_str, pattern_str)
            case rule_mode(pattern_str)
            when :code_aware
              # language-markdown 内のネストされたコードブロックは退避して
              # [!] 等の強調ルールが記法説明用コードに適用されるのを防ぐ
              md_blocks = []
              protected = content.gsub(%r{<pre\b[^>]*\bclass="[^"]*\blanguage-markdown\b[^"]*"[^>]*>.*?</pre>}m) do |block|
                md_blocks << block
                "#{PRE_PLACEHOLDER_PREFIX}MD#{md_blocks.size - 1}#{PLACEHOLDER_SUFFIX}"
              end

              result, applied = replace_with_captures(protected, regex, replacement_str)

              result = result.gsub(/#{Regexp.escape(PRE_PLACEHOLDER_PREFIX)}MD(\d+)#{Regexp.escape(PLACEHOLDER_SUFFIX)}/) do
                md_blocks[Regexp.last_match(1).to_i]
              end
              [result, applied]
            when :text_only
              with_text_scope_protected(content) do |stashed|
                replace_with_captures(stashed, regex, replacement_str)
              end
            else # :tag_aware
              replace_with_captures(content, regex, replacement_str)
            end
          end

          def rule_mode(pattern_str)
            return :code_aware if pattern_str.include?(CODE_AWARE_PATTERN_MARKER)
            return :text_only unless pattern_str.include?('<')

            :tag_aware
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
end
