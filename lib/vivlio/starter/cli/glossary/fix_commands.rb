# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # glossary:fix コマンドと自動修正ロジックを提供するモジュール
      module GlossaryFixCommands
        include GlossarySharedHelpers

        GLOSSARY_PATH_DISPLAY = GlossarySharedHelpers::GLOSSARY_DISPLAY_PATH

        FIX_DESC = {
          short: "用語集（#{GLOSSARY_PATH_DISPLAY}）に基づいて Markdown を自動修正します",
          long: <<~DESC
            用語集に基づいて Markdown を自動修正します。

            修正内容:
              - エイリアスを正規表記に置換
              - first_full_form ルールの適用
              - スタイル統一（capitalization/lowercase/hyphenation）

            対象:
              - contents/**/*.md

            例:
              vs glossary:fix
          DESC
        }.freeze

        def self.included(base)
          base.class_eval do
            desc 'glossary:fix', GlossaryFixCommands::FIX_DESC[:short]
            long_desc GlossaryFixCommands::FIX_DESC[:long]

            # ================================================================
            # Command: glossary:fix（Markdown の自動修正）
            # ------------------------------------------------
            # 概要:
            #   用語集に基づいて Markdown を自動修正する。
            #   - エイリアス置換 / 初出ルール / スタイル統一
            #   コード（フェンス/インライン）は修正対象外。
            # ================================================================
            def glossary_fix
              glossary_path = glossary_path_or_exit('glossary:fix')
              terms = load_glossary_terms(glossary_path)
              markdown_files = collect_markdown_files
              changed_files = fix_markdown_files(markdown_files, terms)

              report_fix_results(changed_files)
            end
          end
        end

        private

        def fix_markdown_files(files, terms)
          files.each_with_object([]) do |path, changed|
            next unless apply_fixes_to_file?(path, terms)

            changed << path
          end
        end

        def apply_fixes_to_file?(path, terms)
          original = File.read(path, encoding: 'UTF-8')
          segments = split_markdown_segments(original)
          segments = replace_aliases_in_segments(segments, terms)
          segments = enforce_first_full_form(segments, terms)
          segments = apply_style_fixes(segments, terms)

          fixed = rebuild_segments(segments)
          return false if fixed == original

          File.write(path, fixed)
          puts "[glossary:fix] 更新: #{path}"
          true
        end

        def split_markdown_segments(content)
          segments = []
          last = 0
          pattern = /```[\s\S]*?```|`[^`]*`/m
          content.to_enum(:scan, pattern).each do
            match = Regexp.last_match
            segments << [:text, content[last...match.begin(0)]] if match.begin(0) > last
            segments << [:code, match[0]]
            last = match.end(0)
          end
          segments << [:text, content[last..]] if last < content.length
          segments
        end

        def replace_aliases_in_segments(segments, terms)
          segments.map do |kind, text|
            next [kind, text] unless kind == :text

            [:text, replace_aliases_in_text(text, terms)]
          end
        end

        def replace_aliases_in_text(text, terms)
          terms.each_with_object(text.dup) do |term, out|
            Array(term[:aliases]).each do |ali|
              next if ali.to_s.strip.empty?

              if ali.downcase == 'vs'
                pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(ali)}(?![A-Za-z0-9_])/i
                out.gsub!(pattern) { '`vs`' }
              else
                replacement = term[:name].to_s
                pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(ali)}(?![A-Za-z0-9_])/
                out.gsub!(pattern, replacement)
              end
            end
          end
        end

        def enforce_first_full_form(segments, terms)
          state = build_first_full_state(terms)
          segments.map do |kind, text|
            next [kind, text] unless kind == :text

            [:text, enforce_first_full_in_text(text, terms, state)]
          end
        end

        def build_first_full_state(terms)
          terms.each_with_object({}) do |term, memo|
            next unless term[:first_full_form]

            name = term[:name].to_s
            abbr = term[:abbr].to_s
            next if name.empty? || abbr.empty?

            memo[term[:key]] = { handled: false }
          end
        end

        def enforce_first_full_in_text(text, terms, state)
          result = text.dup
          terms.each do |term|
            next unless term[:first_full_form]

            info = state[term[:key]]
            next unless info

            name = term[:name].to_s
            abbr = term[:abbr].to_s
            next if name.empty? || abbr.empty?

            full = "#{name}（#{abbr}）"

            if info[:handled]
              pattern = /#{Regexp.escape(name)}(?!（#{Regexp.escape(abbr)}）)/
              result = result.gsub(pattern, abbr)
              next
            end

            if result.include?(full)
              info[:handled] = true
              next
            end

            idx_name = result.index(name)
            idx_abbr = result.index(abbr)
            next if idx_name.nil? && idx_abbr.nil?

            target = if !idx_abbr.nil? && (idx_name.nil? || idx_abbr < idx_name)
                       :abbr
                     else
                       :name
                     end

            result = if target == :abbr
                       result.sub(abbr, full)
                     else
                       result.sub(name, full)
                     end
            info[:handled] = true

            pattern = /#{Regexp.escape(name)}(?!（#{Regexp.escape(abbr)}）)/
            result = result.gsub(pattern, abbr)
          end
          result
        end

        def apply_style_fixes(segments, terms)
          segments.map do |kind, text|
            next [kind, text] unless kind == :text

            [:text, apply_style_to_text(text, terms)]
          end
        end

        def apply_style_to_text(text, terms)
          terms.each_with_object(text.dup) do |term, out|
            style = term[:style].to_s
            next if style.empty?

            name = term[:name].to_s
            abbr = term[:abbr].to_s

            case style
            when 'capitalization'
              out.replace(enforce_capitalization(out, name))
              out.replace(enforce_capitalization(out, abbr))
            when 'lowercase'
              out.replace(enforce_lowercase(out, name))
            when 'hyphenation'
              out.replace(enforce_hyphenation(out, name))
            end
          end
        end

        def enforce_capitalization(text, token)
          return text unless token.to_s =~ /[A-Za-z]/ && !token.to_s.empty?

          pattern_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(token)}(?![A-Za-z0-9_])/i
          text.gsub(pattern_ci, token)
        end

        def enforce_lowercase(text, token)
          return text unless token.to_s =~ /[A-Za-z]/ && !token.to_s.empty?

          pattern_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(token)}(?![A-Za-z0-9_])/i
          text.gsub(pattern_ci) { token }
        end

        def enforce_hyphenation(text, token)
          return text unless token.to_s.include?('-') && token.to_s =~ /[A-Za-z]/

          nohy = token.tr('-', '')
          spc = token.tr('-', ' ')
          [nohy, spc].reduce(text) do |memo, bad|
            pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(bad)}(?![A-Za-z0-9_])/i
            memo.gsub(pattern, token)
          end
        end

        def rebuild_segments(segments)
          segments.map { |_kind, str| str }.join
        end

        def report_fix_results(changed_files)
          if changed_files.empty?
            puts '[glossary:fix] 変更は必要ありません'
            return
          end

          puts "[glossary:fix] #{changed_files.size} 件のファイルを更新しました。"
          puts '確認するには `vs glossary:lint` を実行してください。'
        end
      end
    end
  end
end
