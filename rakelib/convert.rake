require_relative 'common'

# シンプル変換タスク: 指定Markdown(拡張子任意: あり/なし)または全*.mdを vfm でHTML化
desc "Markdown→HTML を変換します"
task :convert do |t, _args|
  opts  = BookBuild.process_args('convert')
  files = opts[:files]

  # 入出力ディレクトリのベース（常にプロジェクトルート）
  base_dir = '.'

  # md の解決ヘルパー（与えられたトークンを base_dir 配下のパスに正規化）
  normalize_md = lambda do |name|
    n = name.to_s
    n = n =~ /\.md\z/ ? n : "#{n}.md"
    # 既にディレクトリを含む場合はそのまま使い、無い場合は base_dir を前置
    if File.dirname(n) == '.'
      File.join(base_dir, n)
    else
      n
    end
  end

  md_files =
    if files.any?
      files.map { |f| normalize_md.call(f) }.uniq
    else
      Dir.glob(File.join(base_dir, '*.md')).reject { |f| File.basename(f) =~ /\A(README|ROADMAP)\.md\z/ }
    end

  md_files.each do |md|
    html = md.sub(/\.md\z/, '.html')
    # 入出力にスペースが含まれても安全に処理
    cmd  = %(#{BookBuild::VFM_COMMAND} "#{md}" > "#{html}")
    success = system(cmd)
    warn("vfm failed: #{md}") unless success
  end
end
