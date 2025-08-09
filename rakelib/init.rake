require_relative 'common'

# プロジェクト初期化
desc "プロジェクトを初期化します"
task :init do |t, args|
  args    = BookBuild.process_args('build')
  options = args[:options]

  BookBuild.log_action("プロジェクトを初期化しています...")
  
  # 必要なディレクトリを作成
  [BookBuild::CONTENTS_DIR, BookBuild::STYLESHEETS_DIR, BookBuild::IMAGES_DIR].each do |dir|
    unless Dir.exist?(dir)
      FileUtils.mkdir_p(dir)
      BookBuild.log_info("#{dir}/ ディレクトリを作成しました")
    end
  end
  
  # スタイルシートの作成
  file_types = ['preface', 'toc', 'chapter', 'appendix', 'postface', 'colophon']
  file_types.each do |type|
    css_file = "#{BookBuild::STYLESHEETS_DIR}/#{type}.css"
    unless File.exist?(css_file)
      File.write(css_file, <<~CSS)
        @charset "utf-8";
        
        /* #{type}用スタイル */
        
      CSS
      BookBuild.log_success("#{css_file} を作成しました")
    end
  end
  
  BookBuild.log_success("プロジェクト初期化完了")
end