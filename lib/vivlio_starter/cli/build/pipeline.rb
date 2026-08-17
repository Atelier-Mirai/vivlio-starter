# frozen_string_literal: true

require 'digest'
require 'tmpdir'

require_relative 'backlink_dedup_orchestrator'
require_relative 'epub_builder'
require_relative 'epub_flow'
require_relative 'print_pdf_builder'
require_relative '../cover'
require_relative 'nombre_stamper'
require_relative 'part_title_generator'
require_relative '../techbook/processor'

module VivlioStarter
  module CLI
    module BuildCommands
      # ------------------------------------------------
      # UnifiedBuildPipeline: フル/単章ビルド統合パイプライン
      # ------------------------------------------------
      # - BuildCommands#build から利用し、各 Step の処理と計時を一元管理する。
      # - mode: :full（全章ビルド）または :single（単章/複数章ビルド）
      # - single mode では Step 6〜12, 14 をスキップし、Step 5 で entries.js + pdf を生成
      # ------------------------------------------------
      class UnifiedBuildPipeline
        # @!attribute phase [Symbol] 実行相（PHASE_ORDER のいずれか）
        Step = Data.define(:label, :handler, :phase, :unit)

        # 相の実行順（build-target-parallelization-spec.md §1.1）。
        # :shared = 両ターゲットが読む中間物を作る共通前段
        # :pdf    = 閲覧用・入稿用 PDF の枝 / :epub = EPUB・Kindle の枝
        # :join   = 両枝の完了後（ワークスペースの掃除）
        # :pdf と :epub は互いに独立なので、両方に仕事があるときは並列に走らせる。
        # :single / :preflight モードは相を持たない（すべて :shared 扱い）。
        PHASE_ORDER = %i[shared pdf epub join].freeze

        # 分岐した直後に 1 行だけ出す予告。EPUB 枝のログは合流時にまとめて出るので、
        # 黙っていると「何も起きていない時間」に見える。
        PARALLEL_NOTICE = '[parallel] EPUB/Kindle を並行生成しています（ログは完了時にまとめて出ます）'

        # @!attribute wall_time [Float, nil] run の実測経過秒。枝を並列に走らせると
        #   ステップ計時の合計より短くなるため、著者へ見せる所要時間はこちらを使う。
        # @!attribute parallel_step_labels [Array<String>] 子枝で並行に走った
        #   ステップのラベル（＝壁時計には現れないぶん）。逐次実行なら空。
        attr_reader :timings, :mode, :entries, :generated_pdf_name, :targets, :wall_time,
                    :parallel_step_labels

        # @param command [Samovar::Command] ビルドコマンドインスタンス
        # @param entries [Array<TokenResolver::Entry>] ビルド対象の Entry 配列
        # @param mode [:full, :single] ビルドモード
        # @param targets [Build::Targets, nil] 出力ターゲット（省略時は book.yml から 1 回だけ解決）。
        #   ビルド中は不変（ターゲット集合はビルド開始時に確定し、reload には追従しない）。
        def initialize(command, entries: [], mode: :full, targets: nil)
          @command = command
          @entries = Array(entries)
          @mode = mode
          @options = command.options
          @targets = targets || Build::Targets.resolve
          @timings = []
          @steps = []
          @generated_pdf_name = nil
          @parallel_step_labels = []
          @aborted = false
          register_steps
        end

        # 登録済みステップを相の順に実行し、経過時間を収集する。
        # :pdf と :epub は互いに独立なので、両方に仕事があるときは並列に走らせる。
        def run
          ensure_entry_files_exist!
          Common.ensure_build_workspace!
          Common.reset_vivliostyle_build_timings
          # 回転テーブルの画像を PDF 枝が用意する構成でだけ、Kindle 枝を待たせる。
          # 待つ相手がいないビルドで永久に待たないよう、ここで明示的に宣言する。
          Build::RotateTableImages.arm!(mode == :full && rotate_table_images?)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          run_phase(:shared)
          fork_branches? ? run_branches_in_parallel : run_branches_sequentially
          run_phase(:join)
          timings
        ensure
          @wall_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at if started_at
        end

        private

        # 1 相ぶんのステップを順に実行する。
        # @param into [Array] 計時の記録先（子枝は自分の配列へ溜め、合流時に親へ足す）
        def run_phase(phase, into: timings)
          phase_steps(phase).each do |step|
            # Ruby の Interrupt はメインスレッドにしか上がらない。子枝は system() が
            # false を返しただけと解釈して次のステップへ進むため、ステップの境目で
            # 中断を見る（build-target-parallelization-spec.md §3.6-1）。
            break if @aborted

            execute(step, position: step_positions[step.label], into:)
          end
        end

        def phase_steps(phase) = @steps.select { it.phase == phase }

        # ラベル → 通し番号。相で区切っても著者から見れば 1 本のビルドなので、
        # 進捗表示の「あと何段階か」は相をまたいだ通し番号のままにする。
        def step_positions
          @step_positions ||= PHASE_ORDER.flat_map { phase_steps(it) }
                                         .each_with_index.to_h { |step, i| [step.label, i + 1] }
        end

        # ================================================================
        # 枝の並列実行（build-target-parallelization-spec.md §1.1・§3.6）
        # ================================================================

        # 両枝に実際の仕事があるときだけ分岐する。
        # pdf 単独・epub 単独のビルドでは、スレッドを起こしても待つ相手がいない。
        def fork_branches? = parallel_enabled? && phase_steps(:pdf).any? && phase_steps(:epub).any?

        # VIVLIO_BUILD_PARALLEL=0 で逐次へ戻す。性能の保険ではなく**切り分けの道具**で、
        # 並列化後に出た不具合が並列由来かどうかを 1 コマンドで判定できる状態を保つ。
        # book.yml には出さない——著者の本の性質ではなく、実行機と切り分け作業の都合。
        def parallel_enabled? = ENV['VIVLIO_BUILD_PARALLEL'].to_s != '0'

        def run_branches_sequentially
          run_pdf_branch
          run_phase(:epub)
        end

        # PDF 枝を走らせ、**終わり方によらず**その成果物を待っている枝を解放する。
        #
        # 通常の解放は抽出ステップ自身が終わった時点で済んでいる（そちらが速い）。
        # ここは取りこぼしの保険で、「ステップが 1 つも登録されなかった」
        # 「中断フラグで 1 つも実行されなかった」経路を拾う——例外だけを見ていると
        # これらを取りこぼし、待っている枝が永久に止まる。
        def run_pdf_branch
          run_phase(:pdf)
        ensure
          Build::RotateTableImages.release!
        end

        # 臨界経路である PDF 枝をメインスレッドで走らせ、EPUB 枝を子スレッドへ出す。
        # こうすると進捗表示（スピナー）も Interrupt もどちらも自然な側に付く。
        def run_branches_in_parallel
          Common.log_action(PARALLEL_NOTICE)
          @parallel_step_labels = phase_steps(:epub).map(&:label)
          branch = start_epub_branch

          parent_error = nil
          begin
            run_pdf_branch
          rescue Exception => e # rubocop:disable Lint/RescueException — Interrupt も拾って子枝へ伝える
            @aborted = true
            parent_error = e
          end

          join_epub_branch(branch, reraise: parent_error.nil?)
          raise parent_error if parent_error
        end

        # EPUB 枝を子スレッドで開始する。ログ・計時・例外はすべて親が持つ Hash へ
        # 書き戻すので、途中で落ちてもそこまでの成果は合流時に読める。
        def start_epub_branch
          branch = { logs: [], timings: [], vivliostyle: [], error: nil }
          branch[:thread] = Thread.new do
            Common.with_emit_sink(branch[:logs]) do
              Common.reset_vivliostyle_build_timings
              run_phase(:epub, into: branch[:timings])
            rescue Exception => e # rubocop:disable Lint/RescueException — 親へ持ち帰って投げ直す
              branch[:error] = e
            ensure
              branch[:vivliostyle] = Common.consume_vivliostyle_build_timings
            end
          end
          branch
        end

        # 子枝の完了を待ち、ログと計時を親へ合流させる。
        #
        # 親が先に死んだ場合も**待ってから**終わる。外部プロセスの pid を握っていないので
        # 殺せないが、待てば宙ぶらりんの Chromium を残さずに済む（待ちは最長でも
        # EPUB 枝の残り時間・§3.6-2）。
        def join_epub_branch(branch, reraise: true)
          # 待つ間はスピナーを回す。**PDF 枝が先に終わる構成があり得る**——索引・用語集を
          # 切ると本文の 2 回目のレンダが消えて PDF 枝が半分になり、EPUB 枝のほうが長くなる。
          # 子枝のログはバッファ済みなので、ここで黙ると端末が無反応に見える。
          # PDF 枝が長い構成では join が即座に返り、スピナーは一瞬で消える（無害）。
          Spinner.while('ビルド中: EPUB/Kindle 枝の完了を待っています …') { branch[:thread].join }
          timings.concat(branch[:timings])
          Common.merge_vivliostyle_build_timings(branch[:vivliostyle])
          flush_branch_logs(branch[:logs])

          return unless branch[:error]
          raise branch[:error] if reraise

          Common.log_error("[parallel] EPUB/Kindle 枝も失敗しました: #{branch[:error].message}")
        end

        # 子枝が溜めたログを親の出口から吐く。読み順が「共通前段 → PDF 枝 → EPUB 枝」で
        # 安定し、ビルドログの diff が取れる。行は捕捉時にログレベルで濾してあるので、
        # ここでは絵文字付きの完成行をそのまま流す。
        def flush_branch_logs(lines)
          return if lines.empty?

          Common.log_action('[parallel] EPUB/Kindle 枝のログ ↓')
          lines.each { Common.log_always(it) }
        end

        attr_reader :command, :options

        # catalog.yml に記載があるのに contents/ に原稿が存在しない場合、
        # 並列前処理のスレッド内で Errno::ENOENT が発生し、著者には
        # 長いスタックトレースしか見えない。ビルド開始前に検証し、
        # 原因と対処を示した上で速やかに終了する。
        def ensure_entry_files_exist!
          missing = entries.reject(&:exists?)
          return if missing.empty?

          Common.log_error('config/catalog.yml に記載されている章ファイルが contents/ に見つかりません:')
          missing.each { Common.log_error("  - contents/#{it.basename}.md") }
          Common.log_error('原稿を削除した場合は、config/catalog.yml から該当する行も削除してください。')
          Common.log_error('（vs delete <章番号> を使うと、原稿・画像・catalog.yml をまとめて削除できます）')
          exit 1
        end

        # Entry 配列から basename 配列を取得
        # @return [Array<String>] basename 配列
        def basenames
          @basenames ||= entries.map(&:basename)
        end

        # モードに応じたステップを登録する
        def register_steps
          case mode
          in :single    then register_single_mode_steps
          in :preflight then register_preflight_steps
          in _          then register_full_mode_steps
          end
        end

        # full mode: 1 枚の宣言的ステップ表を上から評価して登録する。
        # 従来の 5 分岐＋3 補助メソッドを、行ごとの実行条件（targets 依存）を持つ
        # 1 テーブルへ畳んだ（課題 A: 分岐爆発・番号矛盾の解消）。ステップ番号は撤去し、
        # 安定したラベル名をログ・計時・ドキュメントの共通語彙とする。
        # 章単位でありながら、単章ビルドでは意図的に走らせないステップ。
        # **ここに無い逸脱は認めない**（build-mode-parity-spec.md §3.1）。
        # 足すときは必ず理由を書く——書けないなら、それは足し忘れであって逸脱ではない。
        SINGLE_MODE_SKIP = {
          # Type 3 対策は入稿用の関心事で、プレビューには要らない（著者判断・2026-08-11）。
          # 単章では絵文字が画像化されず、囲み数字・波ダッシュも素のまま出る。
          'techbook post-process' => 'Type 3 対策は入稿用の関心事。プレビューには不要'
        }.freeze

        def register_full_mode_steps
          full_mode_step_table.each do |label, handler, enabled, phase, unit|
            add_step(label, handler, phase, unit: unit || :whole_book) if enabled
          end
        end

        # 入稿用 PDF を閲覧用 PDF から導出するか（ビルド開始時に一度だけ確定）。
        # 導出時は print_pdf 単独ターゲットでも閲覧用の中間 PDF が必要になるため、
        # ステップ表の条件と dedup の再レンダ条件がこの値に連動する。
        # プロバイダ能力には依存しない（MIT のみで完結する）。
        def derive_print? = targets.print_pdf && !Common.print_pdf_full_bleed?

        # full mode のステップ表。各行 = [ラベル, ハンドラ, 実行条件, 相, 単位]。
        # 条件はビルド開始時に確定した targets から評価した真偽値（ビルド中は不変）。
        # 分岐はこの条件列に吸収され、経路の組み合わせは表を上から評価するだけで一意に定まる。
        #
        # **相**は :shared → (:pdf ∥ :epub) → :join の順に評価される
        # （build-target-parallelization-spec.md §1.1・§2）。どの出力枝が必要とするか。
        #
        # **単位**は相と直交する第 2 の軸で、処理の**入力**が章か書籍かを表す
        # （build-mode-parity-spec.md §2）。単章ビルドは :chapter の行だけを走らせる。
        #   :chapter    … 1 章だけ読めば答えが出る（前処理・記法変換・HTML 変換）
        #   :whole_book … 全章そろわないと答えが出ない（索引ページ・目次・部扉・結合）
        # 省略時は :whole_book。**足し忘れたステップが単章へ流れ込まない側**に倒してある——
        # 逆にすると章単位でないものが単章で動いて壊れる。
        # 単位は「章単位か」だけを言い、単章で走らせるかは SINGLE_MODE_SKIP が最終的に決める。
        def full_mode_step_table
          t = targets
          derive_print = derive_print?
          # 導出のソースは「dedup 済みの閲覧用中間 PDF」。よって print_pdf 単独でも
          # 本文・前付・奥付の閲覧用 PDF を作る。最終成果物（merge 以降）は従来どおり t.pdf 次第。
          need_viewing_pdf = t.pdf || derive_print
          [
            # --- :shared 共通前段（HTML と共有資産を作る・両枝が読む） ---
            ['clean',                     -> { run_step0_clean },                             true, :shared, :chapter],
            ['optimize images',           -> { run_step1_optimize_images },                   true, :shared, :chapter],
            ['prepare theme images',      -> { Build::ImageOptimizer.prepare_theme_images! }, true, :shared, :chapter],
            # カバー資産は両枝が同じファイルを読む。分岐前に 1 回だけ作る（§3.2）。
            ['prepare cover assets',      -> { run_prepare_cover_assets },      cover_assets_needed?, :shared, :whole_book],
            ['preprocess sections',       -> { Build::SectionBuilder.preprocess_sections!(entries) }, true, :shared, :chapter],
            ['index scan and build',      -> { run_step4_index_processing },                  true, :shared, :chapter],
            ['convert sections html',     -> { Build::SectionBuilder.convert_sections_html!(entries) }, true, :shared, :chapter],
            ['generate part title pages', -> { Build::PartTitleGenerator.generate_all! },     true, :shared, :whole_book],
            # 前付・奥付の HTML は本文レンダへ相乗りさせるため、techbook 後処理より前に置く。
            # ここで作れば html/ の一括後処理が拾い、個別再適用が要らなくなる
            # （front-back-matter-single-render-spec.md §2.1）。EPUB のスパイン末尾も
            # _colophon.html を読むので、生成が :shared にあることが枝の独立を支えている（§3.3）。
            ['generate front and back matter html',
             -> { Build::PdfBuilder.generate_front_and_back_matter_html! },                   true, :shared, :whole_book],
            ['techbook post-process',     -> { run_techbook_post_process },                   true, :shared, :chapter],
            ['generate toc html',
             -> { Build::TocGenerator.generate_toc_html!(Common::BUILD_HTML_DIR, entries) },  true, :shared, :whole_book],
            # --- :pdf 枝（臨界経路。書き換えはワークスペース pdf/ に閉じる） ---
            # 閲覧用 PDF は本文全体を、入稿用のみ経路は entries/config だけを生成する。
            # いずれも html/ → pdf/ のステージングを内包する（P4 §3.4-2）。
            ['build overall pdf', -> { Build::PdfBuilder.build_overall_pdf_from_dir!(entries) },
             need_viewing_pdf, :pdf, :whole_book],
            # Kindle は KFX が transform を解さず回転テーブルが素の表に戻るため、組み上がった
            # ページを画像へ焼く。**dedup 前のこのレンダ**を使う——後段の再レンダを待つと
            # Kindle 枝の開始が 150 秒遅れ、PDF 枝の陰に収まらなくなる
            # （kindle-rotate-table-image-spec.md §7）。
            ['extract rotate table images', -> { run_rotate_table_extraction }, rotate_table_images?, :pdf, :whole_book],
            ['generate entries.js', -> { Build::PdfBuilder.generate_entries_for_sections!(entries) },
             !t.pdf && t.print_pdf && !derive_print, :pdf, :whole_book],
            # 組み上がった PDF から実効解像度を測り、過剰な画像を縮小版へ差し替える。
            # dedup の**直前**に置くのは、あれが浄化後に再レンダするからで、
            # 新しいパスを増やさずに縮小版で組み直せる（`image-format-per-target-spec.md` §3.6）。
            ['shrink oversized images', -> { run_shrink_oversized_images }, t.any_pdf?, :pdf, :whole_book],
            # dedup の破壊的書換は pdf/ 配下のコピーに閉じるため、EPUB 隔離のための
            # 「dedup 前スナップショット」ステップは不要になった（P4 §3.4-3。
            # EPUB/Kindle は html/ のクリーンな原本から直接展開する）。
            ['backlink dedup', -> { Build::BacklinkDedupOrchestrator.run!(entries, rebuild_pdf: need_viewing_pdf) },
             t.any_pdf?, :pdf, :whole_book],
            # 前付・奥付。HTML は共通前段で作り済みなので、ここは相乗りできなかった
            # ときのフォールバックレンダだけを持つ。生成するのは扉・権利ページ（前付）と
            # 奥付（後付）。旧称の "tail" は奥付を指す曖昧語だったため、出版用語に合わせた
            ['build front and back matter', -> { run_step9_front_pages_and_tail }, need_viewing_pdf, :pdf, :whole_book],
            ['merge all pdfs', -> { Build::PdfMerger.merge_all_pdfs!(entries) },            t.pdf, :pdf, :whole_book],
            ['apply outline to output pdf', -> { Build::PdfMerger.add_outline_to_output_pdf!(entries) },
             t.pdf, :pdf, :whole_book],
            # 閲覧用 PDF 単独はリネーム＋圧縮＋クリーンを一括。この行が立つのは他ターゲットが
            # 無いときだけなので、掃除を :pdf 相に含めても EPUB 枝と競合しない。
            ['compress, rename and final clean', -> { run_step12_rename_and_clean },
             t.pdf && !t.print_pdf && !t.epub_or_kindle?, :pdf, :whole_book],
            # 実処理は圧縮（設定次第）＋リネーム。'rename' だけでは圧縮が隠れるため明示する。
            # 他ターゲット併存時はクリーンを :join へ延期する（HTML を EPUB 枝が読むため）。
            ['compress and rename', -> { run_step12_rename_only },
             t.pdf && (t.print_pdf || t.epub_or_kindle?), :pdf, :whole_book],
            ['print pdf', -> { Build::PrintPdfBuilder.new(entries, derive: derive_print).build! },
             t.print_pdf, :pdf, :whole_book],
            # --- :epub 枝（EPUB → Kindle。枝の中は逐次） ---
            ['generate epub', -> { epub_flow.run! }, t.epub_or_kindle?, :epub, :whole_book],
            # --- :join 合流（ワークスペースを消すので両枝の完了後） ---
            ['final clean', -> { run_final_clean }, t.print_pdf || t.epub_or_kindle? || !t.pdf, :join, :whole_book]
          ]
        end

        # preflight mode: Step 1〜4 のみ実行（HTML変換・PDF生成なし）
        # build 側の Step 1〜4 変更が自動追従するよう、既存メソッドを直接呼ぶ
        def register_preflight_steps
          [
            ['optimize images',      -> { run_step1_optimize_images }],
            ['prepare theme images', -> { Build::ImageOptimizer.prepare_theme_images! }],
            ['preprocess sections',  -> { Build::SectionBuilder.preprocess_sections!(entries) }],
            ['index scan and build', -> { run_step4_index_processing }]
          ].each { |label, handler| add_step(label, handler) }
        end

        # single mode は閲覧用 PDF のみ生成する（プレビュー・サンプル配布が主用途）。
        # print_pdf / EPUB / Kindle(KPF) は入稿・配信を前提とした全章成果物なので、
        # 単章では作らず全章 `vs build` 専用とする（中途半端な出力を避け、負担も抑える）。
        def register_single_mode_steps
          warn_single_mode_pdf_only

          # 章単位のステップは full mode の表からそのまま引く。
          # **モードごとの一覧を手で持たない**ので、新しいステップを足したときに
          # 単章へ載るかどうかは表の :chapter 宣言だけで決まる。以前は 2 つの表を
          # 手で維持しており、片方への追加がもう片方へ届かず「単章では ○○ だったが
          # 全章では ×× だった」が繰り返し起きていた（build-mode-parity-spec.md §0）。
          full_mode_step_table.each do |label, handler, enabled, phase, unit|
            next unless enabled
            next unless unit == :chapter
            next if SINGLE_MODE_SKIP.key?(label)

            add_step(label, handler, phase, unit: :chapter)
          end

          # 単章固有の出力。閲覧用 PDF のみ・ファイル名も違う（章名.pdf）ため、
          # 全章の結合・アウトライン・リネームとは別物になる。
          add_step('entries.js + pdf',   -> { generate_entries_and_pdf })
          add_step('rename output pdfs', -> { rename_single_mode_pdf })
          add_step('final clean',        -> { run_final_clean })
        end

        # targets に PDF 以外（print_pdf / EPUB / Kindle）が含まれていても、
        # 単章ビルドは閲覧用 PDF のみ生成する旨を一度だけ案内する。
        def warn_single_mode_pdf_only
          return unless targets.print_pdf || targets.epub_or_kindle?

          Common.log_info('単章ビルドは閲覧用 PDF のみ生成します（print_pdf / EPUB / Kindle は全章 `vs build` で生成してください）')
        end

        # ステップを記録して順次処理できるようにする。
        # 相の既定は :shared（:single / :preflight モードは相を持たない）。
        # 単位の既定は :whole_book——**足し忘れたステップが単章へ流れ込まない**側に倒す
        # （build-mode-parity-spec.md §2.2。既定を :chapter にすると、章単位でないものが
        #  単章ビルドで動いて壊れる。逆向きの事故は「単章に出ない」で済む）。
        def add_step(label, handler, phase = :shared, unit: :whole_book)
          @steps << Step.new(label, handler, phase, unit)
        end

        # 指定ステップを実行し、前後でタイマーを計測する
        # 既定ログレベルではステップ間の出力がなく「止まっている」のと区別が付かないため、
        # TTY のときだけスピナーで進行を示す（表示条件は Spinner が判断する）。
        # step.label はログ・計時と同じ語彙なので、そのまま進捗表示名に使う。
        def execute(step, position: nil, into: timings)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          Common.log_action("[Timer] #{step.label} start")
          Common.with_current_step_label(step.label) do
            Spinner.while(spinner_label(step, position)) { step.handler.call }
          end
        ensure
          finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          elapsed = finish_time - start_time
          into << [step.label, elapsed]
          Common.log_action("[Timer] #{step.label} finish: #{format('%.2f', elapsed)}s")
        end

        # 進行中であることを表す語。
        # preflight は原稿を検査するだけで何も組まないので「ビルド中」とは言わない
        # ——出力物ができると思われると、実行を止める判断を誤らせる。
        PROGRESS_VERB = { preflight: '点検中' }.freeze
        DEFAULT_PROGRESS_VERB = 'ビルド中'

        # スピナーに出す進捗の見出し。総数が分かるので「あと何段階か」が読める
        def spinner_label(step, position)
          verb = PROGRESS_VERB.fetch(@mode, DEFAULT_PROGRESS_VERB)
          return "#{verb}: #{step.label}" if position.nil?

          "#{verb}: #{step.label} … (#{position}/#{@steps.size})"
        end

        # クリーンオプションに応じて中間生成物を削除する
        def run_step0_clean
          if options[:clean] == false
            Common.log_action('[clean] クリーンアップをスキップします（--no-clean）')
          else
            Common.log_action('[clean] クリーンアップを実行します…')
            CleanCommands.execute_clean({})
            # 前回ビルドのワークスペースを一括掃除（stale HTML の混入防止・P4 §3.4-8）
            FileUtils.rm_rf(Common::BUILD_DIR)
          end
        end

        # 組み上がった本文 PDF から実効解像度を測り、過剰な画像を縮小版へ差し替える。
        #
        # 差し替え先は pdf/ の HTML なので、直後の dedup が浄化後に再レンダするとき
        # 縮小版で組まれる。索引を使わず dedup が走らない本では**次回のビルド**から効く
        # ——測定結果は .cache/vs/derived/ に残り、ステージングがそれを読むためである。
        def run_shrink_oversized_images
          sections_pdf = File.join(Common::BUILD_PDF_DIR, '_sections.pdf')
          measured = Build::DerivedImage.measure!(sections_pdf)
          if measured.zero?
            Common.log_info('[shrink] 実効解像度を測れませんでした（本文 PDF が未生成）')
            return
          end

          Common.log_info("[shrink] 実効解像度を測りました: #{measured} 種類の画素数")
          Build::PdfBuilder.swap_images_for_pdf!
        end

        # ここに残っているのは Techbook モードの SVG ラスタライズだけで、画像の WebP 変換は
        # やめた（`ImageOptimizer.optimize_images!` のコメント参照）。品質プリセット
        # （`--high` / `--medium` / `--low`）は行き先を失ったので 2026-08-17 に撤去した。
        #
        # **飛ばす道は用意しない。** 選ぶと入稿できない PDF が黙って出来るうえ
        # （Chromium が SVG 内のパスを Type 3 フォントとして埋め込む）、節約できる時間も
        # 無い——同梱の WebP が効いて、新規プロジェクトの初回ビルドでも **0.06 秒**で終わる
        # （実測 2026-08-17: 3,746 件すべて up-to-date でスキップ）。かつてあった
        # `--no-resize` は同日撤去した。速度より品質を選ぶ判断は `output.pdf.techbook` で行う。
        def run_step1_optimize_images
          Build::ImageOptimizer.optimize_images!
        end

        # カバー資産（表紙 PDF・表紙 JPG）を分岐前に 1 回だけ作る。
        #
        # かつては PDF 枝（PdfMerger）・入稿用（PrintPdfBuilder）・EPUB 枝（EpubFlow）が
        # それぞれ同じ CoverCommands.ensure_cover_files_for_build! を呼び、先に走ったほうが
        # 作って後続は素通りする——という順序頼みの暗黙の調停になっていた。枝を並列に
        # 走らせると同じパスへ 2 つの magick が同時に書き、半端なファイルを他方が読む窓が
        # 開く（build-target-parallelization-spec.md §3.2）。
        #
        # カバー生成は本文レンダに一切依存しないので、共通前段へ引き上げれば競合は消える。
        def run_prepare_cover_assets
          Common.log_action('[prepare cover assets] カバー画像を生成します…')
          CoverCommands.ensure_cover_files_for_build!
          Common.log_info('[prepare cover assets] カバー画像の生成を完了しました')
        rescue StandardError => e
          Common.log_warn("[prepare cover assets] カバー生成中にエラー: #{e.message}")
        end

        # 回転テーブルのページ画像化を PDF 枝が担うか。Kindle を作らないビルドでは不要、
        # 本文 PDF を作らないビルドでは不能（素の表へ縮退し、Kindle 枝が 🟡 で案内する）。
        def rotate_table_images? = targets.kindle && (targets.pdf || derive_print?)

        # 抽出ステップの本体。Kindle 枝を待たせているので、成否によらず必ず解放する。
        # 抽出ステップの本体。**終わった瞬間に解放する**のが要点で、これを怠ると
        # Kindle 枝は PDF 枝の全終了（dedup ＋ アウトラインで 200 秒近く先）まで待たされ、
        # 枝の陰に収まらなくなる（実測 WALL 359.6s → 485.7s）。
        # run_pdf_branch 側の解放は、ここへ到達しなかったときの保険。
        def run_rotate_table_extraction
          count = Build::RotateTableImages.extract!(File.join(Common::BUILD_PDF_DIR, '_sections.pdf'))
          Common.log_info("[rotate-table] 回転テーブルを #{count} 件画像化しました") if count.positive?
        ensure
          Build::RotateTableImages.release!
        end

        # カバー資産を読む枝があるか（従来の各枝の実行条件をそのまま合成したもの）。
        # 閲覧用 PDF は結合が有効なときだけ表紙 PDF を綴じ、EPUB/Kindle は cover.embed が
        # 真のときだけ表紙 JPG を埋める。どちらも使わない構成では作らない。
        def cover_assets_needed?
          (targets.pdf && Common.pdf_combined?) || targets.print_pdf ||
            (targets.epub_or_kindle? && Common.epub_embed?)
        end


        # single mode: 用途別 entries/config を生成して PDF をビルド
        # full mode と同じ「html/ → pdf/ コピー＋生成 config」経路（E5 で成立を実証）
        def generate_entries_and_pdf
          Common.log_action('[entries.js + pdf] entries/config を生成して PDF をビルドします…')
          Build::PdfBuilder.stage_workspace_htmls!
          entry_htmls = entries.map { File.join(Common::BUILD_PDF_DIR, "#{it.basename}.html") }
                               .select { File.exist?(it) }
          config = Build::VivliostyleConfigWriter.write!(name: 'single', entry_htmls:,
                                                         output: single_mode_output_pdf)
          PdfCommands.execute_pdf({}, config_path: config, output_path: single_mode_output_pdf)
        end

        # single mode の中間出力 PDF（ワークスペース pdf/ 内）
        def single_mode_output_pdf
          File.join(Common::BUILD_PDF_DIR, 'output.pdf')
        end

        # single mode: 出力 PDF を章 basename にリネームしてルートへ移動
        # （例: 11-workflow.pdf、複数章指定時は 54-56.pdf）
        def rename_single_mode_pdf
          output_pdf = single_mode_output_pdf

          unless File.exist?(output_pdf)
            Common.log_warn("出力PDFが見つかりません: #{output_pdf}")
            return
          end

          @generated_pdf_name = determine_single_mode_pdf_name
          FileUtils.rm_f(@generated_pdf_name)
          FileUtils.mv(output_pdf, @generated_pdf_name)
          Common.log_success("[rename output pdfs] PDFをリネームしました: #{@generated_pdf_name}")
        end

        # single mode の出力 PDF 名を決定する
        def determine_single_mode_pdf_name
          if basenames.size == 1
            # 単一章: 11-workflow.pdf
            "#{basenames.first}.pdf"
          else
            # 複数章: 54-56.pdf（最初と最後の章番号）
            sorted = basenames.sort_by { |bn| bn[/^(\d+)/, 1].to_i }
            first_num = sorted.first[/^(\d+)/, 1]
            last_num = sorted.last[/^(\d+)/, 1]
            "#{first_num}-#{last_num}.pdf"
          end
        end

        # 前付・奥付の PDF を用意する。
        #
        # 通常は本文レンダに相乗り済みで、ここは何もしない——vivliostyle は PDF を
        # 吐くたび約 22 秒の固定費がかかり、3 ページのために 2 回起動するのが
        # 実測 68 秒の無駄だった（front-back-matter-single-render-spec.md §0.1）。
        # 相乗りできなかったときだけ、従来どおり個別にレンダする。
        def run_step9_front_pages_and_tail
          if Build::PdfBuilder.embedded_special_page_ranges
            Common.log_info('[Step 9] 前付・奥付は本文 PDF に相乗り済みのため、個別レンダをスキップします')
            return
          end

          Build::PdfBuilder.ensure_separate_render_is_safe!
          Common.log_warn('[Step 9] 本文 PDF に前付・奥付が見つかりません。個別にレンダします')
          Build::PdfBuilder.build_front_pages_and_tail!
        end

        # Step 12: リネームと最終クリーンアップを実行
        def run_step12_rename_and_clean
          run_compress_pdf_if_needed
          Build::PdfFinalizer.rename_output_pdfs!
          run_final_clean
        end

        # Step 12 (print_pdf ターゲット時): リネーム・圧縮のみ。クリーンアップは Step 14 へ延期
        def run_step12_rename_only
          run_compress_pdf_if_needed
          Build::PdfFinalizer.rename_output_pdfs!
        end

        # 必要に応じて生成済みPDFを圧縮する
        def run_compress_pdf_if_needed
          should_compress = determine_compress_setting

          if should_compress
            Build::PdfFinalizer.compress_pdf!
          else
            source = compress_setting_source
            Common.log_action("[compress] PDF圧縮をスキップします（#{source}）")
          end
        end

        # 圧縮設定を判定（オプション優先、次に book.yml）
        def determine_compress_setting
          # --compress または --no-compress が明示的に指定されている場合はそれを優先
          return options[:compress] unless options[:compress].nil?

          # オプション未指定の場合は book.yml の output.pdf.compress を参照（デフォルト: false）
          # （従来はレガシーの pdf.compress を読んでおり、正規キーが効いていなかった）
          Common.pdf_compress?
        end

        # 圧縮設定のソース（ログ用）
        def compress_setting_source
          unless options[:compress].nil?
            return options[:compress] ? '--compress オプション' : '--no-compress オプション'
          end

          case Common::CONFIG.output.pdf.compress
          in true then 'book.yml: output.pdf.compress = true'
          in false then 'book.yml: output.pdf.compress = false'
          else 'デフォルト設定 (compress: false)'
          end
        end

        # 最終的なクリーン処理を担当する
        # 中間物はすべてワークスペース（数式 SVG・索引 YAML を含む・P4b）に閉じているため、
        # 掃除は rm_rf BUILD_DIR 一括で完結し、ルートへ個別に触れる理由がない（完了条件 2）。
        # --no-clean 時は残す＝デバッグ資材が 1 箇所に揃う（P4 §3.4-8）
        def run_final_clean
          if options[:clean] == false
            Common.log_action('[final clean] クリーンアップをスキップします（--no-clean）')
          else
            Common.log_action('[final clean] ビルドワークスペースを削除します…')
            FileUtils.rm_rf(Common::BUILD_DIR)
          end
        end

        # EPUB / Kindle ビルドのオーケストレーションは Build::EpubFlow へ移設済み（P2）。
        def epub_flow
          @epub_flow ||= Build::EpubFlow.new(entries, targets, options)
        end

        # Techbook モード: SVG→WebP 参照書き換え + 絵文字差し替え + CSS 注入
        # techbook: true でない場合は何もしない（Processor 内部で判定）
        def run_techbook_post_process
          Techbook::Processor.new(Common::CONFIG).post_process_html_files!
        end

        # Step 4: 索引処理を実行
        def run_step4_index_processing
          unless IndexCommands.index_enabled?
            Common.log_action('[index scan and build] 索引・用語集機能が無効のためスキップします（book.yml: index_glossary.enabled = false）')
            return
          end

          # 対象章を取得（Entry 配列から basename を抽出）
          chapter_targets = if entries.any?
                              basenames.sort
                            else
                              Dir[File.join(Common::CONTENTS_DIR, '*.md')]
                                .map { |p| File.basename(p, '.md') }
                                .reject { |bn| bn.start_with?('_') }
                                .sort
                            end

          # 索引ページ・ページ番号・主要参照は**書籍全体を単位**とするので、章を絞った
          # 実行では作らない（章を絞ると用語集語がほぼ全滅して誤検知になる問題も構造的に
          # 消える。詳細 → preflight-glossary-warning-scope-report.md）。
          #
          # **章ごとのタグ付けは絞っても走らせる。** ここを一緒に止めていたため、単章では
          # 索引語が素のテキスト、全章ではタグ付き、という食い違いが生まれ、前処理側に
          # 埋め合わせを置くことになっていた（build-mode-parity-spec.md §4）。
          unless full_catalog_scope?
            Common.log_action('[index scan and build] 章を絞った実行のため索引ページは作りません（タグ付けは行います）')
            IndexCommands.tag_chapters_for_build!(chapter_targets)
            return
          end

          Common.log_action('[index scan and build] 索引語のスキャンと索引ページ生成を実行します…')
          IndexCommands.process_index_for_build!(chapter_targets)
        end

        # 今回の対象章が catalog の全章を覆っているか。
        # entries が空（＝contents/ 全 .md を対象にするフォールバック）も全章とみなす。
        # catalog を読めない環境では従来どおり実行する（判定材料が無いのに黙るのは危険）。
        def full_catalog_scope?
          catalog = Build::CatalogLoader.load_existing_basenames
          return true if catalog.empty? || entries.empty?

          (catalog - basenames).empty?
        rescue StandardError => e
          Common.log_debug("catalog の全章判定に失敗したため索引処理を実行します: #{e.message}")
          true
        end
      end
    end
  end
end
