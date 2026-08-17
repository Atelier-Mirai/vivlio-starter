# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'shellwords'
require 'yaml'

module VivlioStarter
  module CLI
    module Build
      # ------------------------------------------------
      # DerivedImage: PDF へ渡す画像の派生を作る
      # ------------------------------------------------
      # PDF は WebP を格納できない（ISO 32000 に該当するフィルタが無い）。渡された
      # Chromium はデコードして Flate へ入れ直すが、可逆圧縮では写真がほとんど縮まない
      # ため、素材 280KB が PDF 内で 1,963KB になる。JPEG なら DCTDecode でストリームが
      # そのまま入り、素材のサイズがそのまま PDF のサイズになる
      # （`image-format-per-target-spec.md` §1.2）。
      #
      # **著者の images/ には触れない。** 派生は .cache/vs/derived/pdf/ にだけ作り、
      # PDF 枝がステージングする pdf/ の HTML だけがそこを指す（同 §3.1）。EPUB は
      # html/ の原本を読むので、WebP が最適な EPUB 側は素材のまま変換ゼロで済む。
      # ------------------------------------------------
      module DerivedImage
        # clean が消すのは .cache/vs/build/ だけなので、ここはビルドをまたいで残る
        # （theme-images / covers と同じ流儀）。素材より新しければ作り直さない。
        DERIVED_ROOT = "#{Common::CACHE_DIR}/derived".freeze
        PDF_DERIVED_DIR = "#{DERIVED_ROOT}/pdf".freeze

        # 組み上がった PDF から測った、画素数ごとの「要る画素数」と「版面に対する表示幅の
        # 割合」の対応表。ビルドをまたいで残す——索引を使わない本では Step 8 の再レンダが
        # 無いため、次回のビルドのステージングで初めて効く（§3.6）。
        #
        # **割合は EPUB / Kindle が使う。** あちらはリフローなのでページが確定せず、
        # 「組んでから測る」ができない。しかし版面に対する相対幅は同じなので——`width=30%`
        # の指定も 2 列に並べた表も、PDF 側の測定に既に現れている——読者の画面幅に掛ければ
        # 必要画素数が出る。
        METRICS_FILE = "#{DERIVED_ROOT}/image-metrics.yml".freeze

        # 素材の多くが既に WebP（非可逆）で、派生はその二段目になる。ここで落とすと
        # 劣化が重なるため、resize の「高精細」と同じ 90 を採る。
        JPEG_QUALITY = 90

        # 印刷に必要な解像度。これを下回らせない。
        TARGET_PPI = 350

        # 派生の画素数の段階。必要画素数はここへ**切り上げる**——足りない解像度は後から
        # 取り戻せず、印刷では粗さとして残るためである。実寸ちょうどで作れば数 % 小さく
        # なるが、同じ素材が似た大きさで何箇所にも置かれるとき段階なら 1 つを使い回せる
        # （§3.6）。
        SIZE_STEPS = [480, 800, 1280, 2048].freeze

        # 派生を作らない拡張子。SVG はベクタのまま PDF へ入るのが最善で、ラスタ化が
        # 要る場合は Techbook モードの Type 3 対策（`ResizeCommands.convert_svg_to_webp`）
        # が別途受け持つ。
        PASSTHROUGH_EXTENSIONS = %w[.svg].freeze

        # 派生の拡張子。既存キャッシュを探すときも、この順で見る。
        DERIVED_EXTENSIONS = %w[.jpg .png].freeze

        # 透過を白へ落とす指定。**PDF に限って**透過を捨てる根拠は、地が紙の白だから
        # である（`@page` に背景色の指定は無い。2026-08-17 確認）——透過部分はどのみち
        # 白く出るので、フラット化しても 1 ピクセルも変わらない。代わりに JPEG が使えて、
        # 本書の花の見本 12 枚は PDF 内 37.22 MB → 6.31 MB になる。
        #
        # **EPUB / Kindle では捨てない。** あちらは html/ の原本（素材そのもの）を読む。
        # Kindle 端末のダークモードは背景を黒にするが画像は反転しないため、白で塗って
        # あると矩形が浮く。テーマ素材（`stylesheets/images/`）も CSS 背景で入るので
        # `<img>` を経由せず、この差し替えの対象に最初から入らない——章扉の生成では
        # `-trim` が透過を「絵の範囲」の手掛かりに使っており、潰してはならない。
        FLATTEN_OPTIONS = %w[-background white -alpha remove -alpha off].freeze

        # 派生 1 件。width / height は**素材の**画素数で、縮小しても表示サイズが動かない
        # よう HTML の属性として書き出すために持ち歩く（§3.6 の「懸念は実測で否定された」）。
        Derivative = Data.define(:path, :width, :height)

        module_function

        # 素材群の派生をまとめて用意し、{素材パス => Derivative} を返す。
        #
        # 派生が要らないもの（SVG）と作れなかったものは戻り値に含めない——呼び出し側は
        # 「マップに無ければ素材のまま」と読めばよく、失敗が組版を止めない。
        # @param sources [Hash{String => Boolean}, Array<String>] 素材パス → 透過を保つか。
        #   配列を渡した場合はすべてフラット化の対象とする。
        # @return [Hash{Array(String, Boolean) => Derivative}] [素材パス, 透過保持] → 派生
        def prepare_all(sources)
          requests = normalize_requests(sources)
          return {} if requests.empty?

          mapping = {}
          lock = Mutex.new
          ResizeCommands.each_in_parallel(requests) do |(src, keep_alpha)|
            derived = prepare(src, keep_alpha:)
            lock.synchronize { mapping[[src, keep_alpha]] = derived } if derived
          end
          mapping
        end

        # {パス => 透過保持} を [パス, 透過保持] の一意な配列へ。同じ絵が地色のブロックの
        # 中と外の両方に出ることがあるので、両方を作れるようキーに透過保持を含める。
        def normalize_requests(sources)
          pairs = case sources
                  when Hash then sources.to_a
                  else Array(sources).map { it.is_a?(Array) ? it : [it, false] }
                  end
          pairs.uniq.select { derivable?(it[0]) }
        end

        # 1 件ぶんの派生を用意し、Derivative を返す（作れなければ nil）。
        #
        # @param keep_alpha [Boolean] 透過を保つか。**背景色を持つブロックの中に置かれた画像は
        #   true にしなければならない**——白く塗ると、その矩形が地色の上に浮く（実測: コラムの
        #   緑地に絵文字の白い四角が出た）。判定は呼び出し側が HTML の祖先を見て行う。
        def prepare(source, keep_alpha: false)
          width, height, opaque = probe(source)
          return nil unless width.positive?

          flatten = !opaque && !keep_alpha

          # --- Phase: 使えるキャッシュがあれば作り直さない ---
          # フラット化したものと透過を残したものは**別のファイル**として持つ。同じ絵が
          # 地色のブロックの中と外の両方に出ることがあり、片方で上書きしてはならない。
          shrink_to = shrink_target(width, height)
          base = derived_base(source, shrink_to, alpha: !flatten && !opaque)
          cached = fresh_derivative(base, source)
          return Derivative.new(path: cached, width:, height:) if cached

          # --- Phase: 変換の指定を組み立てる ---
          # 過剰な画素数は段階へ切り上げて縮める。透過の扱いは FLATTEN_OPTIONS 参照。
          options = flatten ? FLATTEN_OPTIONS.dup : []
          options += ['-resize', "#{shrink_to}x#{shrink_to}>"] if shrink_to

          # --- Phase: JPEG と PNG を作って小さいほうを採る ---
          # 色数では分けられないことを実測で確かめた（2026-08-17・本書 78 件。色数 2,701 の
          # 写真は JPEG が、2,731 の図は PNG が勝つ）。サイズの勝敗は「写真か図か」と
          # ほぼ一致するので、この比較は画質の判定も兼ねている——写真は PNG で膨らみ、
          # 文字入りの図は PNG で縮むためである。
          FileUtils.mkdir_p(File.dirname(base))
          png = run_magick(source, "#{base}.png", *options)

          # 透過を残すなら JPEG は選べない（持てない）。サイズの比較をせず PNG で決める。
          return png && Derivative.new(path: png, width:, height:) if !opaque && !flatten

          jpg = run_magick(source, "#{base}.jpg", *options, '-quality', JPEG_QUALITY.to_s)
          winner = smaller_of(jpg, png)
          winner && Derivative.new(path: winner, width:, height:)
        end

        # 組み上がった PDF から実効解像度を測り、画素数ごとの必要画素数を記録する。
        #
        # `pdfimages` はどのファイルから来たかを教えないが、必要なのは「画素数 W×H の
        # 素材には何 px あれば足りるか」だけなので、**画素数をキーに ppi の最小値**
        # （＝最も大きく表示されている場面）を採れば決まる（§3.6）。同じ画素数の素材が
        # 複数あっても、最も大きく表示されているものに合わせるので 350 ppi を下回らない。
        #
        # @return [Integer] 記録した画素数の種類（測れなければ 0）
        def measure!(pdf_path)
          return 0 unless File.file?(pdf_path)

          out, status = Open3.capture2('pdfimages', '-list', pdf_path, err: File::NULL)
          return 0 unless status.success?

          text_width = text_area_width_mm
          # **既存を引き継ぐ。** 2 回目以降のビルドでは 1 回目から縮小版が組まれるため、
          # 素材の画素数のエントリ（初回にしか現れない）が測定から消える。EPUB / Kindle は
          # 素材から派生を作るので、そちらのキーが引けなくなると縮小が効かなくなる。
          # 素材が差し替わればキー自体が変わるので、古い値が悪さをすることはない。
          measured = metrics.dup
          out.each_line do |line|
            cols = line.split
            next unless cols.size >= 15 && cols[2] == 'image'

            width = cols[3].to_i
            ppi = cols[12].to_i
            next unless width.positive? && ppi.positive?

            entry = measured["#{width}x#{cols[4]}"] ||= { 'px' => 0, 'ratio' => 0.0 }
            entry['px'] = [entry['px'], (width * TARGET_PPI.to_f / ppi).ceil].max
            # 版面幅が引けないときは 1.0（版面いっぱい）に倒す——縮めすぎるより素材のまま運ぶ
            display_mm = width / ppi.to_f * 25.4
            ratio = text_width ? (display_mm / text_width) : 1.0
            entry['ratio'] = [entry['ratio'], ratio.clamp(0.0, 1.0)].max
          end
          return 0 if measured.empty?

          FileUtils.mkdir_p(File.dirname(METRICS_FILE))
          File.write(METRICS_FILE, measured.to_yaml)
          @metrics = measured
          measured.size
        end

        # 読者の画面幅（EPUB 2048px / Kindle 1024px）に対して要る画素数。
        #
        # PDF で測った**版面に対する割合**を掛けるだけでよい。リフローではページが確定せず
        # 「組んでから測る」ができないが、相対幅は組版系によらないからである——版面の半分に
        # 並べた見本は EPUB でも画面の半分を占める。測っていなければ画面幅そのもの（＝安全側）。
        #
        # @param viewport_px [Integer] そのターゲットの画面幅
        # @return [Integer] 要る画素数（画面幅を超えない）
        def viewport_target(width, height, viewport_px)
          ratio = metrics.dig("#{width}x#{height}", 'ratio')
          return viewport_px unless ratio&.positive?

          [(viewport_px * ratio).ceil, viewport_px].min
        end

        # 版面幅（mm）。同じ計算を 2 度持たないよう `BookSettingsCss` へ委ねる。
        # 設定が無い直接ビルドや、pre_process が読み込まれていない文脈では nil。
        def text_area_width_mm
          return nil unless Common.configured?

          page_cfg = PreProcessCommands::BookSettingsCss.build_page_cfg(Common::CONFIG)
          PreProcessCommands::BookSettingsCss.text_area_width_mm(page_cfg)
        rescue StandardError
          nil
        end

        # 縮小先の画素数。縮める必要が無ければ nil（素材の画素数のまま渡す）。
        def shrink_target(width, height)
          needed = metrics.dig("#{width}x#{height}", 'px')
          return nil unless needed&.positive?
          return nil if needed >= width

          # 段階へ切り上げる。**段階を超えるときは必要画素数そのものへ丸める**——版面
          # 全幅に置かれた 4K 素材がこれに当たり、2048px で打ち止めにすると素材のまま
          # 運ばれてしまう。段階の利点（使い回し）は 2048px 以下で効き、それを超える
          # 大きな絵は稀なので実寸で作ってよい。
          SIZE_STEPS.find { it >= needed } || needed
        end

        # 測定結果。ビルドをまたいで残るので、索引を使わない本では次回から効く。
        def metrics
          @metrics ||= (YAML.safe_load_file(METRICS_FILE) if File.file?(METRICS_FILE)) || {}
        rescue StandardError
          @metrics = {}
        end

        # プロセス内キャッシュを捨てる（テスト用）。
        def reset_cache!
          @metrics = nil
        end

        # 素材のパス構造を派生側にも残す。ハッシュ名にすると、PDF が大きいときに
        # 「どの絵が効いているか」を人が追えなくなる。縮小したものは画素数を接尾辞に
        # 持たせ、等倍と共存させる（1 回目は等倍、Step 8 以降は縮小版を使うため）。
        def derived_base(source, shrink_to = nil, alpha: false)
          relative = source.sub(%r{\A\./}, '').delete_prefix('/')
          stem = relative.sub(/\.[^.]+\z/, '')
          stem = "#{stem}_#{shrink_to}" if shrink_to
          stem = "#{stem}_alpha" if alpha
          File.join(PDF_DERIVED_DIR, stem)
        end

        # 既存の派生が使えるか。JPEG / PNG のどちらで作られたかは前回の判定次第なので
        # 両方を見る。素材が更新されていれば作り直す。
        def fresh_derivative(base, source)
          src_mtime = File.mtime(source)
          DERIVED_EXTENSIONS.map { "#{base}#{it}" }
                            .find { File.file?(it) && File.mtime(it) >= src_mtime }
        end

        # 勝ったほうを残し、負けたほうは消す。両方失敗していれば nil。
        def smaller_of(jpg, png)
          return png unless jpg
          return jpg unless png

          if File.size(jpg) <= File.size(png)
            FileUtils.rm_f(png)
            jpg
          else
            FileUtils.rm_f(jpg)
            png
          end
        end

        # 変換して成功したパスを返す。失敗したら nil（呼び出し側は素材のまま使う）。
        def run_magick(source, dest, *options)
          cmd = ['magick', source, '-strip', *options, dest]
          return dest if system(*cmd, out: File::NULL, err: File::NULL) && File.size?(dest)

          FileUtils.rm_f(dest)
          Common.log_warn("PDF 向け画像の変換に失敗しました: #{source}")
          nil
        end

        # 画素数と「実際に透明な画素があるか」を 1 回の identify で取る。
        #
        # 透過の判定にアルファチャンネルの有無（`%A`）ではなく `%[opaque]` を使うのは、
        # WebP がチャンネルを持ちながら全画素が不透明なことがあるためである。`%A` だけでは
        # 透過を必要としない絵まで別扱いしてしまう。
        def probe(path)
          out = `magick identify -format '%w %h %[opaque]' #{Shellwords.escape(path)} 2>/dev/null`
          width, height, opaque = out.to_s.split
          [width.to_i, height.to_i, opaque == 'True']
        end

        def derivable?(source)
          File.file?(source) && !PASSTHROUGH_EXTENSIONS.include?(File.extname(source).downcase)
        end
      end
    end
  end
end
