# frozen_string_literal: true

# 用語集ベースの Markdown リンター
# 使い方: rake glossary:lint（または `vs glossary:lint`）
# - `config/glossary.yml` を読み込み
# - `contents/**/*.md` を走査
# - チェック内容:
#   1) エイリアス使用の検出（エイリアスが使われている箇所を報告）
#   2) first_full_form ルール: `first_full_form: true` の用語は、
#      各ファイルで最初の出現を「正式名（略称）」とし、
#      以降は略称のみを用いることを推奨
#
# 違反が見つかった場合は非ゼロ終了ステータスで終了します。

require 'yaml'
require 'set'

namespace :glossary do
  desc '用語集（config/glossary.yml）に基づいて Markdown を検査します'
  task :lint do
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

        # 初出以降は略称のみの使用を推奨
        # 正式名（略称）でない後続の単独 'name' 出現を検出
        # 簡易判定: name 出現数 から full_form 出現数を差し引く
        # 以降のルール（subsequent_abbr）は従来どおり（行番号は省略）
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

  desc '用語集（config/glossary.yml）に基づいて Markdown を自動修正します'
  task :fix do
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
      puts '確認するには `rake glossary:lint` を実行してください。'
    end
  end
end
