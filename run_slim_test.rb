#!/usr/bin/env ruby
# frozen_string_literal: true

require 'slim'
require_relative 'template_compiler'

Book = Data.define(:title, :author, :desc, :cover, :tags)

books = [
  Book.new(
    title: '楽しいRuby',
    author: '高橋征義',
    desc: 'Rubyを楽しく学べる入門書。',
    cover: 'ruby-enjoyer.webp',
    tags: %w[ruby beginner]
  ),
  Book.new(
    title: 'はじめてのC',
    author: '柴田望洋',
    desc: 'C言語の定番入門書。',
    cover: nil,
    tags: %w[c beginner]
  )
]

# テンプレート読み込み
template_path = File.join(__dir__, 'templates/_books.full.md.slim')
source = File.read(template_path)

# プチcompilerで変換
compiled = Vivlio::Starter::TemplateCompiler.compile(source)

puts "=" * 50
puts "【コンパイル後のSlim】"
puts "=" * 50
puts compiled
puts

# Slimでレンダリング
scope = Object.new
scope.define_singleton_method(:books) { books }
result = Slim::Template.new { compiled }.render(scope)

puts "=" * 50
puts "【レンダリング結果】"
puts "=" * 50
puts result
