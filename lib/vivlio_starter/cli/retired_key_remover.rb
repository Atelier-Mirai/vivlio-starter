# frozen_string_literal: true

# ================================================================
# Module: RetiredKeyRemover
# ================================================================
# 責務:
#   config/book.yml から廃止キー（ConfigKeys::RETIRED）を、行単位で取り除く。
#   値を別のキーへ移した廃止キー（moved_to:）は、消さずに移す（multivolume-spec.md §3.5）。
#   vs upgrade の「著者データの整理」が使う（改善案.md #114）。
#
# なぜ YAML を読んで書き直さないか:
#   book.yml は著者が手で育てる設定で、キーごとの説明コメントや並びに意味がある。
#   Hash に読んで to_yaml で書き直すと、それがすべて消える。消すのは廃止キーの行
#   （と、その下の入れ子）だけにして、ほかの行には一切触れない。
#
# 安全策:
#   行の字下げからキーの位置を推し量るので、ブロックスカラーの中身や流れ形式
#   （`verify: { images: true }`）は読み違えうる。そこで書き換えた結果を YAML として
#   読み直し、「廃止キーとその下だけが消え、ほかのキーは 1 つも変わっていない」ことを
#   確かめる。確かめられなければ nil を返し、呼び出し側は書き込まない（従来どおり
#   警告が残り、著者が手で消せる）。
# ================================================================

require 'yaml'
require 'set'

module VivlioStarter
  module CLI
    module RetiredKeyRemover
      extend self

      # 字下げ・キー名・コロンの行（コメント行と配列の項目は含まない）
      KEY_LINE = /\A(?<indent> *)(?<key>[A-Za-z_][\w-]*)[ \t]*:(?=\s|\z)/

      # 書かれている廃止キーのパス。
      # @param text [String] book.yml の中身
      # @param retired_paths [Array<Array<Symbol>>] ConfigKeys::RETIRED のキー
      # @return [Array<Array<String>>] 例: [["verify", "images"]]
      def authored(text, retired_paths)
        written = key_paths(text)
        retired_paths.map { it.map(&:to_s) }.select { written.include?(it) }
      rescue Psych::Exception
        []
      end

      # 廃止キーを取り除いた book.yml の中身を返す。
      #
      # 消した結果、親の下にキーが 1 つも残らなければ親も消す（`spellcheck:` だけが
      # 残ると、値の無いセクションになる）。
      # @param text [String] book.yml の中身
      # @param paths [Array<Array<String>>] 消すキーのパス
      # @return [String, nil] 書き換えた中身。行から特定できない・読み直しで食い違う場合は nil
      def remove(text, paths)
        lines = text.lines
        pending = paths.dup
        removed = []

        until pending.empty?
          path = pending.shift
          range = block_range(lines, path) or return nil
          lines.slice!(range)
          removed << path
          parent = path[0...-1]
          pending << parent if parent.any? && !pending.include?(parent) && empty_block?(lines, parent)
        end

        result = lines.join
        verified?(text, result, removed) ? result : nil
      end

      # 廃止キーの値を、移した先のキーへ移した book.yml の中身を返す。
      #
      # 移した先がまだ無ければ、その親（book:）の最後に同じ値の行を足してから、元の行を消す。
      # 値の後ろの注釈も一緒に写す。移した先がすでにあれば（手で移した後など）、そちらを残して
      # 元の行だけを消す。
      # @param text [String] book.yml の中身
      # @param from [Array<String>] 廃止キーのパス（例: ["output", "cover"]）
      # @param to [Array<String>] 移した先のパス（例: ["book", "cover"]）
      # @return [String, nil] 書き換えた中身。行から特定できない・読み直しで食い違う場合は nil
      def move(text, from, to)
        return remove(text, [from]) if key_paths(text).include?(to)

        lines = text.lines
        source = key_line_index(lines, from) or return nil
        value = lines[source].sub(KEY_LINE, '').strip
        # 値が次の行からの入れ子（ブロック）なら、行で写せない
        return nil if value.empty? || value.start_with?('|', '>')

        parent = block_range(lines, to[0...-1]) or return nil
        # 字下げは親の下の最初のキーにそろえる（孫のキーの字下げを拾わない）
        child = parent.to_a.drop(1).find { lines[it].match?(KEY_LINE) } or return nil
        indent = lines[child][KEY_LINE, :indent]
        lines.insert(parent.last + 1, "#{indent}#{to.last}: #{value}\n")

        result = remove(lines.join, [from]) or return nil
        moved?(text, result, from, to) ? result : nil
      end

      private

      # 移した先に元の値が入り、元のキーとその下だけが無くなり、ほかは変わっていないか
      def moved?(before, after, from, to)
        before_yaml = YAML.safe_load(before, aliases: true)
        after_yaml = YAML.safe_load(after, aliases: true)
        expected = key_paths(before).reject { it.first(from.size) == from } + [to]
        after_yaml.dig(*to) == before_yaml.dig(*from) && key_paths(after) == expected.to_set
      rescue Psych::Exception
        false
      end

      # キーの行から、その下の入れ子（字下げの深い行）の終わりまで。
      # 末尾の空行と、キーより浅い字下げのコメントは、次のキーの前置きなので残す。
      def block_range(lines, path)
        start = key_line_index(lines, path) or return nil
        indent = lines[start][KEY_LINE, :indent].size
        last = start
        (start + 1...lines.size).each do |i|
          line = lines[i]
          next if line.strip.empty?
          break if line[/\A */].size <= indent

          last = i
        end
        start..last
      end

      # 親の下に、キーの行が 1 つも残っていないか
      def empty_block?(lines, path)
        range = block_range(lines, path) or return false
        lines[range].drop(1).none? { it.match?(KEY_LINE) }
      end

      # 字下げで親子をたどり、path に当たるキーの行を探す
      def key_line_index(lines, path)
        stack = []
        lines.each_with_index do |line, i|
          m = line.match(KEY_LINE) or next
          indent = m[:indent].size
          stack.pop while stack.any? && stack.last[0] >= indent
          stack << [indent, m[:key]]
          return i if stack.map(&:last) == path
        end
        nil
      end

      # 消したキーとその下だけが無くなり、ほかのキーがそのまま残っているか
      def verified?(before, after, removed)
        expected = key_paths(before).reject { |path| removed.any? { path.first(it.size) == it } }
        key_paths(after) == expected.to_set
      rescue Psych::Exception
        false
      end

      # 入れ子のキーのパスの集合（文字列）
      def key_paths(text)
        root = YAML.safe_load(text, aliases: true) || {}
        collect(root, [], Set[])
      end

      def collect(node, prefix, into)
        return into unless node.is_a?(Hash)

        node.each do |key, value|
          path = prefix + [key.to_s]
          into << path
          collect(value, path, into)
        end
        into
      end
    end
  end
end
