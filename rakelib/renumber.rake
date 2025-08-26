# ファイル連番付け直しタスク
require_relative 'common'
require 'fileutils'

desc "contents/ディレクトリ内のファイルを連番に付け直します (例: rake renumber または rake renumber 17 16)"
task :renumber do |t, args|
  # コマンドライン引数を処理
  args = BookBuild.process_args('renumber')
  files      = args[:files]
  options    = args[:options]
  
  # 引数を取得（Rakeタスク引数またはfiles配列から）
  old_arg, new_arg = files.take(2)
  
  # 引数の有無で動作を切り替え
  if old_arg && new_arg
    # 個別章の番号変更は rename に委譲（別名）
    BookBuild.log_info("renumber は rename の別名です。内部的に rename を呼び出します")
    orig_argv = ARGV.dup
    begin
      # rename タスクは BookBuild.process_args('rename') で ARGV を読むため、
      # ここで一時的に置き換える
      ARGV.replace([old_arg.to_s, new_arg.to_s])
      Rake::Task['rename'].invoke
    ensure
      ARGV.replace(orig_argv)
      # 次回以降の実行に備えて再度有効化
      Rake::Task['rename'].reenable rescue nil
    end
  else
    # 全体の連番付け直しモード
    renumber_all_chapters
  end
end

def renumber_all_chapters
  BookBuild.log_action("章ファイルの連番付け直しを開始...")
  
  # 現在の章ファイルを取得（数字で始まるもののみ、前書き・あとがき・奥付は除外）
  chapter_files = Dir.glob("#{BookBuild::CONTENTS_DIR}/*.md")
                    .select { |f| File.basename(f) =~ /^\d+-/ }
                    .reject { |f| File.basename(f) =~ /^(0\d|98|99)-/ } # 前書き(0x)・あとがき(98)・奥付(99)を除外
                    .sort
  
  # 通常の章と付録を分離
  regular_chapters = chapter_files.select { |f| File.basename(f) =~ /^[1-8]\d-/ }
  appendix_files = chapter_files.select { |f| File.basename(f) =~ /^9[0-7]-/ } # 90-97のみ（98,99は除外）
  
  if chapter_files.empty?
    BookBuild.log_warn("連番付け直し対象のファイルが見つかりません")
    return
  end
  
  BookBuild.log_info("対象ファイル:")
    
  # 通常の章の表示
  if !regular_chapters.empty?
    BookBuild.log_info("通常の章:")
    regular_chapters.each_with_index do |file, index|
      old_name = File.basename(file, '.md')
      new_number = sprintf("%02d", index + 11)  # 11から開始
      BookBuild.log_info("#{old_name} → #{new_number}-#{old_name.split('-', 2)[1]}")
    end
  end
  
  # 付録の表示
  if !appendix_files.empty?
    BookBuild.log_info("付録:")
    appendix_files.each_with_index do |file, index|
      old_name = File.basename(file, '.md')
      new_number = sprintf("%02d", index + 91)  # 91から開始 (A, B, C...)
      new_letter = BookBuild.appendix_number_to_letter(new_number)
      # 付録の場合は文字も変更して表示
      new_name_part = old_name.split('-', 2)[1].sub(/appendix-[a-z]/, "appendix-#{new_letter}")
      BookBuild.log_info("#{old_name} → #{new_number}-#{new_name_part}")
    end
  end
  
  # 確認
  print "  ❓ 連番付け直しを実行しますか？ (y/N): "
  response = STDIN.gets.chomp.downcase
  
  unless response == 'y' || response == 'yes'
    BookBuild.log_warn("連番付け直しをキャンセルしました")
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
    BookBuild.log_success("すでに正しい連番になっています")
    return
  end
  
  BookBuild.log_action("ファイル名変更を実行中...")
  
  # 1. Markdownファイルのリネーム
  rename_map.each do |old_basename, info|
    BookBuild.log_info("#{old_basename}.md → #{info[:new_basename]}.md")
    FileUtils.mv(info[:old_file], info[:new_file])
  end
  
  # 2. CSSファイルのリネーム
  BookBuild.log_action("CSSファイルの更新中...")
  rename_map.each do |old_basename, info|
    old_css = "stylesheets/#{info[:old_number]}.css"
    new_css = "stylesheets/#{info[:new_number]}.css"
    
    if File.exist?(old_css)
      BookBuild.log_info("#{old_css} → #{new_css}")
      FileUtils.mv(old_css, new_css)
      
      # CSSファイル内のcounter-resetを更新
      BookBuild.update_css_counter(new_css, info[:new_number].to_i)
    end
  end
  
  # 3. 画像ディレクトリのリネーム
  BookBuild.log_action("画像ディレクトリの更新中...")
  rename_map.each do |old_basename, info|
    old_img_dir = "images/#{info[:old_number]}-*"
    Dir.glob(old_img_dir).each do |old_dir|
      if File.directory?(old_dir)
        # 付録の場合は文字も変更する
        if info[:new_number].to_i >= 91 && info[:new_number].to_i <= 97
          new_letter = BookBuild.appendix_number_to_letter(info[:new_number])
          new_dir = old_dir.sub(/\/#{info[:old_number]}-/, "/#{info[:new_number]}-").sub(/appendix-[a-z]/, "appendix-#{new_letter}")
        else
          new_dir = old_dir.sub(/\/#{info[:old_number]}-/, "/#{info[:new_number]}-")
        end
        BookBuild.log_info("#{old_dir} → #{new_dir}")
        FileUtils.mv(old_dir, new_dir)
      end
    end
  end
  
  # 4. 既存の生成ファイルをクリーンアップ
  BookBuild.log_action("既存の生成ファイルをクリーンアップ中...")
  Rake::Task['clean'].invoke
  
  BookBuild.log_success("連番付け直し完了")
  BookBuild.log_info("変更を反映するには以下を実行してください:")
  BookBuild.log_info("rake build")
end

# 付録番号変換・CSS更新ヘルパは BookBuild.* を使用
