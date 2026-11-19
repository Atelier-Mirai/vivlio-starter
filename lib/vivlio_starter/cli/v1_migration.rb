# frozen_string_literal: true

# ================================================================
# File: lib/vivlio_starter/cli/v1_migration.rb
# ================================================================
# 責務:
#   1.x の配置の本（stylesheets/ の直下に 1.x の雛形の CSS がある本）を見分け、
#   `vs upgrade` が 2.0 の配置へ移すときの計画と案内を作る（v2-migration-plan.md §5.2・§5.3・§5.7）。
#
#   - 判定: legacy?（vs build などを 🔴 で止める・vs doctor が 🟡 で示す・vs upgrade が移す）
#   - 計画: 1.x の雛形の CSS と画像を「消す（著者が変えていない）」「stylesheets/_v1/ へ移す（変えた）」に分ける
#   - 原稿の走査: 2.0 で行内の属性として読まれる `]{.` の並び（§5.2）
#
# 判定を scaffold.lock の版で行わない理由:
#   2.0 の公開までは v2 の版も 1.0.x のままで、v2 の vs new で作った本も lock の版は 1.0.x になる。
#   版で比べると、2.0 の配置の本まで 1.x と見なして止めてしまう。配置そのもの（1.x の雛形にしか
#   無い名前の CSS が stylesheets/ の直下にあるか）は、版の付け方に左右されない。移した後は、
#   それらのファイルは消えるか stylesheets/_v1/ へ移っているので、移した本を誤って止めることもない。
# ================================================================

require 'open3'
require 'shellwords'

require_relative 'common'
require_relative 'masking'
require_relative 'pre_process/inline_span_transformer'
require_relative 'scaffold_lock'
require_relative 'scaffold_base'

module VivlioStarter
  module CLI
    module V1Migration
      extend self

      STYLESHEETS = 'stylesheets'

      # 1.x の雛形が stylesheets/ の直下に置いた CSS（1.0.0-beta〜1.0.1 の和集合）。
      # custom.css は著者のファイルで 2.0 でもそのまま読むので含めない。
      # _README.md は 2.0 の雛形にもあるので、ほかの雛形のファイルと同じに更新する
      V1_CSS = %w[appendix.css base.css chapter-common.css chapter.css code.css colophon.css
                  components.css glossary.css image-header.css index.css layout-utils.css
                  legalpage.css page-settings.css pagebreak.css part-title.css postface.css
                  preface.css prism.css replace-list.css simple-header.css spacing.css
                  table.css theme.css titlepage.css toc.css].freeze

      # 本文のページ（章・付録・前書き・後書き）の body のクラス
      BODY_PAGES = %w[chapter appendix preface postface].freeze

      # 1.x でそのファイルを読んでいたページ（body のクラス。theme-contract-spec.md §2.2 のページの種類）。
      # 1.0.1 の雛形の @import をたどった結果で、載っていないファイル（base.css・theme.css・page-settings.css）は
      # すべてのページが読んでいた。2.0 の custom.css はすべてのページで読まれるので、移した規則を写すときに
      # ページを絞る前置きとして示す。絞らずに写すと、同じクラスを使うほかのページ（扉と奥付の .book-title など）
      # にも効く（S11a の予行で、components.css の書名の色が扉と奥付にも出た）
      V1_PAGES = {
        'components.css' => BODY_PAGES, 'prism.css' => BODY_PAGES, 'code.css' => BODY_PAGES,
        'table.css' => BODY_PAGES, 'layout-utils.css' => BODY_PAGES, 'replace-list.css' => BODY_PAGES,
        'pagebreak.css' => BODY_PAGES,
        'spacing.css' => %w[chapter appendix], 'chapter-common.css' => %w[chapter appendix],
        'simple-header.css' => %w[chapter appendix], 'image-header.css' => %w[chapter],
        'chapter.css' => %w[chapter], 'appendix.css' => %w[appendix],
        'preface.css' => %w[preface postface], 'postface.css' => %w[postface],
        'titlepage.css' => %w[titlepage], 'colophon.css' => %w[colophon], 'legalpage.css' => %w[legalpage],
        'part-title.css' => %w[part-title], 'toc.css' => %w[toc], 'index.css' => %w[index-page],
        'glossary.css' => %w[glossary-page]
      }.freeze

      # 1.x の雛形が扉絵・節絵を置いた場所。2.0 ではテーマの images/ に置き換わる
      IMAGES_DIR = File.join(STYLESHEETS, 'images')

      # 著者が変えた 1.x の雛形の CSS の退避先。2.0 のビルドは読まない
      RETIRE_DIR = File.join(STYLESHEETS, '_v1')

      # 移行の計画の 1 行。action は :remove（著者が変えていない）/ :retire（変えたので _v1/ へ移す）
      Item = Data.define(:relative, :action)

      # 原稿の走査で見つけた 1 か所
      Hit = Data.define(:path, :lineno, :line)

      # 1.x の配置のままの本か。scaffold_source を渡すと、その雛形にもある名前は 1.x の印と見なさない
      # （vs upgrade は比べる雛形を差し替えられるので、その雛形が配るファイルを片付けの対象にしない）
      def legacy?(root = '.', scaffold_source: nil)
        v1_css(scaffold_source).any? { File.file?(File.join(root, STYLESHEETS, it)) }
      end

      # 1.x の雛形の CSS の名前のうち、今の雛形に無いもの
      def v1_css(scaffold_source)
        return V1_CSS if scaffold_source.nil?

        V1_CSS.reject { File.file?(File.join(scaffold_source, STYLESHEETS, it)) }
      end

      # 移していない本を止める・示すときの文面（§5.7）。vs build などは 🔴、vs doctor は 🟡 で出す。
      # 二つの道を、そのまま打てる形で示す
      # @return [Array(String, Array<String>)] 見出しと detail の行
      def unmigrated_notice
        ['この本は stylesheets/ が 1.x の配置のままなので、2.0 の vs では組めません',
         ['2.0 へ移すなら: vs upgrade（変えるファイルを全部見せてから尋ねます）',
          "1.x のまま組むなら: Gemfile の gem 'vivlio-starter' を gem 'vivlio-starter', '~> 1.0' に書き換え、" \
          'bundle install の後に bundle exec vs build']]
      end

      # 1.x の雛形の CSS と画像を、消すものと _v1/ へ移すものに分ける（§5.3 の 2・4）。
      #   - CSS: 著者が変えていなければ消す。変えていれば _v1/ へ移す
      #   - 画像: 雛形の画像のままなら消す。著者が足した画像と、雛形と同じ名前で中身を替えた画像は残す
      #     （theme.frontispiece.image は stylesheets/images/ を先に探すので、残した画像がそのまま使われる）
      # 2.0 の雛形にも同じパスがあるファイル（stylesheets/images/floral.webp など）は、ほかの雛形の
      # ファイルと同じに扱うので、ここには載せない
      # @param lock_files [Hash{String => String}] scaffold.lock の files 節
      # @param scaffold_digests [Hash{String => String}] 2.0 の雛形のハッシュ表
      # @param gem_roots [Array<String>] インストール済みの gem の雛形（ScaffoldBase.installed_scaffold_dirs）
      # @return [Array<Item>]
      def plan(lock_files, scaffold_digests, gem_roots)
        css = V1_CSS.map { File.join(STYLESHEETS, it) }.select { File.file?(it) && !scaffold_digests.key?(it) }
        images = Dir.glob('**/*', base: IMAGES_DIR)
                    .map { File.join(IMAGES_DIR, it) }
                    .select { File.file?(it) && !scaffold_digests.key?(it) }
                    .reject { ScaffoldLock::IGNORED_BASENAMES.include?(File.basename(it)) }

        css.map { Item.new(relative: it, action: pristine?(it, lock_files, gem_roots) ? :remove : :retire) } +
          images.select { pristine?(it, lock_files, gem_roots) }.sort.map { Item.new(relative: it, action: :remove) }
      end

      # 雛形のままか。lock の記録と同じか、インストール済みのどれかの版の雛形と同じなら、著者は変えていない。
      # gem の雛形とも比べるのは、lock の無い本（vs upgrade の前の版で作った本）と、著者が手で
      # 新しい版の雛形を写した本を、変えたと見なして _v1/ へ移さないため
      def pristine?(relative, lock_files, gem_roots)
        digest = ScaffoldLock.file_digest(relative)
        return true if digest == lock_files[relative]

        gem_roots.any? do |root|
          path = File.join(root, relative)
          File.file?(path) && ScaffoldLock.file_digest(path) == digest
        end
      end

      # stylesheets/_v1/ へ移した先のパス
      def retired_path(relative) = File.join(RETIRE_DIR, File.basename(relative))

      # 1.x でそのファイルを読んでいたページだけを選ぶ前置き。すべてのページが読んでいたファイルは nil
      # @return [String, nil] 例: ":is(body.chapter, body.appendix)"
      def page_scope(relative)
        pages = V1_PAGES[File.basename(relative)] or return nil
        pages.one? ? "body.#{pages.first}" : ":is(#{pages.map { "body.#{it}" }.join(', ')})"
      end

      # 移したファイルと、もとの雛形との差分を見るコマンド（1 行）。もとの雛形（lock の記録と同じ中身）を
      # 全部持っている 1.x の gem が無ければ nil（§5.3 の「1.x の gem が残っていない場合は、示さない」）
      # @param retired [Array<String>] 移したファイル（移す前のパス）
      # @return [String, nil]
      def diff_command(retired, lock_files, gem_roots)
        root = gem_roots.find do |candidate|
          retired.all? { ScaffoldBase.ancestor_path(it, lock_files[it], [candidate]) }
        end
        return nil if root.nil? || retired.empty?

        original = Shellwords.escape(File.join(root, STYLESHEETS))
        names = retired.map { File.basename(it) }
        return "diff -u #{original}/#{names.first} #{RETIRE_DIR}/#{names.first}" if names.one?

        "for f in #{names.join(' ')}; do diff -u #{original}/$f #{RETIRE_DIR}/$f; done"
      end

      # 2.0 で行内の属性（`[文字]{.class}`）として読まれる並びを、原稿のコードの外から探す（§5.2）。
      # 読み方は前処理と同じ（PreProcessCommands::InlineSpanTransformer）。行末の段落の寄せ
      # （`…{.text-right}`）は 1.x と同じに組まれるので数えない
      # @param paths [Array<String>] 原稿のパス
      # @return [Array<Hit>]
      def inline_attribute_hits(paths)
        paths.sort.flat_map do |path|
          text = File.read(path, encoding: 'utf-8')
          Masking.each_prose_line(text).filter_map do |line, lineno|
            Hit.new(path:, lineno:, line: line.strip) if PreProcessCommands::InlineSpanTransformer.each_span(line).any?
          end
        rescue StandardError
          []
        end
      end

      # 原稿（contents/ の下の .md）
      def manuscript_paths = Dir.glob(File.join(Common::CONTENTS_DIR, '**', '*.md'))

      # Git の作業ツリーの、コミットしていない変更（追跡しているファイルだけ）。
      # 移行の結果を 1 つのコミットにまとめられるよう、移行の前に確かめる（§5.3 の最後）。
      # 追跡していないファイルは移行で触らないので数えない。Git の外の本は空を返す（退避があるので止めない）
      # @return [Array<String>] git status --porcelain の行
      def uncommitted_changes
        out, status = Open3.capture2('git', 'status', '--porcelain', '--untracked-files=no', err: File::NULL)
        status.success? ? out.lines.map(&:chomp).reject(&:empty?) : []
      rescue StandardError
        []
      end
    end
  end
end
