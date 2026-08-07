# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/font_manager.rb
# ================================================================
# 責務:
#   Google Fonts からフォントをダウンロードし、ローカルにキャッシュする。
#   書籍のスタイルシートで使用するフォントを事前に準備する。
#
# 機能:
#   - Google Fonts CSS API からフォント URL を取得
#   - TTF/OTF/WOFF/WOFF2 ファイルをダウンロード
#   - ローカルの fonts/ ディレクトリにキャッシュ
#   - @font-face を定義した CSS バンドルを生成
#
# 標準フォント（ダウンロード不要）:
#   - Zen Old Mincho: 本文用（明朝体）
#   - Zen Kaku Gothic New: 見出し・ノンブル用（ゴシック体）
#   - Zen Maru Gothic: コラム用（丸ゴシック体）
#   - HackGen35 Console NF: コードブロック用（等幅）＋記号フォールバック（Nerd Fonts）
#
# 依存:
#   - Common: ログ出力・設定読み込み
#   - Net::HTTP: Google Fonts API へのリクエスト
# ================================================================

require 'fileutils'
require 'net/http'
require 'uri'
require 'openssl'
require_relative 'common'

module VivlioStarter
  module CLI
    # Google Fonts ダウンロード・キャッシュ管理
    module FontManager
      USER_AGENT = 'VivlioStarter/FontManager (+https://github.com/Atelier-Mirai/vivlio-starter)'
      GOOGLE_FONTS_ENDPOINT = 'https://fonts.googleapis.com/css2'

      # 標準搭載フォント（ダウンロード不要）
      # page-settings.css の @font-face で静的 TTF が定義されているファミリ名
      STANDARD_FONT_FAMILIES = Set.new([
                                         'Zen Old Mincho',
                                         'Zen Kaku Gothic New',
                                         'Zen Maru Gothic',
                                         'HackGen35 Console NF'
                                       ]).freeze

      module_function

      # 指定されたフォントが利用可能か確認し、不足分をダウンロードする
      #
      # @param font_names [Array<String>, String] フォント名（複数可）
      # @return [void]
      #
      # 処理フロー:
      #   1. 標準フォントはスキップ
      #   2. 既にキャッシュ済みのフォントはスキップ
      #   3. Google Fonts から CSS を取得しフォントファイルをダウンロード
      #   4. @font-face バンドル CSS を更新
      def ensure_fonts_available(font_names)
        names = normalize_font_names(font_names)
        return if names.empty?

        downloaded_entries = []
        names.each do |name|
          next if standard_font?(name)
          next if google_font_installed?(name)

          entries = download_google_font(name)
          downloaded_entries.concat(Array(entries))
        end
      rescue StandardError => e
        Common.log_warn("フォント準備中にエラーが発生しました: #{e.class}: #{e.message}")
      ensure
        update_google_bundle!(downloaded_entries)
      end

      def standard_font?(name)
        STANDARD_FONT_FAMILIES.include?(name)
      end

      def google_font_installed?(name)
        dir = File.join(google_fonts_dir, slug_for(name))
        return false unless Dir.exist?(dir)

        !Dir.glob(File.join(dir, '*.{ttf,otf,woff,woff2}')).empty?
      end

      def download_google_font(name)
        css = fetch_google_css(name)
        unless css && !css.strip.empty?
          Common.log_warn("Google Fonts のCSSが取得できませんでした: #{name}",
                          detail: "→ このままだとお使いの PC のフォントで組まれ、入稿用 PDF に Type 3 フォントが混入します。\n" \
                                  '→ 同梱書体（Zen Old Mincho / Zen Kaku Gothic New / Zen Maru Gothic）か、' \
                                  'Google Fonts にある書体名を指定してください。')
          return []
        end

        # 太さは 2 面（本文用と太字用）に絞る。全ウェイトを落とすと和文 1 書体で
        # 数十 MB になるうえ、CSS が使うのはこの 2 面だけ。
        css = select_weight_faces(css, name)

        slug = slug_for(name)
        family_dir = File.join(google_fonts_dir, slug)
        FileUtils.mkdir_p(family_dir)

        downloaded_files = {}
        processed_blocks = []
        FileUtils.rm_f(File.join(family_dir, 'font.json'))
        css.gsub(/@font-face\s*{[^}]+}/m) do |block|
          processed_block = block.gsub(/url\(([^)]+)\)/) do
            raw = Regexp.last_match(1).strip
            url = raw.gsub(/\A['"]|['"]\z/, '')
            if url.start_with?('https://fonts.gstatic.com/')
              begin
                filename = readable_filename_from(block, url, slug)
                dest = File.join(family_dir, filename)
                download_font_file(url, dest)
                downloaded_files[filename] = true
                %(url("google/#{slug}/#{filename}"))
              rescue StandardError => e
                Common.log_warn("フォントファイルの取得に失敗しました: #{url} (#{e.class}: #{e.message})")
                "url(#{raw})"
              end
            else
              "url(#{raw})"
            end
          end
          processed_blocks << processed_block.strip
          processed_block
        end

        Common.log_success("Google Fonts から #{name} を取得しました (#{downloaded_files.keys.size} ファイル)")
        return [] if processed_blocks.empty?

        [[name, build_block_entry(name, processed_blocks.join("\n\n"))]]
      rescue StandardError => e
        Common.log_warn("Google Fonts の取得処理でエラーが発生しました: #{name} (#{e.class}: #{e.message})")
        []
      end

      def download_font_file(url, dest_path)
        return if File.exist?(dest_path)

        uri = URI.parse(url)
        response = perform_get(uri)

        raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        File.binwrite(dest_path, response.body)
        warn_unless_static_truetype(dest_path)
      end

      # 落としたフォントが静的 TrueType かを検査する。
      #
      # Chromium は **CFF ベース（OTF）** と **可変フォント** を Type 3 として PDF へ
      # 埋め込むため、どちらも入稿では使えない。日本語 Google Fonts 55 書体の実測
      # （2026-08-07）では全書体とも静的 TrueType が配信されたが、それは
      # perform_get の User-Agent がブラウザでない（＝旧来の静的 TTF 配信になる）ことに
      # 依存している。配信方針が変わったときに静かに壊れないよう、ここで見張る。
      def warn_unless_static_truetype(path)
        tags = sfnt_table_tags(path)
        return if tags.empty?
        return if tags.include?('glyf') && !tags.include?('fvar')

        reason = tags.include?('CFF ') ? 'CFF ベース（OTF）' : '可変フォント'
        Common.log_warn("取得したフォントが静的 TrueType ではありません: #{File.basename(path)}（#{reason}）",
                        detail: '→ Chromium がこの書体を Type 3 フォントとして PDF へ埋め込むため、' \
                                "入稿用 PDF では使えません。\n" \
                                '→ 同梱書体（Zen Old Mincho / Zen Kaku Gothic New / Zen Maru Gothic）をお使いください。')
      end

      # sfnt のテーブルディレクトリからタグ一覧を読む（先頭数 KB だけで足りる）。
      def sfnt_table_tags(path)
        header = File.binread(path, 12).to_s
        return [] if header.bytesize < 12

        count = header[4, 2].unpack1('n').to_i
        return [] if count.zero? || count > 512

        directory = File.binread(path, count * 16, 12).to_s
        (0...count).filter_map { directory[it * 16, 4] }
      rescue StandardError
        []
      end

      def readable_filename_from(block, url, slug)
        parsed = URI.parse(url)
        basename = File.basename(parsed.path)

        weight = block[/font-weight:\s*(\d{3})/, 1] || '400'
        style = block[/font-style:\s*(italic|normal)/, 1] || 'normal'
        format = block[/format\(['"](\w+)['"]\)/, 1]

        ext = File.extname(basename)
        ext = ".#{format_to_extension(format)}" if (ext.nil? || ext.empty?) && format
        ext = '.ttf' if ext.nil? || ext.empty?

        parts = [slug.tr('_', '-')]
        parts << weight unless weight == '400'
        parts << style if style != 'normal'

        "#{parts.join('-')}#{ext}"
      rescue StandardError
        File.basename(url)
      end

      def format_to_extension(format)
        return nil if format.nil?

        case format.downcase
        when 'woff2' then 'woff2'
        when 'woff' then 'woff'
        when 'opentype' then 'otf'
        when 'truetype' then 'ttf'
        else
          format
        end
      end

      # ------------------------------------------------------------------
      # ウェイトの選定（Type 3 フォント対策の本体）
      # ------------------------------------------------------------------
      # かつては CSS を `family=<名前>` だけで要求していたため、Google は
      # **既定の 400 を 1 面返すだけ**だった。見出しや強調は太字を要求するので、
      # Bold 字面が無い書体では Chromium が faux-bold を合成し、それを
      # **Type 3 フォント**として PDF へ埋め込む——技術書典等の入稿で不可。
      # 実測（2026-08-07）: Noto Sans JP 指定の 1 章ビルドで Type 3 が 195 件。
      #
      # 日本語 Google Fonts 55 書体の調査では、配信されるのは全書体とも
      # 静的 TrueType だが、**太字を持つのは 24 書体だけ**で残り 31 書体は 400 のみ。
      # また太字のウェイトは書体ごとに違う（Klee One は 600・M PLUS 1p は 700 で
      # 600 が無い）ため、700 決め打ちでは取り逃す。
      # 詳細は `type3-font-embedding-notes.md`。

      # 取得を試みるウェイト（Google は存在しないものを黙って落とす）
      WEIGHT_QUERY = '100;200;300;400;500;600;700;800;900'
      REGULAR_WEIGHT = 400
      # 太字とみなす下限と、その中で最も近づけたい狙い値
      BOLD_MIN_WEIGHT = 600
      BOLD_TARGET_WEIGHT = 700

      # 指定書体に太字（BOLD_MIN_WEIGHT 以上）の実体があるか。
      # 同梱書体は Regular/Bold 両字面を持つので常に true。
      # 太字が無い書体は本文強調をゴシックで代用する必要があるため、CSS 生成側が参照する。
      # @param name [String] フォントファミリ名
      # @return [Boolean]
      def bold_available?(name)
        family = name.to_s.strip
        return false if family.empty?
        return true if standard_font?(family)

        dir = File.join(google_fonts_dir, slug_for(family))
        Dir.glob(File.join(dir, '*')).any? { File.basename(it)[/-(\d{3})\./, 1].to_i >= BOLD_MIN_WEIGHT }
      end

      # CSS から本文用（400）と太字用の @font-face だけを残す。
      # 太字が無ければ 400 のみを返し、著者に代用が起きることを伝える。
      def select_weight_faces(css, name)
        by_weight = css.scan(/@font-face\s*{[^}]+}/m).to_h { |b| [b[/font-weight:\s*(\d+)/, 1].to_i, b] }
        # @font-face を読み取れない形（想定外の応答）はそのまま通す。
        return css if by_weight.empty?

        regular = by_weight[REGULAR_WEIGHT] || by_weight.min_by { |w, _| (w - REGULAR_WEIGHT).abs }&.last
        bold_weight = by_weight.keys.select { it >= BOLD_MIN_WEIGHT }
                                    .min_by { (it - BOLD_TARGET_WEIGHT).abs }
        # 1 面しか返らない書体こそが代用の対象なので、ここは早期 return しない。
        warn_missing_bold(name) unless bold_weight

        [regular, bold_weight && by_weight[bold_weight]].compact.join("\n")
      end

      # 太字を持たない書体を選んだ著者への案内。黙って代用すると
      # 「指定した書体と違う字が出た」に見えるため、理由と選択肢を必ず添える。
      def warn_missing_bold(name)
        Common.log_warn("#{name} には太字がありません（Google Fonts の配信は標準の太さのみ）",
                        detail: "→ 本文の**強調**は見出し書体（ゴシック）で代用します。\n" \
                                "→ 疑似太字で組むと入稿用 PDF に Type 3 フォントが混入するため、この代用は外せません。\n" \
                                '→ 太字を含む書体にするなら Noto Sans JP / Noto Serif JP / Zen 系 / ' \
                                'M PLUS 系 / BIZ UD 系などが該当します。')
      end

      # ウェイト指定つきで要求し、受け付けられなければ書体名だけで再試行する。
      # 軸指定を解さない書体でも最低限 400 は取れるようにするための二段構え。
      def fetch_google_css(name)
        css = request_google_css("#{name}:wght@#{WEIGHT_QUERY}")
        css ||= request_google_css(name)
        Common.log_warn("Google Fonts CSS の取得に失敗しました: #{name}") if css.nil?
        css
      end

      def request_google_css(family_spec)
        params = URI.encode_www_form('family' => family_spec, 'display' => 'swap')
        uri = URI.parse("#{GOOGLE_FONTS_ENDPOINT}?#{params}")
        response = perform_get(uri, 'Accept' => 'text/css,*/*;q=0.1')
        response.is_a?(Net::HTTPSuccess) ? response.body : nil
      end

      def update_google_bundle!(new_entries)
        FileUtils.mkdir_p(google_fonts_dir)
        existing_entries = if File.exist?(google_bundle_path)
                             parse_bundle(File.read(google_bundle_path, encoding: 'utf-8'))
                           else
                             {}
                           end

        Array(new_entries).each do |family, block|
          next if family.nil? || family.strip.empty?
          next if block.nil? || block.strip.empty?

          existing_entries[family] = build_block_entry(family, block)
        end

        content = if existing_entries.empty?
                    "/* No Google Fonts downloaded (generated by FontManager) */\n"
                  else
                    existing_entries.sort_by { |family, _| family.downcase }
                                    .map { |_, entry| entry.rstrip }
                                    .join("\n\n") + "\n"
                  end

        File.write(google_bundle_path, content, encoding: 'utf-8')
      rescue StandardError => e
        Common.log_warn("Google Fonts CSS の更新に失敗しました: #{e.class}: #{e.message}")
      end

      def slug_for(name)
        base = name.to_s.strip
        slug = base.gsub(/[^A-Za-z0-9]+/, '_').gsub(/_+/, '_').gsub(/\A_|_\z/, '')
        slug.empty? ? 'font_family' : slug
      end

      def build_block_entry(family_name, block)
        header = "/* Generated from Google Fonts: #{family_name} */\n"
        "#{header}#{block.strip}\n"
      end

      def parse_bundle(content)
        entries = {}
        return entries if content.nil? || content.strip.empty?

        content.scan(%r|/\*\s*Generated from Google Fonts:\s*(.+?)\s*\*/\s*((?:@font-face\s*\{[^}]+\}\s*)+)|m) do |family, block|
          entries[family.strip] = build_block_entry(family.strip, block)
        end

        entries
      end

      def perform_get(uri, headers = {})
        response = nil
        opts = {
          use_ssl: uri.scheme == 'https',
          open_timeout: 10,
          read_timeout: 30,
          verify_mode: OpenSSL::SSL::VERIFY_PEER
        }
        store = cert_store
        opts[:cert_store] = store if store

        Net::HTTP.start(uri.host, uri.port, **opts) do |http|
          request = Net::HTTP::Get.new(uri)
          request['User-Agent'] = USER_AGENT
          headers.each { |k, v| request[k] = v }
          response = http.request(request)
        end

        response
      end

      def cert_store
        return @cert_store if defined?(@cert_store)

        store = OpenSSL::X509::Store.new
        store.set_default_paths

        cert_file = ENV.fetch('SSL_CERT_FILE', nil)
        store.add_file(cert_file) if cert_file && File.file?(cert_file)

        cert_dir = ENV.fetch('SSL_CERT_DIR', nil)
        store.add_path(cert_dir) if cert_dir && Dir.exist?(cert_dir)

        @cert_store = store
      rescue StandardError => e
        Common.log_warn("証明書ストアの構築に失敗しました: #{e.class}: #{e.message}")
        @cert_store = nil
      end

      def normalize_font_names(font_names)
        Array(font_names).flatten.compact.flat_map do |name|
          str = name.to_s.strip
          next [] if str.empty?

          str.split(',').map do |segment|
            cleaned = segment.to_s.strip
            cleaned = cleaned.gsub(/\A['"\s]+/, '').gsub(/['"\s]+\z/, '')
            cleaned
          end
        end.reject(&:empty?).uniq
      end

      def google_bundle_path
        File.join(google_fonts_dir, '..', 'google-fonts.css')
      end

      def google_fonts_dir
        File.join(Common::STYLESHEETS_DIR, 'fonts', 'google')
      end
    end
  end
end
