# frozen_string_literal: true

require 'fileutils'
require_relative '../doctor'
require_relative '../entries'
require_relative '../code_line_blocks'
require_relative '../units'
require_relative '../pre_process/frontmatter_generator'
require_relative '../pre_process/generated_asset_cache'
require_relative '../css/entry_writer'
require_relative 'output_target'
require_relative 'targets/epub'
require_relative 'targets/kindle'
require_relative 'transforms/runner'
require_relative 'finalizers/book'
require_relative 'epub/workspace'
require_relative 'epub/stylesheets'
require_relative 'epub/images'
require_relative 'epub/config'
require_relative 'epub/opf'
require_relative 'epub/kpf'

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
        #
        # 表紙画像はここでは作らない。PDF 枝と同じ `.cache/vs/covers/` へ書くため、
        # 枝を並列に走らせると衝突する——生成は共通前段の `prepare cover assets` が
        # 1 回だけ行う（build-target-parallelization-spec.md §3.2）。
        def run!
          Common.log_action('[generate epub] EPUB を生成します…')

          build_target(OutputTarget.for(:epub)) if targets.epub
          build_target(OutputTarget.for(:kindle)) if targets.kindle
        end

        # 出力先のワークスペースの HTML を、出力先の宣言のとおりに書き換える
        # （v2-architecture-spec.md §4.3 の流れの 2〜4）。
        #
        # 平らな CSS を書いて link を付け替えるのが先で、変換（1 ページずつ）、本全体の段と続く。
        # 本全体の段の要素ごとの判定は、Kindle の印（vs-kindle）と EPUB 用に足す要素が付いた後で
        # なければ Kindle の規則を見落とすので、変換の後に置く。
        #
        # @param target [OutputTarget] 出力先の宣言（:epub / :kindle）
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param dir [String] 出力先のワークスペース（既定は宣言の値。テストは一時ディレクトリを渡す）
        # @return [Array<String>] EPUB に含める HTML のパスの配列（対象が無ければ空）
        def self.prepare_pages!(target, entries, dir: target.workspace)
          Common.log_action("[EPUB] entries.epub.js を生成しています…（flavor: #{target.id}）")

          pages = Epub::Config.collect_epub_htmls(dir, entries)
          if pages.empty?
            Common.log_warn('[EPUB] 対象 HTML が見つかりません。スキップします。')
            return []
          end

          ctx = Transforms::Context.new(target:, workspace: dir)
          # 入口の CSS を平らにしてワークスペースの styles/ へ置き、link を付け替える（KFX は @layer を捨てる）
          sheets = Epub::Stylesheets.bundle_flat!(pages, dir, flavor: target.id)
          Transforms::Runner.apply!(target.transforms, pages, ctx)
          # 書き換えが全部終わった DOM で、要素ごとに判定する
          target.finalizers.reduce(Finalizers::Book.new(pages:, sheets:)) { |book, finalizer| finalizer.call(book, ctx) }

          Epub::Config.write_epub_entries(dir, pages)
          Common.log_success("[EPUB] entries.epub.js を生成しました（#{pages.size} エントリ・flavor: #{target.id}）")
          pages
        end

        private

        attr_reader :entries, :targets, :options

        # 1 つの出力先の EPUB を生成する（クリーンは .epub、Kindle は中間 .epub→.kpf）。
        # 出力先ごとのワークスペース（epub/・kindle/）は html/ 直系で、ここで完結する（P4 §3.1）。
        def build_target(target)
          dir = target.workspace
          flavor = target.id

          # --- Phase: html/ → 消費者 dir へステージ（asset_prefix 剥がし） ---
          Epub::Workspace.stage_consumer_htmls!(dir)

          # --- Phase: 出力先の変換と、EPUB 用 entries.js の生成 ---
          epub_htmls = self.class.prepare_pages!(target, entries)
          if epub_htmls.empty?
            Common.log_warn("[generate epub] EPUB 対象 HTML がありません。スキップします。（flavor: #{flavor}）")
            return
          end

          # --- Phase: 参照資産を消費者 dir 内へローカライズ（E2: パッケージルート＝dir） ---
          Epub::Workspace.localize_assets!(dir, flavor:)

          # --- Phase: 著者の SVG 図版を書体入りの派生へ差し替える ---
          # ここも**ローカライズより後**（差し替えた元 SVG をパッケージから落とすため）。
          # クリーンはベクタのまま運び、Kindle は KFX が SVG を扱えないので PNG / JPEG へ焼く。
          Epub::Images.stage_author_svgs!(epub_htmls, flavor:)

          # --- Phase: クリーン EPUB の PNG / JPEG を WebP へ寄せる ---
          # **ローカライズより後**でなければならない。差し替えた元ファイルをパッケージから
          # 落とすので、コピーが済んでいないと空振りし、未参照の重複が残る（実測で +876KB）。
          # Kindle は WebP 非対応なので通さない。
          Epub::Images.transcode_to_webp!(epub_htmls) if target.assets.images == :webp

          # --- Phase: パッケージから参照の切れた画像を回収する ---
          # **差し替えを全部終えた後**でなければならない。参照の有無で判断するので、
          # 数式のテキスト化・PNG 化や図版のラスタ化、WebP への変換より前に呼ぶと、
          # まだ使われている画像を落としてしまう。ローカライズは原稿で使っていない雛形の
          # 画像まで運ぶ（1 章の本で 18.6MB）。Kindle では、SVG が 1 枚でもあると
          # Previewer 4 が KPF を作らない。
          Epub::Workspace.sweep_unreferenced_assets!(dir, flavor:)

          # --- Phase: EPUB 用 vivliostyle.config.js 生成（entryContext = dir） ---
          config_path = Epub::Config.generate_epub_config!(flavor:, dir:)

          # --- Phase: Vivliostyle build ---
          # Kindle は KPF 変換の入力にすぎないため中間 EPUB（…-kindle.epub）として作る（§1-4）。
          to_kpf = target.packager == :vivliostyle_epub_to_kpf
          target_name = to_kpf ? Common.generate_kindle_epub_filename : Common.generate_epub_filename
          EpubCommands.execute_epub({}, target_name, config_path:,
                                                     output_path: File.join(dir, Epub::Config::EPUB_OUTPUT_FILE))

          # --- Phase: content.opf の数字始まり id を NCName 準拠へ修正 ---
          Epub::Opf.sanitize_epub_opf_ids!(target_name) if File.exist?(target_name)

          # --- Phase: 目次の文書の自分自身へのリンクに飛び先を付ける（Kindle のみ） ---
          Epub::Opf.anchor_nav_self_link!(target_name) if to_kpf && File.exist?(target_name)

          # --- Phase: EPUB identifier 安定化 ---
          Epub::Opf.stabilize_epub_identifier!(target_name) if File.exist?(target_name)

          # --- Phase: Kindle は KPF へ変換（§1-7） ---
          # 中間物（entries/config/資産コピー）は消費者 dir 内にあり final clean が
          # ワークスペースごと掃除する（--no-clean 時はデバッグ資材として残る）。
          run_kpf(target_name) if to_kpf
        end

        # Kindle 中間 EPUB を KPF へ変換し、成功時は中間 EPUB を削除する（§1-7）。
        # kindlepreviewer 未導入時は Epub::Kpf が警告して中間 EPUB を残す（ビルドは継続）。
        def run_kpf(kindle_epub)
          kpf_name = Common.generate_kpf_filename
          converted = Epub::Kpf.convert_epub_to_kpf!(kindle_epub, kpf_name)
          # 成功時のみ中間 EPUB を片付ける。--no-clean では検証用に残す（§1-4）。
          FileUtils.rm_f(kindle_epub) if converted && options[:clean] != false && File.exist?(kindle_epub)
        end
      end
    end
  end
end
