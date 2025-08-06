# ファイル連番付け直しタスク
require_relative 'common'
require 'fileutils'

desc "contents/ディレクトリ内のファイルを連番に付け直します (例: rake renumber または rake renumber 17 16)"
task :renumber do
    # ARGV から引数を取得
    old_arg = ARGV[1]
    new_arg = ARGV[2]
    
    # ARGV の残りの引数をタスクとして実行されないようにする
    ARGV[1..-1].each { |arg| task arg.to_sym do ; end } if ARGV.length > 1
    
    # 引数の有無で動作を切り替え
    if old_arg && new_arg
      # 個別章の番号変更モード
      renumber_single_chapter(old_arg, new_arg)
    else
      # 全体の連番付け直しモード
      renumber_all_chapters
    end
end

def renumber_all_chapters
    puts "📝 章ファイルの連番付け直しを開始..."
    
    # 現在の章ファイルを取得（数字で始まるもののみ、前書き・あとがき・奥付は除外）
    chapter_files = Dir.glob("#{BookBuild::CONTENTS_DIR}/*.md")
                      .select { |f| File.basename(f) =~ /^\d+-/ }
                      .reject { |f| File.basename(f) =~ /^(0\d|98|99)-/ } # 前書き(0x)・あとがき(98)・奥付(99)を除外
                      .sort
    
    # 通常の章と付録を分離
    regular_chapters = chapter_files.select { |f| File.basename(f) =~ /^[1-8]\d-/ }
    appendix_files = chapter_files.select { |f| File.basename(f) =~ /^9[0-7]-/ } # 90-97のみ（98,99は除外）
    
    if chapter_files.empty?
      puts "  ⚠️ 連番付け直し対象のファイルが見つかりません"
      return
    end
    
    puts "  📋 対象ファイル:"
    
    # 通常の章の表示
    if !regular_chapters.empty?
      puts "    📚 通常の章:"
      regular_chapters.each_with_index do |file, index|
        old_name = File.basename(file, '.md')
        new_number = sprintf("%02d", index + 11)  # 11から開始
        puts "      #{old_name} → #{new_number}-#{old_name.split('-', 2)[1]}"
      end
    end
    
    # 付録の表示
    if !appendix_files.empty?
      puts "    📜 付録:"
      appendix_files.each_with_index do |file, index|
        old_name = File.basename(file, '.md')
        new_number = sprintf("%02d", index + 91)  # 91から開始 (A, B, C...)
        new_letter = appendix_number_to_letter(new_number)
        # 付録の場合は文字も変更して表示
        new_name_part = old_name.split('-', 2)[1].sub(/appendix-[a-z]/, "appendix-#{new_letter}")
        puts "      #{old_name} → #{new_number}-#{new_name_part}"
      end
    end
    
    # 確認
    print "  ❓ 連番付け直しを実行しますか？ (y/N): "
    response = STDIN.gets.chomp.downcase
    
    unless response == 'y' || response == 'yes'
      puts "  ❌ 連番付け直しをキャンセルしました"
      return
    end
    
    # 一時的なマッピングを作成
    rename_map = {}
    
    # 通常の章のマッピング
    regular_chapters.each_with_index do |file, index|
      old_basename = File.basename(file, '.md')
      old_number = old_basename.split('-')[0]
      new_number = sprintf("%02d", index + 11)  # 11から開始
      
      if old_number != new_number
        new_basename = old_basename.sub(/^\d+/, new_number)
        rename_map[old_basename] = {
          old_number: old_number,
          new_number: new_number,
          new_basename: new_basename,
          old_file: file,
          new_file: File.join(BookBuild::CONTENTS_DIR, "#{new_basename}.md")
        }
      end
    end
    
    # 付録のマッピング
    appendix_files.each_with_index do |file, index|
      old_basename = File.basename(file, '.md')
      old_number = old_basename.split('-')[0]
      new_number = sprintf("%02d", index + 91)  # 91から開始
      
      if old_number != new_number
        # 付録の場合は文字も変更する
        new_letter = appendix_number_to_letter(new_number)
        new_basename = old_basename.sub(/^\d+/, new_number).sub(/appendix-[a-z]/, "appendix-#{new_letter}")
        
        rename_map[old_basename] = {
          old_number: old_number,
          new_number: new_number,
          new_basename: new_basename,
          old_file: file,
          new_file: File.join(BookBuild::CONTENTS_DIR, "#{new_basename}.md")
        }
      end
    end
    
    if rename_map.empty?
      puts "  ✅ すでに正しい連番になっています"
      return
    end
    
    puts "  🔄 ファイル名変更を実行中..."
    
    # 1. Markdownファイルのリネーム
    rename_map.each do |old_basename, info|
      puts "    📄 #{old_basename}.md → #{info[:new_basename]}.md"
      FileUtils.mv(info[:old_file], info[:new_file])
    end
    
    # 2. CSSファイルのリネーム
    puts "  🎨 CSSファイルの更新中..."
    rename_map.each do |old_basename, info|
      old_css = "stylesheets/#{info[:old_number]}.css"
      new_css = "stylesheets/#{info[:new_number]}.css"
      
      if File.exist?(old_css)
        puts "    🎨 #{old_css} → #{new_css}"
        FileUtils.mv(old_css, new_css)
        
        # CSSファイル内のcounter-resetを更新
        update_css_counter(new_css, info[:new_number].to_i)
      end
    end
    
    # 3. 画像ディレクトリのリネーム
    puts "  🖼️ 画像ディレクトリの更新中..."
    rename_map.each do |old_basename, info|
      old_img_dir = "images/#{info[:old_number]}-*"
      Dir.glob(old_img_dir).each do |old_dir|
        if File.directory?(old_dir)
          # 付録の場合は文字も変更する
          if info[:new_number].to_i >= 91 && info[:new_number].to_i <= 97
            new_letter = appendix_number_to_letter(info[:new_number])
            new_dir = old_dir.sub(/\/#{info[:old_number]}-/, "/#{info[:new_number]}-").sub(/appendix-[a-z]/, "appendix-#{new_letter}")
          else
            new_dir = old_dir.sub(/\/#{info[:old_number]}-/, "/#{info[:new_number]}-")
          end
          puts "    🖼️ #{old_dir} → #{new_dir}"
          FileUtils.mv(old_dir, new_dir)
        end
      end
    end
    
    # 4. 既存の生成ファイルをクリーンアップ
    puts "  🧹 既存の生成ファイルをクリーンアップ中..."
    Rake::Task['clean'].invoke
    
    puts "  ✅ 連番付け直し完了"
    puts "  💡 変更を反映するには以下を実行してください:"
    puts "     rake build"
end

def renumber_single_chapter(old_arg, new_arg)
    
    if old_arg.nil? || new_arg.nil?
      puts <<~USAGE
        指定した章の番号を変更します
        使用法: rake renumber 旧番号 新番号
        
        例:
          rake renumber 17 16  # 17章を16章に変更
          rake renumber 31 18  # 31章を18章に変更
      USAGE
      exit 1
    end
    
    old_number = sprintf("%02d", old_arg.to_i)
    new_number = sprintf("%02d", new_arg.to_i)
    
    # あとがきと奥付の保護
    if old_number == "98" || old_number == "99"
      puts "  ❌ #{old_number}はあとがきまたは奥付のため、変更できません"
      exit 1
    end
    
    if new_number == "98" || new_number == "99"
      puts "  ❌ #{new_number}はあとがきまたは奥付のため、変更先として使用できません"
      exit 1
    end
    
    puts "📝 章番号変更: #{old_number} → #{new_number}"
    
    # 対象ファイルを検索
    old_md_pattern = "#{BookBuild::CONTENTS_DIR}/#{old_number}-*.md"
    old_md_files = Dir.glob(old_md_pattern)
    
    if old_md_files.empty?
      puts "  ❌ #{old_number}章のファイルが見つかりません"
      exit 1
    end
    
    if old_md_files.length > 1
      puts "  ❌ #{old_number}章のファイルが複数見つかりました:"
      old_md_files.each { |f| puts "    - #{File.basename(f)}" }
      exit 1
    end
    
    old_md_file = old_md_files.first
    old_basename = File.basename(old_md_file, '.md')
    
    # 付録の場合は文字も変更する
    if new_number.to_i >= 91 && new_number.to_i <= 97
      # 付録の場合: 番号と文字を変更
      new_letter = appendix_number_to_letter(new_number)
      new_basename = old_basename.sub(/^\d+/, new_number).sub(/appendix-[a-z]/, "appendix-#{new_letter}")
    else
      # 通常の章の場合: 番号のみ変更
      new_basename = old_basename.sub(/^\d+/, new_number)
    end
    
    new_md_file = File.join(BookBuild::CONTENTS_DIR, "#{new_basename}.md")
    
    # 新しい番号のファイルが既に存在するかチェック
    if File.exist?(new_md_file)
      puts "  ❌ #{new_number}章のファイルが既に存在します: #{File.basename(new_md_file)}"
      exit 1
    end
    
    puts "  📄 #{old_basename}.md → #{new_basename}.md"
    
    # 確認
    print "  ❓ 章番号変更を実行しますか？ (y/N): "
    response = STDIN.gets.chomp.downcase
    
    unless response == 'y' || response == 'yes'
      puts "  ❌ 章番号変更をキャンセルしました"
      return
    end
    
    # 1. Markdownファイルのリネーム
    FileUtils.mv(old_md_file, new_md_file)
    puts "    ✅ Markdownファイル変更完了"
    
    # 2. CSSファイルの処理
    old_css = "stylesheets/#{old_number}.css"
    new_css = "stylesheets/#{new_number}.css"
    
    if File.exist?(old_css)
      if File.exist?(new_css)
        puts "    ⚠️ #{new_css} が既に存在するため、CSSファイルは手動で統合してください"
      else
        FileUtils.mv(old_css, new_css)
        update_css_counter(new_css, new_number.to_i)
        puts "    ✅ CSSファイル変更完了"
      end
    end
    
    # 3. 画像ディレクトリの処理
    old_img_dirs = Dir.glob("images/#{old_number}-*")
    old_img_dirs.each do |old_dir|
      if File.directory?(old_dir)
        # 付録の場合は文字も変更する
        if new_number.to_i >= 91 && new_number.to_i <= 97
          new_letter = appendix_number_to_letter(new_number)
          new_dir = old_dir.sub(/\/#{old_number}-/, "/#{new_number}-").sub(/appendix-[a-z]/, "appendix-#{new_letter}")
        else
          new_dir = old_dir.sub(/\/#{old_number}-/, "/#{new_number}-")
        end
        
        if File.exist?(new_dir)
          puts "    ⚠️ #{new_dir} が既に存在するため、画像ディレクトリは手動で統合してください"
        else
          FileUtils.mv(old_dir, new_dir)
          puts "    ✅ 画像ディレクトリ変更完了: #{File.basename(new_dir)}"
        end
      end
    end
    
    # 4. 既存の生成ファイルをクリーンアップ
    old_generated_files = [
      "#{old_basename}.md",
      "#{old_basename}.html"
    ]
    
    old_generated_files.each do |file|
      if File.exist?(file)
        File.delete(file)
        puts "    🗑️ #{file} を削除"
      end
    end
    
    puts "  ✅ 章番号変更完了"
    puts "  💡 変更を反映するには以下を実行してください:"
    puts "     rake preprocess #{new_basename.split('-')[0]}-#{new_basename.split('-', 2)[1]}"
end

# 付録番号を文字に変換
def appendix_number_to_letter(number)
  case number.to_i
  when 91 then 'a'
  when 92 then 'b'
  when 93 then 'c'
  when 94 then 'd'
  when 95 then 'e'
  when 96 then 'f'
  when 97 then 'g'
  else 'x' # 予備
  end
end

# CSSファイル内のcounter-resetを更新
def update_css_counter(css_file, chapter_number)
  return unless File.exist?(css_file)
  
  content = File.read(css_file, encoding: 'utf-8')
  updated_content = content.gsub(
    /counter-reset:\s*chapter-counter\s+\d+/,
    "counter-reset: chapter-counter #{chapter_number - 10}"
  )

  updated_content = updated_content.gsub(
    /\* 第\d+章用スタイル \*\//,
    "* 第#{chapter_number - 10}章用スタイル */"
  )
  
  if content != updated_content
    File.write(css_file, updated_content, encoding: 'utf-8')
    puts "      ✏️ counter-reset を #{chapter_number - 10} に更新"
  end
end
