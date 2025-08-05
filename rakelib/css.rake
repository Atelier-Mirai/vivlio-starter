require_relative 'common'

# CSS関連タスク
namespace :new do
  desc "章ごとのCSSファイルを生成します (例: rake new:css 21-history)"
  task :css do |t|
    # コマンドライン引数を取得
    filename = ARGV[1]

    # CSSディレクトリが存在するか確認
    unless Dir.exist?(BookBuild::STYLESHEETS_DIR)
      FileUtils.mkdir_p(BookBuild::STYLESHEETS_DIR)
      puts "  📂 #{BookBuild::STYLESHEETS_DIR} ディレクトリを作成しました"
    end

    # 引数でファイル名が指定されているか確認
    if filename && !filename.empty?
      # filenameは既に取得済み
      puts "  ℹ️ 指定されたファイル名: #{filename}"
      
      # ファイルタイプを判定
      file_type = BookBuild.get_file_type(filename)
      
      # chapterタイプでない場合は処理を中止
      unless file_type == 'chapter'
        puts "  ℹ️ #{filename} は chapter タイプではないため、CSSファイルは生成しません"
        exit 0 if filename && !filename.empty? # 追加の引数を処理しないようにする
        next
      end
      
      # ファイル名から章番号を抽出（例: 21-history → 21）
      chapter_num = filename.match(/^(\d+)-/)[1] rescue nil
      
      if chapter_num.nil?
        puts "  ❌ 有効な章番号が指定されていません。例: 21-history"
        exit 0 if filename && !filename.empty? # 追加の引数を処理しないようにする
        next
      end
      
      # 指定された章番号のCSSファイルのみ生成
      chapter_numbers = [chapter_num]
    else
      puts "  ℹ️ 全ての章のCSSファイルを生成します"
      
      # Markdownファイルの一覧を取得
      md_files = Dir.glob("#{BookBuild::CONTENTS_DIR}/*.md")
      
      # 章タイプのファイルを抜き出し、章番号を取得
      chapter_numbers = md_files.map do |file_path|
        filename = File.basename(file_path)
        file_type = BookBuild.get_file_type(filename)
        
        if file_type == 'chapter'
          filename =~ /^(\d+)-/ ? $1 : nil
        else
          nil
        end
      end.compact.uniq
    end
    
    # 章ごとのCSSファイルを生成
    chapter_numbers.each do |chapter_num|
      css_filename = "#{BookBuild::STYLESHEETS_DIR}/#{chapter_num}.css"
      
      # 既存のファイルがない場合のみ生成
      if File.exist?(css_filename)
        puts "  ℹ️ #{css_filename} は既に存在します"
        next
      else        
        css_content = <<~CSS
          @charset "utf-8";
          
          /* 第#{chapter_num.to_i - 10}章用スタイル */
          
          /* 章番号を設定 */
          :root {
            counter-reset: chapter-counter #{chapter_num.to_i - 10};
          }
          
          /* 章固有のスタイルをここに追加 */
          
        CSS
        
        File.write(css_filename, css_content, encoding: 'utf-8')
        puts "  ✅ #{css_filename} を生成しました"
      end
    end
    
    puts "✅ 章ごとのCSSファイル生成完了"
    
    # 追加の引数を処理しないようにする
    if filename && !filename.empty?
      exit 0
    end
  end
end
