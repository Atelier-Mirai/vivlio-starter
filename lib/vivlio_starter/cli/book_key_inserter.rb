# frozen_string_literal: true

# ================================================================
# Module: BookKeyInserter
# ================================================================
# 責務:
#   雛形で増えたキーを、著者の config/book.yml へ行単位で差し込む。
#   vs upgrade が使う（scaffold-update-notice-spec.md §10）。
#
# なぜ雛形を土台に著者の値を重ねないか:
#   著者のコメントや、コメントにして残した別の値（`# use: b5_standard`）が消え、
#   雛形に無いキーを別に足す処理と、1 行形式・複数行の値を書いたとおりに戻す処理も要る。
#   差し込むだけなら、著者の行には 1 行も触れずに済む。
#
# 安全策:
#   RetiredKeyRemover と同じく、行の字下げからキーの位置を推し量るので、流れ形式の親
#   （`theme: { color: red }`）は読み違えうる。そこで差し込んだ結果を YAML として読み直し、
#   「足したキーのほかは 1 つも変わらず、足したキーの値は雛形と同じ」ことを確かめる。
#   確かめられないキーは足さずに返し、呼び出し側は行を案内して著者に任せる。
# ================================================================

require 'date'
require 'yaml'
require_relative 'retired_key_remover'

module VivlioStarter
  module CLI
    module BookKeyInserter
      extend self

      # text は差し込んだ後の中身、added と skipped は足したキーと足せなかったキー
      Result = Data.define(:text, :added, :skipped)

      # `{{MAIN_TITLE}}` は vs new が埋める印。空のまま足す
      PLACEHOLDER = /\{\{[A-Z_]+\}\}/

      # @param text [String] 著者の book.yml の中身
      # @param scaffold_text [String] 雛形の book.yml の中身
      # @param keys [Array<String>] 足すキー（雛形の並び。例: "theme.lead_size"）
      # @return [Result]
      def insert(text, scaffold_text, keys)
        scaffold = scaffold_text.gsub(PLACEHOLDER, '').lines
        added, skipped = [[], []]
        current = keys.reduce(text) do |book, key|
          updated = insert_key(book, scaffold, key.split('.'))
          (updated ? added : skipped) << key
          updated || book
        end
        Result.new(text: current, added:, skipped:)
      end

      private

      def insert_key(text, scaffold, path)
        # `section: { min: 1 }` の min には雛形にも自分の行が無く、写す行が決まらない
        source = RetiredKeyRemover.block_range(scaffold, path) or return nil

        lines = (text.end_with?("\n") ? text : "#{text}\n").lines
        place = insertion_point(lines, scaffold, path) or return nil

        block = copied_block(scaffold, source, place)
        result = lines.dup.insert(place.at, *block).join
        verified?(text, result, scaffold, path) ? result : nil
      rescue Psych::Exception
        nil
      end

      # 差し込む行と、そこでの字下げ。after_parent は親の真下か（空行を挟まない）
      Place = Data.define(:at, :indent, :after_parent)

      # 雛形で前にあるキーのうち、著者のファイルにある最も近いキーの後ろ。無ければ親の真下
      def insertion_point(lines, scaffold, path)
        parent = path[0...-1]
        anchor = previous_keys(scaffold, path).filter_map { RetiredKeyRemover.block_range(lines, parent + [it]) }.first
        return after_key(lines, anchor) if anchor

        return below_top(lines) if parent.empty?

        range = RetiredKeyRemover.block_range(lines, parent) or return nil
        Place.new(at: range.first + 1, indent: child_indent(lines, range), after_parent: true)
      end

      # 雛形で同じ親の下の、そのキーより前のキー（近い順）
      def previous_keys(scaffold, path)
        settings = load_yaml(scaffold.join)
        siblings = path[0...-1].reduce(settings) { |node, key| node.fetch(key) }.keys.map(&:to_s)
        siblings.take_while { it != path.last }.reverse
      end

      # キーの後ろへ差し込む。キーの下に残した別の値（`# use: …`）は、そのキーの続きなので越える
      def after_key(lines, range)
        indent = indent_of(lines[range.first])
        at = range.last + 1
        finish = at
        finish += 1 while comment?(lines[finish]) && indent_of(lines[finish]) == indent
        # すぐ下にキーが続くなら、そのコメントは次のキーの説明なので越えない
        key_follows = lines[finish]&.match?(RetiredKeyRemover::KEY_LINE)
        Place.new(at: key_follows ? at : finish, indent:, after_parent: false)
      end

      def below_top(lines)
        first = lines.index { it.match?(RetiredKeyRemover::KEY_LINE) } || lines.size
        Place.new(at: first, indent: 0, after_parent: true)
      end

      # 親の下のキーの字下げ。子がまだ無ければ 2 字深くする
      def child_indent(lines, range)
        child = range.to_a.drop(1).find { lines[it].match?(RetiredKeyRemover::KEY_LINE) }
        child ? indent_of(lines[child]) : indent_of(lines[range.first]) + 2
      end

      # 雛形の行を、上のコメントと一緒に、著者の字下げへそろえて写す
      def copied_block(scaffold, range, place)
        source_indent = indent_of(scaffold[range.first])
        start = range.first
        start -= 1 while start.positive? && comment?(scaffold[start - 1]) && indent_of(scaffold[start - 1]) == source_indent

        shift = place.indent - source_indent
        block = scaffold[start..range.last].map { shifted(it, shift) }
        spaced = start.positive? && scaffold[start - 1].strip.empty? && !place.after_parent
        spaced ? ["\n", *block] : block
      end

      def shifted(line, shift)
        return line if line.strip.empty?

        "#{' ' * [indent_of(line) + shift, 0].max}#{line.lstrip}"
      end

      def comment?(line) = !line.nil? && line.lstrip.start_with?('#')

      def indent_of(line) = line[/\A */].size

      # 足したキーのほかは変わらず、足したキーの値は雛形と同じか
      def verified?(before, after, scaffold, path)
        written = load_yaml(after)
        parent = path[0...-1].reduce(written) { |node, key| node.fetch(key) }
        value = parent.delete(path.last)
        original = before.strip.empty? ? {} : load_yaml(before)
        written == original && value == path.reduce(load_yaml(scaffold.join)) { |node, key| node.fetch(key) }
      rescue KeyError, TypeError, NoMethodError
        false
      end

      def load_yaml(text) = YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)
    end
  end
end
