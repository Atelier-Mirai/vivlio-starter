# frozen_string_literal: true

require 'fileutils'
require 'net/http'
require 'set'
require 'uri'
require 'openssl'

module Vivlio
  module Starter
    module CLI
      module FontManager
        USER_AGENT = 'VivlioStarter/FontManager (+https://github.com/Atelier-Mirai/vivlio-starter)'.freeze
        GOOGLE_FONTS_ENDPOINT = 'https://fonts.googleapis.com/css2'.freeze
        STANDARD_FONT_FAMILIES = Set.new([
          'Noto Serif JP',
          'Noto Sans JP',
          'Zen Maru Gothic',
          'hackgen35'
        ]).freeze

        module_function

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
              unless url.start_with?('https://fonts.gstatic.com/')
                "url(#{raw})"
              else
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
          response = nil
          response = perform_get(uri)

          unless response.is_a?(Net::HTTPSuccess)
            raise "HTTP #{response.code}"
          end

          File.open(dest_path, 'wb') { |file| file.write(response.body) }
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

          content.scan(/\/*\s*Generated from Google Fonts:\s*(.+?)\s*\*\/\s*((?:@font-face\s*\{[^}]+\}\s*)+)/m) do |family, block|
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

          cert_file = ENV['SSL_CERT_FILE']
          store.add_file(cert_file) if cert_file && File.file?(cert_file)

          cert_dir = ENV['SSL_CERT_DIR']
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
end
