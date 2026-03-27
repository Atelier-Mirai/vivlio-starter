# frozen_string_literal: true

# ================================================================
# File: lib/vivlio/starter/cli/create.rb
# ================================================================
# 責務:
#   書籍プロジェクトにおける章ファイル・特殊ページの生成を担当する。
#
# 提供機能:
#   - execute_create: 章 Markdown と画像ディレクトリを生成
#   - execute_titlepage: タイトルページを config/book.yml から生成
#   - execute_colophon: 奥付を config/book.yml から生成
#   - execute_legalpage: 免責・商標ページを config/book.yml から生成
#
# 生成規約:
#   - 章ファイル名は「数字-スラッグ.md」形式（例: 11-install.md）
#   - 画像は章ごとのサブディレクトリに配置（Vivliostyle の相対パス解決のため）
#   - 生成した章は config/catalog.yml に自動追記される
#
# 依存:
#   - Common: 設定読み込み・ログ出力・パス定数
#   - Build::CatalogUpdater: catalog.yml への章追記
#   - config/book.yml: タイトル・著者情報などのメタデータ
# ================================================================

require 'fileutils'
require_relative 'build/catalog_loader'
require_relative 'build/catalog_updater'
require_relative 'token_resolver'

module Vivlio
  module Starter
    module CLI
      # 章ファイル・特殊ページ生成ロジック
      #
      # Samovar CLI コマンドから呼び出される実行メソッド群。
      # 各メソッドは純粋な Hash オプションを受け取る。
      module CreateCommands
        module_function

        MAX_AUTO_CHAPTER = 98

        # --- 章ファイル生成 ---

        # 章ファイルと画像ディレクトリを一括生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        # @param names [Array<String>] 生成する章名のリスト
        #   - 形式: "XX-slug" または "XX-slug.md"（XX は並び順を示す数字）
        #   - 例: ['11-install', '12-tutorial']
        # @return [void]
        # @raise [SystemExit] 1つ以上の章生成に失敗した場合
        def execute_create(options, names)
          apply_verbose(options)
          ensure_names_present!(names)

          resolver = TokenResolver::Resolver.new
          normalized_names = normalize_name_inputs(names, resolver)
          entries = resolver.resolve(normalized_names)

          # 1. 不正な形式をチェック
          invalid_entries = entries.reject(&:valid?)
          if invalid_entries.any?
            Common.log_error("エラー: 不正な形式が含まれています: #{invalid_entries.map(&:slug).join(', ')}")
            exit 1
          end

          # 2. カタログとの重複をチェック
          duplicate_entries = entries.select(&:in_catalog?)
          if duplicate_entries.any?
            Common.log_error("エラー: 以下の章は既にカタログに存在します:")
            duplicate_entries.each { |e| Common.log_error("  - #{e.basename} (#{e.label})") }
            exit 1
          end

          # 3. すべてクリアしたら、一括で作成
          errors = false
          entries.each do |entry|
            fname = ensure_filename(entry.basename)
            unless fname
              Common.log_error("エラー: 無効なファイル名です: #{entry.basename}")
              errors = true
              next
            end

            create_single_chapter(fname, entry)
          rescue StandardError => e
            errors = true
            Common.log_error("作成に失敗しました: #{fname} (#{e.class}: #{e.message})")
          end

          exit 1 if errors
        end

        # --- タイトルページ生成 ---

        # タイトルページ（扉）を config/book.yml から生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # --- カバー生成 ---

        # カバーSVGをconfig/book.ymlから生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        # @return [void]
        #
        # 生成ファイル: 
        # - 表紙: covers/frontcover_dark.svg, covers/frontcover_light.svg
        # - 裏表紙: covers/backcover_dark.svg, covers/backcover_light.svg
        def execute_cover(options)
          apply_verbose(options)
          
          title, subtitle = extract_title_and_subtitle
          author = fetch_config_value('book', 'author')
          series = fetch_config_value('book', 'series')
          release = fetch_config_value('book', 'release')
          
          covers_dir = File.join(Dir.pwd, 'covers')
          FileUtils.mkdir_p(covers_dir) unless Dir.exist?(covers_dir)
          
          # book.yml のパスを取得
          book_config_path = File.join(Dir.pwd, 'config', 'book.yml')
          
          # 表紙と裏表紙の両方を生成
          %w[front back].each do |cover_type|
            %w[dark light].each do |theme|
              if cover_type == 'front'
                content = generate_frontcover_svg_content(title, subtitle, author, series, release, theme)
                filename = "frontcover_#{theme}.svg"
              else
                content = generate_backcover_svg_content(title, subtitle, author, series, release, theme)
                filename = "backcover_#{theme}.svg"
              end
              
              path = File.join(covers_dir, filename)
              log_message = cover_type == 'front' ? "表紙を生成しました: #{path}" : "裏表紙を生成しました: #{path}"
              
              # book.yml が既存の cover より新しい場合のみ生成
              next if File.exist?(path) && File.mtime(path) >= File.mtime(book_config_path)
              
              safe_write(path, content)
              Common.log_info(log_message)
            end
          end
        end

        # 表紙SVGコンテンツを生成する
        #
        # @param title [String] タイトル
        # @param subtitle [String] サブタイトル
        # @param author [String] 著者名
        # @param series [String] シリーズ名
        # @param release [String] 発行日
        # @param theme [String] テーマ ('dark' または 'light')
        # @return [String] SVGコンテンツ
        def generate_frontcover_svg_content(title, subtitle, author, series, release, theme)
          if theme == 'dark'
            generate_dark_frontcover_svg(title, subtitle, author, series, release)
          else
            generate_light_frontcover_svg(title, subtitle, author, series, release)
          end
        end

        # 裏表紙SVGコンテンツを生成する
        #
        # @param title [String] タイトル
        # @param subtitle [String] サブタイトル
        # @param author [String] 著者名
        # @param series [String] シリーズ名
        # @param release [String] 発行日
        # @param theme [String] テーマ ('dark' または 'light')
        # @return [String] SVGコンテンツ
        def generate_backcover_svg_content(title, subtitle, author, series, release, theme)
          if theme == 'dark'
            generate_dark_backcover_svg(title, subtitle, author, series, release)
          else
            generate_light_backcover_svg(title, subtitle, author, series, release)
          end
        end

        # ダークテーマの表紙SVGを生成
        def generate_dark_frontcover_svg(title, subtitle, author, series, release)
          <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 595 842" width="595" height="842">
              <defs>
                <!-- Background gradient: deep navy to dark midnight -->
                <linearGradient id="bg-grad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stop-color="#0e1a2e"/>
                  <stop offset="100%" stop-color="#060d1a"/>
                </linearGradient>

                <!-- Gold shimmer gradient for accent lines -->
                <linearGradient id="gold-line" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#b8902a" stop-opacity="0"/>
                  <stop offset="40%"  stop-color="#e8c85a"/>
                  <stop offset="60%"  stop-color="#f5d96e"/>
                  <stop offset="100%" stop-color="#b8902a" stop-opacity="0"/>
                </linearGradient>

                <!-- Thin gold line for decorative rules -->
                <linearGradient id="gold-thin" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#c9a43a" stop-opacity="0"/>
                  <stop offset="30%"  stop-color="#e0c058"/>
                  <stop offset="70%"  stop-color="#e0c058"/>
                  <stop offset="100%" stop-color="#c9a43a" stop-opacity="0"/>
                </linearGradient>

                <!-- Glow for the central circuit node -->
                <radialGradient id="node-glow" cx="50%" cy="50%" r="50%">
                  <stop offset="0%"   stop-color="#5b9ef5" stop-opacity="0.35"/>
                  <stop offset="100%" stop-color="#5b9ef5" stop-opacity="0"/>
                </radialGradient>

                <!-- Subtle grid texture overlay -->
                <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                  <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#1e3358" stroke-width="0.4"/>
                </pattern>

                <!-- Clip path for grid area -->
                <clipPath id="top-clip">
                  <rect x="0" y="0" width="595" height="560"/>
                </clipPath>
              </defs>

              <!-- === Background === -->
              <rect width="595" height="842" fill="url(#bg-grad)"/>

              <!-- === Grid overlay (top area only) === -->
              <rect width="595" height="560" fill="url(#grid)" opacity="0.3" clip-path="url(#top-clip)"/>

              <!-- === Gold frame accents === -->
              <!-- Top thick gold bar -->
              <rect x="0" y="0" width="595" height="4" fill="#c9a43a"/>
              <!-- Bottom thick gold bar -->
              <rect x="0" y="838" width="595" height="4" fill="#c9a43a"/>
              <!-- Left thin vertical gold accent -->
              <rect x="28" y="0" width="2" height="842" fill="#c9a43a" opacity="0.5"/>
              <!-- Right thin vertical gold accent -->
              <rect x="565" y="0" width="2" height="842" fill="#c9a43a" opacity="0.5"/>

              <!-- === Diagonal geometric accent lines (tech circuit feel) === -->
              <line x1="-20" y1="380" x2="595" y2="60"  stroke="#1e3a60" stroke-width="0.8"/>
              <line x1="-20" y1="500" x2="595" y2="160" stroke="#1e3a60" stroke-width="0.6"/>
              <line x1="0"   y1="620" x2="595" y2="280" stroke="#1e3a60" stroke-width="0.5"/>
              <line x1="0"   y1="740" x2="595" y2="420" stroke="#1e3a60" stroke-width="0.4"/>

              <!-- === Title block (upper 1/3 ≒ y:60〜300) === -->
              <!-- Top thin gold rule above title -->
              <rect x="50" y="68" width="495" height="1" fill="url(#gold-thin)"/>

              <!-- Main title -->
              <text x="297" y="138"
                    text-anchor="middle"
                    font-family="'Hiragino Mincho ProN', 'Yu Mincho', 'MS Mincho', 'Noto Serif CJK JP', serif"
                    font-size="38"
                    font-weight="700"
                    fill="#f0e8d0"
                    letter-spacing="2">#{title}</text>

              <!-- Gold underline beneath title -->
              <rect x="80" y="150" width="435" height="1.5" fill="url(#gold-line)"/>

              <!-- Subtitle -->
              <text x="297" y="190"
                    text-anchor="middle"
                    font-family="'Hiragino Mincho ProN', 'Yu Mincho', 'MS Mincho', 'Noto Serif CJK JP', serif"
                    font-size="24"
                    font-weight="400"
                    fill="#a8b8d0"
                    letter-spacing="4">#{subtitle}</text>

              <!-- Author line -->
              <text x="297" y="247"
                    text-anchor="middle"
                    font-family="'Hiragino Mincho ProN', 'Yu Mincho', 'MS Mincho', 'Noto Serif CJK JP', serif"
                    font-size="22"
                    font-weight="600"
                    fill="#d0c0a0"
                    letter-spacing="4">
                <tspan font-family="'Hiragino Kaku Gothic ProN', 'Yu Gothic', 'Meiryo', sans-serif"
                        font-size="14"
                        fill="#8090a8"
                        letter-spacing="2"
                        baseline-shift="4px">[著]</tspan><tspan>#{author}</tspan>
              </text>

              <!-- Thin gold rule below author, separating title zone from graphic zone -->
              <rect x="50" y="288" width="495" height="1" fill="url(#gold-thin)"/>

              <!-- === Central graphic: abstract circuit / web network (center cy=530) === -->
              <!-- Outer ring (faint) -->
              <circle cx="297" cy="530" r="195" fill="none" stroke="#1a3560" stroke-width="0.8"/>
              <!-- Mid ring -->
              <circle cx="297" cy="530" r="140" fill="none" stroke="#1e4070" stroke-width="0.6"/>
              <!-- Inner ring -->
              <circle cx="297" cy="530" r="86"  fill="none" stroke="#2a5590" stroke-width="0.8"/>
              <!-- Glow behind center node -->
              <circle cx="297" cy="530" r="96"  fill="url(#node-glow)"/>
              <!-- Center node -->
              <circle cx="297" cy="530" r="30"  fill="#0e2040" stroke="#4a80c8" stroke-width="1.2"/>
              <!-- Bracket icon in center -->
              <text x="297" y="538" text-anchor="middle" font-family="'Courier New', monospace"
                    font-size="21" fill="#5b9ef5" font-weight="700">&lt;/&gt;</text>

              <!-- Radial spokes (inner ring r=86 → mid ring r=140) -->
              <!-- 0° right -->
              <line x1="383" y1="530" x2="435" y2="530" stroke="#2a5590" stroke-width="0.8"/>
              <!-- 45° -->
              <line x1="358" y1="469" x2="396" y2="431" stroke="#2a5590" stroke-width="0.8"/>
              <!-- 90° up -->
              <line x1="297" y1="444" x2="297" y2="390" stroke="#2a5590" stroke-width="0.8"/>
              <!-- 135° -->
              <line x1="236" y1="469" x2="198" y2="431" stroke="#2a5590" stroke-width="0.8"/>
              <!-- 180° left -->
              <line x1="211" y1="530" x2="157" y2="530" stroke="#2a5590" stroke-width="0.8"/>
              <!-- 225° -->
              <line x1="236" y1="591" x2="198" y2="629" stroke="#2a5590" stroke-width="0.8"/>
              <!-- 270° down -->
              <line x1="297" y1="616" x2="297" y2="670" stroke="#2a5590" stroke-width="0.8"/>
              <!-- 315° -->
              <line x1="358" y1="591" x2="396" y2="629" stroke="#2a5590" stroke-width="0.8"/>

              <!-- Satellite nodes (mid ring r=140) -->
              <circle cx="437" cy="530" r="8"  fill="#0e2040" stroke="#4a80c8" stroke-width="1"/>
              <circle cx="396" cy="431" r="6"  fill="#0e2040" stroke="#3a70b8" stroke-width="0.8"/>
              <circle cx="297" cy="390" r="8"  fill="#0e2040" stroke="#4a80c8" stroke-width="1"/>
              <circle cx="198" cy="431" r="6"  fill="#0e2040" stroke="#3a70b8" stroke-width="0.8"/>
              <circle cx="157" cy="530" r="8"  fill="#0e2040" stroke="#4a80c8" stroke-width="1"/>
              <circle cx="198" cy="629" r="6"  fill="#0e2040" stroke="#3a70b8" stroke-width="0.8"/>
              <circle cx="297" cy="670" r="8"  fill="#0e2040" stroke="#4a80c8" stroke-width="1"/>
              <circle cx="396" cy="629" r="6"  fill="#0e2040" stroke="#3a70b8" stroke-width="0.8"/>

              <!-- Extend to outer ring (r=195) -->
              <line x1="437" y1="530" x2="491" y2="530" stroke="#2a5a90" stroke-width="0.5"/>
              <line x1="396" y1="431" x2="435" y2="393" stroke="#2a5a90" stroke-width="0.5"/>
              <line x1="297" y1="390" x2="297" y2="335" stroke="#2a5a90" stroke-width="0.5"/>
              <line x1="198" y1="431" x2="159" y2="393" stroke="#2a5a90" stroke-width="0.5"/>
              <line x1="157" y1="530" x2="103" y2="530" stroke="#2a5a90" stroke-width="0.5"/>
              <line x1="198" y1="629" x2="159" y2="667" stroke="#2a5a90" stroke-width="0.5"/>
              <line x1="297" y1="670" x2="297" y2="725" stroke="#2a5a90" stroke-width="0.5"/>
              <line x1="396" y1="629" x2="435" y2="667" stroke="#2a5a90" stroke-width="0.5"/>

              <!-- Outer edge nodes -->
              <circle cx="492" cy="530" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>
              <circle cx="435" cy="393" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>
              <circle cx="297" cy="335" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>
              <circle cx="159" cy="393" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>
              <circle cx="102" cy="530" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>
              <circle cx="159" cy="667" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>
              <circle cx="297" cy="725" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>
              <circle cx="435" cy="667" r="4" fill="none" stroke="#2a5080" stroke-width="0.8"/>

              <!-- === Publication info block === -->
              <!-- Thin gold rule above publication info -->
              <rect x="50" y="752" width="495" height="1" fill="url(#gold-thin)"/>

              <!-- Series label -->
              <text x="297" y="784"
                    text-anchor="middle"
                    font-family="'Hiragino Kaku Gothic ProN', 'Yu Gothic', 'Meiryo', sans-serif"
                    font-size="13"
                    fill="#7080a0"
                    letter-spacing="2">#{series}</text>

              <!-- Release date -->
              <text x="297" y="806"
                    text-anchor="middle"
                    font-family="'Hiragino Kaku Gothic ProN', 'Yu Gothic', 'Meiryo', sans-serif"
                    font-size="12"
                    fill="#5a6a80"
                    letter-spacing="1">#{release}</text>
            </svg>
          SVG
        end

        # ライトテーマの表紙SVGを生成
        def generate_light_frontcover_svg(title, subtitle, author, series, release)
          <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 595 842" width="595" height="842">
              <defs>
                <!-- Background gradient: light cream to off-white -->
                <linearGradient id="bg-grad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stop-color="#f8f6f2"/>
                  <stop offset="100%" stop-color="#f0ece4"/>
                </linearGradient>

                <!-- Gold shimmer gradient for accent lines -->
                <linearGradient id="gold-line" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#b8902a" stop-opacity="0"/>
                  <stop offset="40%"  stop-color="#e8c85a"/>
                  <stop offset="60%"  stop-color="#f5d96e"/>
                  <stop offset="100%" stop-color="#b8902a" stop-opacity="0"/>
                </linearGradient>

                <!-- Flat metallic gradient for center node -->
                <linearGradient id="metallic-gold" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%"   stop-color="#e8c85a"/>
                  <stop offset="20%"  stop-color="#f5d96e"/>
                  <stop offset="40%"  stop-color="#e8c85a"/>
                  <stop offset="60%"  stop-color="#c9a43a"/>
                  <stop offset="80%"  stop-color="#b8902a"/>
                  <stop offset="100%" stop-color="#e8c85a"/>
                </linearGradient>

                <!-- Thin gold line for decorative rules -->
                <linearGradient id="gold-thin" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#c9a43a" stop-opacity="0"/>
                  <stop offset="30%"  stop-color="#e0c058"/>
                  <stop offset="70%"  stop-color="#e0c058"/>
                  <stop offset="100%" stop-color="#c9a43a" stop-opacity="0"/>
                </linearGradient>

                <!-- Subtle glow for the central circuit node -->
                <radialGradient id="node-glow" cx="50%" cy="50%" r="50%">
                  <stop offset="0%"   stop-color="#f5d96e" stop-opacity="0.25"/>
                  <stop offset="30%"  stop-color="#e8c85a" stop-opacity="0.18"/>
                  <stop offset="60%"  stop-color="#c9a43a" stop-opacity="0.12"/>
                  <stop offset="100%" stop-color="#b8902a" stop-opacity="0"/>
                </radialGradient>

                <!-- Subtle grid texture overlay -->
                <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                  <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#d0d0d0" stroke-width="0.4"/>
                </pattern>

                <!-- Clip path for grid area -->
                <clipPath id="top-clip">
                  <rect x="0" y="0" width="595" height="560"/>
                </clipPath>
              </defs>

              <!-- === Background === -->
              <rect width="595" height="842" fill="url(#bg-grad)"/>

              <!-- === Grid overlay (top area only) === -->
              <rect width="595" height="560" fill="url(#grid)" opacity="0.3" clip-path="url(#top-clip)"/>

              <!-- === Gold frame accents === -->
              <!-- Top thick gold bar -->
              <rect x="0" y="0" width="595" height="4" fill="#c9a43a"/>
              <!-- Bottom thick gold bar -->
              <rect x="0" y="838" width="595" height="4" fill="#c9a43a"/>
              <!-- Left thin vertical gold accent -->
              <rect x="28" y="0" width="2" height="842" fill="#c9a43a" opacity="0.5"/>
              <!-- Right thin vertical gold accent -->
              <rect x="565" y="0" width="2" height="842" fill="#c9a43a" opacity="0.5"/>

              <!-- === Diagonal geometric accent lines (tech circuit feel) === -->
              <line x1="-20" y1="380" x2="595" y2="60"  stroke="#e0e0e0" stroke-width="0.8"/>
              <line x1="-20" y1="500" x2="595" y2="160" stroke="#e0e0e0" stroke-width="0.6"/>
              <line x1="0"   y1="620" x2="595" y2="280" stroke="#e0e0e0" stroke-width="0.5"/>
              <line x1="0"   y1="740" x2="595" y2="420" stroke="#e0e0e0" stroke-width="0.4"/>

              <!-- === Title block (upper 1/3 ≒ y:60〜300) === -->
              <!-- Top thin gold rule above title -->
              <rect x="50" y="68" width="495" height="1" fill="url(#gold-thin)"/>

              <!-- Main title -->
              <text x="297" y="138"
                    text-anchor="middle"
                    font-family="'Hiragino Mincho ProN', 'Yu Mincho', 'MS Mincho', 'Noto Serif CJK JP', serif"
                    font-size="38"
                    font-weight="700"
                    fill="#1e3a60"
                    letter-spacing="2">#{title}</text>

              <!-- Gold underline beneath title -->
              <rect x="80" y="150" width="435" height="1.5" fill="url(#gold-line)"/>

              <!-- Subtitle -->
              <text x="297" y="190"
                    text-anchor="middle"
                    font-family="'Hiragino Mincho ProN', 'Yu Mincho', 'MS Mincho', 'Noto Serif CJK JP', serif"
                    font-size="24"
                    font-weight="400"
                    fill="#8090a8"
                    letter-spacing="4">#{subtitle}</text>

              <!-- Author line -->
              <text x="297" y="247"
                    text-anchor="middle"
                    font-family="'Hiragino Mincho ProN', 'Yu Mincho', 'MS Mincho', 'Noto Serif CJK JP', serif"
                    font-size="22"
                    font-weight="600"
                    fill="#d0c0a0"
                    letter-spacing="4">
                <tspan font-family="'Hiragino Kaku Gothic ProN', 'Yu Gothic', 'Meiryo', sans-serif"
                        font-size="14"
                        fill="#a8b8d0"
                        letter-spacing="2"
                        baseline-shift="4px">[著]</tspan><tspan>#{author}</tspan>
              </text>

              <!-- Thin gold rule below author, separating title zone from graphic zone -->
              <rect x="50" y="288" width="495" height="1" fill="url(#gold-thin)"/>

              <!-- === Central graphic: abstract circuit / web network (center cy=530) === -->
              <!-- Outer ring (faint) -->
              <circle cx="297" cy="530" r="195" fill="none" stroke="#e0e0e0" stroke-width="0.8"/>
              <!-- Mid ring -->
              <circle cx="297" cy="530" r="140" fill="none" stroke="#e8e8e8" stroke-width="0.6"/>
              <!-- Inner ring -->
              <circle cx="297" cy="530" r="86"  fill="none" stroke="#d0d0d0" stroke-width="0.8"/>
              <!-- Glow behind center node -->
              <circle cx="297" cy="530" r="96"  fill="url(#node-glow)"/>
              <!-- Center node -->
              <circle cx="297" cy="530" r="30"  fill="url(#metallic-gold)" stroke="#f0f0f0" stroke-width="1.2"/>
              <!-- Bracket icon in center -->
              <text x="297" y="538" text-anchor="middle" font-family="'Courier New', monospace"
                    font-size="21" fill="#f0f0f0" font-weight="700">&lt;/&gt;</text>

              <!-- Radial spokes (inner ring r=86 → mid ring r=140) -->
              <!-- 0° right -->
              <line x1="383" y1="530" x2="435" y2="530" stroke="#f0f0f0" stroke-width="0.8"/>
              <!-- 45° -->
              <line x1="358" y1="469" x2="396" y2="431" stroke="#f0f0f0" stroke-width="0.8"/>
              <!-- 90° up -->
              <line x1="297" y1="444" x2="297" y2="390" stroke="#f0f0f0" stroke-width="0.8"/>
              <!-- 135° -->
              <line x1="236" y1="469" x2="198" y2="431" stroke="#f0f0f0" stroke-width="0.8"/>
              <!-- 180° left -->
              <line x1="211" y1="530" x2="157" y2="530" stroke="#f0f0f0" stroke-width="0.8"/>
              <!-- 225° -->
              <line x1="236" y1="591" x2="198" y2="629" stroke="#f0f0f0" stroke-width="0.8"/>
              <!-- 270° down -->
              <line x1="297" y1="616" x2="297" y2="670" stroke="#f0f0f0" stroke-width="0.8"/>
              <!-- 315° -->
              <line x1="358" y1="591" x2="396" y2="629" stroke="#f0f0f0" stroke-width="0.8"/>

              <!-- Satellite nodes (mid ring r=140) -->
              <circle cx="437" cy="530" r="8"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="1"/>
              <circle cx="396" cy="431" r="6"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>
              <circle cx="297" cy="390" r="8"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="1"/>
              <circle cx="198" cy="431" r="6"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>
              <circle cx="157" cy="530" r="8"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="1"/>
              <circle cx="198" cy="629" r="6"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>
              <circle cx="297" cy="670" r="8"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="1"/>
              <circle cx="396" cy="629" r="6"  fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>

              <!-- Extend to outer ring (r=195) -->
              <line x1="437" y1="530" x2="491" y2="530" stroke="#f0f0f0" stroke-width="0.5"/>
              <line x1="396" y1="431" x2="435" y2="393" stroke="#f0f0f0" stroke-width="0.5"/>
              <line x1="297" y1="390" x2="297" y2="335" stroke="#f0f0f0" stroke-width="0.5"/>
              <line x1="198" y1="431" x2="159" y2="393" stroke="#f0f0f0" stroke-width="0.5"/>
              <line x1="157" y1="530" x2="103" y2="530" stroke="#f0f0f0" stroke-width="0.5"/>
              <line x1="198" y1="629" x2="159" y2="667" stroke="#f0f0f0" stroke-width="0.5"/>
              <line x1="297" y1="670" x2="297" y2="725" stroke="#f0f0f0" stroke-width="0.5"/>
              <line x1="396" y1="629" x2="435" y2="667" stroke="#f0f0f0" stroke-width="0.5"/>

              <!-- Outer edge nodes -->
              <circle cx="492" cy="530" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>
              <circle cx="435" cy="393" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>
              <circle cx="297" cy="335" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>
              <circle cx="159" cy="393" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>
              <circle cx="102" cy="530" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>
              <circle cx="159" cy="667" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>
              <circle cx="297" cy="725" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>
              <circle cx="435" cy="667" r="4" fill="none" stroke="#f0f0f0" stroke-width="0.8"/>

              <!-- === Publication info block === -->
              <!-- Thin gold rule above publication info -->
              <rect x="50" y="752" width="495" height="1" fill="url(#gold-thin)"/>

              <!-- Series label -->
              <text x="297" y="784"
                    text-anchor="middle"
                    font-family="'Hiragino Kaku Gothic ProN', 'Yu Gothic', 'Meiryo', sans-serif"
                    font-size="13"
                    fill="#7080a0"
                    letter-spacing="2">#{series}</text>

              <!-- Release date -->
              <text x="297" y="806"
                    text-anchor="middle"
                    font-family="'Hiragino Kaku Gothic ProN', 'Yu Gothic', 'Meiryo', sans-serif"
                    font-size="12"
                    fill="#5a6a80"
                    letter-spacing="1">#{release}</text>
            </svg>
          SVG
        end

        # ダークテーマの裏表紙SVGを生成
        def generate_dark_backcover_svg(title, subtitle, author, series, release)
          <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 595 842" width="595" height="842">
              <defs>
                <!-- Background gradient: deep navy to dark midnight -->
                <linearGradient id="bg-grad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stop-color="#0e1a2e"/>
                  <stop offset="100%" stop-color="#060d1a"/>
                </linearGradient>

                <!-- Gold shimmer gradient for accent lines -->
                <linearGradient id="gold-line" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#b8902a" stop-opacity="0"/>
                  <stop offset="40%"  stop-color="#e8c85a"/>
                  <stop offset="60%"  stop-color="#f5d96e"/>
                  <stop offset="100%" stop-color="#b8902a" stop-opacity="0"/>
                </linearGradient>

                <!-- Thin gold line for decorative rules -->
                <linearGradient id="gold-thin" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#c9a43a" stop-opacity="0"/>
                  <stop offset="30%"  stop-color="#e0c058"/>
                  <stop offset="70%"  stop-color="#e0c058"/>
                  <stop offset="100%" stop-color="#c9a43a" stop-opacity="0"/>
                </linearGradient>
              </defs>

              <!-- Background -->
              <rect width="595" height="842" fill="url(#bg-grad)"/>

              <!-- === Central graphic: abstract circuit / web network (center cy=421) === -->
              <!-- Mid ring -->
              <circle cx="297" cy="421" r="140" fill="none" stroke="#1e4070" stroke-width="0.6"/>
              <!-- Inner ring -->
              <circle cx="297" cy="421" r="86" fill="none" stroke="#254580" stroke-width="0.5"/>

              <!-- Radial spokes (inner ring r=86 → mid ring r=140) -->
              <!-- 0° right -->
              <line x1="383" y1="421" x2="437" y2="421" stroke="#3a5f9f" stroke-width="0.6"/>
              <!-- 45° up-right -->
              <line x1="358" y1="346" x2="396" y2="308" stroke="#3a5f9f" stroke-width="0.6"/>
              <!-- 90° up -->
              <line x1="297" y1="335" x2="297" y2="281" stroke="#3a5f9f" stroke-width="0.6"/>
              <!-- 135° up-left -->
              <line x1="236" y1="346" x2="198" y2="308" stroke="#3a5f9f" stroke-width="0.6"/>
              <!-- 180° left -->
              <line x1="211" y1="421" x2="157" y2="421" stroke="#3a5f9f" stroke-width="0.6"/>
              <!-- 225° down-left -->
              <line x1="236" y1="496" x2="198" y2="534" stroke="#3a5f9f" stroke-width="0.6"/>
              <!-- 270° down -->
              <line x1="297" y1="507" x2="297" y2="561" stroke="#3a5f9f" stroke-width="0.6"/>
              <!-- 315° down-right -->
              <line x1="358" y1="496" x2="396" y2="534" stroke="#3a5f9f" stroke-width="0.6"/>

              
              <!-- Inner nodes (at inner ring intersections) -->
              <circle cx="383" cy="421" r="4" fill="#4a80c8" stroke="#5b9ef5" stroke-width="0.8"/>
              <circle cx="358" cy="346" r="3" fill="#4a80c8" stroke="#5b9ef5" stroke-width="0.6"/>
              <circle cx="236" cy="346" r="3" fill="#4a80c8" stroke="#5b9ef5" stroke-width="0.6"/>
              <circle cx="211" cy="421" r="4" fill="#4a80c8" stroke="#5b9ef5" stroke-width="0.8"/>
              <circle cx="236" cy="496" r="3" fill="#4a80c8" stroke="#5b9ef5" stroke-width="0.6"/>
              <circle cx="358" cy="496" r="3" fill="#4a80c8" stroke="#5b9ef5" stroke-width="0.6"/>

              <!-- Mid ring nodes -->
              <circle cx="437" cy="421" r="5" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.8"/>
              <circle cx="396" cy="308" r="4" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.6"/>
              <circle cx="297" cy="281" r="4" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.6"/>
              <circle cx="198" cy="308" r="4" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.6"/>
              <circle cx="157" cy="421" r="5" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.8"/>
              <circle cx="198" cy="534" r="4" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.6"/>
              <circle cx="297" cy="561" r="4" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.6"/>
              <circle cx="396" cy="534" r="4" fill="#3a5f9f" stroke="#4a80c8" stroke-width="0.6"/>

              
              <!-- Center icon -->
              <circle cx="297" cy="421" r="30"  fill="#0e2040" stroke="#4a80c8" stroke-width="1.2"/>
              <!-- Bracket icon in center -->
              <text x="297" y="429" text-anchor="middle" font-family="'Courier New', monospace"
                    font-size="21" fill="#5b9ef5" font-weight="700">&lt;/&gt;</text>

              <!-- Gold accent lines at top and bottom -->
              <rect x="50" y="50" width="495" height="1" fill="url(#gold-thin)"/>
              <rect x="50" y="792" width="495" height="1" fill="url(#gold-thin)"/>
            </svg>
          SVG
        end

        # ライトテーマの裏表紙SVGを生成
        def generate_light_backcover_svg(title, subtitle, author, series, release)
          <<~SVG
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 595 842" width="595" height="842">
              <defs>
                <!-- Background gradient: light cream to off-white -->
                <linearGradient id="bg-grad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stop-color="#f8f6f2"/>
                  <stop offset="100%" stop-color="#f0ece4"/>
                </linearGradient>

                <!-- Gold shimmer gradient for accent lines -->
                <linearGradient id="gold-line" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#b8902a" stop-opacity="0"/>
                  <stop offset="40%"  stop-color="#e8c85a"/>
                  <stop offset="60%"  stop-color="#f5d96e"/>
                  <stop offset="100%" stop-color="#b8902a" stop-opacity="0"/>
                </linearGradient>

                <!-- Thin gold line for decorative rules -->
                <linearGradient id="gold-thin" x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%"   stop-color="#c9a43a" stop-opacity="0"/>
                  <stop offset="30%"  stop-color="#e0c058"/>
                  <stop offset="70%"  stop-color="#e0c058"/>
                  <stop offset="100%" stop-color="#c9a43a" stop-opacity="0"/>
                </linearGradient>
              </defs>

              <!-- Background -->
              <rect width="595" height="842" fill="url(#bg-grad)"/>

              <!-- === Central graphic: abstract circuit / web network (center cy=421) === -->
              <!-- Mid ring -->
              <circle cx="297" cy="421" r="140" fill="none" stroke="#e8e8e8" stroke-width="0.6"/>
              <!-- Inner ring -->
              <circle cx="297" cy="421" r="86" fill="none" stroke="#f0f0f0" stroke-width="0.5"/>

              <!-- Radial spokes (inner ring r=86 → mid ring r=140) -->
              <!-- 0° right -->
              <line x1="383" y1="421" x2="437" y2="421" stroke="#f0f0f0" stroke-width="0.6"/>
              <!-- 45° up-right -->
              <line x1="358" y1="346" x2="396" y2="308" stroke="#f0f0f0" stroke-width="0.6"/>
              <!-- 90° up -->
              <line x1="297" y1="335" x2="297" y2="281" stroke="#f0f0f0" stroke-width="0.6"/>
              <!-- 135° up-left -->
              <line x1="236" y1="346" x2="198" y2="308" stroke="#f0f0f0" stroke-width="0.6"/>
              <!-- 180° left -->
              <line x1="211" y1="421" x2="157" y2="421" stroke="#f0f0f0" stroke-width="0.6"/>
              <!-- 225° down-left -->
              <line x1="236" y1="496" x2="198" y2="534" stroke="#f0f0f0" stroke-width="0.6"/>
              <!-- 270° down -->
              <line x1="297" y1="507" x2="297" y2="561" stroke="#f0f0f0" stroke-width="0.6"/>
              <!-- 315° down-right -->
              <line x1="358" y1="496" x2="396" y2="534" stroke="#f0f0f0" stroke-width="0.6"/>

              
              <!-- Inner nodes (at inner ring intersections) -->
              <circle cx="383" cy="421" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>
              <circle cx="358" cy="346" r="3" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="236" cy="346" r="3" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="211" cy="421" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>
              <circle cx="236" cy="496" r="3" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="358" cy="496" r="3" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>

              <!-- Mid ring nodes -->
              <circle cx="437" cy="421" r="5" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>
              <circle cx="396" cy="308" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="297" cy="281" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="198" cy="308" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="157" cy="421" r="5" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.8"/>
              <circle cx="198" cy="534" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="297" cy="561" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>
              <circle cx="396" cy="534" r="4" fill="#f0f0f0" stroke="#1e3a60" stroke-width="0.6"/>

              
              <!-- Center icon -->
              <circle cx="297" cy="421" r="30"  fill="#ffffff" stroke="#1e3a60" stroke-width="1.2"/>
              <!-- Bracket icon in center -->
              <text x="297" y="429" text-anchor="middle" font-family="'Courier New', monospace"
                    font-size="21" fill="#1e3a60" font-weight="700">&lt;/&gt;</text>

              <!-- Gold accent lines at top and bottom -->
              <rect x="50" y="50" width="495" height="1" fill="url(#gold-thin)"/>
              <rect x="50" y="792" width="495" height="1" fill="url(#gold-thin)"/>
            </svg>
          SVG
        end

        # @return [void]
        #
        # 生成ファイル: .cache/vs/_titlepage.md
        def execute_titlepage(options)
          apply_verbose(options)
          title, subtitle = extract_title_and_subtitle
          author  = fetch_config_value('book', 'author')
          series  = fetch_config_value('book', 'series')
          release = fetch_config_value('book', 'release')
          subtitle_class = "subtitle subtitle--#{subtitle_style}"

          content = <<~MD
            <h1 class="book-title">#{title}</h1>
            #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

            #{%(<p class="author"><span>[著]</span> #{author}</p>) unless author.empty?}

            #{%(<div class="publication-info">) unless series.empty? && release.empty?}
            #{%(    <p class="series">#{series}</p>) unless series.empty?}
            #{%(    <p class="release-info">#{release}</p>) unless release.empty?}
            #{%(</div>) unless series.empty? && release.empty?}
          MD

          path = File.join(Common::CACHE_DIR, '_titlepage.md')
          return if File.exist?(path) && !options[:force]

          safe_write(path, content)
        end

        # --- 奥付生成 ---

        # 奥付ページを config/book.yml から生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: .cache/vs/_colophon.md
        def execute_colophon(options)
          apply_verbose(options)
          title, subtitle = extract_title_and_subtitle
          author    = fetch_config_value('book', 'author')
          publisher = fetch_config_value('book', 'publisher')
          # publisher が未設定の場合は publisher_name をフォールバック
          publisher = fetch_config_value('book', 'publisher_name') if publisher.empty?
          contact   = fetch_config_value('book', 'contact')
          release   = fetch_config_value('book', 'release')
          subtitle_class = "subtitle subtitle--#{subtitle_style}"
          current_wareki = "令和#{kanji_year(Time.now.year - 2018)}年"

          content = <<~MD
            <h1 class="book-title">#{title}</h1>
            #{%(<p class="#{subtitle_class}">#{subtitle}</p>) unless subtitle.empty?}

            #{%(<p class="publication-info">#{release}</p>) unless release.empty?}

            <dl class="info-list">
                #{%(<dt>著者</dt>\n                <dd>#{author}</dd>) unless author.empty?}
                #{%(<dt>発行者</dt>\n                <dd>#{publisher}</dd>) unless publisher.empty?}
                #{%(<dt>連絡先</dt>\n                <dd>#{contact}</dd>) unless contact.empty?}
            </dl>

            <p class="copyright">
                <small>
                    &copy; #{current_wareki} #{author.empty? ? '著者' : author} All rights reserved.
                </small>
            </p>

            <p class="powered-by">
                <small>
                    (powered by Vivlio Starter)
                </small>
            </p>
          MD

          path = File.join(Common::CACHE_DIR, '_colophon.md')
          return if File.exist?(path) && !options[:force]

          safe_write(path, content)
        end

        # --- リーガルページ生成 ---

        # 免責事項・商標情報を含むリーガルページを生成する
        #
        # @param options [Hash] オプション
        #   - :verbose [Boolean] 詳細ログ出力
        #   - :force [Boolean] 既存ファイルを強制上書き
        # @return [void]
        #
        # 生成ファイル: .cache/vs/_legalpage.md
        def execute_legalpage(options)
          apply_verbose(options)
          FileUtils.mkdir_p(Common::CACHE_DIR)
          target = File.join(Common::CACHE_DIR, '_legalpage.md')
          return if File.exist?(target) && !options[:force]

          disclaimer, trademark = legal_texts
          # 各行を <p> タグで囲んで HTML 化（Vivliostyle での表示用）
          body = <<~MD
            <h1 style="display: none;">本書について</h1>
            <div class="disclaimer">
              <h2>■免責</h2>
              #{disclaimer.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
            </div>

            <div class="trademark">
              <h2>■商標</h2>
              #{trademark.split(/\r?\n/).map { |line| "  <p>#{line}</p>" }.join("\n")}
            </div>
          MD

          safe_write(target, body)
          Common.log_success("生成しました: #{target}")
        end

        # --- ヘルパー ---

        # verbose オプションが有効な場合、環境変数を設定してログ出力を詳細化する
        #
        # @param options [Hash] オプション Hash
        # @return [void]
        def apply_verbose(options)
          ENV['VERBOSE'] = '1' if options[:verbose]
        end

        # 章名リストが空でないかを判定する
        #
        # @param names [Array, nil] 章名リスト
        # @return [Boolean] 有効な章名が1つ以上あれば true
        def ensure_names_present?(names)
          !names.nil? && !names.empty?
        end

        # 入力トークンを正規化し、slug のみ指定された場合は空き番号を自動割り当てする
        #
        # @param names [Array<String>] 元の入力トークン
        # @param resolver [TokenResolver::Resolver] カタログ情報を参照する Resolver
        # @return [Array<String>] Resolver へ渡す正規化済みトークン
        def normalize_name_inputs(names, resolver)
          used_numbers = used_numbers_pool(resolver)

          Array(names).map do |raw|
            token = raw.to_s.strip
            basename = strip_token_basename(token)

            if numbered_basename?(basename)
              number = extract_number(basename)
              used_numbers << number if number && !used_numbers.include?(number)
              token
            else
              slug = normalize_slug(basename)
              number = next_available_number!(used_numbers)
              generated = "#{number}-#{slug}"
              Common.log_info("[create] #{basename} -> #{generated}")
              generated
            end
          end
        end

        # トークンからベース名（ディレクトリ・拡張子を除いたもの）を取得する
        def strip_token_basename(token)
          base = File.basename(token.to_s.strip)
          base.sub(/\.(md|markdown)\z/i, '')
        rescue StandardError
          token.to_s
        end

        # ベース名が番号で始まるか判定する
        def numbered_basename?(basename)
          basename.match?(/\A\d+/)
        end

        # ベース名から章番号を抽出する（2桁ゼロ埋め）
        def extract_number(basename)
          return unless basename =~ /\A(\d+)/

          format('%02d', Regexp.last_match(1).to_i)
        end

        # 章名リストが空の場合、使い方を表示して終了する
        #
        # @param names [Array, nil] 章名リスト
        # @return [void]
        # @raise [SystemExit] names が空の場合 exit(1)
        def ensure_names_present!(names)
          return if ensure_names_present?(names)

          warn '使い方: vs create NAME [NAME ...]'
          exit 1
        end

        # カタログおよび既存ファイルから使用済み番号のプールを構築する
        def used_numbers_pool(resolver)
          catalog_numbers = resolver.resolve([]).map(&:number).compact
          markdown_numbers = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).filter_map do |path|
            File.basename(path, '.md')[/\A(\d{2})/, 1]
          end

          (catalog_numbers + markdown_numbers).uniq
        end

        # 未使用の章番号を払い出す
        def next_available_number!(used_numbers)
          (1..MAX_AUTO_CHAPTER).each do |candidate|
            number = format('%02d', candidate)
            next if used_numbers.include?(number)

            used_numbers << number
            return number
          end

          raise '01-98 までの章番号がすべて使用済みです'
        end

        # 単一の章ファイルと関連リソースを生成する
        #
        # @param fname [String] ファイル名（XX-slug.md 形式）
        # @return [void]
        #
        # 処理フロー:
        #   1. テンプレートから Markdown コンテンツを生成
        #   2. contents/ に Markdown ファイルを作成
        #   3. images/ に章専用の画像ディレクトリを作成
        #   4. config/catalog.yml の CHAPTERS に章を追記
        def create_single_chapter(fname, entry)
          title   = generate_title(fname)
          content = generate_content_from_template(entry, title)
          path    = create_markdown_file(fname, content)
          # Vivliostyle は章ごとに画像を images/XX-slug/ に配置する規約
          create_image_directory(fname, {})

          # catalog.yml に追記することで build 時に自動的に含まれる
          basename = File.basename(fname, '.md')
          Build::CatalogUpdater.add_chapter(basename)

          Common.log_success("#{path} を作成しました")
        end

        # 章名を正規化し、ファイル名形式（XX-slug.md）に変換する
        #
        # @param name [String, nil] 入力された章名
        # @return [String, nil] 正規化されたファイル名、無効な場合は nil
        #
        # ファイル名規約:
        #   - 先頭は1桁以上の数字（並び順を示す。例: 11, 21）
        #   - オプションでハイフン区切りの slug を続けられる（"11-install"）
        #   - slug を省略した数字のみ（"02"）も許可し、numeric-only ファイルを生成できる
        #   - 英数字・ハイフン・ドット・アンダースコアのみ許可
        #   - 例: "11-install" → "11-install.md"、"02" → "02.md"
        def ensure_filename(name)
          return nil if name.nil?

          n = name.to_s.strip
          n = File.basename(n)
          n = File.basename(n, '.md')
          # 規約: 数字で始まり、オプションで -slug を続ける形式のみ許可
          return nil unless n =~ /\A\d+(?:-[\w.-]+)?\z/

          "#{n}.md"
        rescue StandardError
          nil
        end

        # ファイル名から章タイトルを抽出する
        #
        # @param fname [String] ファイル名（例: "11-sample.md"）
        # @return [String] タイトル部分（例: "sample"）
        #
        # 章番号プレフィックス（数字-）を除去し、タイトルとして使用する
        def generate_title(fname)
          basename = File.basename(fname.to_s, '.md')
          basename.sub(/\A\d+-/, '')
        end

        # slug を chapter 名として利用できる形式へ正規化する
        def normalize_slug(value)
          slug = value.to_s.downcase
                        .tr(' ', '-')
                        .gsub(/[^a-z0-9\-]+/, '-')
                        .gsub(/-+/, '-')
                        .gsub(/\A-+|-+\z/, '')
          slug = 'chapter' if slug.empty?
          slug
        end

        # テンプレートから章コンテンツを生成する
        #
        # @param entry [TokenResolver::Entry, nil] 章エントリ（kind 判定に利用）
        # @param title [String] 章タイトル
        # @return [String] Markdown コンテンツ
        #
        # templates/*.md に存在するテンプレートを kind ごとに使い分け、
        # {{TITLE}} プレースホルダをタイトルで置換する。
        # テンプレートが無い場合はデフォルトの骨子を生成する。
        def generate_content_from_template(entry, title)
          tpl = template_path_for(entry)
          if tpl && File.exist?(tpl)
            File.read(tpl, encoding: 'utf-8').gsub('{{TITLE}}', title.to_s)
          else
            <<~MD
              # #{title}

              <!-- 章テンプレートが見つからなかったため、デフォルトの骨子を生成しました -->

              ここに#{title}の内容を記述してください。
            MD
          end
        end

        def template_path_for(entry)
          case entry&.kind
          when :preface then Common.preface_template_path
          when :appendix then Common.appendix_template_path
          when :postface then Common.postface_template_path
          else Common.chapter_template_path
          end
        end

        # Markdown ファイルを contents/ に作成する
        #
        # @param fname [String] ファイル名
        # @param content [String] ファイル内容
        # @return [String] 作成したファイルのパス
        # @raise [RuntimeError] 同名ファイルが既に存在する場合
        def create_markdown_file(fname, content)
          path = File.join(Common::CONTENTS_DIR, fname)
          raise "既に存在します: #{path}" if File.exist?(path)

          safe_write(path, content)
          path
        end

        # 章に対応する画像ディレクトリを生成する
        #
        # @param fname [String] 章ファイル名（XX-slug.md）
        # @param _options [Hash] 予約（将来拡張用）
        # @return [String] 作成したディレクトリのパス
        #
        # Vivliostyle では章ごとに images/XX-slug/ に画像を配置する規約があり、
        # Markdown 内の相対パス参照が正しく解決されるために必要
        def create_image_directory(fname, _options = {})
          basename = File.basename(fname, '.md')
          dir = File.join(Common::IMAGES_DIR, basename)

          if Dir.exist?(dir)
            Common.log_info("画像ディレクトリは既に存在します: #{dir}")
            return dir
          end

          FileUtils.mkdir_p(dir)
          Common.log_success("画像ディレクトリを作成しました: #{dir}")
          dir
        end

        # ファイルを安全に書き込む（親ディレクトリを自動作成）
        #
        # @param path [String] 書き込み先パス
        # @param content [String] ファイル内容
        # @return [void]
        def safe_write(path, content)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content, encoding: 'utf-8')
        end

        # config/book.yml からタイトルとサブタイトルを取得する
        #
        # @return [Array<String, String>] [タイトル, サブタイトル]
        #
        # 設定キー:
        #   - book.main_title または book.title: メインタイトル
        #   - book.subtitle: サブタイトル（任意）
        def extract_title_and_subtitle
          book = Common::CONFIG.fetch('book', {})
          title = (book['main_title'] || book['title'] || '').to_s
          subtitle = (book['subtitle'] || '').to_s
          [title, subtitle]
        end

        # サブタイトルの装飾スタイルを取得する
        #
        # @return [String] "wave", "bar", "none" のいずれか（デフォルト: "wave"）
        #
        # CSS クラス subtitle--wave, subtitle--bar, subtitle--none に対応
        def subtitle_style
          style = fetch_config_value('book', 'subtitle_style').downcase
          %w[wave bar none].include?(style) ? style : 'wave'
        end

        # config/book.yml から指定キーの値を取得する
        #
        # @param section [String] セクション名（例: 'book', 'legal'）
        # @param key [String] キー名
        # @return [String] 値（nil の場合は空文字列）
        #
        # 使用例: fetch_config_value('book', 'author') → "著者名"
        def fetch_config_value(section, key)
          value = Common::CONFIG.dig(section, key)
          value ? value.to_s : ''
        end

        # 西暦から和暦の漢数字表記を生成する
        #
        # @param num [Integer] 元号からの年数（例: 令和7年なら 7）
        # @return [String] 漢数字表記（例: "七"）
        #
        # 奥付の著作権表示で使用（例: "令和七年"）
        def kanji_year(num)
          km = %w[〇 一 二 三 四 五 六 七 八 九]
          return '〇' if num <= 0
          return km[num] if num < 10
          return '十' if num == 10

          tens = num / 10
          ones = num % 10
          result = ''
          result += "#{km[tens] unless tens == 1}十"
          result += km[ones] unless ones.zero?
          result
        end

        # config/book.yml から免責・商標文面を取得する
        #
        # @return [Array<String, String>] [免責文面, 商標文面]
        #
        # 設定キー:
        #   - legal.disclaimer: 免責事項
        #   - legal.trademark: 商標情報
        #
        # 両方とも未設定の場合は DEFAULT_DISCLAIMER / DEFAULT_TRADEMARK を使用
        def legal_texts
          legal = Common::CONFIG.fetch('legal', {})
          disclaimer = (legal['disclaimer'] || '').strip
          trademark  = (legal['trademark']  || '').strip

          if disclaimer.empty? && trademark.empty?
            Common.log_warn('config/book.yml の legal.disclaimer / legal.trademark が未設定です。テンプレート文面で生成します。')
            disclaimer = DEFAULT_DISCLAIMER
            trademark  = DEFAULT_TRADEMARK
          end

          [disclaimer, trademark]
        end

        # デフォルトの免責事項テンプレート
        DEFAULT_DISCLAIMER = <<~TXT.strip
          本書は教育目的で作成された入門書であり、情報の提供のみを目的としています。内容の正確性には万全を期しておりますが、技術的な詳細については、専門的な文献もあわせてご参照ください。
          本書の内容を参考にした結果生じた損害や、本書の内容を実行・運用・適用したことによって発生した問題について、著者・発行者および関係者は一切の責任を負いかねます。
        TXT

        # デフォルトの商標情報テンプレート
        DEFAULT_TRADEMARK = <<~TXT.strip
          本書に登場するシステム名や製品名は、関係各社の商標または登録商標です。
          本書では ™、®、© などのマークは省略しています。
        TXT
      end
    end
  end
end
