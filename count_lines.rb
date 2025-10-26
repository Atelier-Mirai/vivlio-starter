#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'

root = Pathname.new(__dir__)
rb_files = root.glob('lib/vivlio/**/*.rb').sort
css_files = root.glob('stylesheets/**/*.css').sort

ruby_results = []
rb_files.each do |path|
  total = code = comment = 0
  in_block = false
  in_heredoc = false
  heredoc_end = nil

  path.each_line do |line|
    total += 1
    stripped = line.strip
    lstrip = line.lstrip

    if in_heredoc
      if heredoc_end && stripped.start_with?(heredoc_end)
        in_heredoc = false
        heredoc_end = nil
      end
      next
    end

    if in_block
      comment += 1
      in_block = false if stripped.start_with?('=end')
      next
    end

    next if stripped.empty?

    if stripped.start_with?('=begin')
      comment += 1
      in_block = true
      next
    end

    if lstrip.start_with?('#')
      comment += 1
      next
    end

    code += 1

    if line =~ /<<[-~]?['"]?([A-Za-z0-9_]+)['"]?/
      heredoc_end = Regexp.last_match(1)
      in_heredoc = true
    end
  end

  ruby_results << [path.relative_path_from(root).to_s, total, code, comment]
end

css_results = []
css_files.each do |path|
  total = code = comment = 0
  in_block = false

  path.each_line do |line|
    total += 1
    stripped = line.strip

    if in_block
      comment += 1
      in_block = false if stripped.include?('*/')
      next
    end

    next if stripped.empty?

    if stripped.start_with?('/*')
      comment += 1
      in_block = !stripped.include?('*/') || stripped.index('/*') > stripped.index('*/')
      next
    end

    if stripped.start_with?('//')
      comment += 1
      next
    end

    code += 1
    in_block = true if stripped.include?('/*') && !stripped.include?('*/')
  end

  css_results << [path.relative_path_from(root).to_s, total, code, comment]
end

format_line = lambda do |label, total_lines, code_lines, comment_lines|
  format('%-60s %6d %6d %6d', label, total_lines, code_lines, comment_lines)
end

puts 'Ruby files (lib/vivlio/**/*.rb)'
puts 'path                                                          total   code comment'
ruby_results.each { |row| puts format_line.call(*row) }

puts
puts 'CSS files (stylesheets/**/*.css)'
puts 'path                                                          total   code comment'
css_results.each { |row| puts format_line.call(*row) }

ruby_totals = ruby_results.transpose[1..3].map { |arr| arr.reduce(0, :+) }
css_totals = css_results.transpose[1..3].map { |arr| arr.reduce(0, :+) }

puts
puts 'Totals'
puts format('%-60s %6d %6d %6d', 'Ruby total', *ruby_totals)
puts format('%-60s %6d %6d %6d', 'CSS total', *css_totals)
