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
#   - 00: 前書き（リネーム対象外）
#   - 01-89: 通常の章（先頭章番号を起点、刻み幅は --step で指定可能）
#   - 90-98: 付録（A-I に対応、appendix-a 形式のスラッグを自動調整）
#   - 99: 後書き（リネーム対象外）
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
        # 通常章は 01-89、付録は 90-98 の範囲で連番を振り直す。
        # 先頭章の番号を起点として順に詰める。
        # 刻み幅は --step オプションで指定可能（デフォルト: 1）。
        def renumber_all_chapters
          files = chapter_file_groups

          if files[:all].empty?
            Common.log_warn('連番付け直し対象のファイルが見つかりません')
            exit 0
          end

          start_num = regular_start_number(files[:regular])
          requested_step = normalized_step
          effective_step = effective_step_for(requested_step, files[:regular].size, start_num)
          report_step_adjustment(requested_step, effective_step)

          Common.log_info('対象ファイル:')
          display_regular_chapters(files[:regular], effective_step, start_num)
          display_appendix_files(files[:appendix])

          confirm_or_exit('連番付け直し') unless options[:force] || options[:dry_run]

          if options[:dry_run]
            Common.log_info('[dry-run] ここまでの内容で変更を実行します')
            exit 0
          end

          rename_map = build_rename_map(files[:regular], files[:appendix], effective_step, start_num)

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
        #   - all: 全章ファイル（00, 99 を除く）
        #   - regular: 通常章（01-89）
        #   - appendix: 付録（90-98）
        def chapter_file_groups
          chapter_files = Dir.glob("#{Common::CONTENTS_DIR}/*.md")
                             .select { |f| File.basename(f) =~ /^\d+/ }
                             .reject { |f| File.basename(f) =~ /^(00|99)(?:-|\.)/ }
                             .sort

          {
            all: chapter_files,
            regular: chapter_files.select { |f| File.basename(f) =~ /^[0-8]\d(?:-|\.)/ },
            appendix: chapter_files.select { |f| File.basename(f) =~ /^9[0-8](?:-|\.)/ }
          }
        end

        # オプションから刻み幅を取得し、正の整数に正規化する
        # @return [Integer] 刻み幅（最小 1）
        def normalized_step
          step = (options[:step] || 1).to_i
          step <= 0 ? 1 : step
        end

        # 通常章の先頭章番号を取得する
        #
        # @param regular_chapters [Array<String>] ソート済みの通常章ファイルパス
        # @return [Integer] 先頭章の番号（空の場合は 1）
        def regular_start_number(regular_chapters)
          return 1 if regular_chapters.empty?

          extract_number_and_slug(File.basename(regular_chapters.first, '.md')).first.to_i
        end

        # 章数に応じて刻み幅を調整する（start_number-89 の範囲に収めるため）
        #
        # @param requested_step [Integer] 要求された刻み幅
        # @param chapter_count [Integer] 章数
        # @param start_number [Integer] 先頭章の番号
        # @return [Integer] 実際に使用する刻み幅
        def effective_step_for(requested_step, chapter_count, start_number = 1)
          return requested_step if chapter_count <= 1

          # start_number から 89 までの範囲に収めるための最大刻み幅を計算
          max_step = ((89 - start_number) / (chapter_count - 1)).floor
          max_step = 1 if max_step < 1
          [requested_step, max_step].min
        end

        def report_step_adjustment(requested_step, effective_step)
          if requested_step == effective_step
            Common.log_info("章の刻み幅: #{effective_step}")
          else
            Common.log_warn("章の刻み幅 #{requested_step} は 01..89 の範囲に収まらないため、#{effective_step} に調整しました")
          end
        end

        # 連番後の通常章の新旧対応をログ出力する
        def display_regular_chapters(chapters, effective_step, start_number = 1)
          return if chapters.empty?

          Common.log_info('通常の章:')
          chapters.each_with_index do |file, index|
            old_name = File.basename(file, '.md')
            old_number, old_slug = extract_number_and_slug(old_name)
            new_number = format('%02d', start_number + (index * effective_step))
            new_basename = build_basename(new_number, old_slug)
            Common.log_info("#{old_name} → #{new_basename}")
          end
        end

        # 付録章の新旧対応をログ出力する
        def display_appendix_files(appendix_files)
          return if appendix_files.empty?

          Common.log_info('付録:')
          appendix_files.each_with_index do |file, index|
            old_name = File.basename(file, '.md')
            old_number, old_slug = extract_number_and_slug(old_name)
            new_number = format('%02d', index + 90)
            adjusted_slug = adjust_slug_for_appendix(new_number, old_slug)
            new_slug = adjusted_slug || old_slug
            new_basename = build_basename(new_number, new_slug)
            Common.log_info("#{old_name} → #{new_basename}")
          end
        rescue StandardError => e
          Common.log_warn("付録の一覧表示でエラーが発生しました: #{e}")
        end

        # 操作実行前に y/N でユーザー確認を行う
        def confirm_or_exit(action_label)
          print "  ❓ #{action_label}を実行しますか？ (y/N): "
          response = $stdin.gets&.chomp&.downcase
          return if %w[y yes].include?(response)

          Common.log_warn("#{action_label}をキャンセルしました")
          exit 0
        end

        # 正しい連番へ付け替えるための rename マップを構築する
        def build_rename_map(regular_chapters, appendix_files, effective_step, start_number = 1)
          map = {}

          regular_chapters.each_with_index do |file, index|
            old_basename = File.basename(file, '.md')
            old_number, old_slug = extract_number_and_slug(old_basename)
            new_number = format('%02d', start_number + (index * effective_step))
            next if old_number == new_number

            new_basename = build_basename(new_number, old_slug)
            map[old_basename] = build_mapping(old_basename, new_basename, file)
          end

          appendix_files.each_with_index do |file, index|
            old_basename = File.basename(file, '.md')
            old_number, old_slug = extract_number_and_slug(old_basename)
            new_number = format('%02d', index + 90)
            next if old_number == new_number

            new_slug = adjust_slug_for_appendix(new_number, old_slug) || old_slug
            new_basename = build_basename(new_number, new_slug)
            map[old_basename] = build_mapping(old_basename, new_basename, file)
          rescue StandardError => e
            Common.log_warn("付録のリネームマッピングでエラーが発生しました: #{e} (#{old_basename})")
          end

          map
        end

        # 単一ファイルに対するリネーム情報ハッシュを返す
        def build_mapping(old_basename, new_basename, file)
          old_number, old_slug = extract_number_and_slug(old_basename)
          new_number, new_slug = extract_number_and_slug(new_basename)
          {
            old_basename:,
            old_number:,
            old_slug:,
            new_number:,
            new_slug:,
            new_basename:,
            old_file: file,
            new_file: File.join(Common::CONTENTS_DIR, "#{new_basename}.md")
          }
        end

        # 連番付け直し計画を実ファイルと catalog へ反映する
        def apply_renumber(rename_map)
          Common.log_action('ファイル名変更を実行中...')
          rename_map.each do |old_basename, info|
            Common.log_info("#{old_basename}.md → #{info[:new_basename]}.md")
            FileUtils.mv(info[:old_file], info[:new_file])
            Build::CatalogUpdater.rename_chapter(old_basename, info[:new_basename])
          end

          Common.log_action('画像ディレクトリの更新中...')
          rename_map.each do |old_basename, info|
            old_dir = File.join('images', old_basename)
            next unless File.directory?(old_dir)

            new_dir = File.join('images', info[:new_basename])
            if File.exist?(new_dir)
              Common.log_warn("#{new_dir} が既に存在するため、画像ディレクトリは手動で統合してください")
              next
            end

            Common.log_info("#{old_dir} → #{new_dir}")
            FileUtils.mv(old_dir, new_dir)
          end
        end

        # 連番付け直し後の生成物クリーニングを行う
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
          number_only_from = from_entry.slug.nil?
          base_token = File.basename(new_arg.to_s.strip).sub(/\.(md|markdown)\z/i, '')
          number_only_to = !base_token.empty? && base_token.match?(/\A\d+\z/)

          if number_only_from && number_only_to
            old_number = from_entry.number
            new_number = to_entry.number
            old_md, old_slug = find_markdown_by_number(contents_dir, old_number)
            new_slug = adjust_slug_for_appendix(new_number, old_slug)
          else
            old_number = from_entry.number
            old_slug = from_entry.slug
            new_number = to_entry.number
            new_slug = if number_only_to
                         new_number.to_i.between?(90, 98) ? adjust_slug_for_appendix(new_number, old_slug) : nil
                       else
                         to_entry.slug || old_slug
                       end
            old_md = markdown_path_for(old_number, old_slug)
          end

          new_md = markdown_path_for(new_number, new_slug)
          validate_markdown_paths(old_md, new_md)

          Common.log_action("章名・番号変更: #{chapter_label(old_number, old_slug)} → #{chapter_label(new_number, new_slug)}")
          Common.log_info("Markdown: #{File.basename(old_md)} → #{File.basename(new_md)}")

          confirm_or_exit('章名・番号変更') unless options[:force] || options[:dry_run]

          if options[:dry_run]
            Common.log_info('[dry-run] ここまでの内容で変更を実行します')
            exit 0
          end

          execute_single_rename(old_md, new_md, old_number, old_slug, new_number, new_slug)
        end

        # 新しい章指定を Entry 化し、必要なら仮想 Entry を生成する
        def resolve_target_entry(resolver, new_arg, from_entry)
          return build_virtual_entry_with_slug(from_entry, new_arg) if slug_only_token?(new_arg)

          entry = resolver.resolve([new_arg]).first
          return entry if entry&.valid?

          Common.log_error("変更先の指定が不正です: #{new_arg}")
          exit 1
        end

        # スラッグのみの指定から仮想 Entry を作成して将来のファイル名を確定させる
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

        # 章番号から既存 Markdown を 1 件だけ特定し、スラッグも返す
        def find_markdown_by_number(contents_dir, chapter_number)
          pattern = File.join(contents_dir, "#{chapter_number}-*.md")
          candidates = Dir.glob(pattern)

          if candidates.empty?
            numeric_file = File.join(contents_dir, "#{chapter_number}.md")
            if File.exist?(numeric_file)
              [numeric_file, nil]
            else
              Common.log_error("#{chapter_number}章のファイルが見つかりません")
              exit 1
            end
          elsif candidates.length > 1
            Common.log_error("#{chapter_number}章のファイルが複数見つかりました:")
            candidates.each { |f| Common.log_info("- #{File.basename(f)}") }
            exit 1
          else
            old_md = candidates.first
            old_basename = File.basename(old_md, '.md')
            _, old_slug = old_basename.split('-', 2)
            [old_md, old_slug]
          end
        end

        # 付録番号が変化する際に appendix-a 等のスラッグを付け替える
        def adjust_slug_for_appendix(new_number, old_slug)
          return nil if old_slug.nil? || old_slug.empty?

          if new_number.to_i.between?(90, 98) && old_slug =~ /appendix-[a-z]/
            new_letter = Common.appendix_number_to_letter(new_number)
            old_slug.sub(/appendix-[a-z]/, "appendix-#{new_letter}")
          else
            old_slug
          end
        end

        # リネーム対象と変更先の Markdown 存在状態を検証する
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

        # 単一章の Markdown/画像/catalog を新しいベース名へ切り替える
        def execute_single_rename(old_md, new_md, old_number, old_slug, new_number, new_slug)
          FileUtils.mv(old_md, new_md)
          Common.log_success('Markdownの変更が完了しました')

          old_basename = build_basename(old_number, old_slug)
          new_basename = build_basename(new_number, new_slug)
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

        # 章リネーム後に残る生成物 (HTML) を削除する
        def cleanup_generated_files(old_number, old_slug)
          targets = [
            File.join('.', "#{build_basename(old_number, old_slug)}.html")
          ]
          targets.each do |file|
            next unless File.exist?(file)

            File.delete(file)
            Common.log_info("#{File.basename(file)} を削除")
          end
        end

        # トークンがスラッグのみか（冒頭が数字で始まらないか）を判定する
        def slug_only_token?(token)
          base = normalized_token_base(token)
          return false if base.empty?

          !base.match?(/\A\d/)
        end

        # ファイル名トークンから拡張子を落とした基底文字列を取得する
        def normalized_token_base(token)
          base = File.basename(token.to_s.strip)
          base.sub(/\.(md|markdown)\z/i, '')
        end

        # 指定トークンから CLI 用のスラッグ文字列を生成する
        def normalize_new_slug(token)
          base = normalized_token_base(token)
          slug = base.downcase.tr(' ', '-')
          slug = slug.gsub(/[^a-z0-9._-]+/, '-')
          slug = slug.gsub(/-+/, '-')
          slug = slug.gsub(/\A-|-(md|markdown)\z/i, '')
          slug
        end

        # ベース名から章番号とスラッグ（任意）を取り出す
        def extract_number_and_slug(basename)
          number, slug = basename.split('-', 2)
          slug = nil if slug.nil? || slug.empty?
          [number, slug]
        end

        # 章番号とスラッグから標準的な basename を構築する
        def build_basename(number, slug)
          slug && !slug.to_s.empty? ? "#{number}-#{slug}" : number.to_s
        end

        # basename をもとに contents 配下の Markdown パスを返す
        def markdown_path_for(number, slug)
          File.join(Common::CONTENTS_DIR, "#{build_basename(number, slug)}.md")
        end

        # ログ表示用の章ラベルを生成する
        def chapter_label(number, slug)
          slug && !slug.to_s.empty? ? "#{number}-#{slug}" : number
        end
      end
    end
  end
end

