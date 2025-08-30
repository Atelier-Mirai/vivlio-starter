# frozen_string_literal: true

require 'yaml'
require 'set'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: GlossaryCommands
      # ------------------------------------------------------------------------------
      # 用語集（config/glossary.yml）と Markdown の整合性を保つためのコマンド群。
      # 追加・正準化・Lint・修正などの運用タスクを Thor コマンドとして提供する。
      #
      # 提供コマンド:
      #   - glossary:add [INPUT]                   用語の追加（対話対応）
      #   - glossary:canonicalize:check            glossary.yml の正準化差分の有無を確認（dry-run）
      #   - glossary:canonicalize                  glossary.yml を正準化
      #   - glossary:lint                          用語集に基づき Markdown を検査
      #   - glossary:fix                           用語集に基づき Markdown を自動修正
      #
      # 備考:
      #   - -v/--verbose で詳細ログ（ENV['VERBOSE']=1）。
      #   - Markdown のコードブロック/インラインコードは検査・修正から除外。
      # ==============================================================================
      module GlossaryCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'glossary:add [INPUT]', '用語を対話的に追加します（glossary.yml に追記）'
            long_desc <<~DESC
              用語を対話的に追加します。glossary.yml に追記します。

              引数:
                INPUT    1行入力形式（例: "HTML(HyperText Markup Language)" または "HyperText Markup Language(HTML)"）

              例:
                vs glossary:add
                vs glossary:add "HTML(HyperText Markup Language)"
            DESC

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

              # 逐次表示を保証
              $stdout.sync = true
              glossary_path = File.join('config', 'glossary.yml')
              unless File.file?(glossary_path)
                warn "[glossary:add] #{glossary_path} が見つかりません"
                exit 1
              end

              glossary = YAML.load_file(glossary_path) || {}
              glossary['terms'] ||= []

              raw = input&.strip
              abbr = nil
              name = nil

              if raw && !raw.empty?
                # 形式1: ABBR(Full Name) / ABBR（Full Name）
                if (m = raw.match(/\A\s*([A-Za-z0-9+\-\/]+)\s*[\(（]\s*([^\)）]+?)\s*[\)）]\s*\z/))
                  abbr = m[1]
                  name = m[2]
                # 形式2: Full Name (ABBR) / Full Name（ABBR）
                elsif (m = raw.match(/\A\s*([^\(（]+?)\s*[\(（]\s*([A-Za-z0-9+\-\/]+)\s*[\)）]\s*\z/))
                  name = m[1]
                  abbr = m[2]
                end
              end

              # 対話で不足項目を補う
              if abbr.nil? || abbr.empty?
                print '略称（例: HTML）: '
                abbr = STDIN.gets&.strip.to_s
              end
              if name.nil? || name.empty?
                print '正式名称（例: HyperText Markup Language）: '
                name = STDIN.gets&.strip.to_s
              end

              if abbr.empty? || name.empty?
                warn '[glossary:add] 略称と正式名称の入力が不足しています'
                exit 1
              end

              # 初出表記の確認（既定: yes）
              print "初出は『#{name}（#{abbr}）』にしますか？ [Y/n]: "
              ans = STDIN.gets&.strip
              first_full = ans.nil? || ans.empty? || ans.match?(/\A[yY]\z/)

              # エイリアス提案
              default_aliases = [abbr.downcase]
              cap = abbr[0] ? abbr[0] + abbr[1..].to_s.downcase : abbr
              default_aliases << cap if cap && cap != abbr && cap != abbr.downcase
              default_aliases = default_aliases.uniq

              $stdout.puts <<~ALIAS_GUIDE
                表記ゆれ検出のための別表記をカンマ区切りで指定できます。
                  - 例  : html, Html, HTML5
                （空欄=既定 #{default_aliases.inspect} を採用）
              ALIAS_GUIDE
              print "入力: "
              alias_in = STDIN.gets&.strip.to_s
              aliases = if alias_in.empty?
                default_aliases
              else
                alias_in.split(',').map(&:strip).reject(&:empty?).uniq
              end

              # style の自動推定（新規追加時の初期値）
              inferred_style = infer_style(abbr, name, aliases)

              # 推定結果の上書き受付
              allowed_styles = %w[capitalization lowercase hyphenation spacing punctuation wording]
              $stdout.puts <<~STYLE_GUIDE
                推定された style は '#{inferred_style}' です。
                  - Enter: 推定値を採用
                  - 入力 : 上書き（選択肢: #{allowed_styles.join(', ')})
              STYLE_GUIDE
              print "style 上書き（Enterで '#{inferred_style}'）: "
              style_input = STDIN.gets&.strip.to_s
              style_to_use = if style_input.empty?
                inferred_style
              else
                if allowed_styles.include?(style_input)
                  style_input
                else
                  warn "[glossary:add] 不正な style 入力です。推定値 '#{inferred_style}' を採用します。"
                  inferred_style
                end
              end

              # description 入力（複数行対応: 単独の '.' 行で終了。空欄終了=新規は未設定/更新は既存維持）
              $stdout.puts <<~DESC_GUIDE
                説明文を入力してください（複数行可）。
                  - 入力終了: 単独で '.' を入力して改行
                  - 例     : Webブラウザで扱う文書フォーマット。
                  - 空欄   : 新規作成時は未設定、更新時は既存を維持
              DESC_GUIDE
              $stdout.puts '入力開始（終了するには単独で "." を入力）:'
              description_lines = []
              loop do
                line = STDIN.gets
                if line.nil?
                  break
                end
                line = line.chomp
                break if line == '.'
                description_lines << line
              end
              description_text = description_lines.join("\n")

              # key 生成
              key_source = (abbr && !abbr.empty?) ? abbr : name
              key = key_source.downcase.gsub(/[^a-z0-9_]/, '_').gsub(/_+/, '_').gsub(/^_|_$/, '')

              # 重複チェック（key/abbr/name）
              existing_by_key  = glossary['terms'].find { |t| t['key'] == key }
              existing_by_abbr = glossary['terms'].find { |t| t['abbr'].to_s == abbr }
              existing_by_name = glossary['terms'].find { |t| t['name'].to_s == name }
              if existing_by_key || existing_by_abbr || existing_by_name
                # 既存エントリを表示し、更新するか確認
                target = existing_by_key || existing_by_abbr || existing_by_name
                existing_aliases = Array(target['aliases']).map(&:to_s)
                existing_style = (target['style'] || 'capitalization')
                existing_desc  = target['description']
                existing_preview = [
                  "- key: #{target['key']}",
                  "  name: #{target['name']}",
                  "  abbr: #{target['abbr']}",
                  "  first_full_form: #{!!target['first_full_form']}",
                  "  description: #{existing_desc}",
                  "  aliases: [#{existing_aliases.join(', ')}]",
                  "  style: #{existing_style}"
                ].join("\n")

                prev_desc_block = if description_lines.empty?
                  "  description: "
                else
                  (["  description: |-" ] + description_lines.map { |l| "    #{l}" }).join("\n")
                end
                proposed_preview = [
                  "- key: #{key}",
                  "  name: #{name}",
                  "  abbr: #{abbr}",
                  "  first_full_form: #{first_full}",
                  prev_desc_block,
                  "  aliases: [#{aliases.join(', ')}]",
                  "  style: #{existing_style}"
                ].join("\n")

                $stdout.puts "[glossary:add] 既存のエントリが見つかりました (key='#{target['key']}')"
                $stdout.puts '--- 現在の定義 ---'
                $stdout.puts existing_preview
                $stdout.puts '--- 提案する変更 ---'
                $stdout.puts proposed_preview
                $stdout.puts '----------------------'
                print 'このエントリを更新しますか？ [Y/n]: '
                ans2 = STDIN.gets&.strip
                if ans2.nil? || ans2.empty? || ans2.match?(/\A[yY]\z/)
                  # ファイルを行単位で読み、該当ブロックを差し替え
                  original_text = File.read(glossary_path, encoding: 'UTF-8')
                  lines = original_text.lines
                  # 該当 key ブロックの開始行を検出
                  start_i = nil
                  indent_for_dash = nil
                  lines.each_with_index do |l, i|
                    if l =~ /^(\s*)-\s+key:\s+#{Regexp.escape(target['key'])}\s*$/
                      start_i = i
                      indent_for_dash = Regexp.last_match(1)
                      break
                    end
                  end
                  unless start_i
                    warn "[glossary:add] 既存エントリの位置を特定できませんでした。中止します。"
                    exit 1
                  end
                  indent_kv = (indent_for_dash || '') + '  '
                  # ブロック終端を次の '- key:' か EOF とする
                  j = start_i + 1
                  while j < lines.length && !(lines[j] =~ /^#{Regexp.escape(indent_for_dash)}-\s+key:\s+/)
                    j += 1
                  end
                  end_i = j - 1

                  # 置換用ブロック（description は入力があればブロックで上書き, なければ既存のまま）
                  # 既存 description 行を探し、次のキー行までの内容をそのまま温存
                  existing_desc = ''
                  desc_start = nil
                  ((start_i + 1)..end_i).each do |k|
                    if lines[k] =~ /^#{Regexp.escape(indent_kv)}description:(.*)$/
                      desc_start = k
                      break
                    end
                  end
                  if desc_start
                    desc_buf = []
                    m = desc_start
                    while m <= end_i
                      # 次の key-value 開始（"  name:" 等）や次の項目開始で止める
                      break if m > desc_start && lines[m] =~ /^#{Regexp.escape(indent_kv)}\w[\w\-]*:\s|
^#{Regexp.escape(indent_for_dash)}-\s+key:/
                      desc_buf << lines[m]
                      m += 1
                    end
                    existing_desc = desc_buf.join
                  else
                    existing_desc = "#{indent_kv}description: \n"
                  end

                  # description 行（入力があればブロックで上書き, なければ既存のまま）
                  desc_line = if description_lines.empty?
                    existing_desc
                  else
                    block = "#{indent_kv}description: |-\n"
                    block << description_lines.map { |l| "#{indent_kv}  #{l}\n" }.join
                    block
                  end

                  # 新しい aliases はインライン表記
                  aliases_line = "#{indent_kv}aliases: [#{aliases.join(', ')}]\n"

                  new_block = "#{indent_for_dash}- key: #{key}\n" \
                    + "#{indent_kv}name: #{name}\n" \
                    + "#{indent_kv}abbr: #{abbr}\n" \
                    + "#{indent_kv}first_full_form: #{first_full}\n" \
                    + desc_line \
                    + aliases_line \
                    + "#{indent_kv}style: #{existing_style}\n\n"

                  lines[start_i..end_i] = [new_block]
                  File.write(glossary_path, lines.join)
                  $stdout.puts "[glossary:add] 更新しました: #{abbr}(#{name}) -> key: #{key}"
                else
                  warn '[glossary:add] 追加/更新は行いませんでした'
                  exit 1
                end
              end
              if glossary['terms'].any? { |t| t['abbr'].to_s == abbr }
                warn "[glossary:add] 既に存在します: abbr='#{abbr}'"
                exit 1
              end
              if glossary['terms'].any? { |t| t['name'].to_s == name }
                warn "[glossary:add] 既に存在します: name='#{name}'"
                exit 1
              end

              # ここからはファイルの既存フォーマットを保ったまま追記する
              original_text = File.read(glossary_path, encoding: 'UTF-8')
              lines = original_text.lines

              # 'terms:' の位置と、既存のリストのインデントを検出
              terms_idx = lines.index { |l| l.strip == 'terms:' }
              unless terms_idx
                warn '[glossary:add] glossary.yml に terms: セクションが見つかりません'
                exit 1
              end

              indent_for_dash = '  ' # 既定は2スペース
              # terms: 以降で最初の "- " 行を探し、その先頭空白を採用
              if (after = lines[(terms_idx + 1)..-1])
                sample = after.find { |l| l =~ /^(\s*)-\s+\w/ }
                if sample && sample.match(/^(\s*)-\s+\w/)
                  indent_for_dash = Regexp.last_match(1)
                end
              end
              indent_kv = indent_for_dash + '  '

              # description ブロックを構築
              desc_block = if description_lines.empty?
                "#{indent_kv}description: \n"
              else
                "#{indent_kv}description: |-\n" + description_lines.map { |l| "#{indent_kv}  #{l}\n" }.join
              end

              # YAMLフラグメント生成（インライン aliases、style の後に空行）
              fragment = <<~YAML

                #{indent_for_dash}- key: #{key}
                #{indent_kv}name: #{name}
                #{indent_kv}abbr: #{abbr}
                #{indent_kv}first_full_form: #{first_full}
                #{desc_block}#{indent_kv}aliases: [#{aliases.join(', ')}]
                #{indent_kv}style: #{style_to_use}

              YAML

              # 追記位置: terms: セクションの末尾（通常はファイル末尾）に追加
              # シンプルにファイル末尾へ追記（terms: が最後のセクションである前提）
              File.open(glossary_path, 'a', encoding: 'UTF-8') { |f| f.write(fragment) }
              $stdout.puts "[glossary:add] 追加しました: #{abbr}(#{name}) -> key: #{key}"
            end

            desc 'glossary:canonicalize:check', 'config/glossary.yml を正準化（dry-run）し、差分の有無を返します'
            long_desc <<~DESC
              config/glossary.yml を正準化（dry-run）し、差分の有無を返します。
              実際のファイル書き込みは行いません。
            DESC

            # ================================================================
            # Command: glossary:canonicalize:check（正準化の差分確認: dry-run）
            # ------------------------------------------------
            # 概要:
            #   glossary.yml の正準化結果を生成し、現状との差分の有無のみを返す。
            #   ファイルの書き換えは行わない。
            # ================================================================
            def glossary_canonicalize_check
              path = File.join('config', 'glossary.yml')
              unless File.file?(path)
                warn "[glossary:canonicalize:check] #{path} が見つかりません"
                exit 1
              end

              original = File.read(path, encoding: 'UTF-8')
              canon = canonicalize_glossary_text(original)
              if canon == original
                puts '[glossary:canonicalize:check] 変更はありません'
              else
                warn '[glossary:canonicalize:check] 差分があります（書き込みは行いません）'
                exit 1
              end
            end

            desc 'glossary:canonicalize', 'config/glossary.yml を正準化します（descriptionのブロック化、空行整形、key順ソート）'
            long_desc <<~DESC
              config/glossary.yml を正準化します。
              - description を |- ブロックスカラへ統一
              - 各 - key: ブロックの直前に1行の空行
              - key の昇順でソート
            DESC

            # ================================================================
            # Command: glossary:canonicalize（正準化を実行）
            # ------------------------------------------------
            # 概要:
            #   glossary.yml を正準化する。
            #   - description のブロック化
            #   - ブロック直前の空行整形
            #   - key 昇順ソート
            # ================================================================
            def glossary_canonicalize
              path = File.join('config', 'glossary.yml')
              unless File.file?(path)
                warn "[glossary:canonicalize] #{path} が見つかりません"
                exit 1
              end

              original = File.read(path, encoding: 'UTF-8')
              canon = canonicalize_glossary_text(original)
              if canon == original
                puts '[glossary:canonicalize] 変更はありません'
              else
                File.write(path, canon)
                puts '[glossary:canonicalize] 正準化を完了しました'
              end
            end

            desc 'glossary:lint', '用語集（config/glossary.yml）に基づいて Markdown を検査します'
            long_desc <<~DESC
              用語集に基づいて Markdown を検査します。

              チェック内容:
              - エイリアス使用の検出
              - first_full_form ルール（初出は正式名（略称））
              - スタイル統一（capitalization/lowercase/hyphenation）
            DESC

            # ================================================================
            # Command: glossary:lint（Markdown の検査）
            # ------------------------------------------------
            # 概要:
            #   用語集に基づいて Markdown を検査し、別表記/初出/スタイルの逸脱を検出する。
            #   コード（フェンス/インライン）は検査対象外。
            # ================================================================
            def glossary_lint
              glossary_path = File.join('config', 'glossary.yml')
              unless File.file?(glossary_path)
                warn "[glossary:lint] #{glossary_path} が見つかりません"
                exit 1
              end

              glossary = YAML.load_file(glossary_path)
              terms = (glossary['terms'] || []).map do |t|
                {
                  key: t['key'],
                  name: t['name'],
                  abbr: t['abbr'],
                  first_full_form: !!t['first_full_form'],
                  aliases: (t['aliases'] || []).uniq,
                  style: t['style']
                }
              end

              md_files = Dir.glob(File.join('contents', '**', '*.md')).sort
              violations = []

              # フェンス付きコードブロック（``` 言語 ... ```）とインラインコード（`...`）を除去
              strip_code = lambda do |s|
                # フェンス付きコードブロックを除去
                s2 = s.gsub(/```[\s\S]*?```/m, '')
                # インラインコードを除去
                s2 = s2.gsub(/`[^`]*`/, '')
                s2
              end

              md_files.each do |path|
                original = File.read(path, encoding: 'UTF-8')
                text = strip_code.call(original)

                terms.each do |term|
                  name = term[:name]
                  abbr = term[:abbr]
                  aliases = term[:aliases]
                  first_full = term[:first_full_form]

                  # 1) エイリアス使用の検出（行単位・コード除外・行番号付き）
                  in_fence = false
                  original.each_line.with_index(1) do |line, lineno|
                    # フェンスの開始/終了をトグル
                    if line.match?(/```/)
                      in_fence = !in_fence
                      next
                    end
                    next if in_fence

                    # インラインコードを除去してから判定
                    line_check = line.gsub(/`[^`]*`/, '')
                    aliases.each do |ali|
                      next if ali.to_s.strip.empty?
                      # ラテン文字の語境界を用いた検出（長い単語中の部分一致を除外）
                      pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(ali)}(?![A-Za-z0-9_])/
                      if line_check.match?(pattern)
                        violations << {
                          file: path,
                          rule: '別表記',
                          line: lineno,
                          message: "エイリアス '#{ali}' が使われています。正規表記 '#{name}'#{abbr ? "（または '#{abbr}'）" : ''} を使用してください。",
                        }
                      end
                    end

                    # スタイル検出（Latinトークンのみ）
                    st = term[:style].to_s
                    if !st.empty?
                      case st
                      when 'capitalization'
                        # name
                        if name.to_s =~ /[A-Za-z]/
                          pat_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/i
                          if line_check.match?(pat_ci) && !line_check.match?(/(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/)
                            violations << { file: path, rule: 'スタイル:大文字小文字', line: lineno, message: "大文字小文字を '#{name}' に統一してください。" }
                          end
                        end
                        # abbr
                        if abbr.to_s =~ /[A-Za-z]/
                          pat_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(abbr)}(?![A-Za-z0-9_])/i
                          if line_check.match?(pat_ci) && !line_check.match?(/(?<![A-Za-z0-9_])#{Regexp.escape(abbr)}(?![A-Za-z0-9_])/)
                            violations << { file: path, rule: 'スタイル:大文字小文字', line: lineno, message: "大文字小文字を '#{abbr}' に統一してください。" }
                          end
                        end
                      when 'lowercase'
                        if name.to_s =~ /[A-Za-z]/
                          pat_ci = /(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/i
                          if line_check.match?(pat_ci) && !line_check.match?(/(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/)
                            violations << { file: path, rule: 'スタイル:小文字', line: lineno, message: "小文字表記 '#{name}' に統一してください。" }
                          end
                        end
                      when 'hyphenation'
                        if name.to_s.include?('-') && name.to_s =~ /[A-Za-z]/
                          nohy = name.gsub('-', '')
                          spc  = name.gsub('-', ' ')
                          [nohy, spc].each do |bad|
                            pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(bad)}(?![A-Za-z0-9_])/i
                            if line_check.match?(pattern)
                              violations << { file: path, rule: 'スタイル:ハイフン表記', line: lineno, message: "ハイフン表記は '#{name}' に統一してください。" }
                              break
                            end
                          end
                        end
                      end
                    end
                  end

                  # 2) 初出は正式名（略称）ルール（行番号付き）
                  next unless first_full
                  next if name.nil? || abbr.nil?

                  full_form = "#{name}（#{abbr}）" # 全角かっこを使用

                  # 行単位でフェンス/インラインコードを無視しつつ、最初に現れるトークンを特定
                  in_fence = false
                  first_kind = nil # :full | :name | :abbr
                  first_line = nil

                  original.each_line.with_index(1) do |line, lineno|
                    if line.match?(/```/)
                      in_fence = !in_fence
                      next
                    end
                    next if in_fence

                    line_check = line.gsub(/`[^`]*`/, '')

                    idx_full = line_check.index(full_form)
                    idx_name = line_check.index(name)
                    idx_abbr = line_check.index(abbr)

                    # 何もなければ次の行へ
                    next if idx_full.nil? && idx_name.nil? && idx_abbr.nil?

                    # この行での最初の出現を決定
                    cand = { full: idx_full, name: idx_name, abbr: idx_abbr }.compact
                    kind, min_idx = cand.min_by { |_, v| v }

                    first_kind = kind
                    first_line = lineno
                    break
                  end

                  # 出現がない場合はスキップ
                  next if first_kind.nil?

                  # 最初の出現が正式名（略称）でなければ違反（行番号付き）
                  if first_kind != :full
                    violations << {
                      file: path,
                      rule: '初出:正式名（略称）',
                      line: first_line,
                      message: "最初の出現は '#{full_form}' にしてください。",
                    }
                  end
                end
              end

              if violations.empty?
                puts '[glossary:lint] OK - 問題は見つかりませんでした'
              else
                puts '[glossary:lint] ルール違反が見つかりました:'
                violations.each do |v|
                  loc = v[:line] ? ":#{v[:line]}" : ''
                  puts "- #{v[:file]}#{loc}: [#{v[:rule]}] #{v[:message]}"
                end
                exit 2
              end
            end

            desc 'glossary:fix', '用語集（config/glossary.yml）に基づいて Markdown を自動修正します'
            long_desc <<~DESC
              用語集に基づいて Markdown を自動修正します。

              修正内容:
              - エイリアスを正規表記に置換
              - first_full_form ルールの適用
              - スタイル統一（capitalization/lowercase/hyphenation）
            DESC

            # ================================================================
            # Command: glossary:fix（Markdown の自動修正）
            # ------------------------------------------------
            # 概要:
            #   用語集に基づいて Markdown を自動修正する。
            #   - エイリアス置換 / 初出ルール / スタイル統一
            #   コード（フェンス/インライン）は修正対象外。
            # ================================================================
            def glossary_fix
              glossary_path = File.join('config', 'glossary.yml')
              unless File.file?(glossary_path)
                warn "[glossary:fix] #{glossary_path} が見つかりません"
                exit 1
              end

              glossary = YAML.load_file(glossary_path)
              terms = (glossary['terms'] || []).map do |t|
                {
                  key: t['key'],
                  name: t['name'],
                  abbr: t['abbr'],
                  first_full_form: !!t['first_full_form'],
                  aliases: (t['aliases'] || []).uniq,
                }
              end

              md_files = Dir.glob(File.join('contents', '**', '*.md')).sort

              # Markdown を [[:text, 文字列], [:code, 文字列], ...] のセグメントに分割
              split_segments = lambda do |s|
                segments = []
                last = 0
                # フェンス付きコードブロック（```...```）またはインラインコード（`...`）にマッチ
                regex = /```[\s\S]*?```|`[^`]*`/m
                s.to_enum(:scan, regex).each do
                  m = Regexp.last_match
                  if m.begin(0) > last
                    segments << [:text, s[last...m.begin(0)]]
                  end
                  segments << [:code, m[0]]
                  last = m.end(0)
                end
                if last < s.length
                  segments << [:text, s[last..-1]]
                end
                segments
              end

              # プレーンテキスト中のエイリアスを置換。特例: 生の 'vs' は '`vs`' に整形
              replace_aliases = lambda do |text|
                out = text.dup
                terms.each do |term|
                  (term[:aliases] || []).each do |ali|
                    next if ali.to_s.strip.empty?
                    if ali.downcase == 'vs'
                      # 単独の vs をインラインコードに置換（ASCII 境界で判定）
                      pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(ali)}(?![A-Za-z0-9_])/i
                      out = out.gsub(pattern) { '`vs`' }
                    else
                      # エイリアスを正規表記（ラテン文字は擬似的な語境界を使用）に置換
                      replacement = term[:name].to_s
                      pattern = /(?<![A-Za-z0-9_])#{Regexp.escape(ali)}(?![A-Za-z0-9_])/
                      out = out.gsub(pattern, replacement)
                    end
                  end
                end
                out
              end

              # テキストセグメントを順に処理し、用語ごとに first_full_form を適用
              enforce_first_full = lambda do |segments|
                # 用語ごとの状態: 初出がすでに「正式名（略称）」かどうか
                state = {}
                terms.each do |t|
                  next unless t[:first_full_form]
                  next if t[:name].to_s.empty? || t[:abbr].to_s.empty?
                  state[t[:key]] = { handled: false }
                end

                segments.map do |kind, str|
                  next [kind, str] if kind == :code

                  text = str
                  # 各用語に対して、first_full_form の変換を段階的に適用
                  terms.each do |t|
                    next unless t[:first_full_form]
                    name = t[:name]
                    abbr = t[:abbr]
                    next if name.to_s.empty? || abbr.to_s.empty?

                    full = "#{name}（#{abbr}）"
                    st = state[t[:key]]
                    handled = st && st[:handled]

                    if handled
                      # 既存の「正式名（略称）」は残し、単独の name は abbr に置換
                      # 直後が（略称）の場合は負の先読みで除外
                      pattern = /#{Regexp.escape(name)}(?!（#{Regexp.escape(abbr)}）)/
                      text = text.gsub(pattern, abbr)
                      next
                    end

                    # このセグメント内に「正式名（略称）」があれば、初出済みとして扱う
                    if text.include?(full)
                      st[:handled] = true if st
                      next
                    end

                    idx_name = text.index(name)
                    idx_abbr = text.index(abbr)
                    if idx_name.nil? && idx_abbr.nil?
                      next
                    end

                    # このセグメントで先に出現する方を採用
                    target = nil
                    if !idx_abbr.nil? && (idx_name.nil? || idx_abbr < idx_name)
                      target = :abbr
                    else
                      target = :name
                    end

                    if target == :abbr
                      # 最初の abbr を「正式名（略称）」に置換
                      text = text.sub(abbr, full)
                    else
                      # 最初の name を「正式名（略称）」に置換
                      text = text.sub(name, full)
                    end
                    st[:handled] = true if st

                    # 初出設定後、このセグメントの残りにある単独 name は abbr に変換
                    pattern = /#{Regexp.escape(name)}(?!（#{Regexp.escape(abbr)}）)/
                    text = text.gsub(pattern, abbr)
                  end

                  [:text, text]
                end
              end

              changed = []

              md_files.each do |path|
                original = File.read(path, encoding: 'UTF-8')
                segments = split_segments.call(original)

                # 1) Alias replacements in text segments
                segments = segments.map do |kind, str|
                  if kind == :text
                    [:text, replace_aliases.call(str)]
                  else
                    [kind, str]
                  end
                end

                # 2) Enforce first_full_form
                segments = enforce_first_full.call(segments)

                # 3) Style fixes (capitalization/lowercase/hyphenation)
                segments = segments.map do |kind, str|
                  if kind != :text
                    [kind, str]
                  else
                    text = str.dup
                    terms.each do |t|
                      st = t[:style].to_s
                      name = t[:name].to_s
                      abbr = t[:abbr].to_s
                      case st
                      when 'capitalization'
                        if name =~ /[A-Za-z]/ && !name.empty?
                          text = text.gsub(/(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/i, name)
                        end
                        if abbr =~ /[A-Za-z]/ && !abbr.empty?
                          text = text.gsub(/(?<![A-Za-z0-9_])#{Regexp.escape(abbr)}(?![A-Za-z0-9_])/i, abbr)
                        end
                      when 'lowercase'
                        if name =~ /[A-Za-z]/ && !name.empty?
                          text = text.gsub(/(?<![A-Za-z0-9_])#{Regexp.escape(name)}(?![A-Za-z0-9_])/i, name)
                        end
                      when 'hyphenation'
                        if name.include?('-') && name =~ /[A-Za-z]/
                          nohy = name.gsub('-', '')
                          spc  = name.gsub('-', ' ')
                          [nohy, spc].each do |bad|
                            text = text.gsub(/(?<![A-Za-z0-9_])#{Regexp.escape(bad)}(?![A-Za-z0-9_])/i, name)
                          end
                        end
                      end
                    end
                    [:text, text]
                  end
                end

                fixed = segments.map { |k, s| s }.join

                if fixed != original
                  File.write(path, fixed)
                  changed << path
                  puts "[glossary:fix] 更新: #{path}"
                end
              end

              if changed.empty?
                puts '[glossary:fix] 変更は必要ありません'
              else
                puts "[glossary:fix] #{changed.size} 件のファイルを更新しました。"
                puts '確認するには `vs glossary:lint` を実行してください。'
              end
            end
          end
        end

        private

        # style の自動推定（新規追加時の初期値）
        def infer_style(abbr, name, aliases)
          ab = abbr.to_s
          nm = name.to_s
          als = Array(aliases).map(&:to_s)

          # 1) ハイフン表記の統一が必要そうなら優先
          hyphen_in_canonical = ab.include?('-') || nm.include?('-')
          hyphen_in_alias = als.any? { |a| a.include?('-') }
          if hyphen_in_canonical || hyphen_in_alias
            # さらに、ハイフン有無だけが違う alias があるかを軽く確認
            base = ab.empty? ? nm : ab
            if !base.empty? && als.any? { |a| a.tr('-','') == base.tr('-','') && (a.include?('-') != base.include?('-')) }
              return 'hyphenation'
            end
            # canonical がハイフンを含む場合も hyphenation を推奨
            return 'hyphenation'
          end

          # 2) 略称が全大文字(数字含む)なら大文字小文字の統一
          return 'capitalization' if ab.match?(/\A[A-Z0-9]+\z/)

          # 3) 略称が全小文字(数字含む)の場合: gem 名などは lowercase を推奨
          if ab.match?(/\A[a-z0-9]+\z/)
            # ただし、name が頭字語中心(全大文字語を含む)なら capitalization のほうが無難
            return 'capitalization' if nm.split.any? { |w| w.match?(/\A[A-Z0-9]{2,}\z/) }
            return 'lowercase'
          end

          # 4) デフォルトは capitalization
          'capitalization'
        end

        # 用語集テキストを正準化
        def canonicalize_glossary_text(text)
          lines = text.lines

          # terms: の位置を特定
          terms_idx = lines.index { |l| l.strip == 'terms:' }
          return text unless terms_idx # terms が無ければそのまま

          header = lines[0..terms_idx]
          body = lines[(terms_idx + 1)..-1] || []

          # アイテムのインデント（terms: 直下の `- key:` の先頭空白）を推定
          item_indent = nil
          body.each do |l|
            if (m = l.match(/^(\s*)-\s*key:\s*\S+/))
              item_indent = m[1]
              break
            end
          end
          # 見つからなければ何もしない
          return lines.join unless item_indent

          # ブロック分割
          blocks = []
          current = []
          body.each do |l|
            if l =~ /^#{Regexp.escape(item_indent)}-\s*key:\s*\S+/
              # 新しいブロック開始
              unless current.empty?
                blocks << current
                current = []
              end
            end
            current << l
          end
          blocks << current unless current.empty?

          # 各ブロックの key を取得し、description を整形
          items = blocks.map do |blk|
            blk = strip_blank_edges(blk)
            key = extract_key_from_block(blk)
            canon_blk = canonicalize_block_description(blk)
            canon_blk = strip_blank_edges(canon_blk)
            [key, canon_blk]
          end

          # key でソート（ASCII順）
          items.sort_by! { |(k, _)| k.to_s }

          # 再構成: 先頭ブロックの前には空行なし、以降は1行の空行
          rebuilt = []
          items.each_with_index do |(_k, blk), idx|
            if idx.positive?
              rebuilt << "\n"
            end
            rebuilt.concat(blk)
          end

          (header + rebuilt).join
        end

        # ブロック先頭（- key: ...）から key を抽出
        def extract_key_from_block(block_lines)
          first = block_lines.find { |l| l =~ /-\s*key:\s*\S+/ }
          return nil unless first
          m = first.match(/-\s*key:\s*(\S+)/)
          m ? m[1] : nil
        end

        # ブロック内の description を `|-` ブロック形式へ整形
        def canonicalize_block_description(block_lines)
          out = []
          i = 0
          while i < block_lines.length
            line = block_lines[i]
            # すでにブロック記法ならそのまま
            if line =~ /^(\s*)description:\s*\|\-?\s*$/
              out << line
              i += 1
              # 以降のブロック本文（インデント2空白分）はそのまま写経
              while i < block_lines.length && block_lines[i] =~ /^(\s{2,}|\s*)\S|^\s*$/
                # terminate only when next top-level field at same indent appears
                # 実際には次のフィールド行を検出したいが、元テキストを変えないため単純に次の `\s*\w+:` を検出
                break if block_lines[i] =~ /^(\s*)\w[\w\-]*:\s/
                out << block_lines[i]
                i += 1
              end
              next
            end

            # `description: ...` の単一行
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

        # 先頭末尾の空行を除去
        def strip_blank_edges(arr)
          a = arr.dup
          while !a.empty? && a.first.strip.empty?
            a.shift
          end
          while !a.empty? && a.last.strip.empty?
            a.pop
          end
          a
        end
      end
    end
  end
end
