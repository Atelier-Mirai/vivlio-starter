# クリーンアップ
desc "不要ファイルを削除します"
task :clean do
  
  # .vivliostyle ディレクトリを削除
  BookBuild.log_action(".vivliostyle ディレクトリを削除中...")
  FileUtils.rm_rf('.vivliostyle')
  
  # 生成ファイルを削除（PDFも含む）
  BookBuild.log_action("生成ファイルを削除中...")
  
  # プロジェクトルートの一時ファイルを削除
  cleanup_patterns = [
    '*.html',     # HTMLファイル
    '03-toc.md',  # 生成された目次MD
    'entries.js', # 生成されたentries.js
  ]
  
  # content/からコピーされたMDファイルを削除
  # 重要ドキュメントは保持
  keep_files = ['README.md', 'ROADMAP.md', 'CONTENT-LICENSE.md', 'THIRD-PARTY-LICENSES.md', 'CHANGELOG.md']
  Dir.glob('*.md').each do |file|
    next if keep_files.include?(file)
    cleanup_patterns << file
  end
  
  # 中間PDF（結合・作業用）を削除対象に追加（最終成果物は除外）
  intermediate_pdfs = [
    '00-titlepage.pdf',
    '01-legalpage.pdf',
    '02-preface.pdf',
    '03-toc.pdf',
    'frontmatter.pdf',
    'chapters_appendices.pdf',
    '98-postface.pdf',
    '99-colophon.pdf',
    'blank_page.pdf',
    'blank_frontmatter_insert.pdf'
  ]
  cleanup_patterns.concat(intermediate_pdfs)
  
  # 最終成果物は保持
  final_pdfs = [
    (BookBuild::CONFIG.dig('pdf', 'output_file') || 'output.pdf'),
    (BookBuild::CONFIG.dig('pdf', 'output_file_compressed') || 'output_compressed.pdf')
  ].uniq
  
  cleanup_patterns.each do |pattern|
    Dir.glob(pattern).each do |file|
      next if File.directory?(file)
      
      # 最終成果物は削除しない
      if final_pdfs.include?(file)
        BookBuild.log_info("保持: #{file}")
        next
      end
      
      FileUtils.rm_f(file)
      BookBuild.log_info("#{file} を削除しました")
    end
  end  
end
