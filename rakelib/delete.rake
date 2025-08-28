require_relative 'common'

# 使い方
# vs delete 11-install
# vs delete 11-install.md
# vs delete 11-install 12-tutorial
# vs delete 11-21
# vs delete 11 21-31
  # 削除の確認を求める（--force / -f / --y があれば確認をスキップ）

  
module ChapterDeleter
  extend self

  # 削除の確認を求める（--force / -f / --y があれば確認をスキップ）
  def confirm_deletion(file_path, options = {})
    opts = options || {}
    return true if opts[:force] || opts[:f] || opts[:y]
    print "⚠️ 本当に #{file_path} を削除しますか？ (y/N): "
    response = $stdin.gets&.chomp&.downcase
    response == 'y' || response == 'yes'
  end

  # Markdownファイルを削除する
  def delete_markdown_file(filename, options)
    md_file = "#{BookBuild::CONTENTS_DIR}/#{filename}"

    if File.exist?(md_file)
      if confirm_deletion("文書ファイル: #{md_file}", options)
        File.delete(md_file)
        BookBuild.log_success("文書ファイルを削除しました: #{md_file}")
      else
        BookBuild.log_info("文書ファイルの削除をスキップしました: #{md_file}")
      end
    else
      BookBuild.log_info("文書ファイルは存在しません: #{md_file}")
    end
  end

  # 画像ディレクトリを削除する
  def delete_image_directory(filename, options)
    base_filename = filename.gsub(/\.md$/, '')
    image_dir = "#{BookBuild::IMAGES_DIR}/#{base_filename}"
    
    if Dir.exist?(image_dir)
      if confirm_deletion("画像ディレクトリ: #{image_dir}", options)
        FileUtils.remove_dir(image_dir, true)
        BookBuild.log_success("画像ディレクトリを削除しました: #{image_dir}")
      else
        BookBuild.log_info("画像ディレクトリの削除をスキップしました: #{image_dir}")
      end
    else
      BookBuild.log_info("画像ディレクトリは存在しません: #{image_dir}")
    end
  end
  
  # CSSファイルを削除する
  def delete_css_file(filename, options)
    chapter_num = BookBuild.get_chapter_number(filename)
    return false unless chapter_num
    
    css_file = "#{BookBuild::STYLESHEETS_DIR}/#{chapter_num}.css"
    
    if File.exist?(css_file)
      if confirm_deletion("CSSファイル: #{css_file}", options)
        File.delete(css_file)
        BookBuild.log_success("CSSファイルを削除しました: #{css_file}")
        return true
      else
        BookBuild.log_info("CSSファイルの削除をスキップしました: #{css_file}")
        return false
      end
    else
      BookBuild.log_info("CSSファイルは存在しません: #{css_file}")
      return false
    end
  end

  # --- ここから: 指定の展開ユーティリティ ---
  # contents ディレクトリ内の Markdown ベース名一覧を取得（例: ["11-install.md", ...]）
  def list_contents_basenames
    Dir.glob(File.join(BookBuild::CONTENTS_DIR, '*.md')).map { |p| File.basename(p) }
  end

  # ベース名から章番号を取得（例: "21-history.md" -> 21）
  def chapter_number_from_basename(basename)
    (basename[/^(\d+)-/, 1] || nil)&.to_i
  end

  # 章番号の範囲に一致するベース名を抽出
  def find_basenames_in_range(from_num, to_num)
    a, b = [from_num.to_i, to_num.to_i].minmax
    list_contents_basenames.select do |bn|
      n = chapter_number_from_basename(bn)
      n && n >= a && n <= b
    end
  end

  # トークン（"11", "11-21", "11-install"）を実在ファイル群へ展開
  # 戻り: ["11-foo.md", ...]（存在するもののみ）
  def expand_token_to_basenames(token)
    t = token.to_s.strip
    return [] if t.empty?

    # 範囲指定（例: 11-21）
    if t =~ /(\A\d+)-(\d+\z)/
      return find_basenames_in_range($1, $2)
    end

    # 章番号のみ（例: 11） -> 11- で始まるファイルすべて
    if t =~ /\A\d+\z/
      return list_contents_basenames.select { |bn| bn.start_with?("#{t}-") }
    end

    # スラッグ指定（例: 11-install）
    name = t + '.md'
    path = File.join(BookBuild::CONTENTS_DIR, name)
    return File.exist?(path) ? [name] : []
  end

  # --- ここから: dry-run 用ユーティリティ ---
  def dry_run?(options)
    opts = options || {}
    !!(opts[:dry_run] || opts[:n])
  end

  def preview_deletions(basename, options)
    base = basename.sub(/\.md$/, '')
    md_file = File.join(BookBuild::CONTENTS_DIR, basename)
    img_dir = File.join(BookBuild::IMAGES_DIR, base)
    css_file = nil
    if (num = BookBuild.get_chapter_number(basename))
      css_file = File.join(BookBuild::STYLESHEETS_DIR, "#{num}.css")
    end

    puts "[DRY-RUN] #{base} の削除予定:"
    puts "  - 文書:       #{md_file} #{File.exist?(md_file) ? '(exists)' : '(not found)'}"
    puts "  - 画像Dir:    #{img_dir} #{Dir.exist?(img_dir) ? '(exists)' : '(not found)'}"
    if css_file
      puts "  - CSS:        #{css_file} #{File.exist?(css_file) ? '(exists)' : '(not found)'}"
    else
      puts "  - CSS:        (対象外)"
    end
  end
end

desc "指定した章を削除します (例: rake delete 21-history)"
task :delete do |t, args|
  # コマンドライン引数を取得
  args = BookBuild.process_args('delete')
  files   = args[:files]
  options = args[:options]

  # 引数検証
  if files.empty?
    BookBuild.log_error("エラー: 削除する章のファイル名を指定してください (例: rake delete 21-history)")
    exit 1
  end

  # すべての指定（単体/複数/範囲）を実在ファイルに展開
  targets = files.flat_map { |tok| ChapterDeleter.expand_token_to_basenames(tok) }.uniq

  if targets.empty?
    BookBuild.log_warn("指定に一致する章ファイルが見つかりませんでした: #{files.join(' ')}")
    exit 1
  end

  # dry-run: 削除予定を表示して終了
  if ChapterDeleter.dry_run?(options)
    puts "\n== Dry Run: 削除予定一覧 =="
    targets.each { |basename| ChapterDeleter.preview_deletions(basename, options) }
    puts "\n合計 #{targets.size} 章が対象（dry-run、実ファイルは変更されません）。"
    exit 0
  end

  # 各ターゲットを削除
  targets.each do |basename|
    ChapterDeleter.delete_markdown_file(basename, options)
    ChapterDeleter.delete_image_directory(basename, options)
    ChapterDeleter.delete_css_file(basename, options)
  end
end
