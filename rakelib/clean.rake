# クリーンアップ
desc "不要ファイルを削除します"
task :clean do
  
  # .vivliostyle ディレクトリを削除
  BookBuild.log_action(".vivliostyle ディレクトリを削除中...")
  FileUtils.rm_rf('.vivliostyle')
  
  # 生成されたPDF以外のファイルを削除
  BookBuild.log_action("生成ファイルを削除中...")
  
  # プロジェクトルートの一時ファイルを削除
  cleanup_patterns = [
    '*.html',     # HTMLファイル
    '03-toc.md',  # 生成された目次MD
    'entries.js', # 生成されたentries.js
  ]
  
  # content/からコピーされたMDファイルを削除
  # README.mdとROADMAP.mdは保持
  keep_files = ['README.md', 'ROADMAP.md', 'CONTENT-LICENSE.md', 'THIRD-PARTY-LICENSES.md']
  Dir.glob('*.md').each do |file|
    next if keep_files.include?(file)
    cleanup_patterns << file
  end
  
  cleanup_patterns.each do |pattern|
    Dir.glob(pattern).each do |file|
      next if File.directory?(file)
      
      FileUtils.rm(file)
      BookBuild.log_info("#{file} を削除しました")
    end
  end
  
end
