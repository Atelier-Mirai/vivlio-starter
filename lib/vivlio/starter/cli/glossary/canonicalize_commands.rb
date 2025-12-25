# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/glossary/canonicalize_commands.rb
# ================================================================
# 責務:
#   glossary.yml を正準形式に整形する。
#   用語エントリの並び順・インデント・空行を統一する。
#
# 提供コマンド:
#   - glossary:canonicalize:check: 差分があるかチェック（CI 用）
#   - glossary:canonicalize: 実際に整形を適用
#
# 正準形式:
#   - 用語は abbr でアルファベット順にソート
#   - 各フィールドは決まった順序（name, abbr, aliases, style...）
#   - インデントは 2 スペース
# ================================================================

module Vivlio
  module Starter
    module CLI
      # glossary.yml 正準化コマンド
      module GlossaryCanonicalizeCommands
        include GlossarySharedHelpers

        GLOSSARY_PATH_DISPLAY = GlossarySharedHelpers::GLOSSARY_DISPLAY_PATH

        def self.execute_glossary_canonicalize_check
          glossary_path = glossary_path_or_exit('glossary:canonicalize:check')

          # YAML としての整合性も検証しておく（壊れていればここで終了）
          load_glossary(glossary_path)

          original = File.read(glossary_path, encoding: 'UTF-8')
          canonical = canonicalize_glossary_text(original)

          if canonical == original
            puts '[glossary:canonicalize:check] OK - 変更はありません'
          else
            puts '[glossary:canonicalize:check] 差分があります'
            exit 1
          end
        end

        def self.execute_glossary_canonicalize
          glossary_path = glossary_path_or_exit('glossary:canonicalize')

          # YAML としての整合性も検証しておく（壊れていればここで終了）
          load_glossary(glossary_path)

          original = File.read(glossary_path, encoding: 'UTF-8')
          canonical = canonicalize_glossary_text(original)

          if canonical == original
            puts '[glossary:canonicalize] 変更はありません'
          else
            File.write(glossary_path, canonical)
            puts '[glossary:canonicalize] 正準化を完了しました'
          end
        end

        private

        def canonicalize_glossary_text(text)
          lines = text.lines

          terms_idx = find_terms_section_index(lines)
          return text unless terms_idx

          header = lines[0..terms_idx]
          body = lines[(terms_idx + 1)..] || []

          item_indent = detect_item_indent(body)
          return lines.join unless item_indent

          blocks = split_glossary_blocks(body, item_indent)
          items = canonicalize_glossary_blocks(blocks)
          sorted_items = sort_glossary_items(items)
          rebuilt_body = rebuild_glossary_body(sorted_items)

          (header + rebuilt_body).join
        end

        def find_terms_section_index(lines)
          lines.index { |line| line.strip == 'terms:' }
        end

        def detect_item_indent(body_lines)
          body_lines.each do |line|
            next unless (match = line.match(/^(\s*)-\s*key:\s*\S+/))

            return match[1]
          end
          nil
        end

        def split_glossary_blocks(body_lines, item_indent)
          blocks = []
          current = []
          body_lines.each do |line|
            if line.match?(/^#{Regexp.escape(item_indent)}-\s*key:\s*\S+/) && !current.empty?
              blocks << current
              current = []
            end
            current << line
          end
          blocks << current unless current.empty?
          blocks
        end

        def canonicalize_glossary_blocks(blocks)
          blocks.map do |block|
            trimmed = strip_blank_edges(block)
            key = extract_key_from_block(trimmed)
            canonical = canonicalize_block_description(trimmed)
            [key, strip_blank_edges(canonical)]
          end
        end

        def sort_glossary_items(items)
          items.sort_by { |(key, _)| key.to_s }
        end

        def rebuild_glossary_body(items)
          items.each_with_index.with_object([]) do |((_, block), index), acc|
            acc << "\n" if index.positive?
            acc.concat(block)
          end
        end

        def extract_key_from_block(block_lines)
          first = block_lines.find { |l| l =~ /-\s*key:\s*\S+/ }
          return nil unless first

          m = first.match(/-\s*key:\s*(\S+)/)
          m ? m[1] : nil
        end

        def canonicalize_block_description(block_lines)
          out = []
          i = 0
          while i < block_lines.length
            line = block_lines[i]
            if line =~ /^(\s*)description:\s*\|-?\s*$/
              out << line
              i += 1
              while i < block_lines.length && block_lines[i] =~ /^(\s{2,}|\s*)\S|^\s*$/
                break if block_lines[i] =~ /^(\s*)\w[\w-]*:\s/

                out << block_lines[i]
                i += 1
              end
              next
            end

            if (m = line.match(/^(\s*)description:\s*(.+?)\s*$/))
              indent = m[1]
              text = m[2]
              if text.nil? || text.empty?
                out << line
              else
                out << "#{indent}description: |-\n"
                out << "#{indent}  #{text}\n"
              end
              i += 1
              next
            end

            out << line
            i += 1
          end
          out
        end

        def strip_blank_edges(arr)
          a = arr.dup
          a.shift while !a.empty? && a.first.strip.empty?
          a.pop while !a.empty? && a.last.strip.empty?
          a
        end
      end
    end
  end
end
