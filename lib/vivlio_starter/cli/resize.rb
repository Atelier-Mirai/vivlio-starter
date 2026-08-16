# frozen_string_literal: true

require 'etc'
require 'fileutils'

module VivlioStarter
  module CLI
    # ================================================================
    # Module: 画像リサイズ/変換ロジック
    # ================================================================
    # 提供機能:
    #   - 画像を WebP に変換（高精細/標準/軽量のプリセット）
    #   - SVG を rsvg-convert → lossless WebP に変換（Techbook モード用）
    # ================================================================
    module ResizeCommands
      module_function

      # WebP 変換のプリセット。
      #
      # `method` は画質ではなく「圧縮を探す徹底度」（0〜6）である。`quality` を固定して
      # いる以上、値を上げても見た目は変わらず、縮むのはファイルサイズだけ。
      #
      # **6 を選んではならない**（2026-08-16 実測）。5 → 6 で時間が 22 倍に跳ねる崖があり、
      # 見返りはサイズ 1.5% 減にとどまる。しかも遅くなるのは**透過を持つ絵**に偏る——
      # 同じ扉絵から透過を外すと 10.89 秒 → 0.35 秒（31 倍）で、ピクセル数は関係ない
      # （800px へ縮めても 7.24 秒）。libwebp がアルファチャンネルの探索まで徹底的に行う
      # ためで、章扉のようなイラストを持つ本ほど初回ビルドが遅くなる。スクリーンショット
      # （透過なし・色数が少ない）では 6 でも 0.15 秒/枚で、症状が出ないため気づきにくい。
      #
      # 4 は libwebp / ImageMagick の既定値。3 でもサイズは実質同じ（+0.1%）で 11% 速いが、
      # 既定に合わせておけばエンコーダが改良されたときにそのまま追従できる。
      # 値を動かすときは resize_test.rb の回帰テストも一緒に見ること。
      WEBP_PRESETS = {
        '高精細' => { quality: 90, method: 4, max_px: 2000 },
        '標準' => { quality: 85, method: 4, max_px: 1600 },
        '軽量' => { quality: 75, method: 4, max_px: 1200 }
      }.freeze

      RESIZE_DESC = {
        high: {
          short: '画像を高品質WebPに変換します',
          long: <<~DESC
            画像を高品質WebPに変換します（quality=90, max_px=2000）。

            対象: .png, .jpg, .jpeg
            出力: 同ディレクトリに .webp

            引数:
              DIR    対象ディレクトリ（省略時は images/）

            使用例:
              vs resize:high
              vs resize:high assets/images
          DESC
        },
        medium: {
          short: '画像を標準品質WebPに変換します',
          long: <<~DESC
            画像を標準品質WebPに変換します（quality=85, max_px=1600）。

            対象: .png, .jpg, .jpeg
            出力: 同ディレクトリに .webp

            引数:
              DIR    対象ディレクトリ（省略時は images/）

            使用例:
              vs resize:medium
              vs resize:medium assets/images
          DESC
        },
        low: {
          short: '画像を軽量品質WebPに変換します',
          long: <<~DESC
            画像を軽量品質WebPに変換します（quality=75, max_px=1200）。

            対象: .png, .jpg, .jpeg
            出力: 同ディレクトリに .webp

            引数:
              DIR    対象ディレクトリ（省略時は images/）

            使用例:
              vs resize:low
              vs resize:low assets/images
          DESC
        },
        default: {
          short: '画像をWebPに変換します（標準品質）',
          long: <<~DESC
            画像をWebPに変換します（標準品質が既定）。

            対象: .png, .jpg, .jpeg
            出力: 同ディレクトリに .webp

            引数:
              DIR    対象ディレクトリ（省略時は images/）

            オプション:
              --force   既存ファイルも強制再生成
              --high    高品質プリセットを使用
              --low     軽量品質プリセットを使用

            使用例:
              vs resize
              vs resize assets/images
              vs resize --high
              vs resize --force
          DESC
        }
      }.freeze

      def included(base); end

      # 変換実績。表示は呼び出し側の責務とし、ドメイン層は件数を返すだけにする。
      # `vs build` の Step 1 も同じ関数を対象ディレクトリごとに呼ぶため、ここで結果報告を
      # 出すとビルド中に「対象画像が見つかりませんでした」等が何行も混ざってしまう。
      ResizeSummary = Data.define(:converted, :skipped) do
        def +(other) = ResizeSummary.new(converted: converted + other.converted, skipped: skipped + other.skipped)
        def none? = converted.zero? && skipped.zero?
      end

      # Samovar/直接呼び出し用: 高品質プリセット
      def execute_resize_high(dir = 'images', options = {})
        execute_resize_with_preset('高精細', dir, options)
      end
      module_function :execute_resize_high

      # Samovar/直接呼び出し用: 標準品質プリセット
      def execute_resize_medium(dir = 'images', options = {})
        execute_resize_with_preset('標準', dir, options)
      end
      module_function :execute_resize_medium

      # Samovar/直接呼び出し用: 軽量品質プリセット
      def execute_resize_low(dir = 'images', options = {})
        execute_resize_with_preset('軽量', dir, options)
      end
      module_function :execute_resize_low

      # Samovar/直接呼び出し用: プリセット指定でリサイズ
      def execute_resize_with_preset(preset_name, dir, options = {})
        ENV['VERBOSE'] = '1' if options[:verbose]
        ENV['FORCE'] = '1' if options[:force]

        preset = WEBP_PRESETS[preset_name]
        unless preset
          Common.log_error("未知のプリセットです: #{preset_name}")
          return
        end

        unless Dir.exist?(dir)
          Common.log_error("ディレクトリが存在しません: #{dir}")
          return
        end

        unless system('which magick >/dev/null 2>&1')
          Common.log_error('Error: ImageMagick (magick) が見つかりません。brew install imagemagick 等で導入してください。')
          return
        end

        patterns = %w[png jpg jpeg JPG JPEG PNG]
        files = patterns.flat_map { |ext| Dir.glob(File.join(dir, "**/*.#{ext}")) }.uniq.sort

        if files.empty?
          Common.log_info("対象画像が見つかりませんでした: #{dir}")
          return ResizeSummary.new(converted: 0, skipped: 0)
        end

        Common.log_action("画像変換を開始: Preset=#{preset_name}, Dir=#{dir}, Files=#{files.size}")

        converted = 0
        skipped = 0
        failed = []
        tally = Mutex.new

        each_in_parallel(files) do |src|
          dst = src.sub(/\.[^.]+\z/, '.webp')

          if ENV['FORCE'].nil? && File.exist?(dst) && File.mtime(dst) >= File.mtime(src)
            Common.log_info("skip: up-to-date #{dst}")
            tally.synchronize { skipped += 1 }
            next
          end

          FileUtils.mkdir_p(File.dirname(dst))

          cmd = [
            'magick', src,
            '-resize', "#{preset[:max_px]}x#{preset[:max_px]}>",
            '-strip',
            '-quality', preset[:quality].to_s,
            '-define', "webp:method=#{preset[:method]}",
            dst
          ]

          Common.log_info(cmd.join(' '))
          if system(*cmd)
            tally.synchronize { converted += 1 }
          else
            tally.synchronize { failed << src }
          end
        end

        # 1 件目で打ち切らず、失敗した画像をすべて挙げる。並列で走るので順に止められない
        # という事情もあるが、著者にとっても「あと何枚直せばよいか」が一度で分かるほうがよい
        report_failed_conversions(failed)

        Common.log_success('画像変換が完了しました') if failed.empty?
        summary = ResizeSummary.new(converted: converted, skipped: skipped)

        # --delete-originals: 変換成功した元ファイルを確認後に削除
        return summary unless options[:delete_originals]

        converted_originals = files.select { |src| File.exist?(src.sub(/\.[^.]+\z/, '.webp')) }
        if converted_originals.empty?
          Common.log_info('削除対象の元ファイルはありませんでした')
        else
          Common.log_warn('以下の元画像ファイルを削除しようとしています:')
          converted_originals.each { |f| Common.log_always("  - #{f}") }
          if Common.confirm?('本当に削除しますか？')
            converted_originals.each do |f|
              FileUtils.rm_f(f)
              Common.log_info("削除しました: #{f}")
            end
            Common.log_success("元ファイルを削除しました（#{converted_originals.size}件）")
          else
            Common.log_info('元ファイルの削除をキャンセルしました')
          end
        end

        summary
      end
      module_function :execute_resize_with_preset

      # 変換できなかった画像をまとめて 🔴 で挙げる（1 件も無ければ何もしない）。
      def report_failed_conversions(failed)
        return if failed.empty?

        Common.log_error(
          "画像の変換に失敗しました（#{failed.size} 件）",
          detail: "#{failed.first(10).map { "- #{it}" }.join("\n")}\n" \
                  '対処: 上のファイルを `magick <ファイル> out.webp` で個別に試すと理由が読めます'
        )
      end
      module_function :report_failed_conversions

      # 外部コマンドの起動を伴う変換を並べて走らせる。
      #
      # スレッドで足りるのは、1 件ごとに magick / rsvg-convert のプロセスを起こす形で、
      # Ruby 側は待っているだけだからである（`system` の間 GVL は解放される）。
      # 実測 2026-08-16: スクリーンショット 60 枚が 7.6 秒 → 1.6 秒（10 並列・4.75 倍）。
      #
      # 枚数が 1 以下、または並列度 1 のときは逐次に落とす——スレッドを起こす意味がなく、
      # ログの順序も保たれる。
      def each_in_parallel(items, &)
        list = Array(items)
        concurrency = image_concurrency
        return list.each(&) if concurrency <= 1 || list.size <= 1

        Common.log_info("[resize] 並列変換 concurrency=#{concurrency}")
        queue = Queue.new
        list.each { queue << it }
        sentinel = Object.new
        concurrency.times { queue << sentinel }

        workers = Array.new(concurrency) do
          Thread.new do
            loop do
              item = queue.pop
              break if item.equal?(sentinel)

              yield(item)
            end
          end
        end
        workers.each(&:join)
      end
      module_function :each_in_parallel

      # 画像変換の並列度。既定は CPU コア数（上限 8）。
      #
      # 8 で頭打ちにするのは、magick が 1 プロセスあたり画像 1 枚を丸ごとメモリに載せるため。
      # 大判の原画を多く持つ本で、コア数のぶんだけ無制限に起こすと実メモリを圧迫する。
      # 実測が必要な場面のために VIVLIO_IMAGE_CONCURRENCY で上書きできる（1 で逐次）。
      def image_concurrency
        override = ENV['VIVLIO_IMAGE_CONCURRENCY'].to_i
        return override if override.positive?

        cores = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 2
        [cores, 8].min.clamp(1, 8)
      end
      module_function :image_concurrency

      # SVG → PNG（rsvg-convert）→ lossless WebP（magick）変換
      # Chromium PDF エンジンが SVG 内の <path>/<text> を Type 3 フォントとして
      # 埋め込む問題を回避するため、ビルド前に全 SVG をラスタライズする。
      # @param dirs [Array<String>] 対象ディレクトリの配列
      # @param dpi [Integer] rsvg-convert の DPI（既定: 350）
      def convert_svg_to_webp(dirs, dpi: 350)
        # --- Phase: ツール存在チェック ---
        unless system('which rsvg-convert >/dev/null 2>&1')
          Common.log_error('Error: rsvg-convert が見つかりません。brew install librsvg 等で導入してください。')
          return
        end

        unless system('which magick >/dev/null 2>&1')
          Common.log_error('Error: ImageMagick (magick) が見つかりません。brew install imagemagick 等で導入してください。')
          return
        end

        # --- Phase: SVG ファイル収集 ---
        svg_files = dirs
          .select { Dir.exist?(it) }
          .flat_map { Dir.glob(File.join(it, '**/*.svg')) }
          .uniq.sort

        if svg_files.empty?
          Common.log_info('[SVG→WebP] 対象 SVG ファイルが見つかりませんでした')
          return
        end

        Common.log_action("[SVG→WebP] #{svg_files.size} 件の SVG を変換します（DPI=#{dpi}）")

        # --- Phase: 変換実行 ---
        converted = 0
        tally = Mutex.new

        each_in_parallel(svg_files) do |svg_path|
          webp_path = svg_path.sub(/\.svg\z/i, '.webp')

          # mtime 比較でスキップ（--force 時は強制再生成）
          if ENV['FORCE'].nil? && File.exist?(webp_path) && File.mtime(webp_path) >= File.mtime(svg_path)
            Common.log_info("[SVG→WebP] skip: up-to-date #{webp_path}")
            next
          end

          # Step 1: SVG → PNG（rsvg-convert で高品質ラスタライズ）
          png_tmp = svg_path.sub(/\.svg\z/i, '.svg.tmp.png')
          rsvg_cmd = ['rsvg-convert', '--dpi-x', dpi.to_s, '--dpi-y', dpi.to_s, '-f', 'png', svg_path, '-o', png_tmp]
          Common.log_info("[SVG→WebP] rsvg-convert: #{svg_path}")
          unless system(*rsvg_cmd)
            Common.log_warn("[SVG→WebP] rsvg-convert に失敗しました: #{svg_path}")
            FileUtils.rm_f(png_tmp)
            next
          end

          # Step 2: PNG → lossless WebP（magick で可逆圧縮）
          # ここは非可逆側と違って method=6 のままでよい。lossless では画質が定義上変わらず、
          # 対象の絵文字が小さいため 4 と 6 で時間もサイズも同じだった（実測 2026-08-16: 0.02 秒・472 バイト）
          magick_cmd = ['magick', png_tmp, '-define', 'webp:lossless=true', '-define', 'webp:method=6', '-strip', webp_path]
          Common.log_info("[SVG→WebP] magick lossless: #{webp_path}")
          unless system(*magick_cmd)
            Common.log_warn("[SVG→WebP] magick 変換に失敗しました: #{png_tmp}")
            FileUtils.rm_f(png_tmp)
            next
          end

          # 中間 PNG を削除
          FileUtils.rm_f(png_tmp)
          tally.synchronize { converted += 1 }
        end

        Common.log_success("[SVG→WebP] #{converted} 件の SVG を lossless WebP に変換しました")
      end
      module_function :convert_svg_to_webp
    end
  end
end
