#!/usr/bin/env ruby
# frozen_string_literal: true

# scripts/config.yml + scripts/catalog.yml と scripts/ruby 配下の
# Re:VIEW 作者ツール群を使って、source_material/contents 以下の .re を
# Markdown に変換するラッパースクリプト。

require "rubygems"
require "cgi"

ROOT_DIR    = File.expand_path("..", __dir__)
SOURCE_ROOT = File.join(ROOT_DIR, "source_material")
SCRIPTS_DIR = File.join(ROOT_DIR, "scripts")

Dir.chdir(SOURCE_ROOT) do
  rubygems_dir = File.join(SOURCE_ROOT, "rubygems")
  if ENV["GEM_HOME"].to_s.empty? && Dir.exist?(rubygems_dir)
    Gem.paths = { "GEM_HOME" => rubygems_dir }
  end

  # Re:View 拡張版ライブラリ群をロード（scripts/ruby 配下）
  ruby_lib_dir = File.join(SCRIPTS_DIR, "ruby")
  $LOAD_PATH.unshift(ruby_lib_dir) unless $LOAD_PATH.include?(ruby_lib_dir)

  begin
    require "review-markdownmaker" unless defined?(ReVIEW::MarkdownMaker)
    # Re:VIEW 本体のコンバータ定義と Starter 用モンキーパッチをロード
    require "review/converter" unless defined?(ReVIEW::Converter)
    require "review-monkeypatch" unless ReVIEW::Book::Base.method_defined?(:each_input_file)
  rescue LoadError => e
    warn "[error] cannot require Re:VIEW components: #{e.message}"
    exit 1
  end

  config = File.join(Dir.pwd, "config.yml")
  unless File.exist?(config)
    warn "[error] config.yml not found: #{config}"
    exit 1
  end

  contents_dir = File.join(Dir.pwd, "contents")
  Dir.glob(File.join(contents_dir, "*.re")).sort.each do |re_path|
    content = File.read(re_path)
    replaced = content.gsub(/@<B>\{([^}]*)\}/, '**\\1**')
    replaced = replaced.gsub(/^\s*\/\/clearpage\s*$/, '---')
    next if replaced == content
    File.write(re_path, replaced)
  end

  puts "== Converting source_material/contents with Re:VIEW MarkdownMaker =="
  ReVIEW::MarkdownMaker.execute(config)

  # Markdown 出力に含まれる絶対画像パスを、プロジェクト内で移動しても壊れない
  # 画像ディレクトリ起点の相対パス (images/...) に揃える
  md_dir = File.join(Dir.pwd, "source_material-md")
  if Dir.exist?(md_dir)
    puts "== Normalizing absolute image paths in source_material-md/*.md =="

    strip_html_tags_preserving_code_spans = lambda do |html|
      out = +""
      in_code = false
      i = 0
      while i < html.length
        ch = html[i]
        if ch == "`"
          in_code = !in_code
          out << ch
          i += 1
        elsif !in_code && ch == "<"
          i += 1
          i += 1 while i < html.length && html[i] != ">"
          i += 1 if i < html.length
        else
          out << ch
          i += 1
        end
      end
      out
    end

    Dir.glob(File.join(md_dir, "*.md")).sort.each do |md_path|
      markdown = File.read(md_path)
      fixed = markdown.dup

      # 例: /Users/mirai/projects/vivlio-starter/source_material/images/12-history/Nintoku.png
      #  -> Nintoku.png のように、フルパスと章ディレクトリを取り除き、ファイル名だけにする
      fixed.gsub!(%r{/Users/mirai/projects/vivlio-starter/source_material/images/[^/]+/}, "")

      # <img src="Turing.png"> のようなHTML画像タグを Markdown 画像記法に変換する
      # 例: <img src="Turing.png" width="50%"> -> ![](Turing.png)
      fixed.gsub!(%r{<img\s+[^>]*src=["']([^"']+)["'][^>]*\/?>}i, '![](\1)')

      # Re:VIEW MarkdownBuilder の on_flushright_block が出力する [flushright] ... [/flushright]
      # を Vivlio Starter 向けの .text-right コンテナに変換する
      # 例:
      #   [flushright]
      #   **著者: Matz**
      #   [/flushright]
      #   ->
      #   ::: {.text-right}
      #   **著者: Matz**
      #   :::
      fixed.gsub!(%r{\[flushright\]\s*\n(.*?)\n\[/flushright\]}m) do
        inner = Regexp.last_match(1)
        inner = inner.lines.map { |l| l.rstrip }.join("\n")
        "::: {.text-right}\n#{inner}\n:::"
      end

      # Re:VIEW 由来の <div class="table"> ... </div> を Markdown の表に変換する
      # - <p class="caption">あり/なしの両方に対応する
      fixed.gsub!(%r{<div class="table[^"]*">\s*(?:<p class="caption">(.*?)</p>\s*)?<table>(.*?)</table>\s*</div>}m) do
        caption = Regexp.last_match(1).to_s.strip
        table_html = Regexp.last_match(2).to_s

        rows = table_html.scan(/<tr[^>]*>(.*?)<\/tr>/m).map(&:first)
        table_rows = rows.map do |row_html|
          cells = row_html.scan(/<(?:th|td)[^>]*>(.*?)<\/(?:th|td)>/m).map(&:first)
          cells.map do |cell|
            text = strip_html_tags_preserving_code_spans.call(cell)
            text.strip
          end
        end

        col_count = table_rows.map(&:length).max || 0
        if col_count.zero?
          Regexp.last_match(0)
        else
          header = (table_rows.first || []).dup
          header += [""] * (col_count - header.length)
          body = table_rows[1..] || []
          body = body.map { |cols| cols + [""] * (col_count - cols.length) }

          lines = []
          lines << ""
          unless caption.empty?
            lines << "**#{caption}**"
            lines << ""
          end
          lines << "| #{header.join(' | ')} |"
          lines << "| #{Array.new(col_count, '---').join(' | ')} |"
          body.each do |cols|
            lines << "| #{cols.join(' | ')} |"
          end
          lines.join("\n")
        end
      end

      # [abstract] ... [/abstract] -> .chapter-lead コンテナ
      fixed.gsub!(/^\[abstract\][ \t]*\n(.*?)^\[\/abstract\][ \t]*$/m) do
        inner = Regexp.last_match(1)
        inner = inner.gsub(/\A\n+|\n+\z/, "")
        ":::{.chapter-lead}\n#{inner}\n:::\n"
      end

      # 行単独の <br> を .aki クラスのマーカーに変換
      fixed.gsub!(/^\s*<br>\s*$/, "{.aki}")

      # [column] 見出し -> Markdown 見出しに変換
      fixed.gsub!(/^\[column\][ \t]+(.+?)\s*$/) do
        "### #{Regexp.last_match(1)}"
      end

      # [/column] は削除
      fixed.gsub!(/^\[\/column\]\s*$/, "")

      # [quote] ... [/quote] -> Markdown の引用ブロック
      fixed.gsub!(/^\[quote\][^\n]*\n(.*?)^\[\/quote\]\s*$/m) do
        body = Regexp.last_match(1)
        quoted = body.lines.map { |l| l.chomp.empty? ? ">" : "> #{l.rstrip}" }.join("\n")
        "#{quoted}\n"
      end

      # [tip] ... [/tip] -> .tip コンテナ
      fixed.gsub!(/^\[tip\][^\n]*\n(.*?)^\[\/tip\]\s*$/m) do
        inner = Regexp.last_match(1)
        inner = inner.gsub(/\A\n+|\n+\z/, "")
        ":::{.tip}\n#{inner}\n:::\n"
      end

      # <span class="caption">...</span> -> 太字キャプション
      fixed.gsub!(%r{<span\s+class="caption">(.*?)</span>}) do
        "**#{Regexp.last_match(1).strip}**"
      end

      # <dl><dt>...</dt><dd>...</dd>...</dl> -> 箇条書きリスト
      fixed.gsub!(%r{<dl>\s*(.*?)\s*</dl>}m) do
        inner = Regexp.last_match(1)
        pairs = inner.scan(%r{<dt>(.*?)</dt>\s*<dd>\s*(.*?)\s*</dd>}m)
        if pairs.empty?
          Regexp.last_match(0)
        else
          items = pairs.map do |dt, dd|
            term = dt.strip
            desc = dd.lines.map(&:strip).join(" ")
            "- #{term}  \n  #{desc}"
          end
          items.join("\n\n")
        end
      end

      # ```math ... ``` -> $$ ... $$ （VFMの数式記法に変換）
      fixed.gsub!(/^```math\s*\n(.*?)^```$/m) do
        body = Regexp.last_match(1)
        "$$\n#{body.rstrip}\n$$\n"
      end

      # Markdown 内に残った HTML 文字実体参照 (&amp; や &lt; など) を実文字に戻す
      fixed = CGI.unescapeHTML(fixed)
      next if fixed == markdown
      File.write(md_path, fixed)
    end
  end
end

