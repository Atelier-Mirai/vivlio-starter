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
          Common.log_warn("Google Fonts のCSSが取得できませんでした: #{name}")
          return []
        end

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

      def fetch_google_css(name)
        params = URI.encode_www_form('family' => name, 'display' => 'swap')
        uri = URI.parse("#{GOOGLE_FONTS_ENDPOINT}?#{params}")
        response = perform_get(uri, 'Accept' => 'text/css,*/*;q=0.1')
        return response.body if response.is_a?(Net::HTTPSuccess)

        Common.log_warn("Google Fonts CSS の取得に失敗しました: #{name} (HTTP #{response&.code})")
        nil
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
