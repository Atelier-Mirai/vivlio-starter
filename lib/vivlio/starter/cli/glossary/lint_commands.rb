# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/glossary/lint_commands.rb
# ================================================================
# 責務:
#   用語集（glossary.yml）に基づいて Markdown ファイルの表記揺れを検出する。
#
# 検出対象:
#   - 正式名称の代わりにエイリアスが使用されている箇所
#   - 初出時にフルスペル表記が省略されている箇所
#   - スタイル指定（英字/カタカナ）に反する表記
#
# 終了コード:
#   - 0: 違反なし
#   - 2: 違反あり（CI/CD での検出用）
#
# 依存:
#   - GlossarySharedHelpers: 用語集読み込み・ファイル収集
# ================================================================

module Vivlio
  module Starter
    module CLI
      # 用語集に基づく表記揺れ検出コマンド
      module GlossaryLintCommands
        extend GlossarySharedHelpers
        module_function

        GLOSSARY_PATH_DISPLAY = GlossarySharedHelpers::GLOSSARY_DISPLAY_PATH

        def execute_glossary_lint
          glossary_path = GlossarySharedHelpers.glossary_path_or_exit('glossary:lint')
          terms = GlossarySharedHelpers.load_glossary_terms(glossary_path)
          markdown_files = GlossarySharedHelpers.collect_markdown_files
          violations = lint_markdown_files(markdown_files, terms)

          report_lint_results(violations)
        end

        def lint_markdown_files(files, terms)
          files.flat_map { |path| lint_single_file(path, terms) }
        end

        def lint_single_file(path, terms)
          original = File.read(path, encoding: 'UTF-8')
          terms.flat_map { |term| lint_term_in_file(path, original, term) }
        end

        def lint_term_in_file(path, original, term)
          alias_and_style = detect_alias_and_style_violations(path, original, term)
          alias_and_style + detect_first_full_violation(path, original, term)
        end

        def detect_alias_and_style_violations(path, original, term)
          name = term[:name]
          abbr = term[:abbr]
          aliases = term[:aliases] || []
          style = term[:style].to_s
          violations = []

          each_visible_line(original) do |line, lineno|
            aliases.each do |ali|
              next if ali.to_s.strip.empty?

              pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(ali)}(?![A-Za-z0-9_])/
              next unless line.match?(pattern)

              violations << {
                file: path,
                rule: '別表記',
                line: lineno,
                message: "エイリアス '#{ali}' が使われています。正規表記 '#{name}'#{"（または '#{abbr}'）" if abbr} を使用してください。"
              }
            end

            next if style.empty?

            case style
            when 'capitalization'
              violations.concat(capitalization_violations(path, line, lineno, name, abbr))
            when 'lowercase'
              violations.concat(lowercase_violations(path, line, lineno, name))
            when 'hyphenation'
              violations.concat(hyphenation_violations(path, line, lineno, name))
            end
          end

          violations
        end

        def capitalization_violations(path, line, lineno, name, abbr)
          violations = []
          if name.to_s =~ /[A-Za-z]/
            pattern_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/i
            pattern_exact = /(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/
            if line.match?(pattern_ci) && !line.match?(pattern_exact)
              violations << { file: path, rule: 'スタイル:大文字小文字', line: lineno,
                              message: "大文字小文字を '#{name}' に統一してください。" }
            end
          end

          if abbr.to_s =~ /[A-Za-z]/
            pattern_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(abbr)}(?![A-Za-z0-9_])/i
            pattern_exact = /(?<![A-Za-z0-9_])#{Regexp.escape(abbr)}(?![A-Za-z0-9_])/
            if line.match?(pattern_ci) && !line.match?(pattern_exact)
              violations << { file: path, rule: 'スタイル:大文字小文字', line: lineno,
                              message: "大文字小文字を '#{abbr}' に統一してください。" }
            end
          end

          violations
        end

        def lowercase_violations(path, line, lineno, name)
          return [] unless name.to_s =~ /[A-Za-z]/

          pattern_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/i
          pattern_exact = /(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/
          return [] unless line.match?(pattern_ci) && !line.match?(pattern_exact)

          [{ file: path, rule: 'スタイル:小文字', line: lineno,
             message: "小文字表記 '#{name}' に統一してください。" }]
        end

        def hyphenation_violations(path, line, lineno, name)
          return [] unless name.to_s.include?('-') && name.to_s =~ /[A-Za-z]/

          nohy = name.gsub('-', '')
          spc = name.gsub('-', ' ')
          [nohy, spc].each do |bad|
            pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(bad)}(?![A-Za-z0-9_])/
            next unless line.match?(pattern)

            return [{ file: path, rule: 'スタイル:ハイフン表記', line: lineno,
                      message: "ハイフン表記は '#{name}' に統一してください。" }]
          end

          []
        end

        def detect_first_full_violation(path, original, term)
          return [] unless term[:first_full_form]

          name = term[:name]
          abbr = term[:abbr]
          return [] if name.to_s.empty? || abbr.to_s.empty?

          full_form = "#{name}（#{abbr}）"
          first_kind = nil
          first_line = nil

          each_visible_line(original) do |line, lineno|
            idx_full = line.index(full_form)
            idx_name = line.index(name)
            idx_abbr = line.index(abbr)
            next if idx_full.nil? && idx_name.nil? && idx_abbr.nil?

            candidate = { full: idx_full, name: idx_name, abbr: idx_abbr }.compact
            first_kind, = candidate.min_by { |_, v| v }
            first_line = lineno
            break
          end

          return [] if first_kind.nil? || first_kind == :full

          [{
            file: path,
            rule: '初出:正式名（略称）',
            line: first_line,
            message: "最初の出現は '#{full_form}' にしてください。"
          }]
        end

        def each_visible_line(content)
          in_fence = false
          content.each_line.with_index(1) do |line, lineno|
            if line.match?(/```/)
              in_fence = !in_fence
              next
            end
            next if in_fence

            sanitized = line.gsub(/`[^`]*`/, '')
            yield sanitized, lineno
          end
        end

        def report_lint_results(violations)
          if violations.empty?
            puts '[glossary:lint] OK - 問題は見つかりませんでした'
            return
          end

          puts '[glossary:lint] ルール違反が見つかりました:'
          violations.each do |v|
            loc = v[:line] ? ":#{v[:line]}" : ''
            puts "- #{v[:file]}#{loc}: [#{v[:rule]}] #{v[:message]}"
          end
          exit 2
        end
      end
    end
  end
end
