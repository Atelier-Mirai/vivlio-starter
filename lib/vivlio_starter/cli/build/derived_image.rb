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

        # 組み上がった PDF から測った「画素数 → 350ppi に要る画素数」の対応表。
        # ビルドをまたいで残す——索引を使わない本では Step 8 の再レンダが無いため、
        # 次回のビルドのステージングで初めて効く（§3.6）。
        METRICS_FILE = "#{DERIVED_ROOT}/pdf-metrics.yml".freeze

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
        def prepare_all(sources)
          targets = Array(sources).uniq.select { derivable?(it) }
          return {} if targets.empty?

          mapping = {}
          lock = Mutex.new
          ResizeCommands.each_in_parallel(targets) do |src|
            derived = prepare(src)
            lock.synchronize { mapping[src] = derived } if derived
          end
          mapping
        end

        # 1 件ぶんの派生を用意し、Derivative を返す（作れなければ nil）。
        def prepare(source)
          width, height, opaque = probe(source)
          return nil unless width.positive?

          # --- Phase: 使えるキャッシュがあれば作り直さない ---
          shrink_to = shrink_target(width, height)
          base = derived_base(source, shrink_to)
          cached = fresh_derivative(base, source)
          return Derivative.new(path: cached, width:, height:) if cached

          # --- Phase: 変換の指定を組み立てる ---
          # 透過は白へ落とす（FLATTEN_OPTIONS 参照）。過剰な画素数は段階へ切り上げて縮める。
          options = opaque ? [] : FLATTEN_OPTIONS.dup
          options += ['-resize', "#{shrink_to}x#{shrink_to}>"] if shrink_to

          # --- Phase: JPEG と PNG を作って小さいほうを採る ---
          # 色数では分けられないことを実測で確かめた（2026-08-17・本書 78 件。色数 2,701 の
          # 写真は JPEG が、2,731 の図は PNG が勝つ）。サイズの勝敗は「写真か図か」と
          # ほぼ一致するので、この比較は画質の判定も兼ねている——写真は PNG で膨らみ、
          # 文字入りの図は PNG で縮むためである。
          FileUtils.mkdir_p(File.dirname(base))
          jpg = run_magick(source, "#{base}.jpg", *options, '-quality', JPEG_QUALITY.to_s)
          png = run_magick(source, "#{base}.png", *options)
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

          required = {}
          out.each_line do |line|
            cols = line.split
            next unless cols.size >= 15 && cols[2] == 'image'

            width = cols[3].to_i
            ppi = cols[12].to_i
            next unless width.positive? && ppi.positive?

            key = "#{width}x#{cols[4]}"
            needed = (width * TARGET_PPI.to_f / ppi).ceil
            required[key] = [required[key].to_i, needed].max
          end
          return 0 if required.empty?

          FileUtils.mkdir_p(File.dirname(METRICS_FILE))
          File.write(METRICS_FILE, required.to_yaml)
          @metrics = required
          required.size
        end

        # 縮小先の画素数。縮める必要が無ければ nil（素材の画素数のまま渡す）。
        def shrink_target(width, height)
          needed = metrics["#{width}x#{height}"]
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
        def derived_base(source, shrink_to = nil)
          relative = source.sub(%r{\A\./}, '').delete_prefix('/')
          stem = relative.sub(/\.[^.]+\z/, '')
          stem = "#{stem}_#{shrink_to}" if shrink_to
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
