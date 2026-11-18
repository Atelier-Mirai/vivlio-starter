# frozen_string_literal: true

# ================================================================
# scripts/v1_samples.rb — 移行の見本（1.x の本 4 冊）を作る
# ================================================================
# 使い方:
#   ruby scripts/v1_samples.rb --out DIR [--v1 VERSION]
#
#   --out DIR     見本を作る場所（既にあれば消してから作る）
#   --v1 VERSION  vs new に使う 1.x の gem の版（既定: 1.0.0）
#
# v2-migration-plan.md §5.5 の 4 冊を、1.x の gem の vs new から作る。
#   plain         … 雛形のまま
#   custom        … custom.css で、今の名前の変数に値を入れ（--color-link）、今の名前の変数を読み
#                   （var(--theme-accent)）、内部のクラス（.section-lead）を選んでいる
#   components    … 雛形の components.css を 1 か所直した（本の紹介の書名の色）
#   frontispiece  … stylesheets/images/ に自分の扉絵を足し、theme.frontispiece.image で指定した
#
# どの本も Git で管理し、最初の状態をコミットする（vs upgrade の作業ツリーの確かめが通るように）。
# 作った本は scripts/v1_rehearsal.rb の --book に渡す。1.x の本は 1.x の vs new で作る必要があり、
# 雛形の CSS・書体・画像（1 冊で約 115 MB）を抱えるので、テストの素材（test/vivlio_starter/fixtures/）には置かない。
# ================================================================

require 'fileutils'
require 'open3'
require 'optparse'

options = { v1: '1.0.0' }
OptionParser.new do |o|
  o.banner = 'usage: ruby scripts/v1_samples.rb --out DIR [--v1 VERSION]'
  o.on('--out DIR') { options[:out] = File.expand_path(it) }
  o.on('--v1 VERSION') { options[:v1] = it }
end.parse!(ARGV)
abort 'usage: ruby scripts/v1_samples.rb --out DIR [--v1 VERSION]' unless options[:out]

CUSTOM_CSS = <<~CSS

  /* 移行の見本: 今の名前の変数に値を入れ、今の名前の変数を読み、内部のクラスを選ぶ */
  :root {
    --color-link: #c0392b;
  }

  .section-lead {
    color: var(--theme-accent);
  }
CSS

out = options[:out]
FileUtils.rm_rf(out)
FileUtils.mkdir_p(out)

def sh!(*command, chdir:, stdin: nil)
  output, status = Open3.capture2e(*command, chdir:, stdin_data: stdin.to_s)
  abort "失敗しました: #{command.join(' ')}\n#{output}" unless status.success?
  output
end

%w[plain custom components frontispiece].each do |name|
  # --- Phase: 1.x の vs new（確認には既定で答える） ---
  sh!('vs', "_#{options[:v1]}_", 'new', name, chdir: out, stdin: "\n" * 10)
  book = File.join(out, name)

  # --- Phase: 見本ごとの手入れ ---
  case name
  when 'custom'
    File.write(File.join(book, 'stylesheets', 'custom.css'), CUSTOM_CSS, mode: 'a')
  when 'components'
    path = File.join(book, 'stylesheets', 'components.css')
    css = File.read(path)
    edited = css.sub(/^\.book-title \{\n/) { "#{it}  color: #c0392b;\n" }
    abort 'components.css に .book-title の規則が見つかりません' if edited == css
    File.write(path, edited)
  when 'frontispiece'
    FileUtils.cp(File.join(book, 'stylesheets', 'images', 'bundled', 'ume.webp'),
                 File.join(book, 'stylesheets', 'images', 'my-door.webp'))
    yml = File.join(book, 'config', 'book.yml')
    text = File.read(yml)
    edited = text.sub(/^(    image: )\S+/) { "#{Regexp.last_match(1)}my-door" }
    abort 'book.yml に theme.frontispiece.image が見つかりません' if edited == text
    File.write(yml, edited)
  end

  # --- Phase: 最初の状態をコミットする ---
  sh!('git', 'init', '-q', chdir: book)
  sh!('git', 'add', '-A', chdir: book)
  sh!('git', '-c', 'user.name=v1-samples', '-c', 'user.email=v1-samples@example.invalid',
      'commit', '-qm', "移行の見本: #{name}（vs #{options[:v1]} の vs new）", chdir: book)
  puts "[v1_samples] #{book}"
end
