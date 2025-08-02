# 前処理関連のタスク
require 'fileutils'

desc "序文ファイルにフロントマターを追加し、画像パスを修正してworkspaceディレクトリにコピーします"
task :preprocess do
  puts "📝 序文ファイルを前処理しています..."
  
  src_path  = 'content/00-preface.md'
  temp_path = 'workspace/00-preface.md.tmp'
  dest_path = 'workspace/00-preface.md'
  
  # workspaceディレクトリが存在しない場合は作成
  FileUtils.mkdir_p('workspace') unless Dir.exist?('workspace')
  
  # ファイルが存在するか確認
  unless File.exist?(src_path)
    abort("❌ ファイル #{src_path} が見つかりません")
  end
  
  # 元のファイル内容を読み込み
  content = File.read(src_path)
  
  # 1) フロントマターを追加（既存のフロントマターがある場合は置換）
  frontmatter = <<~FRONT
  ---
  link:
    - rel: 'stylesheet'
      href: '../stylesheets/matter.css'
  lang: 'ja'
  ---

  FRONT
  
  # 既存のフロントマターを削除（あれば）
  content = content.sub(/^---\n.*?---\n\n/m, '')
  
  # 新しいフロントマターを追加
  content = frontmatter + content
  
  # 2) 画像パスを修正
  content = content.gsub(/!\[\]\(([^\/\)]+)\)/, '![](../images/00-preface/\1)')
  
  # 処理済みの内容を一時ファイルに書き込み
  File.write(temp_path, content)
  
  # 3) 処理済みファイルを最終的な場所にコピー
  FileUtils.mv(temp_path, dest_path)
  
  puts "✅ 序文の前処理が完了しました: #{dest_path}"
end

# 今は序文の前処理のみだが、将来的に他の前処理タスクが追加された場合のためのプレースホルダー
# desc "すべての前処理タスクを実行します"
# task :preprocess_all => [:preprocess] do
#   puts "🔄 すべての前処理が完了しました"
# end
