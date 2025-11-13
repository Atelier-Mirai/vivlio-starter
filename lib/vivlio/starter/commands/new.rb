# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require_relative '../scaffolder'

module Vivlio
  module Starter
    module Commands
      module New
        module_function

        def run(name)
          name = (name || '').strip
          abort 'Error: プロジェクト名を指定してください。例: vs new mybook' if name.empty?

          dest = File.expand_path(name)
          abort "Error: '#{name}' は既に存在します。別名を指定してください。" if File.exist?(dest)

          gem_root = File.expand_path('../../../..', __dir__)

          puts "[vivlio-starter] Creating new project: #{name}"

          result = Vivlio::Starter::Scaffolder.scaffold_project(
            name: name,
            dest: dest,
            gem_root: gem_root,
            include_post_replace: true,
            include_readme: true,
            readme_content: default_readme_content(name),
            include_viv_config_update: true
          ) do |event, ctx|
            update_book_config_interactively(ctx[:config_path]) if event == :after_config
          end

          run_vs_config(result.dest)
          synchronize_viv_config(result.vivliostyle_config_path, result.config_path)

          puts "[vivlio-starter] 完了しました。cd #{name} で移動し、執筆を開始できます。"
          puts '例: vivlio-starter build で執筆した書籍をPDFで作成できます。'
          0
        end

        def update_book_config_interactively(config_path)
          return unless $stdin.tty?

          cfg = YAML.load_file(config_path)
          cfg = {} unless cfg.is_a?(Hash)
          book_cfg = cfg['book'] || {}

          puts "\n[vivlio-starter] 書籍情報を入力してください（未入力は現状の値を維持）"
          current_title = book_cfg['main_title'].to_s
          current_sub   = book_cfg['subtitle'].to_s
          current_auth  = book_cfg['author'].to_s

          new_title = prompt_with_default('書籍名（main_title）', current_title)
          new_sub   = prompt_with_default('副題（subtitle）', current_sub)
          new_auth  = prompt_with_default('著者名（author）', current_auth)

          text = File.read(config_path, encoding: 'utf-8')
          lines = text.lines
          book_idx = lines.index { |l| l =~ /^\s*book:\s*$/ }

          keys = {
            'main_title' => new_title,
            'subtitle' => new_sub,
            'author' => new_auth
          }

          if book_idx
            end_idx = lines.length
            ((book_idx + 1)...lines.length).each do |i|
              if lines[i] =~ /^\S/ && lines[i] !~ /^\s{2}/
                end_idx = i
                break
              end
            end

            present = { 'main_title' => false, 'subtitle' => false, 'author' => false }

            ((book_idx + 1)...end_idx).each do |i|
              line = lines[i]
              next unless line =~ /^(\s{2})(main_title|subtitle|author):\s*([^#\n]*)(\s*#.*)?$/

              indent  = ::Regexp.last_match(1)
              key     = ::Regexp.last_match(2)
              comment = ::Regexp.last_match(4).to_s
              value   = keys[key]
              lines[i] = "#{indent}#{key}: '#{value}'#{comment}\n"
              present[key] = true
            end

            insert_pos = book_idx + 1
            %w[main_title subtitle author].each do |key|
              next if present[key]

              lines.insert(insert_pos, "  #{key}: '#{keys[key]}'\n")
              insert_pos += 1
            end

            File.write(config_path, lines.join, encoding: 'utf-8')
            puts "[vivlio-starter] book.yml を更新しました。\n"
          else
            File.open(config_path, 'a:utf-8') do |f|
              f.puts
              f.puts 'book:'
              f.puts "  main_title: '#{new_title}'"
              f.puts "  subtitle: '#{new_sub}'"
              f.puts "  author: '#{new_auth}'"
            end
            puts "[vivlio-starter] book.yml に book セクションを追記しました。\n"
          end
        rescue StandardError => e
          warn "[vivlio-starter] book.yml の対話入力に失敗しました: #{e}"
        end

        def prompt_with_default(label, current)
          print "#{label} [#{current}]: "
          input = $stdin.gets&.strip
          input.nil? || input.empty? ? current : input
        end

        def default_readme_content(name)
          <<~MD
            # #{name}

            このリポジトリは Vivlio Starter で作成された書籍プロジェクトです。執筆・プレビュー・ビルドに関する基本情報をまとめています。

            ## 概要
            - 原稿: `contents/`
            - 画像: `images/`
            - スタイル: `stylesheets/`
            - 設定: `config/`

            ## 必要条件
            - Node.js / npm（Vivliostyle CLI を使用）
            - Ruby（rakeタスク等を使用する場合）

            ## セットアップ
            ```bash
            npm install
            ```

            ## プレビュー
            ```bash
            vivliostyle preview
            ```
            ブラウザで原稿を確認できます。

            ## ビルド（PDFなどの生成）
            ```bash
            vivlio-starter build
            ```
            執筆した書籍をビルドして成果物を生成します。出力先は設定に従います。

            ## ディレクトリ構成（抜粋）
            ```
            #{name}/
              contents/      # Markdown原稿
              images/        # 画像ファイル
              stylesheets/   # 章別・共通CSS
              config/        # 書籍設定 (book.yml など)
              README.md
            ```

            ## ライセンス / 著作権
            各ファイルの先頭や `LICENSE` を参照してください。
          MD
        end

        def run_vs_config(dest)
          system({ 'VIVLIO_QUIET' => '1' }, 'vs', 'config', chdir: dest)
        rescue StandardError => e
          warn "[vivlio-starter] vivliostyle 設定生成に失敗しました（継続）: #{e}"
        end

        def synchronize_viv_config(viv_config_path, config_path)
          return unless viv_config_path && File.exist?(viv_config_path)

          cfg = YAML.load_file(config_path)
          cfg = {} unless cfg.is_a?(Hash)
          book_cfg = cfg['book'] || {}

          Vivlio::Starter::Scaffolder.update_vivliostyle_config(
            viv_config_path: viv_config_path,
            book: book_cfg,
            config: cfg
          )
        rescue StandardError => e
          warn "[vivlio-starter] vivliostyle.config.js の同期に失敗しました（継続）: #{e}"
        end
      end
    end
  end
end