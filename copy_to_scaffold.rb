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

puts "\nDone."
