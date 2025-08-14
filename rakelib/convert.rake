require_relative 'common'
 
# シンプル変換タスク: 指定Markdown(拡張子任意: あり/なし)または全*.mdを vfm でHTML化
desc "Markdown→HTML を変換します"
task :convert do |t, _args|
  opts  = BookBuild.process_args('convert')
  files = opts[:files]

  md_files =
    if files.any?
      files.map { |f| f =~ /\.md\z/ ? f : "#{f}.md" }.uniq
    else
      Dir.glob('*.md').reject { |f| f =~ /\A(README|ROADMAP)\.md\z/ }
    end

  md_files.each do |md|
    html = md.sub(/\.md\z/, '.html')
    cmd  = "#{BookBuild::VFM_COMMAND} #{md} > #{html}"
    success = system(cmd)
    warn("vfm failed: #{md}") unless success
  end
end
