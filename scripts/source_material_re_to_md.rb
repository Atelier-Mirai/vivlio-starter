#!/usr/bin/env ruby
# frozen_string_literal: true

# source_material/contents 以下の .re ファイルを、同名の .md にコピーするだけの
# 簡易コンバータ（中身の記法変換は行わない）。
# 元の .re は削除せず、そのまま残す。
# 既に同名の .md が存在する場合は、上書きせずスキップする。

require "fileutils"

project_root = File.expand_path("..", __dir__)
contents_dir = File.join(project_root, "source_material", "contents")

unless Dir.exist?(contents_dir)
  warn "contents directory not found: #{contents_dir}"
  exit 1
end

Dir.glob(File.join(contents_dir, "*.re")).sort.each do |src|
  dest = src.sub(/\.re\z/, ".md")

  if File.exist?(dest)
    warn "[skip] #{File.basename(dest)} already exists"
    next
  end

  FileUtils.cp(src, dest)
  puts "copied: #{File.basename(src)} -> #{File.basename(dest)}"
end

puts "Done."
