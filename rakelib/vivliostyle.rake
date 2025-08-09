require_relative 'common'

namespace :vivliostyle do
  desc "config/book.yml の設定から vivliostyle.config.js を生成します（既存は自動バックアップ）"
  task :generate_config do |t, args|
    # 引数を処理（将来拡張用、現状未使用）
    _parsed = BookBuild.process_args('vivliostyle:generate_config')

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

    # バックアップ処理（最新のみ保持）
    if File.exist?(config_file)
      Dir.glob("#{config_file}.backup_*").each { |f| FileUtils.rm_f(f) }
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
end

namespace :vs do
  desc "vivliostyle.config.js を生成（vivliostyle:generate_config の短縮形）"
  task :config => 'vivliostyle:generate_config'
end

