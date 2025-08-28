# frozen_string_literal: true

# 用語集を正準化するタスク群
# - description を `|-` ブロックスカラへ統一
# - 各 `- key:` ブロックの直前に1行の空行（先頭は除く）
# - key の昇順でソート
# - 乾式チェック: glossary:canonicalize:check
#
# 実行:
#   ./bin/vs glossary:canonicalize
#   ./bin/vs glossary:canonicalize:check

namespace :glossary do
  namespace :canonicalize do
    desc 'config/glossary.yml を正準化（dry-run）し、差分の有無を返します'
    task :check do
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
  end

  desc 'config/glossary.yml を正準化します（descriptionのブロック化、空行整形、key順ソート）'
  task :canonicalize do
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
end

# =========================
# 内部ヘルパ
# =========================

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
# - 既に `description: |`/`description: |-` の場合はそのまま
# - `description: <1行>` を
#     description: |-
#       <1行>
#   に変換（インデント維持）

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

# =========================
# 使い勝手のためのエイリアス
# =========================

# 短縮: `./bin/vs glossary:format`
task 'glossary:format' => 'glossary:canonicalize'

# Lintの自動修正風: `./bin/vs glossary:lint:fix`
task 'glossary:lint:fix' => 'glossary:canonicalize'
