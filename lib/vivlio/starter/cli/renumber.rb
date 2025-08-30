# frozen_string_literal: true

require 'fileutils'
module Vivlio
  module Starter
    module CLI
      # ================================================================
      # Module: Thor コマンド群: renumber（章番号の付け直しユーティリティ）
      # ------------------------------------------------
      # - 目的: 全章の連番付け直し、または特定章の番号変更（rename の別名）
      # - 提供コマンド: renumber
      # - 補足: 付録(91..97)は appendix-letter を自動調整
      # - 関連: 共通処理は `lib/vivlio/starter/cli/common.rb`
      # ================================================================
      module RenumberCommands
        extend self
        def included(base)
          base.class_eval do
            desc 'renumber [OLD NEW]', '章ファイルの連番付け直し、または個別番号変更 (Thor)'
            long_desc <<~DESC
              引数なし: contents ディレクトリ内の章ファイルを一括で連番に付け直します。
              引数あり: OLD から NEW へ特定章の番号を変更します（rename の別名）。

              例:
                vs renumber                  # 全体の連番付け直し
                vs renumber 17 16            # 個別の番号変更（内部的に rename を呼びます）

              備考:
                ・前書き(0x)、あとがき(98)、奥付(99)は対象外
                ・付録(91..97)は appendix の letter も自動調整
            DESC
            method_option :dry_run, type: :boolean, aliases: '-n', desc: '変更予定のみ表示（実行しない）'
            method_option :force,   type: :boolean, aliases: %w[-f -y], desc: '確認なしで変更を実行'
            # ================================================================
            # Command: renumber（章番号の付け直し/変更）
            # ------------------------------------------------
            # - 概要: 引数なしで全体の連番を再構築。OLD NEW 指定時は特定章の番号変更（rename を呼び出し）
            # - 入力: なし、または OLD NEW
            # - オプション: --dry-run (-n), --force (-f, -y), --verbose (-v)
            # ================================================================
            def renumber(old_arg = nil, new_arg = nil)
              ENV['VERBOSE'] = '1' if options[:verbose]
              # Common ベース実装

              if old_arg && new_arg
                # rename の別名として実行
                invoke :rename, [old_arg, new_arg], options
                return
              end

              # 以降は全体の連番付け直しモード
              Common.log_action('章ファイルの連番付け直しを開始...')

              chapter_files = Dir.glob("#{Common::CONTENTS_DIR}/*.md")
                                  .select { |f| File.basename(f) =~ /^\d+-/ }
                                  .reject { |f| File.basename(f) =~ /^(0\d|98|99)-/ }
                                  .sort

              regular_chapters = chapter_files.select { |f| File.basename(f) =~ /^[1-8]\d-/ }
              appendix_files   = chapter_files.select { |f| File.basename(f) =~ /^9[0-7]-/ }

              if chapter_files.empty?
                Common.log_warn('連番付け直し対象のファイルが見つかりません')
                return
              end

              Common.log_info('対象ファイル:')

              # 表示（通常）
              unless regular_chapters.empty?
                Common.log_info('通常の章:')
                regular_chapters.each_with_index do |file, index|
                  old_name   = File.basename(file, '.md')
                  new_number = format('%02d', index + 11)
                  Common.log_info("#{old_name} → #{new_number}-#{old_name.split('-', 2)[1]}")
                end
              end

              # 表示（付録）
              unless appendix_files.empty?
                Common.log_info('付録:')
                appendix_files.each_with_index do |file, index|
                  old_name   = File.basename(file, '.md')
                  new_number = format('%02d', index + 91)
                  new_letter = Common.appendix_number_to_letter(new_number)
                  new_name_part = old_name.split('-', 2)[1].sub(/appendix-[a-z]/, "appendix-#{new_letter}")
                  Common.log_info("#{old_name} → #{new_number}-#{new_name_part}")
                end
              end

              # 確認
              unless options[:force] || options[:dry_run]
                print '  ❓ 連番付け直しを実行しますか？ (y/N): '
                response = STDIN.gets&.chomp&.downcase
                unless response == 'y' || response == 'yes'
                  Common.log_warn('連番付け直しをキャンセルしました')
                  return
                end
              end

              if options[:dry_run]
                Common.log_info('[dry-run] ここまでの内容で変更を実行します')
                return
              end

              # マッピング
              rename_map = {}

              regular_chapters.each_with_index do |file, index|
                old_basename = File.basename(file, '.md')
                old_number   = old_basename.split('-')[0]
                new_number   = format('%02d', index + 11)
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
                old_basename = File.basename(file, '.md')
                old_number   = old_basename.split('-')[0]
                new_number   = format('%02d', index + 91)
                next if old_number == new_number

                new_letter   = Common.appendix_number_to_letter(new_number)
                new_basename = old_basename.sub(/^\d+/, new_number).sub(/appendix-[a-z]/, "appendix-#{new_letter}")
                rename_map[old_basename] = {
                  old_number: old_number,
                  new_number: new_number,
                  new_basename: new_basename,
                  old_file: file,
                  new_file: File.join(Common::CONTENTS_DIR, "#{new_basename}.md")
                }
              end

              if rename_map.empty?
                Common.log_success('すでに正しい連番になっています')
                return
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
                  Common.update_css_counter(new_css, info[:new_number].to_i)
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

              # 4. 既存生成物のクリーンアップ
              Common.log_action('既存の生成ファイルをクリーンアップ中...')
              Common.clean_generated_files!

              Common.log_success('連番付け直し完了')
              Common.log_info('変更を反映するには以下を実行してください:')
              Common.log_info('vs build')
            end
          end
        end
      end
    end
  end
end
