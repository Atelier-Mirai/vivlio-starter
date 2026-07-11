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

FILES = %w[README.md .gitignore package.json].freeze

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

  File.write(book_yml, content, encoding: 'utf-8')
  puts "TMPL  config/book.yml -> テンプレート記法に置換しました"
end

puts "\nDone."
