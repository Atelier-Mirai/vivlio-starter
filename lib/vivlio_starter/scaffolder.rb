# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/scaffolder.rb
# ================================================================
# 責務:
#   新規書籍プロジェクトの雛形を生成する。
#   vs new コマンドから呼び出される。
#
# 生成されるディレクトリ:
#   - config/: 設定ファイル（book.yml, catalog.yml 等）
#   - contents/: 章 Markdown ファイル
#   - images/: 画像ファイル
#   - stylesheets/: CSS ファイル
#   - codes/: コードサンプル
#   - chapter_templates/: 章テンプレート
#
# 生成されるファイル:
#   - Gemfile, README.md, .gitignore
#   - vivliostyle.config.js
#   - 初期章ファイル（00-preface.md 〜 99-postface.md）
#
# 依存:
#   - gem_root 内の templates/ ディレクトリ
# ================================================================

require 'fileutils'
require 'yaml'

module VivlioStarter
  # プロジェクト雛形生成モジュール
  module Scaffolder
    DEFAULT_DIRECTORIES = %w[config contents images stylesheets codes chapter_templates].freeze
    DEFAULT_CONTENT_FILES = %w[
      00-preface.md
      11-install.md
      12-tutorial.md
      21-customize.md
      31-advance.md
      91-appendix-a.md
      92-appendix-b.md
      93-appendix-c.md
      99-postface.md
    ].freeze
    DEFAULT_NEEDED_CHAPTER_CSS = %w[11 12 21 31].freeze
    DEFAULT_GITIGNORE = <<~GITIGNORE
      .DS_Store
      node_modules/
      *.log
      *.tmp
      *.pdf
      entries.js
    GITIGNORE
    DEFAULT_BOOK_CONFIG = <<~YML
      # book.yml
      book:
        main_title: ''
        subtitle: ''
        subtitle_style: wave
        author: ''
        language: 'ja'
    YML
    DEFAULT_DISCLAIMER = <<~TXT
      本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
      本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
    TXT
    DEFAULT_TRADEMARK = <<~TXT
      本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
      本書では ™、®、© などのマークは省略しています。
    TXT
    MINIMAL_VIV_CONFIG = <<~JS
      import { VivliostyleConfig } from '@vivliostyle/cli'

      const vivliostyleConfig = {
        title: 'My Book',
        author: '',
        language: 'ja',
        readingProgression: 'ltr',
        entry: [
          'contents/_titlepage.md',
          'contents/_legalpage.md',
          'contents/00-preface.md',
          'contents/11-install.md',
          'contents/12-tutorial.md',
          'contents/21-customize.md',
          'contents/31-advance.md',
          'contents/91-appendix-a.md',
          'contents/92-appendix-b.md',
          'contents/93-appendix-c.md',
          'contents/99-postface.md',
          'contents/_colophon.md'
        ],
        output: [
          './output.pdf'
        ]
      } satisfies VivliostyleConfig

      export default vivliostyleConfig
    JS

    Result = Struct.new(
      :name,
      :dest,
      :config_path,
      :vivliostyle_config_path,
      :copy_list,
      :scaffold_root,
      keyword_init: true
    )

    module_function

    def scaffold_project(
      name:,
      dest:,
      gem_root:,
      scaffold_root: nil,
      directories: DEFAULT_DIRECTORIES,
      copy_list: DEFAULT_CONTENT_FILES,
      needed_chapter_css: DEFAULT_NEEDED_CHAPTER_CSS,
      readme_template: nil,
      readme_renderer: nil,
      readme_content: nil,
      readme_output: 'README.md',
      gitignore_content: DEFAULT_GITIGNORE,
      copy_styles_mode: :subset,
      include_ci_workflow: false,
      include_post_replace: false,
      include_viv_config_update: true,
      include_gemfile: true,
      include_readme: true,
      copy_codes: true,
      copy_chapter_templates: true,
      copy_images: true,
      copy_styles: true,
      copy_contents: true,
      copy_viv_config: true,
      post_replace_source: nil,
      gemfile_source: nil,
      viv_config_template: nil,
      gitignore_path: '.gitignore',
      &block
    )
      scaffold_root ||= File.join(gem_root, 'lib', 'project_scaffold')
      source_contents_dir = File.join(scaffold_root, 'contents')
      source_styles_dir   = File.join(scaffold_root, 'stylesheets')
      source_images_dir   = File.join(scaffold_root, 'images')
      source_codes_dir    = File.join(scaffold_root, 'codes')
      source_chapter_tpl  = File.join(scaffold_root, 'chapter_templates')
      readme_template   ||= File.join(scaffold_root, 'README.md') if include_readme && readme_template.nil?
      if include_post_replace && post_replace_source.nil?
        post_replace_source ||= File.join(gem_root,
                                          '_post_replace_list.yml')
      end
      gemfile_source ||= File.join(scaffold_root, 'Gemfile') if include_gemfile && gemfile_source.nil?
      if copy_viv_config && viv_config_template.nil?
        viv_config_template ||= File.join(scaffold_root,
                                          'vivliostyle.config.js')
      end
      ci_workflow_source = (File.join(scaffold_root, '.github', 'workflows', 'build.yml') if include_ci_workflow)

      FileUtils.mkdir_p(dest)
      Array(directories).each do |dir|
        FileUtils.mkdir_p(File.join(dest, dir))
      end

      config_source = File.join(gem_root, 'config', 'book.yml')
      config_path = File.join(dest, 'config', 'book.yml')
      if File.file?(config_source)
        FileUtils.cp(config_source, config_path)
      else
        File.write(config_path, DEFAULT_BOOK_CONFIG, encoding: 'utf-8')
      end

      block&.call(:after_config, { config_path: config_path, dest: dest, copy_list: copy_list })

      if include_post_replace && post_replace_source && File.file?(post_replace_source)
        FileUtils.cp(post_replace_source, File.join(dest, '_post_replace_list.yml'))
      end

      if copy_contents
        dest_contents = File.join(dest, 'contents')
        copy_list.each do |fname|
          src = File.join(source_contents_dir, fname)
          dst = File.join(dest_contents, fname)
          if File.file?(src)
            FileUtils.cp(src, dst)
          else
            fallback = "# #{File.basename(fname, '.md')}\n\nコンテンツをここに記述してください。\n"
            File.write(dst, fallback, encoding: 'utf-8')
          end
        end
      end

      if include_readme
        readme_path = File.join(dest, readme_output)
        readme_text = nil
        if readme_template && File.file?(readme_template)
          readme_text = File.read(readme_template, encoding: 'utf-8')
          readme_text = readme_text.gsub(/\{\{\s*PROJECT_NAME\s*\}\}/, name)
        elsif readme_renderer
          readme_text = readme_renderer.call(name)
        elsif readme_content
          readme_text = readme_content
        end
        File.write(readme_path, readme_text, encoding: 'utf-8') if readme_text
      end

      gitignore_full_path = File.join(dest, gitignore_path)
      File.write(gitignore_full_path, gitignore_content, encoding: 'utf-8') if gitignore_content

      if copy_chapter_templates && Dir.exist?(source_chapter_tpl)
        target = File.join(dest, 'chapter_templates')
        FileUtils.mkdir_p(target)
        Dir.children(source_chapter_tpl).each do |entry|
          FileUtils.cp_r(File.join(source_chapter_tpl, entry), File.join(target, entry))
        end
      end

      if copy_codes && Dir.exist?(source_codes_dir)
        target = File.join(dest, 'codes')
        FileUtils.mkdir_p(target)
        Dir.children(source_codes_dir).each do |entry|
          FileUtils.cp_r(File.join(source_codes_dir, entry), File.join(target, entry))
        end
      end

      if include_gemfile && gemfile_source && File.file?(gemfile_source)
        begin
          FileUtils.cp(gemfile_source, File.join(dest, 'Gemfile'))
        rescue StandardError => e
          warn "[vivlio-starter] Gemfile のコピーに失敗しました（継続）: #{e}"
        end
      end

      if include_ci_workflow && ci_workflow_source && File.file?(ci_workflow_source)
        target_ci_dir = File.join(dest, '.github', 'workflows')
        FileUtils.mkdir_p(target_ci_dir)
        FileUtils.cp(ci_workflow_source, File.join(target_ci_dir, 'build.yml'))
      end

      if copy_styles && Dir.exist?(source_styles_dir)
        target_styles_dir = File.join(dest, 'stylesheets')
        FileUtils.mkdir_p(target_styles_dir)
        case copy_styles_mode
        when :all
          FileUtils.cp_r(Dir[File.join(source_styles_dir, '*')], target_styles_dir)
        when :subset
          Dir[File.join(source_styles_dir, '*/')].each do |src_dir|
            FileUtils.cp_r(src_dir, target_styles_dir)
          end
          Dir[File.join(source_styles_dir, '*')]
            .select { |path| File.file?(path) }
            .reject { |path| File.basename(path) =~ /^\d+\.css$/ }
            .each do |css|
              FileUtils.cp(css, File.join(target_styles_dir, File.basename(css)))
            end
          Array(needed_chapter_css).each do |num|
            src = File.join(source_styles_dir, "#{num}.css")
            FileUtils.cp(src, File.join(target_styles_dir, "#{num}.css")) if File.file?(src)
          end
        when nil, false
          # no-op
        else
          raise ArgumentError, "Unknown copy_styles_mode: #{copy_styles_mode.inspect}"
        end
      end

      if copy_images
        target_images_dir = File.join(dest, 'images')
        FileUtils.mkdir_p(target_images_dir)
        if Dir.exist?(source_images_dir)
          FileUtils.cp_r(Dir[File.join(source_images_dir, '*')], target_images_dir)
        else
          copy_list.each do |fname|
            slug = File.basename(fname, '.md')
            FileUtils.mkdir_p(File.join(target_images_dir, slug))
          end
        end
      end

      viv_config_path = File.join(dest, 'vivliostyle.config.js')
      if copy_viv_config
        if viv_config_template && File.file?(viv_config_template)
          FileUtils.cp(viv_config_template, viv_config_path)
        else
          File.write(viv_config_path, MINIMAL_VIV_CONFIG, encoding: 'utf-8')
        end
      end

      cfg = begin
        YAML.load_file(config_path)
      rescue StandardError
        {}
      end
      cfg = {} unless cfg.is_a?(Hash)
      book_cfg = cfg['book'] || {}

      generate_frontmatter(dest: dest, book: book_cfg, config: cfg)

      if include_viv_config_update && copy_viv_config && File.exist?(viv_config_path)
        update_vivliostyle_config(
          viv_config_path: viv_config_path,
          book: book_cfg,
          config: cfg
        )
      end

      Result.new(
        name: name,
        dest: dest,
        config_path: config_path,
        vivliostyle_config_path: viv_config_path,
        copy_list: copy_list,
        scaffold_root: scaffold_root
      )
    end

    def generate_frontmatter(dest:, book:, config: {})
      contents_dir = File.join(dest, 'contents')

      full_title = (book['title'] || '').to_s
      main_title = (book['main_title'] || '').to_s
      subtitle   = (book['subtitle'] || '').to_s

      title = main_title.empty? ? full_title : main_title
      if subtitle.empty? && !full_title.empty? && (full_title =~ /(.*?)[ \u3000]*[～〜](.+?)[～〜]\s*$/)
        title = ::Regexp.last_match(1).to_s.strip
        subtitle = ::Regexp.last_match(2).to_s.strip
      end
      title = title.to_s.gsub(/[ \u3000]*[～〜].*$/, '').strip

      author  = (book['author'] || '').to_s
      series  = (book['series'] || '').to_s
      release = (book['release'] || '').to_s
      style   = (book['subtitle_style'] || 'wave').to_s.downcase
      style   = 'wave' unless %w[wave bar none].include?(style)
      subtitle_class = "subtitle subtitle--#{style}"

      title_md = <<~MD
        <h1 class="book-title">#{title}</h1>
        #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

        #{%(<p class="author"><span>[著]</span> #{author}</p>) unless author.empty?}

        #{%(<div class="publication-info">) unless series.empty? && release.empty?}
        #{%(    <p class="series">#{series}</p>) unless series.empty?}
        #{%(    <p class="release-info">#{release}</p>) unless release.empty?}
        #{%(</div>) unless series.empty? && release.empty?}
      MD
      File.write(File.join(contents_dir, '00-titlepage.md'), title_md, encoding: 'utf-8')

      legal_cfg = config['legal'] || {}
      disclaimer = (legal_cfg['disclaimer'] || '').to_s.strip
      trademark  = (legal_cfg['trademark']  || '').to_s.strip
      disclaimer = DEFAULT_DISCLAIMER if disclaimer.empty?
      trademark  = DEFAULT_TRADEMARK  if trademark.empty?

      legal_md = <<~MD
        <div class="disclaimer">
          <h2>■免責</h2>
          #{disclaimer.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
        </div>

        <div class="trademark">
          <h2>■商標</h2>
          #{trademark.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
        </div>
      MD
      File.write(File.join(contents_dir, '01-legalpage.md'), legal_md, encoding: 'utf-8')

      publisher = (book['publisher'] || book['publisher_name'] || '').to_s
      contact   = (book['contact'] || '').to_s
      current_year = Time.now.year
      start_year = extract_start_year(release)
      current_wareki = to_wareki_year(current_year)
      copyright_years = if start_year && start_year != current_year && start_year >= 2019
                          start_wareki = to_wareki_year(start_year)
                          "#{start_wareki} #{current_wareki}"
                        else
                          current_wareki
                        end

      colophon_md = <<~MD
        <h1 class="book-title">#{title}</h1>
        #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

        #{%(<p class="publication-info">#{release}</p>) unless release.empty?}

        <dl class="info-list">
            #{%(<dt>著者</dt>\n        <dd>#{author}</dd>) unless author.empty?}
            #{%(<dt>発行者</dt>\n        <dd>#{publisher}</dd>) unless publisher.empty?}
            #{%(<dt>連絡先</dt>\n        <dd>#{contact}</dd>) unless contact.empty?}
        </dl>

        <p class="copyright">
            <small>
                &copy; #{copyright_years} #{author.empty? ? '著者' : author} All rights reserved.
            </small>
        </p>

        <p class="powered-by">
            <small>
                (powered by Vivlio Starter)
            </small>
        </p>
      MD
      File.write(File.join(contents_dir, '99-colophon.md'), colophon_md, encoding: 'utf-8')
    end

    def update_vivliostyle_config(viv_config_path:, book:, config: {})
      js = File.read(viv_config_path, encoding: 'utf-8')
      title = (book['main_title'] || book['title'] || '').to_s
      title = 'My Book' if title.strip.empty?
      author = (book['author'] || '').to_s
      language = (book['language'] || 'ja').to_s
      reading_progression = (config.dig('vivliostyle', 'reading_progression') || 'ltr').to_s
      output_file = (config.dig('pdf', 'output_file') || 'output.pdf').to_s

      js.gsub!(/(^\s*title:\s*)['"][^'"]*['"]/, "\\1'#{title}'")
      js.gsub!(/(^\s*author:\s*)['"][^'"]*['"]/, "\\1'#{author}'")
      js.gsub!(/(^\s*language:\s*)['"][^'"]*['"]/, "\\1'#{language}'")
      js.gsub!(/(^\s*readingProgression:\s*)['"][^'"]*['"]/, "\\1'#{reading_progression}'")
      js.gsub!(%r{(^\s*['"]\./output\.pdf['"])|(^\s*['"][^'"]*\.pdf['"])}, "'./#{output_file}'")
      js.gsub!(/(^\s*output:\s*\[\s*)['"][^'"]*\.pdf['"](\s*\])/m, "\\1'./#{output_file}'\\2")

      File.write(viv_config_path, js, encoding: 'utf-8')
    end

    def extract_start_year(release)
      return unless release

      if release =~ /令和([一二三四五六七八九十百]+)年/
        kan = Regexp.last_match(1)
        2018 + kan_to_i(kan)
      elsif release =~ /(\d{4})/
        Regexp.last_match(1).to_i
      end
    end

    def kan_to_i(value)
      map = { '零' => 0, '一' => 1, '二' => 2, '三' => 3, '四' => 4, '五' => 5, '六' => 6, '七' => 7, '八' => 8, '九' => 9 }
      s = value.dup
      total = 0
      if s.include?('百')
        s = s.sub('百', '')
        total += 100
      end
      if s.include?('十')
        parts = s.split('十', 2)
        tens = parts[0].empty? ? 1 : map[parts[0]]
        ones = parts[1].to_s.empty? ? 0 : map[parts[1]]
        total += (tens.to_i * 10) + ones.to_i
      elsif !s.empty?
        total += map[s].to_i
      end
      total
    end

    def to_wareki_year(year)
      km = %w[零 一 二 三 四 五 六 七 八 九]
      diff = year - 2018
      return "令和#{km[0]}年" if diff <= 0
      return "令和#{km[diff]}年" if diff < 10
      return '令和十年' if diff == 10

      tens = diff / 10
      ones = diff % 10
      s = ''
      s += km[tens] unless tens == 1
      s += '十'
      s += km[ones] unless ones.zero?
      "令和#{s}年"
    end
  end
end
