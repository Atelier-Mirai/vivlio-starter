# frozen_string_literal: true

require 'fileutils'
module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: rename（章のスラッグ/番号変更ユーティリティ）
      # ------------------------------------------------
      # - 目的: 章のスラッグ（名前）と番号の変更、関連する CSS と画像ディレクトリの追随
      # - 提供コマンド: rename
      # - 補足: 番号だけの変更(NN→NN)／番号+スラッグ(NN-slug→NN-slug) の両方をサポート
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module RenameCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'rename [OLD NEW]', '章のスラッグ/番号変更（単体 or 一括連番）(Thor)'
            long_desc <<~DESC
              使い方:
                ・引数あり: 指定した章のスラッグ（名前）と番号を変更します。
                ・引数なし: contents ディレクトリを走査し、通常章/付録を一括で連番に付け直します。

              受理パターン（単体変更）:
                1) NN-slug → NN-slug
                2) NN → NN （番号のみ変更: 既存 slug を維持。付録番号(91..97)の場合は appendix-letter を調整）

              例:
                vs rename 81-install 81-introduction
                vs rename 81-install.md 81-introduction.md
                vs rename 81 72
                vs rename -S 10      # 一括連番（章刻み幅=10）

              備考:
                ・拡張子 .md は省略可能です（自動付与/内部で除去）
                ・images/NN-slug ディレクトリがある場合は新しい番号/スラッグにリネームします
                ・番号変更時に stylesheets/NN.css がある場合は CSS もリネームし counter-reset を更新します
            DESC
            method_option :dry_run, type: :boolean, aliases: '-n', desc: '変更予定のみ表示（実行しない）'
            method_option :force,   type: :boolean, aliases: %w[-f -y], desc: '確認なしで変更を実行'
            # 一括連番向けオプション（renumber からマージ）
            method_option :chapter_step, type: :numeric, aliases: '-S', desc: '章番号の刻み幅を指定（既定: 1）。付録には影響しません'
            method_option :step,         type: :numeric, desc: '[互換] 章番号の刻み幅（--chapter-step と同義）'
            # ================================================================
            # Command: rename（章のスラッグ/番号変更）
            # ------------------------------------------------
            # - 概要: Markdown, 章別CSS, 画像ディレクトリの名称を一貫して変更
            # - 入力: OLD NEW（NN→NN または NN-slug→NN-slug）
            # - オプション: --dry-run (-n), --force (-f, -y), --verbose (-v)
            # ================================================================
            def rename(old_arg = nil, new_arg = nil)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # dry-run はプレビュー表示が主目的のため、-v がなくても常に表示する
              ENV['VERBOSE'] = '1' if options[:dry_run]
              contents_dir = Common::CONTENTS_DIR

              # 引数なしの場合は一括連番モード（旧 renumber の機能）
              if old_arg.nil? && new_arg.nil?
                # 走査
                chapter_files = Dir.glob("#{Common::CONTENTS_DIR}/*.md")
                                    .select { |f| File.basename(f) =~ /^\d+-/ }
                                    .reject { |f| File.basename(f) =~ /^(0\d|98|99)-/ }
                                    .sort

                regular_chapters = chapter_files.select { |f| File.basename(f) =~ /^[1-8]\d-/ }
                appendix_files   = chapter_files.select { |f| File.basename(f) =~ /^9[0-7]-/ }

                if chapter_files.empty?
                  Common.log_warn('連番付け直し対象のファイルが見つかりません')
                  exit 0
                end

                # 刻み幅の決定
                requested_step = (options[:chapter_step] || options[:step] || 1).to_i
                requested_step = 1 if requested_step <= 0

                effective_step = requested_step
                if regular_chapters.size > 1
                  # 11 + (n-1)*step <= 89 を満たす最大 step
                  max_step = ((89 - 11) / (regular_chapters.size - 1)).floor
                  max_step = 1 if max_step < 1
                  effective_step = [requested_step, max_step].min
                end

                if requested_step != effective_step
                  Common.log_warn("章の刻み幅 #{requested_step} は 11..89 の範囲に収まらないため、#{effective_step} に調整しました")
                else
                  Common.log_info("章の刻み幅: #{effective_step}")
                end

                Common.log_info('対象ファイル:')

                # 表示（通常）
                if regular_chapters.any?
                  Common.log_info('通常の章:')
                  regular_chapters.each_with_index do |file, index|
                    old_name   = File.basename(file, '.md')
                    new_number = format('%02d', 11 + index * effective_step)
                    Common.log_info("#{old_name} → #{new_number}-#{old_name.split('-', 2)[1]}")
                  end
                end

                # 表示（付録）
                if appendix_files.any?
                  Common.log_info('付録:')
                  begin
                    appendix_files.each_with_index do |file, index|
                      old_name   = File.basename(file, '.md')
                      new_number = format('%02d', index + 91)
                      new_letter = Common.appendix_number_to_letter(new_number) ||
                                   Common.appendix_number_to_letter(old_name[/^\d+/]) || 'a'
                      name_tail = old_name.split('-', 2)[1] || old_name
                      new_name_part = name_tail.sub(/appendix-[a-z]/, "appendix-#{new_letter}")
                      Common.log_info("#{old_name} → #{new_number}-#{new_name_part}")
                    end
                  rescue => e
                    Common.log_warn("付録の一覧表示でエラーが発生しました: #{e}")
                  end
                end

                # 確認
                if !(options[:force] || options[:dry_run])
                  print '  ❓ 連番付け直しを実行しますか？ (y/N): '
                  response = STDIN.gets&.chomp&.downcase
                  if response != 'y' && response != 'yes'
                    Common.log_warn('連番付け直しをキャンセルしました')
                    exit 0
                  end
                end

                if options[:dry_run]
                  Common.log_info('[dry-run] ここまでの内容で変更を実行します')
                  exit 0
                end

                # マッピング作成
                rename_map = {}
                regular_chapters.each_with_index do |file, index|
                  old_basename = File.basename(file, '.md')
                  old_number   = old_basename.split('-')[0]
                  new_number   = format('%02d', 11 + index * effective_step)
                  next if old_number == new_number
                  new_basename = old_basename.sub(/^\d+/, new_number)
                  rename_map[old_basename] = {
                    old_number: old_number,
                    new_number: new_number,
                    new_basename: new_basename,
                    old_file: file,
                    new_file: File.join(Common::CONTENTS_DIR, "#{new_basename}.md")
                  }
                end

                appendix_files.each_with_index do |file, index|
                  begin
                    old_basename = File.basename(file, '.md')
                    old_number   = old_basename.split('-')[0]
                    new_number   = format('%02d', index + 91)
                    next if old_number == new_number
                    new_letter = Common.appendix_number_to_letter(new_number) ||
                                 Common.appendix_number_to_letter(old_number) || 'a'
                    new_basename = (old_basename.sub(/^\d+/, new_number))
                                     .sub(/appendix-[a-z]/, "appendix-#{new_letter}")
                    rename_map[old_basename] = {
                      old_number: old_number,
                      new_number: new_number,
                      new_basename: new_basename,
                      old_file: file,
                      new_file: File.join(Common::CONTENTS_DIR, "#{new_basename}.md")
                    }
                  rescue => e
                    Common.log_warn("付録のリネームマッピングでエラーが発生しました: #{e} (#{old_basename})")
                  end
                end

                if rename_map.empty?
                  Common.log_success('すでに正しい連番になっています')
                  exit 0
                end

                Common.log_action('ファイル名変更を実行中...')

                # 1. Markdown リネーム
                rename_map.each do |old_basename, info|
                  Common.log_info("#{old_basename}.md → #{info[:new_basename]}.md")
                  FileUtils.mv(info[:old_file], info[:new_file])
                end

                # 2. CSS リネーム
                Common.log_action('CSSファイルの更新中...')
                rename_map.each do |old_basename, info|
                  old_css = "stylesheets/#{info[:old_number]}.css"
                  new_css = "stylesheets/#{info[:new_number]}.css"
                  if File.exist?(old_css)
                    Common.log_info("#{old_css} → #{new_css}")
                    FileUtils.mv(old_css, new_css)
                    # 章番号から10引いた値をCSSの counter-reset に設定
                    BuildHelpers.update_css_counter(new_css, info[:new_number].to_i - 10)
                  end
                end

                # 3. 画像ディレクトリのリネーム
                Common.log_action('画像ディレクトリの更新中...')
                rename_map.each do |old_basename, info|
                  old_img_glob = "images/#{info[:old_number]}-*"
                  Dir.glob(old_img_glob).each do |old_dir|
                    next unless File.directory?(old_dir)
                    new_dir = if info[:new_number].to_i.between?(91, 97)
                      new_letter = Common.appendix_number_to_letter(info[:new_number])
                      old_dir.sub(/\/#{info[:old_number]}-/, "/#{info[:new_number]}-")
                             .sub(/appendix-[a-z]/, "appendix-#{new_letter}")
                    else
                      old_dir.sub(/\/#{info[:old_number]}-/, "/#{info[:new_number]}-")
                    end
                    Common.log_info("#{old_dir} → #{new_dir}")
                    FileUtils.mv(old_dir, new_dir)
                  end
                end

                # 4. 既存生成物のクリーンアップ（Thor の clean コマンドを呼び出し）
                Common.log_action('既存の生成ファイルをクリーンアップ中...')
                begin
                  Vivlio::Starter::ThorCLI.start(['clean'])
                rescue => e
                  Common.log_warn("クリーンアップ中にエラー: #{e}")
                end

                Common.log_success('連番付け直し完了')
                exit 0
              end

              # ここから単体変更モード（旧来の rename 動作）
              # .md 許容 + 共通正規化
              tokens = Common.normalize_tokens([old_arg, new_arg])
              old_name, new_name = tokens

              if old_name.nil? || new_name.nil? || old_name.empty? || new_name.empty?
                warn '使い方: vs rename <旧名> <新名> または 引数なしで一括連番'
                exit 1
              end

              # 判定: NN → NN（番号のみ）か NN-slug → NN-slug
              number_only = old_name =~ /^\d{2}\z/ && new_name =~ /^\d{2}\z/

              if number_only
                old_number = old_name
                new_number = new_name
                # 旧番号のMDを一意に特定
                old_md_candidates = Dir.glob(File.join(contents_dir, "#{old_number}-*.md")).sort
                if old_md_candidates.empty?
                  Common.log_error("#{old_number}章のファイルが見つかりません")
                  exit 1
                elsif old_md_candidates.length > 1
                  Common.log_error("#{old_number}章のファイルが複数見つかりました:")
                  old_md_candidates.each { |f| Common.log_info("- #{File.basename(f)}") }
                  exit 1
                end
                old_md = old_md_candidates.first
                old_basename = File.basename(old_md, '.md')
                _, old_slug = old_basename.split('-', 2)
                # new_slug は基本維持。付録番号(91-97)へ移す場合は appendix-letter を調整
                if new_number.to_i.between?(91, 97) && old_slug =~ /appendix-[a-z]/
                  new_letter = Common.appendix_number_to_letter(new_number)
                  new_slug = old_slug.sub(/appendix-[a-z]/, "appendix-#{new_letter}")
                else
                  new_slug = old_slug
                end
              else
                unless old_name =~ /^\d{2}-.+/ && new_name =~ /^\d{2}-.+/
                  Common.log_error("引数は 'NN-slug' または 'NN' 形式で指定してください (例: 81-install / 81)")
                  exit 1
                end
                old_number, old_slug = old_name.split('-', 2)
                new_number, new_slug = new_name.split('-', 2)
              end

              old_md = File.join(contents_dir, "#{old_number}-#{old_slug}.md")
              new_md = File.join(contents_dir, "#{new_number}-#{new_slug}.md")

              unless File.exist?(old_md)
                Common.log_error("対象のMarkdownが見つかりません: #{File.basename(old_md)}")
                exit 1
              end
              if File.exist?(new_md)
                Common.log_error("変更先のMarkdownが既に存在します: #{File.basename(new_md)}")
                exit 1
              end

              Common.log_action("章名・番号変更: #{old_number}-#{old_slug} → #{new_number}-#{new_slug}")
              Common.log_info("Markdown: #{File.basename(old_md)} → #{File.basename(new_md)}")

              # 確認プロンプト
              unless options[:force] || options[:dry_run]
                print "  ❓ 章名・番号変更を実行しますか？ (y/N): "
                response = STDIN.gets&.chomp&.downcase
                unless response == 'y' || response == 'yes'
                  Common.log_warn('章名・番号変更をキャンセルしました')
                  exit 0
                end
              end

              # ドライラン時はここまで
              if options[:dry_run]
                Common.log_info('[dry-run] ここまでの内容で変更を実行します')
                exit 0
              end

              # 1. Markdown のリネーム
              FileUtils.mv(old_md, new_md)
              Common.log_success('Markdownの変更が完了しました')

              # 2. CSS のリネーム（番号が変わる場合）
              old_css = File.join('stylesheets', "#{old_number}.css")
              new_css = File.join('stylesheets', "#{new_number}.css")
              if old_number != new_number && File.exist?(old_css)
                if File.exist?(new_css)
                  Common.log_warn("#{File.basename(new_css)} が既に存在するため、CSSファイルは手動で統合してください")
                else
                  FileUtils.mv(old_css, new_css)
                  # 章番号から10引いた値をCSSの counter-reset に設定
                  BuildHelpers.update_css_counter(new_css, new_number.to_i - 10)
                  Common.log_success('CSSファイルの変更が完了しました')
                end
              end

              # 3. 画像ディレクトリのリネーム（存在する場合）
              old_img_dir = File.join('images', "#{old_number}-#{old_slug}")
              new_img_dir = File.join('images', "#{new_number}-#{new_slug}")
              if File.directory?(old_img_dir)
                if File.exist?(new_img_dir)
                  Common.log_warn("#{new_img_dir} が既に存在するため、画像ディレクトリは手動で統合してください")
                else
                  FileUtils.mv(old_img_dir, new_img_dir)
                  Common.log_success("画像ディレクトリの変更が完了しました: #{File.basename(new_img_dir)}")
                end
              else
                Common.log_info("画像ディレクトリは見つかりませんでした: #{old_img_dir}")
              end

              # 4. 既存生成物のクリーンアップ（旧名に紐づくもの）
              [
                File.join('.', "#{old_number}-#{old_slug}.html")
              ].each do |f|
                if File.exist?(f)
                  File.delete(f)
                  Common.log_info("#{File.basename(f)} を削除")
                end
              end

              Common.log_success('章名・番号変更が完了しました')
            end
          end
        end
      end
    end
  end
end
