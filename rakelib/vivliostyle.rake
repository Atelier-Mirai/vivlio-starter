require_relative 'common'

# Vivliostyle設定生成関連タスク
desc <<~DESC
  book.ymlの情報をもとにvivliostyle.config.jsを生成します
  
  既存の設定ファイルがある場合、以下のコマンドでバックアップを作成できます
    rake vivliostyle -- --backup
  
  バックアップファイルは `vivliostyle.config.js.backup_YYYYMMDD_HHMMSS` として保存されます
DESC
task :vivliostyle do |t, args|
  # コマンドライン引数を取得
  args    = BookBuild.process_args('vivliostyle')
  options = args[:options]

  BookBuild.log_action("vivliostyle.config.jsを生成しています...")
  
  # 設定を取得
  config             = BookBuild::CONFIG
  book_config        = config['book'] || {}
  vivliostyle_config = config['vivliostyle'] || {}
  pdf_config         = config['pdf'] || {}
  
  # 設定値を取得（デフォルト値付き）
  title               = book_config['title'] || '書籍タイトル'
  author              = book_config['author'] || '著者名'
  language            = book_config['language'] || 'ja'
  reading_progression = vivliostyle_config['reading_progression'] || 'ltr'
  image               = vivliostyle_config['image'] || 'ghcr.io/vivliostyle/cli:9.5.0'
  entries_file        = vivliostyle_config['entries_file'] || 'entries.js'
  output_file         = pdf_config['output_file'] || 'output.pdf'
  config_file         = vivliostyle_config['config_file'] || 'vivliostyle.config.js'
  
  # バックアップ処理（オプション指定時）
  if options[:b] || options[:backup] && File.exist?(config_file)
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_file = "#{config_file}.backup_#{timestamp}"
    FileUtils.cp(config_file, backup_file)
    BookBuild.log_info("既存ファイルをバックアップしました: #{backup_file}")
  end
  
  # vivliostyle.config.jsの内容を生成
  config_content = <<~JS
    import entries from './#{entries_file}';

    // @ts-check
    /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
    const vivliostyleConfig = {
      title: '#{title}', // 書籍のタイトル
      author: '#{author}', // 著者名
      language: '#{language}', // 言語設定
      readingProgression: '#{reading_progression}', // 読み進め方向（ltr: 横書き, rtl: 縦書き）
      image: '#{image}', // VivliostyleのDockerイメージ
      entry: entries, // 章立て構成（#{entries_file}から読み込み）
      output: [ // 出力ファイル設定
        './#{output_file}' // PDFファイル
      ]
    };

    export default vivliostyleConfig;
  JS
  
  # ファイルに書き込み
  File.write(config_file, config_content)
  
  BookBuild.log_success("#{config_file} を生成しました")
  BookBuild.log_info("タイトル: #{title}")
  BookBuild.log_info("著者: #{author}")
  BookBuild.log_info("言語: #{language}")
  BookBuild.log_info("読み進め方向: #{reading_progression}")
  BookBuild.log_info("Dockerイメージ: #{image}")
  BookBuild.log_info("出力ファイル: #{output_file}")
end

# 設定の差分を表示
desc "現在のvivliostyle.config.jsとbook.ymlの設定の差分を表示します"
task :vivliostyle_diff do
  BookBuild.log_action("設定の差分を確認しています...")
  
  config             = BookBuild::CONFIG
  book_config        = config['book'] || {}
  vivliostyle_config = config['vivliostyle'] || {}
  pdf_config         = config['pdf'] || {}
  config_file        = vivliostyle_config['config_file'] || 'vivliostyle.config.js'
  
  if File.exist?(config_file)
    BookBuild.log_info("現在の#{config_file}:")
    current_content = File.read(config_file)
    
    # 現在の設定から値を抽出（簡易的）
    current_title    = current_content[/title: '([^']*)'/, 1] || '不明'
    current_author   = current_content[/author: '([^']*)'/, 1] || '不明'
    current_language = current_content[/language: '([^']*)'/, 1] || '不明'
    current_reading  = current_content[/readingProgression: '([^']*)'/, 1] || '不明'
    
    BookBuild.log_info("タイトル: #{current_title}")
    BookBuild.log_info("著者: #{current_author}")
    BookBuild.log_info("言語: #{current_language}")
    BookBuild.log_info("読み進め方向: #{current_reading}")
    
    puts ""
    BookBuild.log_info("book.ymlの設定:")
    BookBuild.log_info("タイトル: #{book_config['title'] || 'デフォルト'}")
    BookBuild.log_info("著者: #{book_config['author'] || 'デフォルト'}")
    BookBuild.log_info("言語: #{book_config['language'] || 'デフォルト'}")
    BookBuild.log_info("読み進め方向: #{vivliostyle_config['reading_progression'] || 'デフォルト'}")
    
    # 差分があるかチェック
    differences = []
    differences << "タイトル" if current_title != (book_config['title'] || '書籍タイトル')
    differences << "著者" if current_author != (book_config['author'] || '著者名')
    differences << "言語" if current_language != (book_config['language'] || 'ja')
    differences << "読み進め方向" if current_reading != (vivliostyle_config['reading_progression'] || 'ltr')
    
    if differences.any?
      puts ""
      BookBuild.log_warn("差分が検出されました: #{differences.join(', ')}")
      BookBuild.log_info("'rake vivliostyle' で設定を更新できます")
    else
      puts ""
      BookBuild.log_success("設定に差分はありません")
    end
  else
    BookBuild.log_warn("#{config_file} が見つかりません")
    BookBuild.log_info("'rake vivliostyle' で新規作成できます")
  end
end
