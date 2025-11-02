# frozen_string_literal: true

require 'rbconfig'
require 'fileutils'
require 'net/http'
require 'uri'
require 'tempfile'
require 'digest'
require 'shellwords'
require 'open-uri'
require 'tmpdir'
require 'json'

module Vivlio
  module Starter
    module CLI
      # ==============================================================================
      # Module: DoctorCommands
      # ------------------------------------------------------------------------------
      # 必要な外部ツール(Xcode Command Line Tools, qpdf, pdfinfo, gs, ImageMagick 他)の存在チェックと、
      # macOS + Homebrew 環境での自動インストール支援を行うコマンド。
      # ==============================================================================
      module DoctorCommands
        module_function

        DOCTOR_DESC = {
          short: '必要ツール(Xcode Command Line Tools, qpdf, pdfinfo, gs, ImageMagick)の診断とセットアップを行います',
          long: <<~DESC
            環境診断を行い、以下の外部コマンドの存在をチェックします:
              - Xcode Command Line Tools (macOS)
              - qpdf
              - pdfinfo (poppler)
              - node
              - vivliostyle
              - gs
              - imagemagick
              - waifu2x

            役割の補足:
              - 圧縮は Ghostscript(pdfwrite) を使用します
              - qpdf は分割/結合・ページ抽出などの PDF 操作用に使用します（圧縮用途ではありません）

            --fix オプション指定時、macOS かつ Homebrew が利用可能であれば
            不足しているツールの自動インストールを試みます。

            例:
              vs doctor
              vs doctor --fix
          DESC
        }.freeze

        def included(base)
          base.class_eval do
            desc 'doctor', DOCTOR_DESC[:short]
            long_desc DOCTOR_DESC[:long]
            method_option :fix, type: :boolean, default: false, desc: '不足ツールを自動インストール (macOS Homebrew)'
            method_option :yes, aliases: '-y', type: :boolean, default: false, desc: '確認を省略して実行'
            def doctor
              ENV['VERBOSE'] = '1' if options[:verbose]

              missing = []
              os = RbConfig::CONFIG['host_os']
              is_macos = os =~ /darwin/i

              # まず macOS の場合に Xcode Command Line Tools をチェック
              if is_macos
                clt_ok = system('xcode-select -p >/dev/null 2>&1')
                if clt_ok
                  Common.echo_always('✅ Xcode Command Line Tools: OK')
                else
                  Common.echo_always('❌ Xcode Command Line Tools: 見つかりません')
                  missing << 'xcode-command-line-tools'
                end
              end

              # コマンド存在チェック定義
              checks = {
                'node' => 'node',
                'vivliostyle' => 'vivliostyle',
                'qpdf' => 'qpdf',
                'pdfinfo' => 'pdfinfo',
                'gs' => 'gs', # Ghostscript
                'imagemagick' => nil,
                'waifu2x' => nil
              }

              Common.echo_always('🔎 環境診断を開始します…')
              checks.each do |label, cmd|
                ok = case label
                     when 'imagemagick'
                       command_exists?('convert') || command_exists?('magick')
                     when 'waifu2x'
                       waifu2x_available?
                     else
                       command_exists?(cmd)
                     end

                if ok
                  Common.echo_always("✅ #{label}: OK")
                else
                  Common.echo_always("❌ #{label}: 見つかりません")
                  missing << label
                end
              end

              if is_macos
                if ssl_certificate_configured?
                  Common.echo_always('✅ Google Fonts 用 SSL 証明書: OK')
                else
                  Common.echo_always('❌ Google Fonts 用 SSL 証明書: 未設定 (Google Fonts のダウンロードに必要)')
                  missing << 'ssl-certificates'
                end
              end

              os_family = detect_os_family(os)
              waifu2x_install_root = nil
              if options[:fix] && missing.include?('waifu2x')
                if os_family != :macos
                  Common.echo_always('⚠️ waifu2x の自動インストールは現在 macOS のみ対応しています。Linux / Windows では手動セットアップを行ってください。')
                elsif install_waifu2x_macos! do |paths|
                        waifu2x_install_root = paths[:install]
                      end
                  missing.delete('waifu2x') if waifu2x_available?
                else
                  Common.echo_always('⚠️ waifu2x の自動インストールに失敗しました。手動セットアップを確認してください。')
                end
              end

              if missing.empty?
                Common.echo_always('🎉 すべての必要ツールが見つかりました')
                return
              end

              Common.echo_always("不足しているツール: #{describe_missing(missing).join(', ')}")

              unless options[:fix]
                Common.echo_always('ヒント: macOS の場合は `vs doctor --fix` で自動インストールを試行できます')
                if missing.include?('xcode-command-line-tools')
                  Common.echo_always('  Xcode Command Line Tools は手動でも `xcode-select --install` で導入できます')
                end
                return
              end

              # --fix: 自動インストール試行
              unless is_macos
                Common.echo_always('自動インストールは macOS(Homebrew) のみ対応です。手動でインストールしてください。')
                return
              end

              # 先に CLT を処理（GUI 承認が必要）
              if missing.include?('xcode-command-line-tools')
                proceed = options[:yes]
                if !proceed && $stdin.tty?
                  $stdout.print('Xcode Command Line Tools をインストールしますか？ [y/N]: ')
                  ans = $stdin.gets
                  proceed = ans && ans.strip.downcase == 'y'
                end
                if proceed
                  Common.echo_always('Xcode Command Line Tools のインストーラを起動します…')
                  system('xcode-select --install >/dev/null 2>&1 || true')
                  # ポーリングで最大 5 分間待機（5 秒間隔）
                  waited = 0
                  until system('xcode-select -p >/dev/null 2>&1') || waited >= 300
                    sleep 5
                    waited += 5
                  end
                  if system('xcode-select -p >/dev/null 2>&1')
                    Common.echo_always('✅ Xcode Command Line Tools が確認できました')
                    missing.delete('xcode-command-line-tools')
                  else
                    Common.echo_always('⚠️ インストールの確認ができませんでした。インストーラ完了後に再実行してください。')
                  end
                else
                  Common.echo_always('Xcode Command Line Tools の自動インストールをスキップします。必要に応じて `xcode-select --install` を実行してください。')
                end
              end

              unless system('which brew >/dev/null 2>&1')
                Common.echo_always('Homebrew が見つかりません。自動インストールを試みます。')
                proceed = options[:yes]
                if !proceed && $stdin.tty?
                  $stdout.print('Homebrew をインストールしますか？ [y/N]: ')
                  ans = $stdin.gets
                  proceed = ans && ans.strip.downcase == 'y'
                end
                if proceed
                  begin
                    # 公式インストーラ実行（要ネットワーク）
                    cmd = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
                    system(cmd)
                  rescue StandardError => e
                    Common.log_warn("Homebrew のインストールでエラー: #{e}")
                  end
                  # PATH 調整（Apple Silicon / Intel を想定）
                  brew_bins = ['/opt/homebrew/bin', '/usr/local/bin']
                  brew_bin = brew_bins.find { |p| File.exist?(File.join(p, 'brew')) }
                  ENV['PATH'] = [brew_bin, ENV.fetch('PATH', nil)].compact.join(':') if brew_bin
                else
                  Common.echo_always('Homebrew をインストールしないため、自動インストール処理を中止します。手動で https://brew.sh/ を参照してください。')
                  return
                end
                unless system('which brew >/dev/null 2>&1')
                  Common.echo_always('Homebrew コマンドが見つかりませんでした。シェルの再起動や PATH 設定を確認してください。')
                  return
                end
              end

              Common.echo_always('🛠 Homebrew による不足ツールのインストールを実行します…')
              begin
                # Node.js（node@20 を優先）
                if missing.include?('node')
                  Common.echo_always('node をインストールします（node@20 優先）…')
                  ok = system('brew install node@20')
                  ok ||= system('brew install node')
                  Common.echo_always('node の Homebrew インストールに失敗しました。手動インストールをご検討ください。') unless ok
                end

                # qpdf / pdfinfo(poppler)
                system('brew install qpdf') if missing.include?('qpdf')
                system('brew install poppler') if missing.include?('pdfinfo')

                # Ghostscript
                system('brew install ghostscript') if missing.include?('gs')

                # ImageMagick
                system('brew install imagemagick') if missing.include?('imagemagick')

                if missing.include?('ssl-certificates')
                  install_ssl_certificates!
                end
              rescue StandardError => e
                Common.log_warn("brew 実行でエラー: #{e}")
              end

              # Vivliostyle CLI（npm -g）
              begin
                if missing.include?('vivliostyle')
                  if system('which npm >/dev/null 2>&1')
                    Common.echo_always('Vivliostyle CLI(@vivliostyle/cli) をグローバルインストールします…')
                    system('npm install -g @vivliostyle/cli')
                  else
                    Common.echo_always('npm が見つかりません。node のインストール後に `npm install -g @vivliostyle/cli` を実行してください。')
                  end
                end
              rescue StandardError => e
                Common.log_warn("npm 実行でエラー: #{e}")
              end

              # 再診断
              Common.echo_always('🔁 インストール後の再診断…')
              still_missing = []
              checks.each do |label, cmd|
                ok = case label
                     when 'imagemagick'
                       command_exists?('convert') || command_exists?('magick')
                     when 'waifu2x'
                       waifu2x_available? || (waifu2x_install_root && waifu2x_present_at?(waifu2x_install_root, os_family))
                     else
                       command_exists?(cmd)
                     end
                still_missing << label unless ok
              end
              if is_macos && !ssl_certificate_configured?
                still_missing << 'ssl-certificates'
              end
              if still_missing.empty?
                Common.echo_always('✅ すべてのツールがインストールされました')
              else
                Common.echo_always("❗ まだ見つからないツールがあります: #{describe_missing(still_missing).join(', ')}。手動でのセットアップをご確認ください。")
              end
            end
          end
        end
      end
    end
  end
end

module Vivlio
  module Starter
    module CLI
      module DoctorCommands
        module_function

        def ssl_certificate_configured?
          test_cmd = "ruby -ropen-uri -e 'URI.open(\"https://fonts.googleapis.com/css2?family=Roboto&display=swap\") { |r| exit(r.status.first == \"200\" ? 0 : 1) }'"
          system(test_cmd)
        rescue StandardError
          false
        end

        def install_ssl_certificates!
          Common.echo_always('Google Fonts 用に ca-certificates / openssl@3 を設定します…')
          system('brew update >/dev/null 2>&1')
          system('brew install openssl@3') unless system('brew list --versions openssl@3 >/dev/null 2>&1')
          system('brew reinstall ca-certificates')

          openssl_prefix = capture_command('brew --prefix openssl@3').strip
          openssl_prefix = File.join(capture_command('brew --prefix').strip, 'opt', 'openssl@3') if openssl_prefix.empty?

          cert_file = File.join(openssl_prefix, 'etc', 'openssl@3', 'cert.pem')
          cert_dir  = File.join(openssl_prefix, 'etc', 'openssl@3', 'certs')

          if File.file?(cert_file)
            ENV['SSL_CERT_FILE'] = cert_file
            ENV['SSL_CERT_DIR'] = cert_dir if Dir.exist?(cert_dir)

            persist_env('SSL_CERT_FILE', cert_file)
            persist_env('SSL_CERT_DIR', cert_dir) if Dir.exist?(cert_dir)

            Common.echo_always("✅ SSL_CERT_FILE を #{cert_file} に設定しました")
            Common.echo_always("✅ SSL_CERT_DIR を #{cert_dir} に設定しました") if Dir.exist?(cert_dir)
          else
            Common.echo_always("⚠️ 証明書ファイルが見つかりませんでした。#{openssl_prefix} に openssl@3 が存在するか確認してください。")
          end
        end

        def capture_command(cmd)
          `#{cmd}`
        rescue StandardError
          ''
        end

        def persist_env(key, value)
          return if value.nil? || value.empty?

          line = %(export #{key}="#{value}")
          profiles = %w[~/.zshrc ~/.bash_profile ~/.bashrc]
          profiles.each do |path|
            expanded = File.expand_path(path)
            begin
              if File.exist?(expanded)
                next if File.read(expanded, encoding: 'utf-8').include?(line)

                File.open(expanded, 'a', encoding: 'utf-8') do |f|
                  f.puts unless File.read(expanded, encoding: 'utf-8').end_with?("\n")
                  f.puts(line)
                end
              else
                FileUtils.mkdir_p(File.dirname(expanded))
                File.write(expanded, "#{line}\n", mode: 'a', encoding: 'utf-8')
              end
            rescue StandardError => e
              Common.log_warn("環境変数 #{key} の永続化に失敗しました (#{expanded}): #{e.class}: #{e.message}")
            end
          end
        end

        def describe_missing(keys)
          return [] unless keys

          label_map = {
            'xcode-command-line-tools' => 'Xcode Command Line Tools',
            'node' => 'node',
            'vivliostyle' => 'Vivliostyle CLI',
            'qpdf' => 'qpdf',
            'pdfinfo' => 'pdfinfo (poppler)',
            'gs' => 'Ghostscript',
            'imagemagick' => 'ImageMagick',
            'waifu2x' => 'waifu2x-ncnn-vulkan',
            'ssl-certificates' => 'Google Fonts 用 SSL 証明書'
          }
          keys.uniq.map { |key| label_map[key] || key }
        end

        def command_exists?(cmd)
          return false if cmd.nil? || cmd.strip.empty?

          candidate = cmd.strip
          return file_executable?(candidate) if candidate.include?(File::SEPARATOR) || candidate.include?('\\')

          pathext = windows_platform? ? ENV.fetch('PATHEXT', '').split(';').map(&:downcase) : ['']
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            pathext.any? do |ext|
              extname = ext.empty? || candidate.downcase.end_with?(ext) ? candidate : "#{candidate}#{ext.downcase}"
              resolved = File.join(path, extname)
              file_executable?(resolved)
            end
          end
        end

        def waifu2x_available?
          os_family = detect_os_family(RbConfig::CONFIG['host_os'])
          paths = waifu2x_paths(os_family)

          candidates = [ENV['WAIFU2X_BIN'],
                        'waifu2x-ncnn-vulkan',
                        'waifu2x-ncnn-vulkan.exe']

          if paths
            %w[waifu2x-ncnn-vulkan waifu2x-ncnn-vulkan.exe].each do |name|
              candidates << File.join(paths[:bin], name)
              candidates << File.join(paths[:bundle], name)
            end
            candidates << paths[:binary]
          end

          candidates.compact.any? { |cmd| command_exists?(cmd) }
        end

        def windows_platform?
          RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/i
        end

        def detect_os_family(host_os)
          case host_os
          when /mswin|mingw|cygwin/i then :windows
          when /darwin/i then :macos
          when /linux/i then :linux
          else :unknown
          end
        end

        def install_waifu2x_macos!
          paths = waifu2x_paths(:macos)
          unless paths
            Common.log_warn('macOS 用のインストール先を決定できませんでした')
            return false
          end

          FileUtils.mkdir_p(paths[:bin])
          FileUtils.mkdir_p(paths[:bundle])

          release = fetch_waifu2x_release
          return false unless release

          asset = Array(release['assets']).find { |a| a['name'].to_s.include?('macos') }
          unless asset
            Common.log_warn('macOS 用 waifu2x アセットが見つかりませんでした')
            return false
          end

          Dir.mktmpdir('waifu2x-install') do |tmpdir|
            archive_path = File.join(tmpdir, asset['name'])
            return false unless download_asset(asset['browser_download_url'], archive_path)

            return false unless verify_asset_digest(asset['digest'], archive_path)

            extracted_dir = File.join(tmpdir, 'extracted')
            FileUtils.mkdir_p(extracted_dir)
            return false unless extract_archive(archive_path, extracted_dir)

            payload_root = detect_payload_root(extracted_dir)
            return false unless payload_root

            # 既存の waifu2x 一式を削除
            clean_waifu2x_bins(paths[:bin], paths[:bundle])
            FileUtils.rm_rf(paths[:bundle])
            FileUtils.mkdir_p(paths[:bundle])

            Dir.children(payload_root).each do |child|
              src = File.join(payload_root, child)
              dst = File.join(paths[:bundle], child)
              FileUtils.cp_r(src, dst, preserve: true, remove_destination: true)
            end

            binary_path = locate_waifu2x_binary(paths[:bundle], :macos)
            unless binary_path
              Common.log_warn('waifu2x 実行ファイルが見つかりませんでした')
              return false
            end

            FileUtils.chmod(0o755, binary_path)

            Common.echo_always("✅ waifu2x を #{paths[:bundle]} に配置しました")
            Common.echo_always("   実行ファイル: #{binary_path}")
            unless path_included?(paths[:bin])
              if ensure_zsh_path(paths[:bin])
                Common.echo_always("ℹ️ ~/.zshrc に PATH を追記しました。新しいシェルで有効になります")
              else
                Common.echo_always(path_hint_message(paths[:bin], :macos))
              end
            end
            yield(paths) if block_given?
            return true
          end
        rescue StandardError => e
          Common.log_warn("waifu2x 自動インストールで例外: #{e.class}: #{e.message}")
          false
        end

        def waifu2x_paths(os_family = :macos)
          return nil unless os_family == :macos

          base_dir = File.join(Dir.home, '.local')
          bin_dir = File.join(base_dir, 'bin')
          bundle_dir = File.join(bin_dir, 'waifu2x')
          binary_path = File.join(bundle_dir, 'waifu2x-ncnn-vulkan')
          { install: bundle_dir, bin: bin_dir, bundle: bundle_dir, binary: binary_path }
        end

        def fetch_waifu2x_release
          uri = URI.parse('https://api.github.com/repos/nihui/waifu2x-ncnn-vulkan/releases/tags/20250915')
          response = uri.open('User-Agent' => 'vivlio-starter')
          JSON.parse(response.read)
        rescue StandardError => e
          Common.log_warn("waifu2x リリース情報の取得に失敗しました: #{e.class}: #{e.message}")
          nil
        end

        def select_waifu2x_asset(release, os_family)
          name_fragment = case os_family
                          when :windows then 'windows'
                          when :macos then 'macos'
                          when :linux then 'linux'
                          else return nil
                          end
          Array(release['assets']).find { |asset| asset['name'].to_s.include?(name_fragment) }
        end

        def download_asset(url, destination)
          URI.parse(url).open('User-Agent' => 'vivlio-starter') do |data|
            File.open(destination, 'wb') { |f| IO.copy_stream(data, f) }
          end
          true
        rescue StandardError => e
          Common.log_warn("waifu2x アセットのダウンロードに失敗しました: #{e.class}: #{e.message}")
          false
        end

        def verify_asset_digest(digest_field, file_path)
          return true unless digest_field.to_s.start_with?('sha256:')

          expected = digest_field.split(':', 2).last
          actual = Digest::SHA256.file(file_path).hexdigest
          return true if actual.casecmp?(expected)

          Common.log_warn('ダウンロードした waifu2x アセットの SHA256 が一致しません')
          false
        end

        def extract_archive(archive_path, destination, os_family = :macos)
          if os_family == :windows
            extract_with_powershell(archive_path, destination)
          else
            extract_with_unzip(archive_path, destination)
          end
        end

        def extract_with_unzip(archive_path, destination)
          cmd = ['unzip', '-qq', archive_path, '-d', destination]
          system(*cmd)
        rescue Errno::ENOENT
          Common.log_warn('unzip コマンドが見つかりません。手動で解凍してください。')
          false
        end

        def extract_with_powershell(archive_path, destination)
          ps = %(powershell -NoLogo -NoProfile -Command "Expand-Archive -Force -LiteralPath '#{archive_path.gsub("'", "''")}' -DestinationPath '#{destination.gsub("'", "''")}'")
          system(ps)
        rescue Errno::ENOENT
          Common.log_warn('PowerShell が見つかりません。手動で解凍してください。')
          false
        end

        def detect_payload_root(extracted_dir)
          entries = Dir.children(extracted_dir)
          return extracted_dir if entries.empty?

          first = File.join(extracted_dir, entries.first)
          File.directory?(first) ? first : extracted_dir
        rescue StandardError
          nil
        end

        def locate_waifu2x_binary(install_root, os_family)
          pattern = os_family == :windows ? 'waifu2x-ncnn-vulkan.exe' : 'waifu2x-ncnn-vulkan'
          Dir.glob(File.join(install_root, '**', pattern)).find { |path| File.file?(path) }
        end

        def waifu2x_present_at?(install_root, os_family)
          return false unless install_root && File.directory?(install_root)

          binary = locate_waifu2x_binary(install_root, os_family)
          models = Dir.glob(File.join(install_root, 'models-*')).any? { |path| File.directory?(path) }
          binary && models
        end

        def clean_waifu2x_bins(bin_dir, bundle_dir)
          targets = []
          targets.concat(Dir.glob(File.join(bin_dir, 'waifu2x*')))
          targets << File.join(bin_dir, 'waifu2x-ncnn-vulkan.cmd')
          targets << File.join(bin_dir, 'waifu2x-ncnn-vulkan.exe')
          targets << bundle_dir
          targets.uniq.each do |path|
            next unless path.start_with?(bin_dir)

            FileUtils.rm_rf(path)
          end
        end

        def ensure_zsh_path(bin_dir)
          zshrc = File.join(Dir.home, '.zshrc')
          export_line = %(export PATH="#{bin_dir}:$PATH")

          contents = File.exist?(zshrc) ? File.read(zshrc) : ''
          return true if contents.include?(bin_dir)

          FileUtils.mkdir_p(File.dirname(zshrc)) unless File.directory?(File.dirname(zshrc))
          File.open(zshrc, 'a', encoding: 'utf-8') do |file|
            file.puts "\n# Added by vs doctor"
            file.puts export_line
          end
          true
        rescue StandardError => e
          Common.log_warn("PATH 追記に失敗しました: #{e.class}: #{e.message}")
          false
        end

        def file_executable?(path)
          return false unless File.exist?(path)

          windows_platform? ? true : File.executable?(path)
        end

        def path_included?(dir)
          normalized = File.expand_path(dir)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |entry|
            next if entry.nil? || entry.empty?

            File.expand_path(entry) == normalized
          end
        end

        def path_hint_message(bin_dir, os_family)
          display_path = case os_family
                         when :windows then '%LOCALAPPDATA%\\vs\\bin'
                         when :macos, :linux then '$HOME/.local/bin'
                         else bin_dir
                         end
          "ℹ️ PATH に #{display_path} を追加すると waifu2x-ncnn-vulkan が利用可能になります"
        end
      end
    end
  end
end
