# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/config_guide.rb
# ================================================================
# 責務:
#   vs config:book・vs config:catalog・vs config:talk の本体。設定ファイルの書き方を
#   見せる（config-command-spec.md）。読むだけで、どのファイルも書き換えない。
#
# なぜ雛形のコメントを読むか:
#   説明を別に持つと雛形とずれる。雛形の設定ファイルにはキーの説明がすでに書かれていて、
#   著者が vs new で受け取る文章と同じものを見せられる（§3）。
#
# なぜ CONFIG を読まないか:
#   CONFIG は既定値をマージした後の値なので、「書いたのか、書いていないのか」が分からない。
#   本の外でも動かすので、Common.ensure_configured! も呼ばない（§6）。
#
# なぜ 3 つの見せ方が違うか:
#   book.yml はキーと説明の表だが、catalog.yml の値はその本の章立て、talk.yml の大半は
#   その本の話者で、雛形の値を見せても参考にならない。キーを引くのは book.yml と
#   talk.yml の display: だけで、ほかは書き方の説明と、その本の中身を見せる（§2）。
# ================================================================

require 'date'
require 'yaml'
require_relative 'common'
require_relative 'config_keys'
require_relative 'new'
require_relative 'pre_process/talk_registry'
require_relative 'retired_key_remover'
require_relative 'scaffold_lock'

module VivlioStarter
  module CLI
    # 設定ファイルの書き方を見せる
    module ConfigGuide
      BOOK_FILE = ScaffoldLock::BOOK_RELATIVE

      module_function

      def scaffold_text(scaffold_source, file) = File.read(File.join(scaffold_source, file), encoding: 'utf-8')

      def load_yaml(text) = YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)

      def print_listing(lines) = lines.each { puts "  #{it}".rstrip }

      # キーと説明の表として読める設定ファイルを引く。ファイルごとの違いは下の Book・Talk が埋める
      class KeyGuide
        # 雛形の 1 キーぶんの説明。
        # lead はキーのすぐ上のコメント行、notes は検索に使う説明の文、summary は一覧の 1 行
        Entry = Data.define(:key, :path, :lead, :notes, :summary)

        NOT_WRITTEN = Object.new.freeze

        # @param scaffold_source [String] 雛形のルート
        def initialize(scaffold_source: NewCommands::SCAFFOLD_SOURCE)
          # `{{MAIN_TITLE}}` は vs new が埋める印で、著者には見せない
          source = ConfigGuide.scaffold_text(scaffold_source, file).gsub(/\{\{[A-Z_]+\}\}/, '')
          @lines = source.lines(chomp: true)
          @scaffold = ConfigGuide.load_yaml(source)
          @known_keys = ScaffoldLock.book_keys(source).select { in_scope?(it) }
          @entries = parse_entries
        end

        # @param query [String, nil] キーか探す言葉。nil ならファイルの全体の案内
        # @return [Integer] 終了コード（見つからなければ 1）
        def show(query)
          query = query.to_s.strip
          return show_overview if query.empty?
          return show_key(query, query.split('.')) if known_keys.include?(query)

          show_unknown_key(query)
        end

        private

        attr_reader :lines, :scaffold, :known_keys, :entries

        def file = self.class::FILE
        def command = self.class::COMMAND

        # 引けるキーか（既定はすべて）
        def in_scope?(_key) = true

        # 書いていないときの既定値。無ければ NOT_WRITTEN か nil
        def default_value(_path) = NOT_WRITTEN

        # 著者の値の見せ方
        def written_value(_path, value) = format_value(value)

        def show_unknown_key(query) = show_matches(query)

        # --- Phase: 雛形の読み取り ---

        # キーの行を、字下げで親子をたどって読む。YAML の結果にあるキーだけを採る
        # （コメントに書いた例や、値の中の `:` をキーと取り違えないように）
        def parse_entries
          stack = []
          lines.each_with_index.with_object({}) do |(line, index), found|
            matched = RetiredKeyRemover::KEY_LINE.match(line) or next

            indent = matched[:indent].size
            stack.pop while stack.any? && stack.last.first >= indent
            stack.push([indent, matched[:key]])
            path = stack.map(&:last)
            key = path.join('.')
            next unless known_keys.include?(key)

            inherited = found[path[0...-1].join('.')]&.summary
            found[key] = build_entry(key, path, index, indent, inherited)
          end
        end

        # 説明の無い子のキー（`typography.body.font`）は、親の説明を要約にする
        def build_entry(key, path, index, indent, inherited)
          lead = lead_lines(index, indent)
          trailing = lines[index][/\s#\s+(.*)\z/, 1]
          below = below_lines(index, indent)
          leading = lead.map { plain_comment(it) }
          following = below.map { plain_comment(it) }
          notes = [trailing, *leading, *following].compact.reject(&:empty?)
          summary = [trailing, leading.first, following.first, inherited].compact.reject(&:empty?).first
          Entry.new(key:, path:, lead:, notes:, summary:)
        end

        # キーのすぐ上の、同じ字下げのコメント。深い字下げのコメントは前のキーの続きなので含めない
        def lead_lines(index, indent)
          start = index
          start -= 1 while start.positive? && comment_at?(lines[start - 1]) { it == indent }
          lines[start...index]
        end

        # キーのすぐ下の、深い字下げのコメント
        def below_lines(index, indent)
          finish = index + 1
          finish += 1 while finish < lines.size && comment_at?(lines[finish]) { it > indent }
          lines[(index + 1)...finish]
        end

        def comment_at?(line)
          line.lstrip.start_with?('#') && yield(line[/\A */].size)
        end

        # `# ======= 索引設定 =======` の飾りと `#` を外す
        def plain_comment(line)
          line.strip.sub(/\A#\s*/, '').gsub(/\A[=-]{3,}\s*|\s*[=-]{3,}\z/, '').strip
        end

        # --- Phase: キーの説明 ---

        def show_key(key, path)
          puts key, ''
          ConfigGuide.print_listing(scaffold_listing(nearest_entry(path)))

          value = value_line(path)
          puts '', value if value
          0
        end

        # `{ min: 1, max: 9 }` の min には自分の行が無いので、行のある親をたどる
        def nearest_entry(path)
          path = path[0...-1] until entries.key?(path.join('.'))
          entries.fetch(path.join('.'))
        end

        # 雛形の行をそのまま、親のキーと見出しをつけて並べる。book.yml へ写せる形にする（§4.2）
        def scaffold_listing(entry)
          parents = (1...entry.path.size).flat_map do |depth|
            path = entry.path.first(depth)
            entries.fetch(path.join('.')).lead + ["#{'  ' * (depth - 1)}#{path.last}:"]
          end
          parents + entry.lead + lines[RetiredKeyRemover.block_range(lines, entry.path)]
        end

        # 値を 1 つ持つキーにだけ今の値を添える。本の外と読めないファイルでは出さない（§4.2）
        def value_line(path)
          return if dig(scaffold, path).is_a?(Hash)

          written = authored or return
          value = dig(written, path)
          return "今の値: #{written_value(path, value)}（#{file}）" unless value.equal?(NOT_WRITTEN)

          default = default_value(path)
          return '今の値: 書いていません' if default.equal?(NOT_WRITTEN) || default.nil?

          "今の値: 書いていません（既定値: #{format_value(default)}）"
        end

        def authored
          return unless File.file?(file)

          written = ConfigGuide.load_yaml(File.read(file, encoding: 'utf-8'))
          written if written.is_a?(Hash)
        rescue Psych::Exception
          nil
        end

        def dig(node, path)
          path.reduce(node) do |current, key|
            break NOT_WRITTEN unless current.is_a?(Hash) && current.key?(key)

            current[key]
          end
        end

        def format_value(value)
          case value
          in nil | '' then '（空）'
          in Array then "[#{value.join(', ')}]"
          else value.to_s
          end
        end

        # --- Phase: 言葉で探す ---

        def show_matches(query)
          matches = search(query)
          return not_found(query) if matches.empty?
          return show_key(matches.first.key, matches.first.path) if matches.one?

          width = matches.map { it.key.size }.max
          puts "「#{query}」を含む設定（#{matches.size} 件）", ''
          matches.each { puts "  #{it.key.ljust(width)}  #{it.summary}".rstrip }
          puts '', 'キーを指定すると、説明と今の値を表示します。'
          0
        end

        # キーの名前と説明を、英字の大小を区別せずに探す
        def search(query)
          word = query.downcase
          entries.values.select { [it.key, *it.notes].any? { |text| text.downcase.include?(word) } }
        end

        def not_found(query)
          nearest = DidYouMean::SpellChecker.new(dictionary: entries.keys).correct(query).first
          Common.log_error("「#{query}」に当てはまる設定が見つかりませんでした",
                           detail: "→ #{command}#{" #{nearest}" if nearest}")
          1
        end
      end

      # vs config:book。book.yml のキーを、区分・キー・言葉から引く
      class Book < KeyGuide
        FILE = BOOK_FILE
        COMMAND = 'vs config:book'

        private

        def show_overview
          sections = entries.values.select { it.path.size == 1 }
          width = sections.map { it.key.size }.max

          puts 'book.yml の設定', ''
          sections.each { puts "  #{it.key.ljust(width)}  #{it.summary}" }
          puts '', '区分やキーを指定すると、説明を表示します。言葉で探すこともできます。', ''
          puts "  #{COMMAND} index", "  #{COMMAND} index.target_terms", "  #{COMMAND} 目次"
          0
        end

        def default_value(path)
          path.reduce(ConfigKeys.default_schema) { |node, key| node.is_a?(Hash) ? node[key.to_sym] : nil }
        end

        def show_unknown_key(query)
          retired, notice = retired_notice(query.split('.'))
          retired ? show_retired(retired, notice) : super
        end

        # 廃止キーの案内。廃止した区分の子を聞かれたら、区分の案内を返す
        # @return [Array(Array<Symbol>, String), nil]
        def retired_notice(path)
          symbols = path.map(&:to_sym)
          ConfigKeys.retirement_notices.find { |retired, _| symbols.first(retired.size) == retired }
        end

        def show_retired(retired, notice)
          key = retired.join('.')
          target = ConfigKeys.moves[retired]&.join('.')
          puts target ? "#{key} は #{target} へ移りました" : "#{key} は廃止されました"
          puts "  #{notice}"
          puts "  → #{COMMAND} #{target}" if target
          0
        end
      end

      # vs config:talk。話者はその本のものなので、キーで引くのは display: だけにする
      class Talk < KeyGuide
        FILE = 'config/talk.yml'
        COMMAND = 'vs config:talk'
        DISPLAY = PreProcessCommands::TalkRegistry::DISPLAY_KEY

        private

        def in_scope?(key) = key == DISPLAY || key.start_with?("#{DISPLAY}.")

        def default_value(path)
          PreProcessCommands::TalkRegistry::DEFAULT_DISPLAY.to_h.fetch(path.last.to_sym, nil)
        end

        # YAML は `avatar: on` を真偽値に読むので、著者が書いた綴りへ戻す
        def written_value(path, value)
          return super unless path.last == 'avatar' && [true, false].include?(value)

          value ? 'on' : 'off'
        end

        def show_overview
          ConfigGuide.print_listing(writing_guide)
          show_speakers
          0
        end

        # 説明と記入例の行。本書の物語の話者（記入例の後のコメントから下）は見せない
        def writing_guide
          first_speaker = lines.index { top_level_key(it) && top_level_key(it) != DISPLAY } or return lines

          finish = (first_speaker...lines.size).find { lines[it].lstrip.start_with?('#') } || lines.size
          lines[0...finish].reverse.drop_while(&:empty?).reverse
        end

        def top_level_key(line)
          matched = RetiredKeyRemover::KEY_LINE.match(line)
          matched[:key] if matched && matched[:indent].empty?
        end

        def show_speakers
          return unless File.file?(BOOK_FILE)
          return puts('', "この本には #{FILE} がありません（会話文を使うときに作ります）") unless File.file?(FILE)

          speakers = (authored || {}).except(DISPLAY)
          return puts('', "#{FILE} に話者が書かれていません") if speakers.empty?

          width = speakers.keys.map { it.to_s.size }.max
          puts '', "この本の話者（#{FILE}）", ''
          speakers.each { |key, value| puts "  #{key.to_s.ljust(width)}  #{speaker_name(key, value)}" }
        end

        def speaker_name(key, value) = (value['name'] if value.is_a?(Hash)) || key
      end

      # vs config:catalog。値はその本の章立てなので、書き方の説明と、その本の章立てを見せる
      class Catalog
        FILE = 'config/catalog.yml'

        # @param scaffold_source [String] 雛形のルート
        def initialize(scaffold_source: NewCommands::SCAFFOLD_SOURCE)
          @lines = ConfigGuide.scaffold_text(scaffold_source, FILE).lines(chomp: true)
        end

        # @return [Integer] 終了コード
        def show
          ConfigGuide.print_listing(writing_guide)
          show_structure
          0
        end

        private

        attr_reader :lines

        # 雛形の値（本書の章立て）を飛ばし、その前後の説明だけを取る。
        # 値のすぐ上の `# 前書き` は値の見出しなので、最後の空行までにする
        def writing_guide
          first = lines.index { entry?(it) } or return lines
          last = lines.rindex { entry?(it) }
          head = lines[0...first]
          head[0...(head.rindex(&:empty?) || 0)] + [''] + lines[(last + 1)..].drop_while(&:empty?)
        end

        def entry?(line) = !line.strip.empty? && !line.lstrip.start_with?('#')

        def show_structure
          return unless File.file?(FILE)

          puts '', "この本の章立て（#{FILE}）", ''
          ConfigGuide.print_listing(File.readlines(FILE, encoding: 'utf-8', chomp: true).select { entry?(it) })
        end
      end
    end
  end
end
