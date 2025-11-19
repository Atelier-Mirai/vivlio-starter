#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"

PROJECT_ROOT = File.expand_path("..", __dir__)
SOURCE_ROOT  = File.expand_path("..", PROJECT_ROOT)

SOURCE_BOOKS = %w[
  book_janken
  book_sakura_fubuki
  book_study_js
  book_yutakana_website_old
].freeze

TARGET_BASE_DIR     = File.join(PROJECT_ROOT, "source_material")
TARGET_CONTENTS_DIR = File.join(TARGET_BASE_DIR, "contents")
TARGET_IMAGES_DIR   = File.join(TARGET_BASE_DIR, "images")
TARGET_CODES_DIR    = File.join(TARGET_BASE_DIR, "codes")

FileUtils.mkdir_p(TARGET_CONTENTS_DIR)
FileUtils.mkdir_p(TARGET_IMAGES_DIR)
FileUtils.mkdir_p(TARGET_CODES_DIR)

PrefixKey = Struct.new(:book, :old_prefix)

def extract_prefix(name)
  match = name.match(/\A(\d{2})/)
  return nil unless match

  match[1].to_i
end

# Generate a destination path with -2, -3, ... suffix if needed
# to avoid overwriting existing files.
def next_suffix_path(dir, basename)
  ext  = File.extname(basename)
  base = File.basename(basename, ext)
  index = 2

  loop do
    candidate = File.join(dir, "#{base}-#{index}#{ext}")
    return candidate unless File.exist?(candidate)

    index += 1
  end
end

body_keys = []
appendix_keys = []

SOURCE_BOOKS.each do |book|
  contents_dir = File.join(SOURCE_ROOT, book, "contents")
  unless Dir.exist?(contents_dir)
    warn "contents directory not found: #{contents_dir}"
    next
  end

  Dir.glob(File.join(contents_dir, "*.re")).sort.each do |path|
    basename = File.basename(path)
    num = extract_prefix(basename)

    unless num
      warn "skip (no numeric prefix): #{path}"
      next
    end

    case num
    when 0, 99
      # skip preface / postface
      next
    when 1..89
      key = PrefixKey.new(book, num)
      body_keys << key unless body_keys.include?(key)
    when 90..98
      key = PrefixKey.new(book, num)
      appendix_keys << key unless appendix_keys.include?(key)
    else
      warn "skip (unsupported prefix #{num}): #{path}"
    end
  end
end

body_keys.sort_by! { |k| [SOURCE_BOOKS.index(k.book), k.old_prefix] }
appendix_keys.sort_by! { |k| [SOURCE_BOOKS.index(k.book), k.old_prefix] }

mapping = {}

body_keys.each_with_index do |key, idx|
  new_num = 11 + idx
  if new_num > 89
    warn "body chapter overflow: new number #{new_num} > 89 for #{key.book} #{key.old_prefix}"
    next
  end
  mapping[[key.book, key.old_prefix]] = new_num
end

appendix_keys.each_with_index do |key, idx|
  new_num = 91 + idx
  mapping[[key.book, key.old_prefix]] = new_num
end

puts "Body chapters:     #{body_keys.size}"
puts "Appendix chapters: #{appendix_keys.size}"
puts "Total mappings:    #{mapping.size}"

# Copy contents
SOURCE_BOOKS.each do |book|
  contents_dir = File.join(SOURCE_ROOT, book, "contents")
  next unless Dir.exist?(contents_dir)

  Dir.glob(File.join(contents_dir, "*.re")).sort.each do |src_path|
    basename = File.basename(src_path)
    num = extract_prefix(basename)
    next unless num

    case num
    when 0, 99
      next
    when 1..89, 90..98
      new_num = mapping[[book, num]]
      unless new_num
        warn "no mapping for contents #{src_path} (prefix #{num})"
        next
      end

      if basename =~ /\A\d{2}([-_].*)\z/
        rest = Regexp.last_match(1)
        dest_basename = format("%02d%s", new_num, rest)
      else
        dest_basename = format("%02d-%s", new_num, basename.sub(/\A\d{2}/, ""))
      end

      dest_path = File.join(TARGET_CONTENTS_DIR, dest_basename)
      if File.exist?(dest_path)
        warn "destination already exists, skipping: #{dest_path}"
        next
      end

      FileUtils.cp(src_path, dest_path)
    else
      next
    end
  end
end

# Copy images
SOURCE_BOOKS.each do |book|
  images_dir = File.join(SOURCE_ROOT, book, "images")
  next unless Dir.exist?(images_dir)

  Dir.children(images_dir).sort.each do |name|
    src_path = File.join(images_dir, name)

    num = extract_prefix(name)

    if num
      case num
      when 0, 99
        next
      when 1..89, 90..98
        new_num = mapping[[book, num]]
        unless new_num
          warn "no mapping for image #{src_path} (prefix #{num})"
          next
        end

        if name =~ /\A\d{2}([-_].*)\z/
          rest = Regexp.last_match(1)
          dest_name = format("%02d%s", new_num, rest)
        else
          dest_name = format("%02d-%s", new_num, name.sub(/\A\d{2}/, ""))
        end

        dest_path = File.join(TARGET_IMAGES_DIR, dest_name)
      else
        warn "skip image (unsupported prefix #{num}): #{src_path}"
        next
      end
    else
      # no numeric prefix: copy as-is, resolving conflicts by adding -2, -3...
      dest_path = File.join(TARGET_IMAGES_DIR, name)
      dest_path = next_suffix_path(TARGET_IMAGES_DIR, name) if File.exist?(dest_path)
    end

    if File.directory?(src_path)
      FileUtils.cp_r(src_path, dest_path)
    else
      FileUtils.cp(src_path, dest_path)
    end
  end
end

# Copy codes (flatten)
SOURCE_BOOKS.each do |book|
  source_dir = File.join(SOURCE_ROOT, book, "source")
  next unless Dir.exist?(source_dir)

  Dir.glob(File.join(source_dir, "**", "*")).each do |src_path|
    next unless File.file?(src_path)

    basename = File.basename(src_path)
    dest_path = File.join(TARGET_CODES_DIR, basename)
    dest_path = next_suffix_path(TARGET_CODES_DIR, basename) if File.exist?(dest_path)

    FileUtils.cp(src_path, dest_path)
  end
end

puts "Done."
