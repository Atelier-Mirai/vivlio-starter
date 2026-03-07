# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/rename.rb
# ================================================================
# 責務:
#   章ファイルの名前変更・番号変更を行うコマンドを提供する。
#   Markdown ファイル、画像ディレクトリ、catalog.yml を一括で更新する。
#
# 機能:
#   - 単一章のリネーム: vs rename 11-old 12-new
#   - 番号のみ変更: vs rename 11 12（スラッグは維持）
#   - 全章の連番付け直し: vs rename（引数なし）
#
# 章番号の規約:
#   - 11-89: 通常の章（11から開始、刻み幅は --step で指定可能）
#   - 91-97: 付録（A-G に対応、appendix-a 形式のスラッグを自動調整）
#   - 00-09, 98-99: 特殊ページ（リネーム対象外）
#
# 副作用:
#   - contents/XX-slug.md をリネーム
#   - images/XX-slug/ ディレクトリをリネーム
#   - config/catalog.yml のエントリを更新
#   - 古い生成ファイル（*.html）を削除
#
# 依存:
#   - Common: ログ出力・パス定数・付録番号変換
#   - Build::CatalogUpdater: catalog.yml の更新
#   - CleanCommands: リネーム後のクリーンアップ
# ================================================================

require 'fileutils'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'clean'
require_relative 'token_resolver'

module Vivlio
  module Starter
    module CLI
      # rename コマンドのモジュール（現在は空、実装は RenameCommandExecutor）
      module RenameCommands
      end

      # 章のリネーム・連番付け直しを実行するクラス
      #
      # 使用方法:
      #   RenameCommandExecutor.new(options).call(old_arg, new_arg)
      #   RenameCommandExecutor.new(options).call  # 全章連番付け直し
      class RenameCommandExecutor
        # @param options [Hash] オプション設定
        #   - :force [Boolean] 確認をスキップ
        #   - :dry_run [Boolean] 実行せずに変更予定のみ表示
        #   - :verbose [Boolean] 詳細ログを出力
        #   - :step [Integer] 章番号の刻み幅（デフォルト: 1）
        def initialize(options = {})
          @options = (options || {}).dup
        end

        # リネーム処理を実行する
        #
        # @param old_arg [String, nil] 旧名（nil の場合は全章連番付け直し）
        # @param new_arg [String, nil] 新名（nil の場合は全章連番付け直し）
        # @return [void]
        # @raise [SystemExit] エラー時または dry-run 完了時
        def call(old_arg = nil, new_arg = nil)
          enable_verbose_mode

          if old_arg.nil? && new_arg.nil?
            renumber_all_chapters
          else
            rename_single_chapter(old_arg, new_arg)
          end
        end

        private

        attr_reader :options

        # verbose または dry_run 時はログを詳細化する
        def enable_verbose_mode
          ENV['VERBOSE'] = '1' if options[:verbose] || options[:dry_run]
        end

        # 全章の連番を付け直す
        #
        # 通常章は 11 から開始し、付録は 91 から開始する。
        # 刻み幅は --step オプションで指定可能（デフォルト: 1）。
        # 11-89 の範囲に収まるよう、刻み幅は自動調整される。
        def renumber_all_chapters
          files = chapter_file_groups

          if files[:all].empty?
            Common.log_warn('連番付け直し対象のファイルが見つかりません')
            exit 0
          end

          requested_step = normalized_step
          effective_step = effective_step_for(requested_step, files[:regular].size)
          report_step_adjustment(requested_step, effective_step)

          Common.log_info('対象ファイル:')
          display_regular_chapters(files[:regular], effective_step)
          display_appendix_files(files[:appendix])

          confirm_or_exit('連番付け直し') unless options[:force] || options[:dry_run]

          if options[:dry_run]
            Common.log_info('[dry-run] ここまでの内容で変更を実行します')
            exit 0
          end

          rename_map = build_rename_map(files[:regular], files[:appendix], effective_step)

          if rename_map.empty?
            Common.log_success('すでに正しい連番になっています')
            exit 0
          end

          apply_renumber(rename_map)
          cleanup_after_renumber
          Common.log_success('連番付け直し完了')
          exit 0
        end

        # contents/ 内の章ファイルを種別ごとにグループ化する
        #
        # @return [Hash] { all: [...], regular: [...], appendix: [...] }
        #   - all: 全章ファイル（00-09, 98-99 を除く）
        #   - regular: 通常章（10-89）
        #   - appendix: 付録（90-97）
        def chapter_file_groups
          chapter_files = Dir.glob("#{Common::CONTENTS_DIR}/*.md")
                             .select { |f| File.basename(f) =~ /^\d+-/ }
                             .reject { |f| File.basename(f) =~ /^(0\d|98|99)-/ }
                             .sort

          {
            all: chapter_files,
            regular: chapter_files.select { |f| File.basename(f) =~ /^[1-8]\d-/ },
            appendix: chapter_files.select { |f| File.basename(f) =~ /^9[0-7]-/ }
          }
        end

        # オプションから刻み幅を取得し、正の整数に正規化する
        # @return [Integer] 刻み幅（最小 1）
        def normalized_step
          step = (options[:chapter_step] || options[:step] || 1).to_i
          step <= 0 ? 1 : step
        end

        # 章数に応じて刻み幅を調整する（11-89 の範囲に収めるため）
        #
        # @param requested_step [Integer] 要求された刻み幅
        # @param chapter_count [Integer] 章数
        # @return [Integer] 実際に使用する刻み幅
        def effective_step_for(requested_step, chapter_count)
          return requested_step if chapter_count <= 1

          # 11 から 89 までの範囲に収めるための最大刻み幅を計算
          max_step = ((89 - 11) / (chapter_count - 1)).floor
          max_step = 1 if max_step < 1
          [requested_step, max_step].min
        end

        def report_step_adjustment(requested_step, effective_step)
          if requested_step == effective_step
            Common.log_info("章の刻み幅: #{effective_step}")
          else
            Common.log_warn("章の刻み幅 #{requested_step} は 11..89 の範囲に収まらないため、#{effective_step} に調整しました")
          end
        end

        def display_regular_chapters(chapters, effective_step)
          return if chapters.empty?

          Common.log_info('通常の章:')
          chapters.each_with_index do |file, index|
            old_name   = File.basename(file, '.md')
            new_number = format('%02d', 11 + (index * effective_step))
            Common.log_info("#{old_name} → #{new_number}-#{old_name.split('-', 2)[1]}")
          end
        end

        def display_appendix_files(appendix_files)
          return if appendix_files.empty?

          Common.log_info('付録:')
          appendix_files.each_with_index do |file, index|
            old_name   = File.basename(file, '.md')
            new_number = format('%02d', index + 91)
            new_letter = Common.appendix_number_to_letter(new_number) ||
                         Common.appendix_number_to_letter(old_name[/^\d+/]) || 'a'
            name_tail = old_name.split('-', 2)[1] || old_name
            new_name_part = name_tail.sub(/appendix-[a-z]/, "appendix-#{new_letter}")
            Common.log_info("#{old_name} → #{new_number}-#{new_name_part}")
          end
        rescue StandardError => e
          Common.log_warn("付録の一覧表示でエラーが発生しました: #{e}")
        end

        def confirm_or_exit(action_label)
          print "  ❓ #{action_label}を実行しますか？ (y/N): "
          response = $stdin.gets&.chomp&.downcase
          return if %w[y yes].include?(response)

          Common.log_warn("#{action_label}をキャンセルしました")
          exit 0
        end

        def build_rename_map(regular_chapters, appendix_files, effective_step)
          map = {}

          regular_chapters.each_with_index do |file, index|
            old_basename = File.basename(file, '.md')
            old_number   = old_basename.split('-')[0]
            new_number   = format('%02d', 11 + (index * effective_step))
            next if old_number == new_number

            new_basename = old_basename.sub(/^\d+/, new_number)
            map[old_basename] = build_mapping(old_basename, new_basename, file)
          end

          appendix_files.each_with_index do |file, index|
            old_basename = File.basename(file, '.md')
            old_number   = old_basename.split('-')[0]
            new_number   = format('%02d', index + 91)
            next if old_number == new_number

            new_letter = Common.appendix_number_to_letter(new_number) ||
                         Common.appendix_number_to_letter(old_number) || 'a'
            new_basename = old_basename.sub(/^\d+/, new_number)
                                       .sub(/appendix-[a-z]/, "appendix-#{new_letter}")
            map[old_basename] = build_mapping(old_basename, new_basename, file)
          rescue StandardError => e
            Common.log_warn("付録のリネームマッピングでエラーが発生しました: #{e} (#{old_basename})")
          end

          map
        end

        def build_mapping(old_basename, new_basename, file)
          {
            old_number: old_basename.split('-')[0],
            new_number: new_basename.split('-')[0],
            new_basename: new_basename,
            old_file: file,
            new_file: File.join(Common::CONTENTS_DIR, "#{new_basename}.md")
          }
        end

        def apply_renumber(rename_map)
          Common.log_action('ファイル名変更を実行中...')
          rename_map.each do |old_basename, info|
            Common.log_info("#{old_basename}.md → #{info[:new_basename]}.md")
            FileUtils.mv(info[:old_file], info[:new_file])
            Build::CatalogUpdater.rename_chapter(old_basename, info[:new_basename])
          end

          Common.log_action('画像ディレクトリの更新中...')
          rename_map.each_value do |info|
            old_img_glob = "images/#{info[:old_number]}-*"
            Dir.glob(old_img_glob).each do |old_dir|
              next unless File.directory?(old_dir)

              new_dir = new_directory_for(old_dir, info)
              Common.log_info("#{old_dir} → #{new_dir}")
              FileUtils.mv(old_dir, new_dir)
            end
          end
        end

        def new_directory_for(old_dir, info)
          if info[:new_number].to_i.between?(91, 97)
            new_letter = Common.appendix_number_to_letter(info[:new_number])
            old_dir.sub(%r{/#{info[:old_number]}-}, "/#{info[:new_number]}-")
                   .sub(/appendix-[a-z]/, "appendix-#{new_letter}")
          else
            old_dir.sub(%r{/#{info[:old_number]}-}, "/#{info[:new_number]}-")
          end
        end

        def cleanup_after_renumber
          Common.log_action('既存の生成ファイルをクリーンアップ中...')
          CleanCommands.execute_clean({})
        rescue StandardError => e
          Common.log_warn("クリーンアップ中にエラー: #{e}")
        end

        # 単一章のリネームを実行する
        #
        # @param old_arg [String] 旧名（"NN-slug" または "NN" 形式）
        # @param new_arg [String] 新名（"NN-slug" または "NN" 形式）
        #
        # 引数形式:
        #   - "NN-slug" 形式: 番号とスラッグの両方を指定
        #   - "NN" 形式: 番号のみ指定（スラッグは維持、付録の場合は自動調整）
        def rename_single_chapter(old_arg, new_arg)
          if old_arg.nil? || new_arg.nil?
            warn '使い方: vs rename <旧名> <新名> または 引数なしで一括連番'
            exit 1
          end

          resolver = TokenResolver::Resolver.new
          from_entry = resolver.resolve([old_arg]).first

          unless from_entry&.valid?
            Common.log_error("変更元の指定が不正です: #{old_arg}")
            exit 1
          end

          to_entry = resolve_target_entry(resolver, new_arg, from_entry)

          # 変更元がカタログに存在するかチェック
          unless from_entry.in_catalog?
            Common.log_error("変更元の章 #{from_entry.basename} はカタログに存在しません")
            exit 1
          end

          # 変更先の重複チェック（仕様書 9.4 のルールに従う）
          # - to が in_catalog かつ from.number != to.number なら拒否
          if to_entry.in_catalog? && from_entry.number != to_entry.number
            Common.log_error("変更先の番号 #{to_entry.number} は既に '#{to_entry.label}' で使用されています")
            exit 1
          end

          contents_dir = Common::CONTENTS_DIR
          # 両方が2桁数字のみの場合は番号変更モード
          number_only = from_entry.slug.nil? && to_entry.slug.nil?

          if number_only
            old_number = from_entry.number
            new_number = to_entry.number
            old_md, old_slug = find_markdown_by_number(contents_dir, old_number)
            # 付録番号（91-97）に変更する場合、appendix-X のスラッグを自動調整
            new_slug = adjust_slug_for_appendix(new_number, old_slug)
          else
            old_number = from_entry.number
            old_slug = from_entry.slug
            new_number = to_entry.number
            new_slug = to_entry.slug || old_slug
            old_md = File.join(contents_dir, "#{old_number}-#{old_slug}.md")
          end

          new_md = File.join(contents_dir, "#{new_number}-#{new_slug}.md")
          validate_markdown_paths(old_md, new_md)

          Common.log_action("章名・番号変更: #{old_number}-#{old_slug} → #{new_number}-#{new_slug}")
          Common.log_info("Markdown: #{File.basename(old_md)} → #{File.basename(new_md)}")

          confirm_or_exit('章名・番号変更') unless options[:force] || options[:dry_run]

          if options[:dry_run]
            Common.log_info('[dry-run] ここまでの内容で変更を実行します')
            exit 0
          end

          execute_single_rename(old_md, new_md, old_number, old_slug, new_number, new_slug)
        end

        def resolve_target_entry(resolver, new_arg, from_entry)
          return build_virtual_entry_with_slug(from_entry, new_arg) if slug_only_token?(new_arg)

          entry = resolver.resolve([new_arg]).first
          return entry if entry&.valid?

          Common.log_error("変更先の指定が不正です: #{new_arg}")
          exit 1
        end

        def build_virtual_entry_with_slug(from_entry, new_arg)
          slug = normalize_new_slug(new_arg)
          if slug.nil? || slug.empty?
            Common.log_error('変更先スラッグの形式が不正です')
            exit 1
          end

          number = from_entry.number
          path = File.join(Common::CONTENTS_DIR, "#{number}-#{slug}.md")
          TokenResolver::Entry.new(
            number:,
            slug: slug,
            kind: from_entry.kind,
            label: 'RENAME_TARGET',
            path:,
            exists: File.exist?(path),
            in_catalog: false,
            valid: true
          )
        end

        def find_markdown_by_number(contents_dir, chapter_number)
          candidates = Dir.glob(File.join(contents_dir, "#{chapter_number}-*.md"))
          if candidates.empty?
            Common.log_error("#{chapter_number}章のファイルが見つかりません")
            exit 1
          elsif candidates.length > 1
            Common.log_error("#{chapter_number}章のファイルが複数見つかりました:")
            candidates.each { |f| Common.log_info("- #{File.basename(f)}") }
            exit 1
          end

          old_md = candidates.first
          old_basename = File.basename(old_md, '.md')
          _, old_slug = old_basename.split('-', 2)
          [old_md, old_slug]
        end

        def adjust_slug_for_appendix(new_number, old_slug)
          if new_number.to_i.between?(91, 97) && old_slug =~ /appendix-[a-z]/
            new_letter = Common.appendix_number_to_letter(new_number)
            old_slug.sub(/appendix-[a-z]/, "appendix-#{new_letter}")
          else
            old_slug
          end
        end

        def validate_markdown_paths(old_md, new_md)
          unless File.exist?(old_md)
            Common.log_error("対象のMarkdownが見つかりません: #{File.basename(old_md)}")
            exit 1
          end
          if File.exist?(new_md)
            Common.log_error("変更先のMarkdownが既に存在します: #{File.basename(new_md)}")
            exit 1
          end
        end

        def execute_single_rename(old_md, new_md, old_number, old_slug, new_number, new_slug)
          FileUtils.mv(old_md, new_md)
          Common.log_success('Markdownの変更が完了しました')

          old_basename = "#{old_number}-#{old_slug}"
          new_basename = "#{new_number}-#{new_slug}"
          Build::CatalogUpdater.rename_chapter(old_basename, new_basename)

          old_img_dir = File.join('images', old_basename)
          new_img_dir = File.join('images', new_basename)
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

          cleanup_generated_files(old_number, old_slug)
          Common.log_success('章名・番号変更が完了しました')
        end

        def cleanup_generated_files(old_number, old_slug)
          targets = [
            File.join('.', "#{old_number}-#{old_slug}.html")
          ]
          targets.each do |file|
            next unless File.exist?(file)

            File.delete(file)
            Common.log_info("#{File.basename(file)} を削除")
          end
        end

        def slug_only_token?(token)
          base = File.basename(token.to_s.strip)
          base = base.sub(/\.(md|markdown)\z/i, '')
          return false if base.empty?

          !base.match?(/\A\d/)
        end

        def normalize_new_slug(token)
          base = File.basename(token.to_s.strip)
          base = base.sub(/\.(md|markdown)\z/i, '')
          slug = base.downcase.tr(' ', '-')
          slug = slug.gsub(/[^a-z0-9._-]+/, '-')
          slug = slug.gsub(/-+/, '-')
          slug.gsub(/\A-+|-+\z/, '')
        rescue StandardError
          ''
        end
      end
    end
  end
end

