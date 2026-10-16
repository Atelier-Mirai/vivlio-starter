# frozen_string_literal: true

# ================================================================
# Test: guards/checks_test.rb
# ================================================================
# テスト対象:
#   Guards の各 Check（lib/vivlio_starter/cli/guards/*.rb）
#
# 検証内容（precondition-guard-spec.md §7.1）:
#   GC-01: CatalogEntriesCheck - 全参照先が実在 → 違反 0 件
#   GC-02: CatalogEntriesCheck - 1 件欠落 → :error 1 件・detail に該当パス
#   GC-03: CatalogEntriesCheck - catalog.yml なし → 違反 0 件
#   GC-04: OrphanFileCheck - 未登録ファイル → :warn 1 件・detail に該当パス
#   GC-04b: DuplicateNumberCheck - 章番号の重複 → :error 1 件・重なった番号とファイル・振り直すコマンドを列挙
#   GC-05: CatalogFileCheck - catalog.yml なし → :error 1 件
#   GC-06: NodeCheck - node なし（runner DI） → :error 1 件
#   GC-07: VfmCheck  - vfm なし（runner DI） → :error 1 件・正しいパッケージ名を案内
# ================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/guards'

module VivlioStarter
  module CLI
    class GuardsChecksTest < Minitest::Test
      # GC-01: 全参照先が実在すれば合格
      def test_should_pass_when_all_catalog_entries_exist
        with_temp_project do
          write_catalog(chapters: %w[11-intro])
          write_content('11-intro')

          assert_empty Guards::CatalogEntriesCheck.new.validate
        end
      end

      # GC-02: 欠落があれば :error 1 件に集約し、detail に該当パスと対処を含む
      def test_should_report_error_with_missing_entry_path_in_detail
        with_temp_project do
          write_catalog(chapters: %w[11-intro 89-bugfix-check])
          write_content('11-intro') # 89-bugfix-check.md は作らない

          violations = Guards::CatalogEntriesCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert violations.first.detail.any? { it.include?('contents/89-bugfix-check.md') },
                 'detail に欠落ファイルのパスを含むべき'
          assert violations.first.detail.any? { it.include?('vs delete') },
                 'detail に対処方法を含むべき'
        end
      end

      # GC-03: catalog.yml の不在は CatalogFileCheck の責務のため合格扱い
      def test_should_pass_when_catalog_file_is_absent
        with_temp_project do
          assert_empty Guards::CatalogEntriesCheck.new.validate
        end
      end

      # GC-04: 未登録原稿は :warn 1 件に集約し、detail に列挙する
      def test_should_warn_orphan_files_in_single_violation
        with_temp_project do
          write_catalog(chapters: %w[11-intro])
          write_content('11-intro')
          write_content('12-orphan')
          write_content('_titlepage') # システムページは対象外

          violations = Guards::OrphanFileCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :warn?
          assert violations.first.detail.any? { it.include?('contents/12-orphan.md') }
          refute violations.first.detail.any? { it.include?('_titlepage') },
                 'アンダースコア始まりのシステムページは孤立扱いしない'
        end
      end

      # GC-05: catalog.yml がなければ :error
      def test_should_report_error_when_catalog_file_missing
        with_temp_project do
          violations = Guards::CatalogFileCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert_includes violations.first.message, 'config/catalog.yml'
        end
      end

      # GC-06: node が見つからなければ :error（runner DI で外部コマンドを差し替え）
      def test_should_report_error_when_node_is_unavailable
        failing_runner = Class.new { def system(*) = false }.new

        violations = Guards::NodeCheck.new(runner: failing_runner).validate

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_includes violations.first.message, 'Node.js'
      end

      def test_should_pass_when_node_is_available
        passing_runner = Class.new { def system(*) = true }.new

        assert_empty Guards::NodeCheck.new(runner: passing_runner).validate
      end

      # GC-07: vfm が見つからなければ :error。
      # 案内で肝心なのはパッケージ名——npm の `vfm` は同名の別物（Vue 用）で、
      # それを入れても変換は動かないため、@vivliostyle/vfm と明示する
      def test_should_report_error_with_scoped_package_name_when_vfm_is_unavailable
        failing_runner = Class.new { def system(*) = false }.new

        violations = Guards::VfmCheck.new(runner: failing_runner).validate

        assert_equal 1, violations.size
        assert_predicate violations.first, :error?
        assert_includes violations.first.message, 'VFM'
        assert violations.first.detail.any? { it.include?('@vivliostyle/vfm') },
               'detail に正しいパッケージ名を含むべき'
      end

      def test_should_pass_when_vfm_is_available
        passing_runner = Class.new { def system(*) = true }.new

        assert_empty Guards::VfmCheck.new(runner: passing_runner).validate
      end

      # GS-01: 章の末尾に取り残された `---` は白紙を 1 枚増やすだけなので指摘する
      def test_should_warn_page_break_left_at_end_of_chapter
        with_temp_project do
          write_markdown('11-intro', <<~MD)
            # 章題

            本文です。

            ---
          MD

          violations = stray_check.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :warn?
          assert violations.first.detail.any? { it.include?('L5') }, '行番号を示すべき'
          assert violations.first.detail.any? { it.include?('白紙') }
        end
      end

      # GS-02: 項見出し（h3）の直前は正規化されないため、そこでページが切れる
      def test_should_warn_page_break_before_subsection_heading_with_its_title
        with_temp_project do
          write_markdown('11-intro', <<~MD)
            # 章題

            本文です。

            ---

            ### 項の名前

            続きの本文。
          MD

          violations = stray_check.validate

          assert_equal 1, violations.size
          assert violations.first.detail.any? { it.include?('### 項の名前') },
                 'どの見出しの前で切れるかを示すべき'
          assert violations.first.detail.any? { it.include?('@pagebreak') },
                 '意図した改ページの書き方を案内すべき'
        end
      end

      # GS-03: 節見出し（h2）の直前は、h2 が自動改ページする設定なら本文が
      # 「気にせず書いてよい」と説明している箇所。警告すると説明と機能が矛盾する
      def test_should_not_warn_before_section_heading_when_normalized
        with_temp_project do
          write_markdown('11-intro', <<~MD)
            # 章題

            前節の本文。

            ---

            ## 次の節

            本文。
          MD

          assert_empty stray_check(section_pagebreak: true).validate
        end
      end

      # GS-04: 同じ原稿でも、節を続けて組む設定（正規化されない）なら指摘する
      def test_should_warn_before_section_heading_when_sections_are_continuous
        with_temp_project do
          write_markdown('11-intro', <<~MD)
            # 章題

            前節の本文。

            ---

            ## 次の節

            本文。
          MD

          violations = stray_check(section_pagebreak: false).validate

          assert_equal 1, violations.size
          assert violations.first.detail.any? { it.include?('## 次の節') }
        end
      end

      # GS-05: 指摘しないもの——連続した `---`（意図的な空白ページ）・後ろに本文が続く
      # 改ページ・コードフェンス内の記法解説・見出しの下線（setext heading）
      def test_should_not_warn_intentional_or_non_break_usages
        with_temp_project do
          write_markdown('11-intro', <<~MD)
            # 章題

            意図的に空白ページを入れる。

            ---
            ---

            ## 節

            区切りとしての改ページ。

            ---

            続きの本文があるので正当。

            ```markdown
            ---
            ```

            見出しの下線
            ---
          MD

          assert_empty stray_check.validate
        end
      end

      # ProjectRootCheck: config/book.yml の有無で判定
      def test_should_detect_project_root_by_book_yml
        with_temp_project do
          violations = Guards::ProjectRootCheck.new.validate
          assert_equal 1, violations.size
          assert_predicate violations.first, :error?

          File.write('config/book.yml', "book:\n  main_title: 'test'\n")
          assert_empty Guards::ProjectRootCheck.new.validate
        end
      end

      # ContentsDirCheck: 存在チェック
      # （vivliostyle.config.js の存在 Guard は P3-4 で撤去。config は
      #  'prepare theme images' ステップで全文生成され欠落が自己修復されるため）
      def test_should_detect_missing_contents_dir
        Dir.mktmpdir('vs-guards') do |dir|
          Dir.chdir(dir) do
            assert_equal 1, Guards::ContentsDirCheck.new.validate.size

            FileUtils.mkdir_p('contents')

            assert_empty Guards::ContentsDirCheck.new.validate
          end
        end
      end

      # ImagesDirCheck: images/ の存在チェック
      def test_should_detect_missing_images_dir
        Dir.mktmpdir('vs-guards') do |dir|
          Dir.chdir(dir) do
            violations = Guards::ImagesDirCheck.new.validate
            assert_equal 1, violations.size
            assert_predicate violations.first, :error?

            FileUtils.mkdir_p('images')
            assert_empty Guards::ImagesDirCheck.new.validate
          end
        end
      end

      # PdfArtifactCheck: パス未指定は検証スキップ（ドメイン層の自動解決に委ねる）
      def test_should_skip_pdf_artifact_check_when_path_is_blank
        assert_empty Guards::PdfArtifactCheck.new(nil).validate
        assert_empty Guards::PdfArtifactCheck.new('').validate
        assert_empty Guards::PdfArtifactCheck.new('   ').validate
      end

      # PdfArtifactCheck: 明示パスは実在を検証する
      def test_should_verify_pdf_artifact_when_path_is_given
        Dir.mktmpdir('vs-guards') do |dir|
          Dir.chdir(dir) do
            violations = Guards::PdfArtifactCheck.new('missing.pdf').validate
            assert_equal 1, violations.size
            assert_includes violations.first.message, 'missing.pdf'

            File.write('exists.pdf', '%PDF-1.4')
            assert_empty Guards::PdfArtifactCheck.new('exists.pdf').validate
          end
        end
      end

      # PdfArtifactCheck: 拡張子を省いた指定は、コマンド本体と同じく .pdf を補って探す
      def test_should_find_pdf_artifact_given_without_extension
        Dir.mktmpdir('vs-guards') do |dir|
          Dir.chdir(dir) do
            File.write('97-sample.pdf', '%PDF-1.4')
            assert_empty Guards::PdfArtifactCheck.new('97-sample').validate

            violations = Guards::PdfArtifactCheck.new('98-missing').validate
            assert_includes violations.first.message, '98-missing.pdf'
          end
        end
      end

      # RelaxedCheck: :error を :warn に格下げする（○=推奨 の表現）
      def test_should_downgrade_error_to_warn_with_relaxed_check
        failing = Class.new(Guards::BaseCheck) do
          define_method(:validate) do
            [Guards::Violation.new(severity: :error, message: '違反', detail: nil)]
          end
        end.new

        violations = Guards::RelaxedCheck.new(failing).validate

        assert_equal 1, violations.size
        assert_predicate violations.first, :warn?
        assert_equal '違反', violations.first.message
      end

      # Guards.precheck: 合格なら nil、エラー違反なら 1 を返す（コマンド call 冒頭用）
      def test_should_precheck_return_nil_on_pass_and_one_on_error
        passing = Class.new(Guards::BaseCheck) { define_method(:validate) { [] } }.new
        failing = Class.new(Guards::BaseCheck) do
          define_method(:validate) do
            [Guards::Violation.new(severity: :error, message: '違反', detail: nil)]
          end
        end.new

        assert_nil Guards.precheck(passing)

        out, = capture_io do
          assert_equal 1, Guards.precheck(failing)
        end
        assert_includes out, '🔴 違反'
        refute_includes out, '前提条件を満たしていません', '違反を 1 件ずつ出したうえで、要約を重ねない'
      end

      # ------------------------------------------------------------------
      # GC-04b: DuplicateNumberCheck
      #
      # vs create / vs rename / vs renumber を通していれば起きないが、著者が
      # ファイル名を手で変えたときに起こる。番号が重なると、その番号でどちらを
      # 指すか決められない（vs build 02 でどちらを組むか）ので、ビルドを止める。
      # ------------------------------------------------------------------
      def test_should_stop_when_chapter_numbers_are_duplicated
        with_temp_project do
          write_content('02-dltest')
          write_content('02-vivlio')
          write_content('03-other')

          violations = Guards::DuplicateNumberCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert violations.first.detail.any? { it.include?('contents/02-dltest.md') }
          assert violations.first.detail.any? { it.include?('contents/02-vivlio.md') }
          refute violations.first.detail.any? { it.include?('03-other') }, '重複していない章は挙げない'
        end
      end

      # 2 つめ以降を、同じ区分（ここでは付録）の空き番号へ振り直すコマンドを添える
      def test_should_suggest_rename_to_a_free_number_in_the_same_section
        with_temp_project do
          write_catalog(chapters: %w[97-sample 97-sample-ocr])
          write_content('97-sample')
          write_content('97-sample-ocr')

          detail = Guards::DuplicateNumberCheck.new.validate.first.detail

          assert_includes detail, '  → vs rename 97-sample-ocr 90-sample-ocr'
          refute detail.any? { it.include?('vs rename 97-sample ') }, '1 つめは振り直さない'
        end
      end

      # Finder で複製した原稿（catalog.yml に無い）は vs rename が扱わないので mv を示す。
      # 使えない字は直し、空白はエスケープして引用符を求めない。残すのは決まりの形の名前
      def test_should_suggest_mv_with_a_repaired_name_for_a_finder_copy
        with_temp_project do
          write_catalog(chapters: %w[97-sample])
          write_content('97-sample')
          write_content('97-sample のコピー')

          detail = Guards::DuplicateNumberCheck.new.validate.first.detail

          assert_includes detail, '- 97: contents/97-sample.md、contents/97-sample のコピー.md'
          assert_includes detail, '  → mv contents/97-sample\ のコピー.md contents/90-sample-2.md'
        end
      end

      # `_` で番号を区切った原稿も、章の解決と同じく番号の重なりとして数える（すり抜けていた）
      def test_should_count_an_underscore_after_the_number
        with_temp_project do
          write_content('97-sample')
          write_content('97_sample-x')

          assert_equal 1, Guards::DuplicateNumberCheck.new.validate.size
        end
      end

      # ------------------------------------------------------------------
      # GC-04d: ChapterFileNameCheck
      #
      # 章のファイル名は vs create の作る形（2 桁の番号と英小文字・数字・ハイフン）に限る。
      # 点を含む名前は章の解決が別の章を指し、全体ビルドを Errno::ENOENT で止めていた。
      # ------------------------------------------------------------------
      def test_should_stop_on_chapter_file_names_outside_the_rule
        with_temp_project do
          write_catalog(chapters: %w[01-vol.53_09_482 02-Intro 03_draft])
          %w[01-vol.53_09_482 02-Intro 03_draft 04-memo\ copy 11-good 15 memo].each { write_content(it) }

          violations = Guards::ChapterFileNameCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          detail = violations.first.detail
          assert_includes detail, '  → vs rename 01-vol.53_09_482 01-vol-53-09-482'
          assert_includes detail, '  → vs rename 02-Intro 02-intro'
          assert_includes detail, '  → mv contents/03_draft.md contents/03-draft.md（config/catalog.yml の 03_draft も 03-draft に書き換える）'
          assert_includes detail, '  → mv contents/04-memo\ copy.md contents/04-memo-copy.md'
          refute detail.any? { it.include?('11-good') || it.include?('contents/15.md') || it.include?('memo.md') },
                 '決まりの形の章と、番号で始まらない原稿は挙げない'
        end
      end

      # 3 桁の番号と、数字だけのスラッグ（章の範囲と読まれる）も決まりの外
      def test_should_reject_three_digit_numbers_and_numeric_slugs
        with_temp_project do
          write_content('999-sample-original')
          write_content('01-245')

          detail = Guards::ChapterFileNameCheck.new.validate.first.detail

          assert_includes detail, '  → mv contents/999-sample-original.md contents/02-sample-original.md'
          assert_includes detail, '  → mv contents/01-245.md contents/01-chapter-245.md'
        end
      end

      # catalog.yml に載っている章も数える。目次の読み込みが番号の重なった片方を外し、
      # 全体ビルドがその章を抜いて組み上がっていた
      def test_should_count_chapters_listed_in_catalog
        with_temp_project do
          write_catalog(chapters: %w[05-alpha 05-beta])
          write_content('05-alpha')

          violations = Guards::DuplicateNumberCheck.new.validate

          assert_equal 1, violations.size
          assert violations.first.detail.any? { it.include?('contents/05-beta.md') }
        end
      end

      # ------------------------------------------------------------------
      # GC-04c: DuplicateSlugCheck
      #
      # 01-sample と 97-sample は番号で指せば組めるが、vs build sample が片方だけを組み、
      # 章のラベル ID（@ch-sample）が重なる。止めて、2 つめ以降の名前を変えるコマンドを添える。
      # ------------------------------------------------------------------
      def test_should_stop_when_two_chapters_share_a_name
        with_temp_project do
          write_catalog(chapters: %w[01-sample 97-sample])
          write_content('01-sample')
          write_content('97-sample')
          write_content('11-other')

          violations = Guards::DuplicateSlugCheck.new.validate

          assert_equal 1, violations.size
          assert_predicate violations.first, :error?
          assert_includes violations.first.detail, '- sample: contents/01-sample.md、contents/97-sample.md'
          assert_includes violations.first.detail, '  → vs rename 97-sample 97-sample-2'
          refute violations.first.detail.any? { it.include?('11-other') }, '重なっていない章は挙げない'
        end
      end

      # 大文字と小文字の違いだけの名前も同じとみなす
      def test_should_treat_names_differing_only_in_case_as_the_same
        with_temp_project do
          write_content('01-Sample')
          write_content('97-sample')

          assert_equal 1, Guards::DuplicateSlugCheck.new.validate.size
        end
      end

      def test_should_pass_when_chapter_names_are_unique
        with_temp_project do
          write_content('01-sample')
          write_content('02-sample-ocr')
          write_content('15')

          assert_empty Guards::DuplicateSlugCheck.new.validate
        end
      end

      def test_should_pass_when_chapter_numbers_are_unique
        with_temp_project do
          write_content('01-intro')
          write_content('02-basic')

          assert_empty Guards::DuplicateNumberCheck.new.validate
        end
      end

      # アンダースコア始まり（システムページ）と、番号を持たないファイルは対象外
      def test_should_ignore_system_pages_and_unnumbered_files
        with_temp_project do
          write_content('_titlepage')
          write_content('_colophon')
          write_content('appendix')
          write_content('memo')

          assert_empty Guards::DuplicateNumberCheck.new.validate
        end
      end

      # 桁数が違えば別の番号として扱う（`02` と `020` は重ならない）
      def test_should_not_confuse_numbers_of_different_width
        with_temp_project do
          write_content('02-first')
          write_content('020-second')

          assert_empty Guards::DuplicateNumberCheck.new.validate
        end
      end

      private

      # config/ contents/ を備えた一時プロジェクトへ chdir して検証する
      def with_temp_project(&)
        Dir.mktmpdir('vs-guards') do |dir|
          Dir.chdir(dir) do
            FileUtils.mkdir_p('config')
            FileUtils.mkdir_p('contents')
            yield
          end
        end
      end

      # 実際の構造（PREFACE / CHAPTERS / APPENDICES / POSTFACE）で catalog.yml を書く
      def write_catalog(chapters:)
        yaml = +"PREFACE:\nCHAPTERS:\n"
        chapters.each { yaml << "  - #{it}\n" }
        yaml << "APPENDICES:\nPOSTFACE:\n"
        File.write('config/catalog.yml', yaml)
      end

      def write_content(basename)
        File.write("contents/#{basename}.md", "# #{basename}\n")
      end

      def write_markdown(basename, body)
        File.write("contents/#{basename}.md", body)
      end

      # StrayPageBreakCheck は h2 の扱いが設定で変わるため、既定は「h2 が自動改ページする」
      # 側（＝二重改ページが正規化される側）に固定してテストする
      def stray_check(section_pagebreak: true)
        Guards::StrayPageBreakCheck.new(section_pagebreak:)
      end
    end
  end
end
