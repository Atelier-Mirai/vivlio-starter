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
      # dedup 隔離（⑦）のため、backlink dedup 直前の章 HTML スナップショットを保持する
      # 必要があり、その退避（snapshot_pre_dedup!）と EPUB 生成（run!）は別々のパイプライン
      # ステップから呼ばれる。両ステップが同一インスタンスを共有できるよう、pipeline 側は
      # 本フローを 1 度だけ生成して使い回す。
      # ================================================================
      class EpubFlow
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param targets [Build::Targets] 出力ターゲット（epub / kindle の有無を参照）
        # @param options [Hash] ビルドオプション（--no-clean 判定に options[:clean] を参照）
        def initialize(entries, targets, options)
          @entries = Array(entries)
          @targets = targets
          @options = options
          @pre_dedup_snapshot = nil
        end

        # backlink dedup 直前の章 HTML を退避する（⑦）。
        # dedup は共有の章 HTML を「PDF ページ依存」で破壊的に書き換える（同一ページ内の
        # 2 回目以降の † / index-term を削除）。EPUB はこの dedup 済み HTML を再利用すると
        # †・索引リンクが間引かれてしまうため、dedup 前の状態を保持し run! で復元する。
        # docs/specs/epub-backlink-dedup-isolation-spec.md ⑦ を参照。
        def snapshot_pre_dedup!
          @pre_dedup_snapshot = snapshot_chapter_htmls
        end

        # EPUB / Kindle 生成のメインフロー。
        # クリーン EPUB（:epub）と Kindle（:kindle）の両方が対象の場合、クリーンを先に確定し、
        # その章 HTML を Kindle の rewrite が破壊しないよう、クリーン処理前の章 HTML を
        # スナップショットしておき、Kindle ビルド前に復元してフレーバ間の相互汚染を防ぐ。
        def run!
          Common.log_action('[generate epub] EPUB を生成します…')

          # --- Phase: EPUB 用カバー画像生成 ---
          generate_cover_if_needed

          # dedup 前の章 HTML を復元して EPUB を dedup（backlink dedup）から隔離する（⑦）。
          # PDF（閲覧用・入稿用）は dedup 済み HTML で既に生成済み。リフロー型 EPUB は
          # 「全 † / 全出現リンク」を持つべきなので、dedup 前の状態へ戻してからビルドする。
          restore_chapter_htmls(@pre_dedup_snapshot) if @pre_dedup_snapshot

          # 両フレーバ同時のときだけ、クリーン処理が書き換える前の章 HTML を退避する。
          # 上で pre-dedup 状態へ戻した後に退避するため、Kindle も dedup 前から始まる。
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
