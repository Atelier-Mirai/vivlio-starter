# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/support/build_helper.rb
#
# 実ビルドを伴うテスト（判型 / マニュアルビルド / 冪等性 / EPUB / カナリア）の
# 共通基盤（docs/specs/test-suite-expansion-spec.md §15）。
#
#   - BookYmlPatcher : config/book.yml をブロック復元保証付きで書き換える
#   - VsBuilder      : vs build の実行と成果物 PDF の探索
#   - PdfInspector   : PDF のフォント・本文テキスト・アウトラインの検査
#
# BookYmlPatcher / VsBuilder は page_layout_test.rb から移設したもの。
# 検証ロジックは移設時に変更していない（VsBuilder にコマンド差し替え引数を
# 追加したのみ。既定値は従来どおり `vs build`）。
# =============================================================================

require "fileutils"
require "tmpdir"

begin
  require "pdf/reader"
rescue LoadError
  abort <<~MSG
    pdf-reader gem が見つかりません。インストールしてください：
      gem install pdf-reader
  MSG
end

module VsTestSupport
  BOOK_YML_PATH = "config/book.yml"

  # ===========================================================================
  # BookYmlPatcher — config/book.yml のプリセット行などを安全に書き換える
  # ===========================================================================
  module BookYmlPatcher
    # vs build が book.yml のページ設定から再生成する派生ファイル。
    # プリセットを切り替えてビルドすると最終プリセットの値で上書きされ、
    # book.yml だけ復元しても作業ツリーに差分が残る。apply のブロック終了時に
    # book.yml と一緒に元の内容へ復元する（docs/specs/test-suite-expansion-spec.md §15）。
    BUILD_GENERATED_FILES = [
      File.join("stylesheets", "page-settings.css"),
      "vivliostyle.config.js"
    ].freeze

    # 指定プリセットだけ有効化し、残りをコメントアウト。
    # ブロックを渡すと実行後に元の内容へ自動復元する。
    # ブロック内で vs build を実行すると派生ファイルも書き換わるため、
    # それらも退避し、book.yml と一緒に復元する。
    def self.apply(preset_name, &)
      raise "#{BOOK_YML_PATH} が見つかりません" unless File.exist?(BOOK_YML_PATH)

      original = File.read(BOOK_YML_PATH)
      generated_snapshot = snapshot_generated_files

      patched = original.lines.map do |line|
        next line unless line.match?(/^\s*#?\s*use:\s*[a-z0-9_]+/)

        if line.match?(/use:\s*#{Regexp.escape(preset_name)}(\s|$)/)
          # 先頭の「# 」を除去して有効化（インデント保持）
          line.sub(/^(\s*)#\s*/, '\1').rstrip + "\n"
        else
          # コメントアウト（既にコメントならそのまま）
          line.match?(/^\s*#/) ? line : line.sub(/^(\s*)/, '\1# ')
        end
      end.join

      File.write(BOOK_YML_PATH, patched)

      if block_given?
        yield
      end
    ensure
      if block_given?
        File.write(BOOK_YML_PATH, original) if original
        restore_generated_files(generated_snapshot) if generated_snapshot
      end
    end

    # BUILD_GENERATED_FILES の現在の内容を退避する（存在しなければ nil を記録）
    def self.snapshot_generated_files
      BUILD_GENERATED_FILES.to_h { |path| [path, (File.read(path) if File.exist?(path))] }
    end
    private_class_method :snapshot_generated_files

    # 退避した派生ファイルを復元する。退避時に存在しなかったものは削除して元に戻す。
    def self.restore_generated_files(snapshot)
      snapshot.each do |path, content|
        if content
          File.write(path, content)
        elsif File.exist?(path)
          File.delete(path)
        end
      end
    end
    private_class_method :restore_generated_files

    # `key: value` 形式のトップレベル設定行を書き換える汎用版（EPUB 切替等に使用）。
    # 例: rewrite_line(/^(\s*)targets:.*$/, '\1targets: epub') { ... }
    # ブロック終了時に必ず元の内容へ復元する。
    def self.rewrite_line(pattern, replacement)
      raise "#{BOOK_YML_PATH} が見つかりません" unless File.exist?(BOOK_YML_PATH)

      original = File.read(BOOK_YML_PATH)
      File.write(BOOK_YML_PATH, original.sub(pattern, replacement))
      yield
    ensure
      File.write(BOOK_YML_PATH, original) if original
    end
  end

  # ===========================================================================
  # VsBuilder — vs build の実行と PDF 探索
  # ===========================================================================
  module VsBuilder
    OUTPUT_DIRS = %w[dist output _dist _output].freeze

    # リポジトリのソースコードを直接実行するコマンド（インストール済み gem に依存しない）。
    # マニュアルビルド系テストは「現在のソース」を検証対象とするためこちらを使う。
    def self.repo_vs_command
      repo_root = File.expand_path("../../..", __dir__)
      "#{RbConfig.ruby} -I#{File.join(repo_root, 'lib')} #{File.join(repo_root, 'bin', 'vs')}"
    end

    # @param vs_command [String] 実行する vs コマンド（既定: PATH 上の `vs`）
    # @return [Array(Boolean, String)] [成功?, 出力全文]
    def self.build!(vs_command: "vs")
      output = `#{vs_command} build 2>&1`
      [$?.success?, output]
    end

    # 直近に更新されたPDFを返す
    def self.find_latest_pdf
      candidates = OUTPUT_DIRS
        .filter_map { |dir| Dir.glob("#{dir}/**/*.pdf") if Dir.exist?(dir) }
        .flatten
      candidates += Dir.glob("*.pdf")
      candidates.max_by { |f| File.mtime(f) }
    end
  end

  # ===========================================================================
  # PdfInspector — PDF のフォント・テキスト・アウトライン検査（FT / ID / CN 用）
  # ===========================================================================
  module PdfInspector
    # 1 フォントの観測結果
    FontInfo = Data.define(:page, :name, :subtype, :embedded) do
      def type3? = subtype == :Type3
    end

    # 全ページのフォントを列挙する（同名フォントもページごとに観測する）
    # @return [Array<FontInfo>]
    def self.fonts(pdf_path)
      reader = PDF::Reader.new(pdf_path)
      reader.pages.flat_map do |page|
        page.fonts.map { |_label, ref| describe_font(page.objects, ref, page.number) }
      end
    end

    # 各ページの抽出テキスト（冪等性比較用）
    # @return [Array<String>]
    def self.page_texts(pdf_path)
      PDF::Reader.new(pdf_path).pages.map(&:text)
    end

    # アウトライン（しおり）のタイトルを階層順に平坦化して返す
    # @return [Array<String>]
    def self.outline_titles(pdf_path)
      reader = PDF::Reader.new(pdf_path)
      root = reader.objects.deref(reader.objects.trailer[:Root])
      outlines = reader.objects.deref(root[:Outlines])
      return [] unless outlines

      collect_outline_titles(reader.objects, outlines[:First])
    end

    # --- 内部実装 ---

    def self.describe_font(objects, font_ref, page_number)
      font = objects.deref(font_ref)
      descriptor = resolve_descriptor(objects, font)
      embedded = descriptor.is_a?(Hash) &&
                 %i[FontFile FontFile2 FontFile3].any? { descriptor.key?(it) }

      FontInfo.new(
        page: page_number,
        name: objects.deref(font[:BaseFont]).to_s,
        subtype: objects.deref(font[:Subtype]),
        embedded: embedded
      )
    end
    private_class_method :describe_font

    # Type0（CID 合成フォント）は DescendantFonts 側に FontDescriptor を持つ
    def self.resolve_descriptor(objects, font)
      if objects.deref(font[:Subtype]) == :Type0
        descendants = objects.deref(font[:DescendantFonts])
        descendant = objects.deref(descendants&.first)
        descendant && objects.deref(descendant[:FontDescriptor])
      else
        objects.deref(font[:FontDescriptor])
      end
    end
    private_class_method :resolve_descriptor

    def self.collect_outline_titles(objects, first_ref)
      titles = []
      node = objects.deref(first_ref)
      while node
        titles << decode_pdf_string(objects.deref(node[:Title]))
        titles.concat(collect_outline_titles(objects, node[:First])) if node[:First]
        node = objects.deref(node[:Next])
      end
      titles
    end
    private_class_method :collect_outline_titles

    # PDF 文字列は UTF-16BE（BOM 付き）の場合がある
    def self.decode_pdf_string(raw)
      str = raw.to_s
      if str.bytes.first(2) == [0xFE, 0xFF]
        str.byteslice(2..).force_encoding("UTF-16BE").encode("UTF-8")
      else
        str.dup.force_encoding("UTF-8")
      end
    rescue EncodingError
      str.to_s
    end
    private_class_method :decode_pdf_string
  end

  # ===========================================================================
  # EpubInspector — EPUB の spine 構成・本文テキスト検査（ターゲット整合性テスト用）
  # ===========================================================================
  module EpubInspector
    # spine（読み順）に並ぶドキュメントの basename 配列（拡張子なし）を返す。
    # 例: ["cover", "00-preface", "_part1", "11-workflow", ..., "_indexpage", "_colophon"]
    # @return [Array<String>]
    def self.spine_documents(epub_path)
      with_unzipped(epub_path) do |dir|
        opf = Dir.glob(File.join(dir, "**", "content.opf")).first
        next [] unless opf

        content = File.read(opf, encoding: "UTF-8")
        manifest = content.scan(/<item\b[^>]*\bid="([^"]+)"[^>]*\bhref="([^"]+)"/).to_h
        content.scan(/<itemref\b[^>]*\bidref="([^"]+)"/).flatten.filter_map do |idref|
          href = manifest[idref]
          File.basename(href, ".*") if href
        end
      end
    end

    # 全 xhtml の本文テキスト（タグ・実体参照・空白を除去）をファイル名順で連結して返す。
    # フォーマット間/単体・複合間の「本文がほぼ同じ」を量・内容で比較するための指紋。
    # @return [String]
    def self.body_text(epub_path)
      with_unzipped(epub_path) do |dir|
        Dir.glob(File.join(dir, "**", "*.xhtml")).sort.map do |path|
          strip_markup(File.read(path, encoding: "UTF-8"))
        end.join
      end
    end

    # EPUB パッケージ内に同梱された .webp ファイルの相対パス配列を返す。
    # Kindle は WebP 非対応のため、トランスコード後は 0 件であるべき
    # （docs/specs/epub-kindle-webp-transcode-spec.md §6-1）。
    # @return [Array<String>]
    def self.webp_files(epub_path)
      with_unzipped(epub_path) do |dir|
        Dir.glob(File.join(dir, "**", "*.webp")).map { it.delete_prefix("#{dir}/") }.sort
      end
    end

    # 全 xhtml の <img src> のうち、EPUB 内の実体に解決できない参照の配列を返す
    # （data: / 外部 URL は対象外）。空配列ならリンク切れなし。
    # @return [Array<String>]
    def self.unresolved_image_refs(epub_path)
      with_unzipped(epub_path) do |dir|
        Dir.glob(File.join(dir, "**", "*.xhtml")).sort.flat_map do |xhtml|
          html = File.read(xhtml, encoding: "UTF-8")
          html.scan(/<img\b[^>]*\bsrc="([^"]*)"/i).flatten.reject do |src|
            src.start_with?("data:", "http://", "https://") ||
              File.exist?(File.expand_path(decode_entities(src), File.dirname(xhtml)))
          end
        end.uniq.sort
      end
    end

    def self.decode_entities(str)
      str.gsub("&apos;", "'").gsub("&quot;", '"').gsub("&lt;", "<").gsub("&gt;", ">").gsub("&amp;", "&")
    end
    private_class_method :decode_entities

    def self.with_unzipped(epub_path)
      Dir.mktmpdir("vs-epub-inspect") do |dir|
        system("unzip", "-o", "-q", File.expand_path(epub_path), "-d", dir,
               out: File::NULL, err: File::NULL)
        yield(dir)
      end
    end
    private_class_method :with_unzipped

    def self.strip_markup(html)
      html.gsub(/<[^>]+>/, " ").gsub(/&[a-zA-Z#0-9]+;/, " ").gsub(/\s+/, "")
    end
    private_class_method :strip_markup
  end
end
