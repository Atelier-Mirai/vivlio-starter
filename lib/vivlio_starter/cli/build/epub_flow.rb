# frozen_string_literal: true

require 'fileutils'
require_relative 'epub_builder'

module VivlioStarter
  module CLI
    module Build
      # ================================================================
      # Build::EpubFlow — EPUB / Kindle ビルドのオーケストレーション（§1-3 方式B）
      # ================================================================
      # 生成済みの章 HTML を再利用して EPUB（クリーン）/ Kindle（KPF）を生成する一連の
      # フローを担う。P2 で pipeline.rb から本フローへ移設した。
      #
      # P4 段階 3: dedup の破壊的書換はワークスペース pdf/ 配下のコピーに閉じたため、
      # 「dedup 前スナップショット」（旧 snapshot_pre_dedup!・⑦）は不要になった。
      # 章 HTML は html/（常にクリーンな原本）からルートへ展開して現行の EPUB 経路を
      # そのまま動かす（暫定ブリッジ）。段階 4（epub/・kindle/ 消費者 dir 化）で
      # ブリッジとフレーバ間スナップショットは撤去される。
      # ================================================================
      class EpubFlow
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param targets [Build::Targets] 出力ターゲット（epub / kindle の有無を参照）
        # @param options [Hash] ビルドオプション（--no-clean 判定に options[:clean] を参照）
        def initialize(entries, targets, options)
          @entries = Array(entries)
          @targets = targets
          @options = options
        end

        # EPUB / Kindle 生成のメインフロー。
        # クリーン EPUB（:epub）と Kindle（:kindle）の両方が対象の場合、クリーンを先に確定し、
        # その章 HTML を Kindle の rewrite が破壊しないよう、クリーン処理前の章 HTML を
        # スナップショットしておき、Kindle ビルド前に復元してフレーバ間の相互汚染を防ぐ。
        def run!
          Common.log_action('[generate epub] EPUB を生成します…')

          # --- Phase: EPUB 用カバー画像生成 ---
          generate_cover_if_needed

          # ワークスペース html/ のクリーンな原本（dedup 非通過）をルートへ展開する。
          # リフロー型 EPUB は「全 † / 全出現リンク」を持つべきところ、pdf/ に閉じた
          # dedup の影響を構造的に受けない（P4 §3.1: kindle/ ・epub/ は html/ 直系）。
          stage_root_htmls_from_workspace!

          # 両フレーバ同時のときだけ、クリーン処理が書き換える前の章 HTML を退避する。
          snapshot = (targets.epub && targets.kindle) ? snapshot_chapter_htmls : nil

          build_flavor(:epub) if targets.epub

          return unless targets.kindle

          restore_chapter_htmls(snapshot) if snapshot
          build_flavor(:kindle)
        end

        private

        attr_reader :entries, :targets, :options

        # 1 フレーバ分の EPUB を生成する（クリーンは .epub、Kindle は中間 .epub→.kpf）。
        def build_flavor(flavor)
          # --- Phase: EPUB 用 entries.js 生成 ---
          epub_htmls = Build::EpubBuilder.generate_epub_entries!('.', entries, flavor:)
          if epub_htmls.empty?
            Common.log_warn("[generate epub] EPUB 対象 HTML がありません。スキップします。（flavor: #{flavor}）")
            return
          end

          # --- Phase: EPUB 用 vivliostyle.config.js 生成 ---
          Build::EpubBuilder.generate_epub_config!(flavor:)

          # --- Phase: Vivliostyle build ---
          # Kindle は KPF 変換の入力にすぎないため中間 EPUB（…-kindle.epub）として作る（§1-4）。
          target_name = flavor == :kindle ? Common.generate_kindle_epub_filename : Common.generate_epub_filename
          EpubCommands.execute_epub({}, target_name)

          # --- Phase: EPUB 内 CSS サニタイズ（@page マージンボックス除去・webp url() は kindle のみ） ---
          Build::EpubBuilder.sanitize_epub_css!(target_name, flavor:) if File.exist?(target_name)

          # --- Phase: content.opf の数字始まり id を NCName 準拠へ修正 ---
          Build::EpubBuilder.sanitize_epub_opf_ids!(target_name) if File.exist?(target_name)

          # --- Phase: EPUB identifier 安定化 ---
          Build::EpubBuilder.stabilize_epub_identifier!(target_name) if File.exist?(target_name)

          # --- Phase: 中間ファイルクリーンアップ（entries/config/output.epub） ---
          Build::EpubBuilder.cleanup!

          # --- Phase: Kindle は KPF へ変換（§1-7） ---
          run_kpf(target_name) if flavor == :kindle
        end

        # P4 段階 3 暫定ブリッジ: ワークスペース html/ の全 HTML をルートへ展開する。
        # asset_prefix（../../../../）を剥がすことで、従来ルートに置かれていた
        # 中間 HTML と同一の内容になり、既存の EPUB 経路（ルート基準の rewrite・
        # copyAsset excludes・book-settings.css 同梱）が無変更で成立する。
        # 展開したルート HTML は final clean の既存パターン（*.html）が掃除する。
        # 段階 4 で「epub/ ・kindle/ への選択コピー＋entryContext」方式に置き換える。
        def stage_root_htmls_from_workspace!
          Dir.glob(File.join(Common::BUILD_HTML_DIR, '*.html')).each do |src|
            content = File.read(src, encoding: 'utf-8').gsub(Common::ASSET_PREFIX, '')
            File.write(File.basename(src), content, encoding: 'utf-8')
          end
        end

        # クリーン処理前の章 HTML（パス→内容）を退避する。
        def snapshot_chapter_htmls
          Build::EpubBuilder.collect_epub_htmls('.', entries)
                            .each_with_object({}) { |path, acc| acc[path] = File.read(path, encoding: 'utf-8') }
        end

        # 退避した章 HTML を書き戻し、Kindle ビルドをクリーンな状態から始める。
        def restore_chapter_htmls(snapshot)
          snapshot.each { |path, content| File.write(path, content) }
        end

        # Kindle 中間 EPUB を KPF へ変換し、成功時は中間 EPUB を削除する（§1-7）。
        # kindlepreviewer 未導入時は EpubBuilder 側が警告して中間 EPUB を残す（ビルドは継続）。
        def run_kpf(kindle_epub)
          kpf_name = Common.generate_kpf_filename
          converted = Build::EpubBuilder.convert_epub_to_kpf!(kindle_epub, kpf_name)
          # 成功時のみ中間 EPUB を片付ける。--no-clean では検証用に残す（§1-4）。
          FileUtils.rm_f(kindle_epub) if converted && options[:clean] != false && File.exist?(kindle_epub)
        end

        # EPUB 用カバー画像を生成（cover_{theme}.jpg が未生成の場合のみ）
        def generate_cover_if_needed
          unless Common.validate_cover_settings
            Common.log_warn('[EPUB] カバー設定が無効なためカバー生成をスキップします')
            return
          end

          unless Common.epub_embed?
            Common.log_info('[EPUB] カバー埋め込みが無効なためスキップします')
            return
          end

          config = Common::CONFIG
          cover_path = Build::EpubBuilder.resolve_cover_image_path(config)

          if cover_path && File.exist?(cover_path)
            Common.log_info("[EPUB] カバー画像は既に存在します: #{cover_path}")
            return
          end

          Common.log_action('[EPUB] カバー画像を生成しています…')
          CoverCommands.ensure_cover_files_for_build!
        end
      end
    end
  end
end
