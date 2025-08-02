# クリーンアップ関連のタスク
require 'fileutils'

desc ".vivliostyle ディレクトリと生成ファイルを削除します"
task :clean do
  puts "🧹 一時ファイルを削除しています..."
  # .vivliostyle ディレクトリを削除
  FileUtils.rm_rf('.vivliostyle')

  # workspace ディレクトリの内容を削除（PDFと特定のHTML以外）
  if Dir.exist?('workspace')
    Dir.glob('workspace/*.html').reject { |f| f == 'workspace/99-colophon.html' || f == 'workspace/00-toc.html' }.each { |f| File.delete(f) }
  else
    FileUtils.mkdir_p('workspace')
  end
end
