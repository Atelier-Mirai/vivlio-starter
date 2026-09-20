# frozen_string_literal: true

require 'fileutils'
require 'yaml'

require_relative 'common'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'import/image_processor'
require_relative 'import/yaml_processor'
require_relative 'import/re_parser'
require_relative 'import/re_renderer'
require_relative 'import/re_report'
require_relative 'units'
require_relative 'upgrade'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: import（Re:VIEW Starter からの移行）
    # ================================================================
    # 責務:
    #   Re:VIEW Starter プロジェクトから vivlio-starter への移行処理を行う。
    #
    # 処理内容:
    #   1. 既存ディレクトリ（contents/, images/, codes/）の削除
    #   2. .re → .md 直変換（ReParser → ReRenderer）
    #   3. ラベル ID の一意化（Vivlio のラベルは本全体で一意）
    #   4. 画像の WebP 変換（ResizeCommands 使用）
    #   5. source/ → codes/ コピー
    #   6. catalog.yml / config.yml の変換
    #
    # なぜ直変換か:
    #   かつては Re:VIEW Starter 同梱の Ruby（review 2.5 固定）に `rake markdown`
    #   させ、その出力を追従変換していた。Starter の開発は停止しており、Ruby が
    #   進んで 2.5 が動かなくなった時点でこの経路は丸ごと死ぬ。著者の .re を直接
    #   読めば何年後でも取り込める（re-direct-import-spec.md §0）。
    #
    # 依存:
    #   - ResizeCommands: 画像最適化
    #   - Common: ログ出力
    # ================================================================
    module ImportCommands
      module_function

      # 取り込みで空に戻す著者辞書（原稿を入れ替えるので中身が意味を失う）
      INDEX_DICTIONARY_FILES = [
        File.join('config', 'index_glossary_terms.yml'),
        File.join('config', 'index_glossary_rejected.yml')
      ].freeze

      # 判型が読めないときの版面幅（mm）。B5 標準相当
      DEFAULT_TEXT_WIDTH_MM = 137.0

      PAGE_PRESETS_FILE = 'config/page_presets.yml'

      # Re:VIEW Starter の表紙指定と、取り込み先のマスター画像の対応
      COVER_SIDES = [
        { key: 'frontcover_pdffile', master: CoverCommands::FRONTCOVER_MASTER, label: '表表紙' },
        { key: 'backcover_pdffile', master: CoverCommands::BACKCOVER_MASTER, label: '裏表紙' }
      ].freeze

      # メイン実行メソッド
      def execute_import(starter_dir, options = {})
        @options = options
        @starter_dir = File.expand_path(starter_dir)

        validate_starter_directory!
        return 1 unless confirm_cleanup_or_force?

        cleanup_existing_directories!
        reset_index_dictionaries!
        convert_re_to_md!
        Import::ImageProcessor.convert_to_webp!(@starter_dir)
        copy_source_to_codes!
        Import::YamlProcessor.convert_catalog!(@starter_dir)
        convert_config_with_cover!

        # 実績を添えて既定ログレベルでも報告する（vs build からは呼ばれない独立コマンド）
        chapters = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).size
        Common.log_result("インポートしました（contents/ に #{chapters} 章）", status: :success)
        0
      rescue StandardError => e
        Common.log_error("インポート中にエラーが発生しました: #{e.message}")
        Common.log_error(e.backtrace.join("\n")) if ENV['VS_DEBUG']
        1
      end

      # 取り込み元の検証。
      #
      # 直変換では Starter 同梱の Ruby を動かさないので、要るのは catalog.yml と
      # 原稿ディレクトリだけ——結果として素の Re:VIEW プロジェクトも取り込める。
      def validate_starter_directory!
        raise "取り込み元のディレクトリが見つかりません: #{@starter_dir}" unless Dir.exist?(@starter_dir)

        catalog = File.join(@starter_dir, 'catalog.yml')
        raise "catalog.yml が見つかりません: #{catalog}" unless File.exist?(catalog)

        re_dir = review_contents_dir
        return if Dir.exist?(re_dir) && Dir.glob(File.join(re_dir, '*.re')).any?

        raise "原稿（.re）が見つかりません: #{re_dir}"
      end

      # 確認プロンプトまたは --force
      def confirm_cleanup_or_force?
        return true if @options[:force]

        dirs_to_delete = %w[contents images codes].select do |dir|
          Dir.exist?(dir)
        end

        return true if dirs_to_delete.empty?

        Common.log_warn('以下のディレクトリを削除してインポートを行います:')
        dirs_to_delete.each { |d| Common.log_warn("  - #{d}/") }

        # 非対話（パイプ/CI）では質問せず安全側に倒す
        return false unless $stdin.tty?

        Common.confirm?('続行しますか？')
      end

      # 取り込み先ディレクトリを空の状態で用意する。
      #
      # 「あれば作り直す」ではなく必ず作る——後段の move / cp は入れ物があることを
      # 前提にしており、contents/ を持たないプロジェクトへ取り込むと
      # `No such file or directory @ rb_file_s_rename` で落ちていた。
      def cleanup_existing_directories!
        %w[contents images codes].each do |dir|
          FileUtils.rm_rf(dir)
          FileUtils.mkdir_p(dir)
        end
      end

      # 索引・用語集の辞書を空に戻す。
      #
      # 辞書は「いま消した原稿」を説明するデータなので、contents/ と一緒に片付ける。
      # 残すと雛形の見本原稿の語が取り込んだ本の用語集・索引に載り、ビルドのたびに
      # 「原稿のどこにも出現しません」が並ぶ。空の初期形は vs upgrade が辞書の無い
      # プロジェクトへ配るものと同じ。取り込んだ原稿からは vs index:auto で作り直す。
      def reset_index_dictionaries!
        INDEX_DICTIONARY_FILES.each do |relative|
          next unless File.exist?(relative)

          File.write(relative, UpgradeCommands::EMPTY_DICTIONARY_TEMPLATES.fetch(relative), encoding: 'utf-8')
        end
        Common.log_info('  索引・用語集の辞書を空にしました（vs index:auto で取り込んだ原稿から作り直せます）')
      end

      # 章ひとつぶんの変換結果
      Chapter = Data.define(:basename, :markdown, :labels, :lines)

      # .re → .md の直変換。
      #
      # catalog.yml に載っている章だけを変換する。Re:VIEW では catalog に載せて
      # いない .re は原稿ではない（書きかけ・没の章がそのまま残っている。実測:
      # book_c は 26 個の .re のうち catalog にあるのは 7 個だけだった）。
      def convert_re_to_md!
        Common.log_action('[Step 2] 原稿（.re）を変換します')

        report = Import::ReReport.new
        basenames = catalog_chapters
        raise 'catalog.yml から原稿の一覧を読み取れませんでした' if basenames.empty?

        chapters = unify_labels(basenames.filter_map { render_chapter(it, report) }, report)
        write_chapters!(chapters)

        report.emit!
        report.summary(chapters: chapters.size, lines: chapters.sum(&:lines))
      end

      # catalog.yml に並ぶ原稿の basename（拡張子なし）を出現順に返す
      def catalog_chapters
        catalog = YAML.safe_load_file(File.join(@starter_dir, 'catalog.yml'), permitted_classes: [Symbol])
        return [] unless catalog.is_a?(Hash)

        %w[PREDEF CHAPS APPENDIX POSTDEF].flat_map do |section|
          # 部（`- 初級編:` のあとに章が並ぶ）は Hash として現れる
          Array(catalog[section]).flat_map { it.is_a?(Hash) ? it.values.flatten : it }
        end.compact.map { File.basename(it.to_s, '.re') }
      end

      def render_chapter(basename, report)
        path = File.join(review_contents_dir, "#{basename}.re")

        unless File.exist?(path)
          Common.log_warn("  #{basename}.re が見つかりません（catalog.yml には載っています）。",
                          detail: '対処: 原稿を用意するか、catalog.yml から行を外してください。')
          return nil
        end

        nodes = Import::ReParser.parse(path, report:)
        renderer = Import::ReRenderer.new(report:, file: "#{basename}.re", words: starter_words,
                                          text_width_mm: text_area_width_mm)
        Chapter.new(basename:, markdown: renderer.render(nodes), labels: renderer.labels.uniq,
                    lines: File.foreach(path).count)
      end

      # Vivlio のラベルは本全体で一意（Re:VIEW は章内で一意ならよい）。
      # 2 つ以上の章に現れた ID だけ、章 basename を前置して改名する
      # ——重複しなかった ID は著者が覚えている名前のまま残す。
      def unify_labels(chapters, report)
        owners = Hash.new { |hash, key| hash[key] = [] }
        chapters.each { |chapter| chapter.labels.each { |label| owners[label] << chapter.basename } }
        duplicated = owners.select { |_, list| list.uniq.size > 1 }.keys
        return chapters if duplicated.empty?

        chapters.map { rename_labels(it, duplicated, report) }
      end

      def rename_labels(chapter, duplicated, report)
        targets = chapter.labels & duplicated
        return chapter if targets.empty?

        markdown = targets.inject(chapter.markdown) do |text, label|
          report.count(:relabel)
          text.gsub(/@#{Regexp.escape(label)}(?![\w-])/, "@#{chapter.basename}-#{label}")
        end

        report.degraded('label', file: "#{chapter.basename}.re", line: 0,
                                 message: "章をまたいで重複したラベル #{targets.join('、')} を " \
                                          "#{chapter.basename}-… へ改名しました。",
                                 detail: 'Vivlio Starter のラベルは本全体で一意である必要があります（クロスリファレンスの章）。')
        chapter.with(markdown:)
      end

      def write_chapters!(chapters)
        chapters.each do |chapter|
          File.write(File.join(Common::CONTENTS_DIR, "#{chapter.basename}.md"), chapter.markdown, encoding: 'utf-8')
        end
      end

      # Re:VIEW の原稿ディレクトリ（config.yml の contentdir。既定は contents）
      def review_contents_dir
        config = File.join(@starter_dir, 'config.yml')
        dir = (YAML.safe_load_file(config, permitted_classes: [Symbol])['contentdir'] if File.exist?(config))
        File.join(@starter_dir, dir.to_s.strip.empty? ? 'contents' : dir.to_s.strip)
      end

      # `@<w>{key}` の展開に使う辞書（Starter の単語展開機能）
      def starter_words
        @starter_words ||= begin
          file = File.join(@starter_dir, 'words.yml')
          File.exist?(file) ? (YAML.safe_load_file(file) || {}) : {}
        end
      end

      # 版面幅（mm）＝ 紙幅 − ノド − 小口。//sideimage の mm 指定を比率へ直す基準
      def text_area_width_mm
        @text_area_width_mm ||= begin
          preset = target_page_preset
          width = Units.length_to_mm(Common::PAGE_SIZES.dig(preset&.fetch('size', nil).to_s.upcase, :width))
          inner = Units.length_to_mm(preset&.fetch('margin_inner', nil))
          outer = Units.length_to_mm(preset&.fetch('margin_outer', nil))
          width&.positive? && inner && outer ? [width - inner - outer, 1.0].max : DEFAULT_TEXT_WIDTH_MM
        end
      end

      # 取り込み先で使う判型プリセットの中身
      def target_page_preset
        starter_config = File.join(@starter_dir, 'config-starter.yml')
        return nil unless File.exist?(starter_config) && File.exist?(PAGE_PRESETS_FILE)

        pagesize = YAML.safe_load_file(starter_config, permitted_classes: [Symbol]).dig('starter', 'pagesize')
        name = Import::YamlProcessor::PAGE_PRESETS[pagesize.to_s.strip.upcase]
        return nil unless name

        # プリセットは YAML アンカー（`<<: *b5_std`）で共通部を引くため aliases が要る
        YAML.safe_load_file(PAGE_PRESETS_FILE, aliases: true)[name]
      end

      # source/ → codes/ コピー
      def copy_source_to_codes!
        starter_source = File.join(@starter_dir, 'source')
        return unless Dir.exist?(starter_source)

        FileUtils.cp_r(Dir.glob(File.join(starter_source, '*')), 'codes/')
      end

      # config.yml / config-starter.yml の変換と表紙 PDF の取り込み
      #
      # config-starter.yml の frontcover_pdffile / backcover_pdffile を
      # covers/ のマスター画像へ変換し、book.yml の output.cover を master に揃える。
      def convert_config_with_cover!
        # 基本的な設定変換
        Import::YamlProcessor.convert_config!(@starter_dir)

        # 表紙 PDF の処理
        starter_config_starter = File.join(@starter_dir, 'config-starter.yml')
        return unless File.exist?(starter_config_starter)

        config_starter = YAML.safe_load_file(starter_config_starter, permitted_classes: [Symbol])
        imported = COVER_SIDES.map { import_cover_side!(config_starter, it) }
        return if imported.none?

        Import::YamlProcessor.use_master_cover!
      end

      # 表紙 1 面を取り込む。
      #
      # 取り込めなかった面は雛形の見本画像がそのまま本の表紙になってしまうので、
      # 差し替え先のパスを添えて知らせる。
      #
      # @return [Boolean] 取り込めたら true
      def import_cover_side!(config_starter, side)
        imported = Import::ImageProcessor.import_master_cover!(
          @starter_dir, config_starter.dig('starter', side[:key]),
          master: side[:master], label: side[:label]
        )
        return true if imported

        Common.log_warn("  #{side[:label]}は雛形の見本画像のままです。",
                        detail: "対処: covers/#{side[:master]} を自分の#{side[:label]}画像に置き換えてください。")
        false
      end
    end
  end
end
