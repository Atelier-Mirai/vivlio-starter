# frozen_string_literal: true

require_relative '../image_filename_sanitizer'

module VivlioStarter
  module CLI
    module Guards
      # 著者が配置した画像のファイル名に、ビルド／EPUB を壊す文字が含まれていないかを
      # ビルド前に検出して警告する（docs/specs/epub-kindle-webp-transcode-spec.md §4）。
      #
      # きっかけ: アポストロフィ `'` を含む画像が Kindle で解決できず W14010 になった。
      # `'` 限定ではなく「確実に壊れる文字」一般を、改名案と出現箇所を添えて警告する。
      # 重大度は警告のみ（非ブロッキング）。検出は images/・covers/・stylesheets/images/ の
      # 3 ディレクトリすべてに対して行い、出現箇所の行番号報告は本文画像（contents/*.md
      # 参照）にのみ付ける（表紙・扉絵は config/CSS 経由のため固定文言の軽い案内）。
      class ImageFilenameCheck < BaseCheck
        # 検出対象とする画像拡張子。
        IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .webp .gif .svg].freeze

        # @return [Array<Violation>] 警告の配列（合格なら空配列）
        def validate
          scan_targets.flat_map { |dir, usage| scan_directory(dir, usage) }
        end

        private

        # 走査対象ディレクトリ → 用途（出現箇所案内の出し分けに使う）。
        def scan_targets
          {
            Common::IMAGES_DIR => :contents,
            Common::COVERS_DIR => :cover,
            File.join(Common::STYLESHEETS_DIR, 'images') => :frontispiece
          }
        end

        # 1 ディレクトリ配下の画像ファイル名を検査し、問題があれば警告を作る。
        def scan_directory(dir, usage)
          return [] unless Dir.exist?(dir)

          image_files(dir).filter_map do |path|
            bad = offending_characters(File.basename(path))
            next if bad.empty?

            warning(
              "画像ファイル名に問題のある文字 #{bad.join(' ')} が含まれています: #{path}",
              detail: violation_detail(path, usage)
            )
          end
        end

        # ディレクトリ配下（再帰）の画像ファイルパスを返す。
        def image_files(dir)
          Dir.glob(File.join(dir, '**', '*')).select do |path|
            File.file?(path) && IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
          end.sort
        end

        # basename に含まれる「危険文字」を重複なく取り出す（表示順は出現順）。
        def offending_characters(basename)
          ImageFilenameSanitizer.offending_characters(basename)
        end

        # 警告の詳細（改名案 ＋ 出現箇所案内）を行配列で返す。
        def violation_detail(path, usage)
          lines = ["→ #{suggest_rename(path)} に変更してください"]
          lines << occurrence_hint(path, usage)
          lines
        end

        # 危険文字を取り除いた改名案を返す（提示のみ・実ファイルは不変）。
        # 削除方式にすることで Einstein's → Einsteins のように自然な名前になる
        # （import 時の正規化と同一基準を共有する。ImageFilenameSanitizer）。
        def suggest_rename(path)
          dir = File.dirname(path)
          ext = File.extname(path)
          safe = ImageFilenameSanitizer.sanitize(File.basename(path, ext))
          File.join(dir, "#{safe}#{ext}")
        end

        # 出現箇所の案内。本文画像は contents/*.md の行番号、表紙・扉絵は固定文言。
        def occurrence_hint(path, usage)
          case usage
          in :contents     then contents_occurrence_hint(path)
          in :cover        then '表紙・裏表紙として配置されています'
          in :frontispiece then '扉絵・節絵として配置されています'
          end
        end

        # contents/*.md から当該画像の参照行を探して「ファイル名 の N 行目」案内を作る。
        def contents_occurrence_hint(path)
          basename = File.basename(path)
          occurrences = Dir.glob(File.join(Common::CONTENTS_DIR, '*.md')).sort.filter_map do |md|
            line_numbers = []
            File.foreach(md).with_index(1) { |line, ln| line_numbers << ln if line.include?(basename) }
            next if line_numbers.empty?

            "#{md} の #{line_numbers.map { "#{it} 行目" }.join(', ')}"
          end

          occurrences.empty? ? '（本文での参照は見つかりませんでした）' : "出現箇所: #{occurrences.join(' / ')}"
        end
      end
    end
  end
end
