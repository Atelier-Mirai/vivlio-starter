require_relative 'common'

# entries.js生成タスク
desc "entries.jsを生成します"
task :entries do |t, args|
  args = BookBuild.process_args('entries')
  files = args[:files] || []
  options = args[:options] || {}

  # デバッグ用にオプションを表示
  BookBuild.log_action("entries.jsを生成しています...")
  
  # unless files.any?
  #   # 目次を生成
  #   Rake::Task['toc'].invoke
  # end
  
  # ベースディレクトリ（mybook 設定が有効なら mybook/ 配下）
  base_dir = '.'

  # 処理対象のHTMLファイル一覧を取得
  if files.any?
    # 引数で指定されたファイル群のみを対象（拡張子未指定なら .html を補完）
    html_files = files.map do |f|
      name = File.extname(f).empty? ? "#{f}.html" : f
      File.dirname(name) == '.' ? File.join(base_dir, name) : name
    end
  else
    # カレントディレクトリの .html 全てを対象
    html_files = Dir.glob(File.join(base_dir, "*.html"))
  end
  
  # 処理対象ファイルを表示
  BookBuild.log_info("目次作成対象ファイル: #{html_files.join(', ')}")
  
  # entries.jsの生成
  entries = html_files.map do |html_file|
    base_name = File.basename(html_file, ".html")
    title = base_name
    
    # HTMLファイルからタイトルを取得（優先）
    html_title = nil
    if File.exist?(html_file)
      content = File.read(html_file)
      if content =~ /<title>(.+?)<\/title>/
        html_title = $1.strip
        title = html_title if !html_title.empty?
      end
    end
    
    # HTMLからタイトルが取得できなかった場合のフォールバック処理
    if html_title.nil? || html_title.empty?
      # ファイル名からタイトルを生成
      if base_name =~ /^\d+-(.+)$/
        title = $1
      end
    end
    
    # エントリーを生成
    { path: html_file, title: title }
  end
  
  # entries.jsをES Module形式で書き込み
  File.open(File.join(base_dir, "entries.js"), "w") do |f|
    f.puts "export default ["
    entries.each_with_index do |entry, i|
      f.puts "  {"
      f.puts "    \"path\": \"#{entry[:path]}\","
      f.puts "    \"title\": \"#{entry[:title]}\""
      f.puts "  }#{i < entries.length - 1 ? ',' : ''}"
    end
    f.puts "]";
  end
  
  BookBuild.log_success("entries.js生成完了: #{entries.length}件のエントリを登録")
end
