#!/usr/bin/env ruby
# frozen_string_literal: true

# copy_to_scaffold.rb
# contents/, stylesheets/, config/, codes/, data/, templates/ を
# lib/project_scaffold/ 以下に上書きコピーする。
#
# 使い方: ruby copy_to_scaffold.rb

require 'fileutils'

SCAFFOLD = File.join(__dir__, 'lib/project_scaffold')

DIRS = %w[contents stylesheets images config codes data templates covers].freeze

DIRS.each do |dir|
  src = File.join(__dir__, dir)
  dst = File.join(SCAFFOLD, dir)

  unless Dir.exist?(src)
    puts "SKIP  #{dir}/ (not found)"
    next
  end

  FileUtils.rm_rf(dst)
  FileUtils.cp_r(src, dst, verbose: false)
  puts "COPY  #{dir}/ -> lib/project_scaffold/#{dir}/"
end

# ================================================================
# 残骸画像の保険除去
# ================================================================
# バリアント（*_portrait/*_landscape）と covers 生成物は generated-assets 移設で
# .cache/vs/ に出るようになり、ソースツリーには通常発生しない。ここは移設前の
# 残骸や生成途中の中間ファイル (*_alpha* / *_color* / *_merged*) が万一混入しても
# scaffold に運ばないための保険掃除のみ残す。
prune_globs = %w[
  **/*_alpha*.webp **/*_color*.webp **/*_merged*.webp
  **/*_alpha*.png **/*_color*.png **/*_merged*.png
]
generated = Dir.glob(prune_globs.map { File.join(SCAFFOLD, it) })
generated.each { FileUtils.rm_f(it) }
puts "PRUNE 中間生成物の残骸 #{generated.size} 件を除去"

# ================================================================
# covers/ の開発ローカルファイル除去
# ================================================================
# 移設後の covers/ はソースのみだが、開発リポジトリ固有の作業ファイル
# (Keynote ソース .key / .DS_Store / 検証用 PDF など) は scaffold に運ばない。
covers_dir = File.join(SCAFFOLD, 'covers')
if Dir.exist?(covers_dir)
  keep_exts = %w[.png .jpg .jpeg .svg .md].freeze
  removed = Dir.glob(File.join(covers_dir, '**', '*')).select { File.file?(it) }
                                                      .reject { keep_exts.include?(File.extname(it).downcase) }
  removed.each { FileUtils.rm_f(it) }
  puts "PRUNE covers/ の開発ローカルファイル #{removed.size} 件を除去 (#{keep_exts.join(' / ')} 以外)"
end

FILES = %w[.gitignore package.json].freeze

FILES.each do |file|
  src = File.join(__dir__, file)
  dst = File.join(SCAFFOLD, file)

  unless File.exist?(src)
    puts "SKIP  #{file} (not found)"
    next
  end

  FileUtils.cp(src, dst, verbose: false)
  puts "COPY  #{file} -> lib/project_scaffold/#{file}"
end

# ================================================================
# 著者のプロジェクト用 README
# ================================================================
# ルートの README.md は gem のリポジトリを訪れた人へ向けたもので、ライセンスや
# 開発者向け情報まで載っている。`vs new` した著者の手元に置かれるのは「あなたの
# 本のプロジェクト」なので、別に用意した README を配る。
scaffold_readme = File.join(__dir__, 'docs', 'scaffold-README.md')
if File.exist?(scaffold_readme)
  FileUtils.cp(scaffold_readme, File.join(SCAFFOLD, 'README.md'), verbose: false)
  puts 'COPY  docs/scaffold-README.md -> lib/project_scaffold/README.md'
else
  puts 'SKIP  docs/scaffold-README.md (not found)'
end

# ================================================================
# book.yml のテンプレート化
# ================================================================
# config/book.yml をそのままコピーした後、vs new で置換されるべき値を
# {{PLACEHOLDER}} 記法に差し替える。キーやコメントはすべて維持する。
book_yml = File.join(SCAFFOLD, 'config', 'book.yml')
if File.exist?(book_yml)
  content = File.read(book_yml, encoding: 'utf-8')

  # main_title: '...' or main_title: "..."
  content.gsub!(/^(\s+main_title:\s*)(['"].+?['"])/, '\1"{{MAIN_TITLE}}"')
  # subtitle: '...' or subtitle: "..." （subtitle_style は除外）
  content.gsub!(/^(\s+subtitle:\s*)(['"].+?['"])(\s*$)/, '\1"{{SUBTITLE}}"\3')
  # author: "..." （コメント付き行にも対応）
  content.gsub!(/^(\s+author:\s*)(['"].+?['"])(\s*#.*)?$/, '\1"{{AUTHOR}}"\3')
  # publisher: "..." （コメント付き行にも対応）
  content.gsub!(/^(\s+publisher:\s*)(['"].+?['"])(\s*#.*)?$/, '\1"{{PUBLISHER}}"\3')
  # project.name: "..."（コメント付き行にも対応）
  content.gsub!(/^(\s+name:\s*)(['"].+?['"])(\s*#.*)?$/, '\1"{{PROJECT_NAME}}"\3')

  # この本固有の値は空にして配る。{{ }} にしないのは vs new の質問を増やさないため
  # （いずれも任意項目で、空でもビルドが通る）。埋め忘れより、他人の連絡先が
  # 初期値として入っているほうが害が大きい——著者が気づかず奥付へ載せうる。
  content.gsub!(/^(\s+series:\s*)(['"].*?['"])(\s*#.*)?$/, '\1""\3')
  content.gsub!(/^(\s+release:\s*)(['"].*?['"])(\s*#.*)?$/, '\1""\3')
  content.gsub!(/^(\s+contact:\s*)(['"].*?['"])(\s*#.*)?$/, '\1""\3')

  # 扉絵は季節を選ばない桜を既定にする（ルートは himawari を選んでいる）
  content.gsub!(/^(\s+image:\s*)himawari(\s*#.*)?$/, '\1sakura\2')

  # ルートの値がそのまま配布物の既定になると具合が悪いものを、配布向けの値へ。
  # ここを書き換えたら ConfigKeys::KEYS の default: も合わせること
  # （config_keys_test.rb が scaffold の book.yml と突き合わせる）。
  #   version      … 本書は 1.0.0 だが、新しく始める本は 0.1.0 から
  #   window_bounds … ルートは 5K の外部モニタ向け。一般的な画面に収まる値へ
  #   *_pagebreak  … 本書はページ数を抑えるため節の改ページと改丁をやめているが、
  #                   新しく始める本には組版として整った側を渡す
  content.gsub!(/^(\s+version:\s*)(['"].+?['"])(\s*#.*)?$/, '\1"0.1.0"\3')
  content.gsub!(/^(\s+section_pagebreak:\s*)\S+(\s*#.*)?$/, '\1true\2')
  content.gsub!(/^(\s+chapter_pagebreak:\s*)\S+(\s*#.*)?$/, '\1recto\2')
  # 行末コメントごと差し替える（ルートのコメントは 5K モニタ前提の説明なので、
  # 値だけ替えると配布物で値と説明が食い違う）
  content.gsub!(/^(\s+window_bounds:\s*)(['"].+?['"])(\s*#.*)?$/,
                '\1"{0, 0, 1280, 960}"    # PDF を表示する位置とサイズ')

  File.write(book_yml, content, encoding: 'utf-8')
  puts "TMPL  config/book.yml -> テンプレート記法に置換しました"
end

puts "\nDone."
