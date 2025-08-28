# frozen_string_literal: true

# 対話プロンプトで用語を `config/glossary.yml` に追加するタスク
# 使い方:
#   1) 対話形式
#      ./bin/vs glossary:add
#   2) 1行入力から（簡易）
#      ./bin/vs 'glossary:add[HTML(HyperText Markup Language)]'
#      ./bin/vs 'glossary:add[HyperText Markup Language(HTML)]'
#
# 挙動:
# - `abbr` と `name` を取得（1行入力をパース or 対話で聞く）
# - `first_full_form` は既定 true（確認プロンプトあり）
# - `aliases` は既定で [abbr.downcase, Abbr] を提案（入力で上書き可）
# - 既存の key/name/abbr 重複があれば中止
# - YAML として上書き保存（フォーマットは Ruby の YAML.dump に準拠）

require 'yaml'

namespace :glossary do
  desc '用語を対話的に追加します（glossary.yml に追記）'
  task :add, [:input] do |_t, args|
    # 逐次表示を保証
    $stdout.sync = true
    glossary_path = File.join('config', 'glossary.yml')
    unless File.file?(glossary_path)
      warn "[glossary:add] #{glossary_path} が見つかりません"
      exit 1
    end

    glossary = YAML.load_file(glossary_path) || {}
    glossary['terms'] ||= []

    raw = args[:input]&.strip
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
    infer_style = lambda do |abbr_s, name_s, aliases_arr|
      ab = abbr_s.to_s
      nm = name_s.to_s
      als = Array(aliases_arr).map(&:to_s)

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

    inferred_style = infer_style.call(abbr, name, aliases)

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

        # 置換用ブロック（description は入力が空なら既存維持、入力があれば上書き）
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
            break if m > desc_start && lines[m] =~ /^#{Regexp.escape(indent_kv)}\w+:|
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
        next
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
end
