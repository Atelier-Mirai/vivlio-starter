require_relative 'common'

# CSS関連タスク
namespace :css do
  desc "章ごとのCSSファイルを生成します"
  task :chapter do |t, args|
    puts "🎨 章ごとのCSSファイルを生成しています..."
    
    # Markdownファイルの一覧を取得
    md_files = Dir.glob("#{BookBuild::CONTENT_DIR}/*.md")
    
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
    
    # CSSディレクトリが存在するか確認
    unless Dir.exist?(BookBuild::STYLESHEETS_DIR)
      FileUtils.mkdir_p(BookBuild::STYLESHEETS_DIR)
      puts "  📂 #{BookBuild::STYLESHEETS_DIR} ディレクトリを作成しました"
    end
    
    # 章ごとのCSSファイルを生成
    chapter_numbers.each do |chapter_num|
      css_filename = "#{BookBuild::STYLESHEETS_DIR}/#{chapter_num}.css"
      
      # 既存のファイルがない場合のみ生成
      unless File.exist?(css_filename)
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
      else
        puts "  ℹ️ #{css_filename} は既に存在します"
      end
    end
    
    puts "✅ 章ごとのCSSファイル生成完了"
  end
end
