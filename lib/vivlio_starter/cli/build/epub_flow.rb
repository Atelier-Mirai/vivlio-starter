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
      # P4 段階 4: 各フレーバは専用の消費者 dir（.cache/vs/build/epub/・kindle/）で
      # 完結する。html/（常にクリーンな原本・dedup 非通過）から prefix を剥がして
      # ステージし、参照資産を dir 内へローカライズ、entryContext 指定の生成 config で
      # ビルドする（実験 E2 の確定案）。フレーバごとに dir が分かれるため、
      # 旧来の「dedup 前スナップショット」「epub⇄kindle フレーバ間スナップショット」は
      # 構造的に不要となり撤去した（完了条件 1）。
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
        # 各フレーバは独立した消費者 dir でビルドされるため相互汚染は構造的に起こらない。
        def run!
          Common.log_action('[generate epub] EPUB を生成します…')

          # --- Phase: EPUB 用カバー画像生成 ---
          generate_cover_if_needed

          build_flavor(:epub) if targets.epub
          build_flavor(:kindle) if targets.kindle
        end

        private

        attr_reader :entries, :targets, :options

        # フレーバごとの消費者 dir（P4 §3.1: epub/ ・kindle/ は html/ 直系）。
        def consumer_dir(flavor)
          flavor == :kindle ? Common::BUILD_KINDLE_DIR : Common::BUILD_EPUB_DIR
        end

        # 1 フレーバ分の EPUB を生成する（クリーンは .epub、Kindle は中間 .epub→.kpf）。
        def build_flavor(flavor)
          dir = consumer_dir(flavor)

          # --- Phase: html/ → 消費者 dir へステージ（asset_prefix 剥がし） ---
          Build::EpubBuilder.stage_consumer_htmls!(dir)

          # --- Phase: EPUB 用 entries.js 生成（フレーバ別 rewrite を含む） ---
          epub_htmls = Build::EpubBuilder.generate_epub_entries!(dir, entries, flavor:)
          if epub_htmls.empty?
            Common.log_warn("[generate epub] EPUB 対象 HTML がありません。スキップします。（flavor: #{flavor}）")
            return
          end

          # --- Phase: 参照資産を消費者 dir 内へローカライズ（E2: パッケージルート＝dir） ---
          Build::EpubBuilder.localize_assets!(dir, flavor:)

          # --- Phase: EPUB 用 vivliostyle.config.js 生成（entryContext = dir） ---
          config_path = Build::EpubBuilder.generate_epub_config!(flavor:, dir:)

          # --- Phase: Vivliostyle build ---
          # Kindle は KPF 変換の入力にすぎないため中間 EPUB（…-kindle.epub）として作る（§1-4）。
          target_name = flavor == :kindle ? Common.generate_kindle_epub_filename : Common.generate_epub_filename
          EpubCommands.execute_epub({}, target_name, config_path:,
                                                     output_path: File.join(dir, Build::EpubBuilder::EPUB_OUTPUT_FILE))

          # --- Phase: EPUB 内 CSS サニタイズ（@page マージンボックス除去・webp url() は kindle のみ） ---
          Build::EpubBuilder.sanitize_epub_css!(target_name, flavor:) if File.exist?(target_name)

          # --- Phase: content.opf の数字始まり id を NCName 準拠へ修正 ---
          Build::EpubBuilder.sanitize_epub_opf_ids!(target_name) if File.exist?(target_name)

          # --- Phase: EPUB identifier 安定化 ---
          Build::EpubBuilder.stabilize_epub_identifier!(target_name) if File.exist?(target_name)

          # --- Phase: Kindle は KPF へ変換（§1-7） ---
          # 中間物（entries/config/資産コピー）は消費者 dir 内にあり final clean が
          # ワークスペースごと掃除する（--no-clean 時はデバッグ資材として残る）。
          run_kpf(target_name) if flavor == :kindle
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

          cover_path = Build::EpubBuilder.resolve_cover_image_path

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
