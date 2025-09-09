#!/usr/bin/env ruby
# frozen_string_literal: true
require 'hexapdf'

if ARGV.empty?
  warn 'Usage: scripts/check_pdf_outlines.rb <pdf> [<pdf> ...]'
  exit 1
end

ARGV.each do |path|
  unless File.exist?(path)
    puts "MISSING: #{path}"
    next
  end
  begin
    doc = HexaPDF::Document.open(path)
    outlines = doc.catalog[:Outlines]
    if outlines.nil?
      puts "#{path}: NO_OUTLINES"
      next
    end
    # Traverse outline tree and print titles
    count = 0
    stack = [[outlines, 0]]
    while (cur = stack.pop)
      node, depth = cur
      first = node[:First]
      while first
        title = (first[:Title] || '').to_s.encode('UTF-8', invalid: :replace, undef: :replace)
        puts ("  " * depth) + "- #{title}"
        count += 1
        stack << [first, depth + 1] if first[:First]
        first = first[:Next]
      end
    end
    puts "#{path}: TOTAL_OUTLINES=#{count}"
  rescue => e
    puts "#{path}: OPEN_ERROR: #{e}"
  end
end
