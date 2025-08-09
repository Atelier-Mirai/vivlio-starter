require_relative 'common'

module ChapterDeleter
  # 引数を検証し、正規化する
  def self.ensure_filename(filename)
    name = filename.to_s.strip
    if name.empty?
      BookBuild.log_error("ファイル名を指定してください (例: rake delete 21-history)")
      return nil
    end

    # 拡張子付与
    name << '.md' unless name.end_with?('.md')

    # 既存チェック
    file_path = "#{BookBuild::CONTENTS_DIR}/#{name}"
    unless File.exist?(file_path)
      BookBuild.log_warn("#{file_path} は存在しません")
      return nil
    end

    name
  end

  # 削除の確認を求める
  def self.confirm_deletion(file_path)
    print "⚠️ 本当に #{file_path} を削除しますか？ (y/N): "
    response = $stdin.gets.chomp.downcase
    response == 'y' || response == 'yes'
  end

  # Markdownファイルを削除する
  def self.delete_markdown_file(filename, options)
    md_file = "#{BookBuild::CONTENTS_DIR}/#{filename}"

    if File.exist?(md_file)
      if confirm_deletion("文書ファイル: #{md_file}")
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
  def self.delete_image_directory(filename, options)
    base_filename = filename.gsub(/\.md$/, '')
    image_dir = "#{BookBuild::IMAGES_DIR}/#{base_filename}"
    
    if Dir.exist?(image_dir)
      if confirm_deletion("画像ディレクトリ: #{image_dir}")
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
  def self.delete_css_file(filename, options)
    chapter_num = BookBuild.get_chapter_number(filename)
    return false unless chapter_num
    
    css_file = "#{BookBuild::STYLESHEETS_DIR}/#{chapter_num}.css"
    
    if File.exist?(css_file)
      if confirm_deletion("CSSファイル: #{css_file}")
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

  # ファイル名の検証・正規化
  filename = ChapterDeleter.ensure_filename(files.first)
  unless filename
    BookBuild.log_error("エラー: 無効なファイル名です")
    exit 1
  end

  ChapterDeleter.delete_markdown_file(filename, options)
  ChapterDeleter.delete_image_directory(filename, options)
  ChapterDeleter.delete_css_file(filename, options)
end
