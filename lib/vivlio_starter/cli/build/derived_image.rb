# frozen_string_literal: true

require 'fileutils'
require 'shellwords'

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
        PDF_DERIVED_DIR = "#{Common::CACHE_DIR}/derived/pdf".freeze

        # 素材の多くが既に WebP（非可逆）で、派生はその二段目になる。ここで落とすと
        # 劣化が重なるため、resize の「高精細」と同じ 90 を採る。
        JPEG_QUALITY = 90

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

        module_function

        # 素材群の派生をまとめて用意し、{素材パス => 派生パス} を返す。
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

        # 1 件ぶんの派生を用意し、そのパスを返す（作れなければ nil）。
        def prepare(source)
          # --- Phase: 使えるキャッシュがあれば作り直さない ---
          base = derived_base(source)
          cached = fresh_derivative(base, source)
          return cached if cached

          # --- Phase: 透過があれば白へ落とす（PDF 限定・FLATTEN_OPTIONS 参照） ---
          flatten = opaque?(source) ? [] : FLATTEN_OPTIONS

          # --- Phase: JPEG と PNG を作って小さいほうを採る ---
          # 色数では分けられないことを実測で確かめた（2026-08-17・本書 78 件。色数 2,701 の
          # 写真は JPEG が、2,731 の図は PNG が勝つ）。サイズの勝敗は「写真か図か」と
          # ほぼ一致するので、この比較は画質の判定も兼ねている——写真は PNG で膨らみ、
          # 文字入りの図は PNG で縮むためである。
          FileUtils.mkdir_p(File.dirname(base))
          jpg = run_magick(source, "#{base}.jpg", *flatten, '-quality', JPEG_QUALITY.to_s)
          png = run_magick(source, "#{base}.png", *flatten)
          smaller_of(jpg, png)
        end

        # 素材のパス構造を派生側にも残す。ハッシュ名にすると、PDF が大きいときに
        # 「どの絵が効いているか」を人が追えなくなる。
        def derived_base(source)
          relative = source.sub(%r{\A\./}, '').delete_prefix('/')
          File.join(PDF_DERIVED_DIR, relative.sub(/\.[^.]+\z/, ''))
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

        # 実際に透明な画素があるか。アルファチャンネルの有無（`%A`）ではなく `%[opaque]`
        # を見る——WebP はチャンネルを持ちながら全画素が不透明なことがあり、`%A` だけでは
        # 透過を必要としない絵まで PNG へ送ってしまう。
        def opaque?(path)
          out = `magick identify -format '%[opaque]' #{Shellwords.escape(path)} 2>/dev/null`
          out.to_s.strip == 'True'
        end

        def derivable?(source)
          File.file?(source) && !PASSTHROUGH_EXTENSIONS.include?(File.extname(source).downcase)
        end
      end
    end
  end
end
