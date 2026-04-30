#!/usr/bin/env ruby
# frozen_string_literal: true

# sync_scaffold.rb
# contents/, stylesheets/, config/, codes/, data/, templates/ を
# lib/project_scaffold/ 以下に上書きコピーする。
#
# 使い方: ruby sync_scaffold.rb

require 'fileutils'

SCAFFOLD = File.join(__dir__, 'lib/project_scaffold')

DIRS = %w[contents stylesheets images config codes data templates].freeze

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

FILES = %w[README.md .gitignore].freeze

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
