# frozen_string_literal: true

require 'open3'

module VivlioStarter
  module PDF
    # 抜き出した図を、著者が持っている元の画像と見た目で突き合わせる（pdf-read-ocr-improvement-notes.md §4.18）。
    # スキャンから切り出した図は印刷を撮り直したもので、解像度が半分ほどになり、網点や色のずれも入る。
    # 元の画像があれば、それに差し替えたほうが原稿の画像として使え、ファイル名も原稿のものに戻る。
    #
    # 縮めた灰色の画像（16×16）の相関で比べる。平均を引いて長さをそろえるので、印刷とスキャンで変わる
    # 明るさとコントラストは効かない。97 章のスキャンから切り出した 13 枚で、正しい元の画像との相関は
    # 0.58〜0.99、2 番目に近い画像は 0.47 以下だった。文字の層のある PDF から抜き出した画像は 1.00 になる
    class ImageMatcher
      # 比べる画像の大きさ（px）
      SIZE = 16
      # 採る相関の下限と、2 番目に近い画像との差の下限。切り出しが図の大きな部分を欠くと相関が下がり
      # （下半分を欠いた 97 章の表紙で 0.28）、似た画像の取り違えは差で防ぐ
      MIN_CORRELATION = 0.5
      MIN_MARGIN = 0.2
      # 縦横比の差の上限（比の対数）。図の一部を欠いた切り出しでも、相関がはっきり高ければ採る（元の画像に
      # 差し替えれば欠けも直る。97 章の光格子時計の絵は差 0.10・相関 0.80）。形が大きく違うものは採らない
      MAX_ASPECT_GAP = 0.2
      # 突き合わせる画像の拡張子
      IMAGE_EXTENSIONS = %w[.webp .png .jpg .jpeg .gif .tif .tiff .bmp].freeze

      Fingerprint = Data.define(:vector, :aspect)

      # @param dir [String] 元の画像を置いたフォルダ（サブフォルダは見ない）
      def initialize(dir)
        @originals = Dir.children(dir).sort.filter_map do |name|
          path = File.join(dir, name)
          next unless File.file?(path) && IMAGE_EXTENSIONS.include?(File.extname(name).downcase)

          fingerprint = fingerprint(path)
          [name, path, fingerprint] if fingerprint
        end
      end

      # @return [Array<String>] 突き合わせに使える元の画像のファイル名
      def names = @originals.map(&:first)

      # @return [Array(String, String), nil] 見た目の一致した元の画像の [ファイル名, パス]。決まらなければ nil
      def match(path)
        target = fingerprint(path)
        return nil unless target

        best, second = @originals.map { |name, original, print| [name, original, correlation(target, print), print] }
                                 .sort_by { -it[2] }
        return nil unless best && best[2] >= MIN_CORRELATION && (second.nil? || best[2] - second[2] >= MIN_MARGIN)
        return nil if Math.log(target.aspect / best[3].aspect).abs > MAX_ASPECT_GAP

        best.first(2)
      end

      private

      # 灰色にして 16×16 に縮めた画素から平均を引き、長さを 1 にそろえる。読めない画像は nil
      def fingerprint(path)
        size, size_status = Open3.capture2('magick', 'identify', '-format', '%w %h', "#{path}[0]")
        pixels, pixel_status = Open3.capture2('magick', "#{path}[0]", '-colorspace', 'Gray', '-resize', "#{SIZE}x#{SIZE}!",
                                              '-depth', '8', 'gray:-', binmode: true)
        return nil unless size_status.success? && pixel_status.success?

        width, height = size.split.map(&:to_f)
        values = pixels.unpack('C*')
        return nil unless values.size == SIZE * SIZE && width.positive? && height.positive?

        mean = values.sum.fdiv(values.size)
        centered = values.map { it - mean }
        length = Math.sqrt(centered.sum { it * it })
        Fingerprint.new(vector: centered.map { length.zero? ? 0.0 : it / length }, aspect: width / height)
      rescue Errno::ENOENT
        nil
      end

      def correlation(a, b) = a.vector.zip(b.vector).sum { |x, y| x * y }
    end
  end
end
