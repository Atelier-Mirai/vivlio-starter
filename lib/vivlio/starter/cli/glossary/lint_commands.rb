# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # glossary:lint コマンド群とその判定ロジックを提供するモジュール
      module GlossaryLintCommands
        include GlossarySharedHelpers

        LINT_DESC = {
          short: '用語集（config/glossary.yml）に基づいて Markdown を検査します',
          long: <<~DESC
            用語集に基づいて Markdown を検査します。

            対象:
              - contents/**/*.md
              - config/glossary.yml

            例:
              vs glossary:lint
          DESC
        }.freeze

        def self.included(base)
          base.class_eval do
            desc 'glossary:lint', GlossaryLintCommands::LINT_DESC[:short]
            long_desc GlossaryLintCommands::LINT_DESC[:long]

            # ================================================================
            # Command: glossary:lint（Markdown の検査）
            # ------------------------------------------------
            # 概要:
            #   用語集に基づいて Markdown を検査し、別表記/初出/スタイルの逸脱を検出する。
            #   コード（フェンス/インライン）は検査対象外。
            # ================================================================
            def glossary_lint
              glossary_path = glossary_path_or_exit('glossary:lint')
              terms = load_glossary_terms(glossary_path)
              markdown_files = collect_markdown_files
              violations = lint_markdown_files(markdown_files, terms)

              report_lint_results(violations)
            end
          end
        end

        private

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
