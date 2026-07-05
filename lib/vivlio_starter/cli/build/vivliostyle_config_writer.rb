# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/build/vivliostyle_config_writer.rb
# ================================================================
# 責務:
#   ビルドパイプライン用の「用途別 entries / vivliostyle config」を生成する（P4 §3.2）。
#
# 設計背景（P4: 固定名単一資源の廃止）:
#   従来はルートの entries.js（固定名・単一）を全ビルドが共有し、前付・奥付の
#   ビルドが本文用 entries.js を上書き →「上書きされたから再生成」という病理を
#   生んでいた。用途ごとに entries.<name>.js / vivliostyle.config.<name>.js を
#   .cache/vs/build/pdf/ へ生成し `--config` で渡すことで、上書き衝突が概念ごと
#   消滅する。EPUB 経路の既存方式（entries.epub.js ＋ vivliostyle.config.epub.js）の
#   PDF 側への一般化。
#
# パス表記の規則（着手前実験 E1 で確定・P4 §6.1）:
#   - config 内の entry / output / workspaceDir はすべて cwd（プロジェクトルート）
#     相対で書く。実行 cwd はルート固定（node_modules 解決のため）。
#   - entries ファイルの読込（ESM import）だけは config ファイル基準
#     → entries は config と同居させ './entries.<name>.js' で参照する。
#   - PDF 消費者は entryContext を使わない（E1: dev サーバの 404 が SUCCESS で
#     完走し様式欠落 PDF が黙って生まれるため、この経路は封じる）。
#   - single-doc（-d）は生成 config と併用不可（E5）。パイプラインでは使わない。
#
# メタデータ解決（title/author/language/size）は本モジュールに集約し、
# EPUB config（EpubBuilder.generate_epub_config!・P3-4 §2.6）と共用する。
# かつて本モジュールが全文生成していたルートの vivliostyle.config.js は、
# 手動フロー（vs entries → vs pdf）の実体消滅に伴い撤去した
# （docs/specs/vivlioverso-manual-flow-removal-spec.md）。
# ================================================================

require 'fileutils'

module VivlioStarter
  module CLI
    module Build
      # 用途別 entries / vivliostyle config の生成モジュール
      module VivliostyleConfigWriter
        module_function

        # entries と config をペアで生成する。
        # @param name [String] 用途名（'sections' / 'front' / 'colophon' / 'single' 等）
        # @param entry_htmls [Array<String>] エントリ HTML（cwd 相対パス・結合順）
        # @param output [String] 出力 PDF（cwd 相対パス）
        # @param dir [String] 生成先ディレクトリ（既定: ワークスペースの pdf/）
        # @return [String] 生成した config ファイルのパス
        def write!(name:, entry_htmls:, output:, dir: Common::BUILD_PDF_DIR)
          FileUtils.mkdir_p(dir)
          entries_file = File.join(dir, "entries.#{name}.js")
          write_entries!(entries_file, entry_htmls)
          write_config_only!(name:, entries_name: name, output:, dir:)
        end

        # 既存の entries.<entries_name>.js を共用し、config だけを生成する
        # （入稿用: 本文 entries を共用して出力ファイル名だけ差し替える・P4 §3.2）。
        # @return [String] 生成した config ファイルのパス
        def write_config_only!(name:, entries_name:, output:, dir: Common::BUILD_PDF_DIR)
          FileUtils.mkdir_p(dir)
          config_file = File.join(dir, "vivliostyle.config.#{name}.js")
          File.write(config_file, config_content(entries_basename: "entries.#{entries_name}.js", output:),
                     encoding: 'utf-8')
          Common.log_info("[config-writer] #{config_file} を生成しました")
          config_file
        end

        # entries ファイルを書き出す（EntriesCommands の ESM 形式と同一）。
        # path は cwd 相対のまま './' を前置する（E1: entry は cwd 基準で解決される）。
        def write_entries!(path, entry_htmls)
          entries = entry_htmls.map { EntriesCommands.build_entry(it) }
          File.open(path, 'w') do |f|
            f.puts 'export default ['
            entries.each_with_index do |entry, i|
              f.puts '  {'
              f.puts %(    "path": "#{entry[:path]}",)
              f.puts %(    "title": "#{entry[:title]}")
              f.puts "  }#{',' if i < entries.length - 1}"
            end
            f.puts ']'
          end
          path
        end

        # config 全文を組み立てる。メタデータの解決（resolve_title/author/language・
        # EpubBuilder.resolve_page_size）は EPUB config（P3-4 §2.6 で
        # EpubBuilder.generate_epub_config! が本モジュールのリゾルバを呼ぶ）と共通。
        def config_content(entries_basename:, output:)
          # JS 単一引用符文字列向けエスケープ。ブロック形で返すことで gsub の置換文字列
          # 内バックリファレンス（\' = 後方一致）解釈を避け、\ と ' を確実に \ で退避する。
          esc = ->(s) { s.to_s.gsub(/[\\']/) { |c| "\\#{c}" } }

          <<~JS
            import entries from './#{entries_basename}';

            // @ts-check
            // ビルドパイプライン専用設定ファイル（自動生成・編集不要）
            /** @type {import('@vivliostyle/cli').VivliostyleConfigSchema} */
            const vivliostyleConfig = {
              title: '#{esc.call(resolve_title)}',
              author: '#{esc.call(resolve_author)}',
              language: '#{esc.call(resolve_language)}',
              size: '#{esc.call(EpubBuilder.resolve_page_size(Common::CONFIG))}',
              readingProgression: 'ltr',
              workspaceDir: '#{Common::BUILD_DIR}/.vivliostyle',
              entry: entries,
              output: [
                './#{output}'
              ]
            };

            export default vivliostyleConfig;
          JS
        end

        # book.title（明示）→ main_title + subtitle 合成 → プレースホルダ。
        def resolve_title
          book = Common::CONFIG.book
          title_raw = book.title.to_s.strip
          return title_raw unless title_raw.empty?

          combined = [book.main_title, book.subtitle].compact.map { it.to_s.strip }.reject(&:empty?).join(' ')
          combined.empty? ? '書籍タイトル' : combined
        end

        # vivliostyle 11 の config スキーマは author / language に 1 文字以上を
        # 要求するため、未設定はプレースホルダへ寄せる（EPUB 経路と同一規則）。
        def resolve_author
          author = Common::CONFIG.book.author.to_s.strip
          author.empty? ? '著者名' : author
        end

        def resolve_language
          language = Common::CONFIG.book.language.to_s.strip
          language.empty? ? 'ja' : language
        end
      end
    end
  end
end
