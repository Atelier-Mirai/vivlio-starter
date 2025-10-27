# frozen_string_literal: true

module Vivlio
  module Starter
    module CLI
      # glossary:add 系のコマンド実装と補助処理をまとめたモジュール
      module GlossaryAddCommands
        include GlossarySharedHelpers

        ADD_DESC = {
          short: '用語を対話的に追加します（glossary.yml に追記）',
          long: <<~DESC
            用語を対話的に追加します。glossary.yml に追記します。

            引数:
              INPUT    1行入力形式（例: "HTML(HyperText Markup Language)" または "HyperText Markup Language(HTML)")

            例:
              vs glossary:add
              vs glossary:add "HTML(HyperText Markup Language)"
          DESC
        }.freeze

        # Thor クラスへ glossary:add コマンドを登録する
        def self.included(base)
          base.class_eval do
            desc 'glossary:add', GlossaryAddCommands::ADD_DESC[:short]
            long_desc GlossaryAddCommands::ADD_DESC[:long]

            # ================================================================
            # Command: glossary:add（用語の追加）
            # ------------------------------------------------
            # 概要:
            #   1行入力または対話により、abbr/name、別表記(aliases)、style、説明を収集し
            #   glossary.yml に追記または既存エントリの更新を行う。
            # 引数:
            #   input  "HTML(HyperText Markup Language)" 等の1行入力（省略可）
            # ================================================================
            def glossary_add(input = nil)
              ENV['VERBOSE'] = '1' if options[:verbose]
              $stdout.sync = true

              glossary_path = glossary_path_or_exit('glossary:add')
              glossary = load_glossary(glossary_path)

              term = collect_term_metadata(input)
              ensure_term_presence(term)

              term[:first_full_form] = ask_first_full_form(term)
              term[:aliases] = ask_aliases(term[:abbr])
              term[:style] = ask_style(term)
              term[:description_lines] = ask_description_lines
              term[:key] = generate_term_key(term)

              status = handle_existing_entry(glossary_path, glossary, term)
              return if status == :updated

              append_new_entry(glossary_path, term)
            end
          end
        end

        private

        # 1行入力および対話入力から略称と正式名称を取得する
        def collect_term_metadata(input)
          raw = input&.strip
          abbr, name = parse_inline_input(raw)
          abbr = prompt_input('略称（例: HTML）: ', abbr)
          name = prompt_input('正式名称（例: HyperText Markup Language）: ', name)
          { abbr:, name: }
        end

        # `HTML(HyperText ...)` 形式の文字列から abbr/name を抽出する
        def parse_inline_input(raw)
          return [nil, nil] if raw.nil? || raw.empty?

          if (m = raw.match(%r{\A\s*([A-Za-z0-9+\-/]+)\s*[(（]\s*([^)）]+?)\s*[)）]\s*\z}))
            [m[1], m[2]]
          elsif (m = raw.match(%r{\A\s*([^(（]+?)\s*[(（]\s*([A-Za-z0-9+\-/]+)\s*[)）]\s*\z}))
            [m[2], m[1]]
          else
            [nil, nil]
          end
        end

        # 既定値が無い場合に標準入力から値を取得する
        def prompt_input(message, suggestion)
          return suggestion unless suggestion.nil? || suggestion.empty?

          print message
          $stdin.gets&.strip.to_s
        end

        # 略称と正式名称が空でないことを検証する
        def ensure_term_presence(term)
          return unless term[:abbr].to_s.empty? || term[:name].to_s.empty?

          warn '[glossary:add] 略称と正式名称の入力が不足しています'
          exit 1
        end

        # 初出表記を「正式名（略称）」にするかユーザーへ確認する
        def ask_first_full_form(term)
          print "初出は『#{term[:name]}（#{term[:abbr]}）』にしますか？ [Y/n]: "
          ans = $stdin.gets&.strip
          ans.nil? || ans.empty? || ans.match?(/\A[yY]\z/)
        end

        # 別表記（エイリアス）の入力を促し配列で返す
        def ask_aliases(abbr)
          default_aliases = build_default_aliases(abbr)
          $stdout.puts <<~ALIAS_GUIDE
            表記ゆれ検出のための別表記をカンマ区切りで指定できます。
              - 例  : html, Html, HTML5
            （空欄=既定 #{default_aliases.inspect} を採用）
          ALIAS_GUIDE
          print '入力: '
          alias_in = $stdin.gets&.strip.to_s
          alias_in.empty? ? default_aliases : alias_in.split(',').map(&:strip).reject(&:empty?).uniq
        end

        # 略称から downcase/capitalize した既定の別表記候補を生成する
        def build_default_aliases(abbr)
          base = abbr.to_s
          return [] if base.empty?

          downcase = base.downcase
          cap = base[0] ? base[0] + base[1..].to_s.downcase : base
          [downcase, cap].uniq
        end

        # style の推定値を提示しユーザーに確定させる
        def ask_style(term)
          inferred_style = infer_style(term[:abbr], term[:name], term[:aliases])
          allowed_styles = %w[capitalization lowercase hyphenation spacing punctuation wording]
          $stdout.puts <<~STYLE_GUIDE
            推定された style は '#{inferred_style}' です。
              - Enter: 推定値を採用
              - 入力 : 上書き（選択肢: #{allowed_styles.join(', ')})
          STYLE_GUIDE
          print "style 上書き（Enterで '#{inferred_style}'）: "
          style_input = $stdin.gets&.strip.to_s
          if style_input.empty?
            inferred_style
          elsif allowed_styles.include?(style_input)
            style_input
          else
            warn "[glossary:add] 不正な style 入力です。推定値 '#{inferred_style}' を採用します。"
            inferred_style
          end
        end

        # 説明文を複数行入力で受け取り配列として返す
        def ask_description_lines
          $stdout.puts <<~DESC_GUIDE
            説明文を入力してください（複数行可）。
              - 入力終了: 単独で '.' を入力して改行
              - 例     : Webブラウザで扱う文書フォーマット。
              - 空欄   : 新規作成時は未設定、更新時は既存を維持
          DESC_GUIDE
          $stdout.puts '入力開始（終了するには単独で "." を入力）:'
          lines = []
          loop do
            line = $stdin.gets
            break if line.nil?

            line = line.chomp
            break if line == '.'

            lines << line
          end
          lines
        end

        # 略称/正式名称から YAML の key を生成する
        def generate_term_key(term)
          source = term[:abbr].to_s.empty? ? term[:name].to_s : term[:abbr].to_s
          source.downcase.gsub(/[^a-z0-9_]/, '_').gsub(/_+/, '_').gsub(/^_|_$/, '')
        end

        # 既存エントリの有無に応じて更新処理または競合検証を行う
        def handle_existing_entry(glossary_path, glossary, term)
          existing = find_existing_term(glossary, term)
          return :updated if existing && replace_existing_entry(glossary_path, term, existing)

          abort_if_conflict(glossary, term)
        end

        # key/abbr/name のいずれかが一致する既存エントリを返す
        def find_existing_term(glossary, term)
          glossary['terms'].find do |t|
            t['key'] == term[:key] || t['abbr'].to_s == term[:abbr] || t['name'].to_s == term[:name]
          end
        end

        # 既存エントリを更新するか確認し、承認された場合は書き換える
        def replace_existing_entry(glossary_path, term, target)
          preview_existing_entry(term, target)
          print 'このエントリを更新しますか？ [Y/n]: '
          ans = $stdin.gets&.strip
          unless ans.nil? || ans.empty? || ans.match?(/\A[yY]\z/)
            warn '[glossary:add] 追加/更新は行いませんでした'
            exit 1
          end

          update_existing_block(glossary_path, term, target)
          $stdout.puts "[glossary:add] 更新しました: #{term[:abbr]}(#{term[:name]}) -> key: #{term[:key]}"
          true
        end

        # 既存エントリと更新案を比較表示する
        def preview_existing_entry(term, target)
          existing_aliases = Array(target['aliases']).map(&:to_s)
          existing_style = target['style'] || 'capitalization'
          existing_desc = target['description']
          current = [
            "- key: #{target['key']}",
            "  name: #{target['name']}",
            "  abbr: #{target['abbr']}",
            "  first_full_form: #{!target['first_full_form'].nil?}",
            "  description: #{existing_desc}",
            "  aliases: [#{existing_aliases.join(', ')}]",
            "  style: #{existing_style}"
          ].join("\n")

          proposed_desc = if term[:description_lines].empty?
                            '  description: '
                          else
                            (['  description: |-'] + term[:description_lines].map { |l| "    #{l}" }).join("\n")
                          end
          proposed = [
            "- key: #{term[:key]}",
            "  name: #{term[:name]}",
            "  abbr: #{term[:abbr]}",
            "  first_full_form: #{term[:first_full_form]}",
            proposed_desc,
            "  aliases: [#{term[:aliases].join(', ')}]",
            "  style: #{existing_style}"
          ].join("\n")

          $stdout.puts "[glossary:add] 既存のエントリが見つかりました (key='#{target['key']}')"
          $stdout.puts '--- 現在の定義 ---'
          $stdout.puts current
          $stdout.puts '--- 提案する変更 ---'
          $stdout.puts proposed
          $stdout.puts '----------------------'
        end

        # glossary.yml 内の既存ブロックを更新案で置き換える
        def update_existing_block(glossary_path, term, target)
          original_text = File.read(glossary_path, encoding: 'UTF-8')
          lines = original_text.lines
          start_i, indent_for_dash = locate_existing_block(lines, target['key'])
          indent_kv = "#{indent_for_dash || ''}  "
          end_i = find_block_end(lines, start_i, indent_for_dash)

          desc_line = build_description_block(
            indent_kv,
            term[:description_lines],
            lines,
            start_i,
            end_i,
            indent_for_dash
          )
          aliases_line = "#{indent_kv}aliases: [#{term[:aliases].join(', ')}]\n"

          new_block = "#{indent_for_dash}- key: #{term[:key]}\n" \
            + "#{indent_kv}name: #{term[:name]}\n" \
            + "#{indent_kv}abbr: #{term[:abbr]}\n" \
            + "#{indent_kv}first_full_form: #{term[:first_full_form]}\n" \
            + desc_line \
            + aliases_line \
            + "#{indent_kv}style: #{target['style'] || 'capitalization'}\n\n"

          lines[start_i..end_i] = [new_block]
          File.write(glossary_path, lines.join)
        end

        # 指定 key の YAML ブロック開始位置とインデントを返す
        def locate_existing_block(lines, key)
          start_i = nil
          indent_for_dash = nil
          lines.each_with_index do |line, idx|
            next unless line =~ /^(\s*)-\s+key:\s+#{Regexp.escape(key)}\s*$/

            start_i = idx
            indent_for_dash = Regexp.last_match(1)
            break
          end
          unless start_i
            warn '[glossary:add] 既存エントリの位置を特定できませんでした。中止します。'
            exit 1
          end
          [start_i, indent_for_dash]
        end

        # YAML ブロックの終端インデックスを計算する
        def find_block_end(lines, start_i, indent_for_dash)
          j = start_i + 1
          j += 1 while j < lines.length && lines[j] !~ /^#{Regexp.escape(indent_for_dash)}-\s+key:\s+/
          j - 1
        end

        # description を |- ブロック形式で生成する
        def build_description_block(indent_kv, new_lines, lines, start_i, end_i, indent_for_dash)
          return existing_description_block(indent_kv, lines, start_i, end_i, indent_for_dash) if new_lines.empty?

          block = "#{indent_kv}description: |-\n"
          block << new_lines.map { |l| "#{indent_kv}  #{l}\n" }.join
          block
        end

        # 既存 description ブロックをそのまま再利用する
        def existing_description_block(indent_kv, lines, start_i, end_i, indent_for_dash)
          desc_start = nil
          (start_i + 1).upto(end_i) do |idx|
            if lines[idx] =~ /^#{Regexp.escape(indent_kv)}description:(.*)$/
              desc_start = idx
              break
            end
          end
          return "#{indent_kv}description: \n" unless desc_start

          desc_buf = []
          idx = desc_start
          while idx <= end_i
            if idx > desc_start
              next_field = /^#{Regexp.escape(indent_kv)}\w[\w-]*:\s/
              next_entry = /^#{Regexp.escape(indent_for_dash)}-\s+key:/
              break if lines[idx] =~ next_field || lines[idx] =~ next_entry
            end

            desc_buf << lines[idx]
            idx += 1
          end
          desc_buf.join
        end

        # 同じ name/abbr が存在する場合はエラー終了する
        def abort_if_conflict(glossary, term)
          if glossary['terms'].any? { |t| t['abbr'].to_s == term[:abbr] }
            warn "[glossary:add] 既に存在します: abbr='#{term[:abbr]}'"
            exit 1
          end
          return unless glossary['terms'].any? { |t| t['name'].to_s == term[:name] }

          warn "[glossary:add] 既に存在します: name='#{term[:name]}'"
          exit 1
        end

        # glossary.yml の末尾へ新しいエントリを追記する
        def append_new_entry(glossary_path, term)
          original_text = File.read(glossary_path, encoding: 'UTF-8')
          lines = original_text.lines

          terms_idx = lines.index { |l| l.strip == 'terms:' }
          unless terms_idx
            warn '[glossary:add] glossary.yml に terms: セクションが見つかりません'
            exit 1
          end

          indent_for_dash = detect_terms_indent(lines, terms_idx)
          indent_kv = "#{indent_for_dash}  "

          desc_block = if term[:description_lines].empty?
                         "#{indent_kv}description: \n"
                       else
                         join_description_lines(indent_kv, term[:description_lines])
                       end

          fragment = <<~YAML

            #{indent_for_dash}- key: #{term[:key]}
            #{indent_kv}name: #{term[:name]}
            #{indent_kv}abbr: #{term[:abbr]}
            #{indent_kv}first_full_form: #{term[:first_full_form]}
            #{desc_block}#{indent_kv}aliases: [#{term[:aliases].join(', ')}]
            #{indent_kv}style: #{term[:style]}

          YAML

          File.open(glossary_path, 'a', encoding: 'UTF-8') { |f| f.write(fragment) }
          $stdout.puts "[glossary:add] 追加しました: #{term[:abbr]}(#{term[:name]}) -> key: #{term[:key]}"
        end

        def join_description_lines(indent_kv, lines)
          body = lines.map { |l| "#{indent_kv}  #{l}\n" }.join
          "#{indent_kv}description: |-\n" + body
        end

        # terms: セクション配下の `- key:` インデント幅を推定する
        def detect_terms_indent(lines, terms_idx)
          indent_for_dash = '  '
          if (after = lines[(terms_idx + 1)..])
            sample = after.find { |l| l =~ /^(\s*)-\s+\w/ }
            indent_for_dash = Regexp.last_match(1) if sample&.match(/^(\s*)-\s+\w/)
          end
          indent_for_dash
        end

        # 入力された略称・正式名・別表記から style を推定する
        def infer_style(abbr, name, aliases)
          canonical_abbr = abbr.to_s
          canonical_name = name.to_s
          alias_list = Array(aliases).map(&:to_s)

          return 'hyphenation' if hyphenation_needed?(canonical_abbr, canonical_name, alias_list)
          return 'capitalization' if uppercase_abbreviation?(canonical_abbr)

          lowercase_choice = lowercase_preference(canonical_abbr, canonical_name)
          return lowercase_choice if lowercase_choice

          'capitalization'
        end

        # ハイフン表記を優先すべきケースか判定する
        def hyphenation_needed?(abbr, name, aliases)
          return true if contains_hyphen?(abbr) || contains_hyphen?(name)

          base = canonical_hyphen_base(abbr, name)
          aliases.any? do |ali|
            contains_hyphen?(ali) || hyphen_variant?(ali, base)
          end
        end

        # 略称が大文字主体かどうかを判定する
        def uppercase_abbreviation?(abbr)
          abbr.match?(/\A[A-Z0-9]+\z/)
        end

        # 小文字主体の略称に対する推奨スタイルを返す
        def lowercase_preference(abbr, name)
          return nil unless abbr.match?(/\A[a-z0-9]+\z/)

          return 'capitalization' if name_contains_acronym?(name)

          'lowercase'
        end

        # 名称に頭字語が含まれるか検査する
        def name_contains_acronym?(name)
          name.split.any? { |word| word.match?(/\A[A-Z0-9]{2,}\z/) }
        end

        # ハイフン比較の基準となる canonical 文字列を返す
        def canonical_hyphen_base(abbr, name)
          base = abbr.empty? ? name : abbr
          base.to_s
        end

        # 文字列にハイフンが含まれるか確認する
        def contains_hyphen?(value)
          value.to_s.include?('-')
        end

        # ハイフンの有無だけが異なる別表記か判定する
        def hyphen_variant?(alias_term, base)
          return false if alias_term.to_s.empty? || base.to_s.empty?

          alias_term.tr('-', '') == base.tr('-', '') && alias_term.include?('-') != base.include?('-')
        end
      end
    end
  end
end
