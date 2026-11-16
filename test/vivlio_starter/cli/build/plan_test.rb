# frozen_string_literal: true

# ================================================================
# Test: build/plan_test.rb
# ================================================================
# テスト対象:
#   BuildPlan（lib/vivlio_starter/cli/build/plan.rb）と、段の表の条件
#   （v2-architecture-spec.md §3.2・§8 の S5 の完了の条件 3・5）
#   - 出力先と機能から導く値（入稿用の導出・閲覧用 PDF・回転テーブル・表紙）
#   - 設定から plan を作る
#   - 索引・用語集が無効の本では、index scan and build と backlink dedup が段の一覧に出ない
#   - Type 3 対策が無効の本では、techbook post-process が段の一覧に出ない
#   - 段の表とハンドラが、設定を直接読んで走るかどうかを決めていない
# ================================================================

require 'test_helper'
require 'vivlio_starter/cli/common'
require 'vivlio_starter/cli/build'

module VivlioStarter
  module CLI
    class BuildPlanTest < Minitest::Test
      PIPELINE_SOURCE = File.expand_path('../../../../lib/vivlio_starter/cli/build/pipeline.rb', __dir__)

      def setup
        skip 'config/book.yml が見つかりません（リポジトリルートで実行してください）' unless File.exist?('config/book.yml')
      end

      # --- 導く値 ---

      def test_should_derive_print_pdf_unless_the_book_has_full_bleed_elements
        assert_predicate plan(%w[print_pdf]), :derive_print?
        assert_predicate plan(%w[print_pdf]), :viewing_pdf?, '導出の元になる閲覧用の中間 PDF が要る'
        refute_predicate plan(%w[print_pdf], print_full_bleed: true), :derive_print?
        refute_predicate plan(%w[print_pdf], print_full_bleed: true), :viewing_pdf?
        refute_predicate plan(%w[pdf]), :derive_print?
        assert_predicate plan(%w[pdf]), :viewing_pdf?
      end

      def test_should_extract_rotate_table_images_only_when_kindle_has_a_body_pdf
        assert_predicate plan(%w[pdf kindle]), :rotate_table_images?
        assert_predicate plan(%w[print_pdf kindle]), :rotate_table_images?
        refute_predicate plan(%w[pdf epub]), :rotate_table_images?
        refute_predicate plan(%w[print_pdf kindle], print_full_bleed: true), :rotate_table_images?
      end

      def test_should_need_cover_assets_only_when_a_branch_reads_them
        assert_predicate plan(%w[pdf]), :cover_assets?
        refute_predicate plan(%w[pdf epub], pdf_cover: false, epub_cover: false), :cover_assets?
        assert_predicate plan(%w[pdf epub], pdf_cover: false), :cover_assets?
        assert_predicate plan(%w[print_pdf], pdf_cover: false, epub_cover: false), :cover_assets?, '入稿用は表紙を必ず作る'
      end

      # --- 設定から作る ---

      def test_should_resolve_the_plan_of_this_book_from_the_configuration
        resolved = BuildPlan.resolve

        assert_equal Build::Targets.resolve, resolved.targets
        assert_equal Common.traits, resolved.traits
        assert_equal Common.index_enabled?, resolved.features.index
        assert_equal Common::CONFIG.output.pdf.techbook == true, resolved.features.techbook_post_process
        assert_equal false, resolved.features.web_novel, '本書（techbook）は小説投稿サイトの記法を使わない'
      end

      def test_should_take_the_targets_given_by_the_caller
        targets = targets_from(%w[epub])

        assert_equal targets, BuildPlan.resolve(targets:).targets
      end

      # --- 段の一覧（完了の条件 5） ---

      def test_should_drop_the_index_steps_when_the_index_is_disabled
        targets = targets_from(%w[pdf print_pdf])
        enabled  = Common.stub(:index_enabled?, true)  { step_labels(:full, targets) }
        disabled = Common.stub(:index_enabled?, false) { step_labels(:full, targets) }

        assert_equal ['index scan and build', 'backlink dedup'], enabled - disabled
        assert_empty disabled - enabled
      end

      def test_should_drop_the_index_step_from_single_and_preflight_modes_too
        %i[single preflight].each do |mode|
          enabled  = Common.stub(:index_enabled?, true)  { step_labels(mode, targets_from(%w[pdf])) }
          disabled = Common.stub(:index_enabled?, false) { step_labels(mode, targets_from(%w[pdf])) }

          assert_equal ['index scan and build'], enabled - disabled, "#{mode} モード"
        end
      end

      # --- 段の表は plan だけを読む（完了の条件 3） ---

      def test_step_table_should_not_read_the_configuration_for_its_conditions
        source = File.read(PIPELINE_SOURCE)
        table = source[/def full_mode_step_table\n.*?\n        end\n/m]

        refute_nil table
        # 条件の列（各行の 3 番目）に、設定の述語や Common::CONFIG が現れない。
        # ハンドラ（-> { ... }）の中の Common は、段の処理が使うもので条件ではない
        conditions = table.gsub(/-> \{.*?\}(?=,\s)/m, '').lines.reject { it.lstrip.start_with?('#') }.join

        refute_match(/Common\b|CONFIG|IndexCommands|needed\?/, conditions)
      end

      def test_step_handlers_should_not_return_early_on_a_disabled_feature
        source = File.read(PIPELINE_SOURCE)

        refute_match(/index_enabled\?/, source, '索引の有効・無効は plan.features.index が持つ')
        refute_match(/(unless|if)\s+.*\benabled\?\s*$/, source)
      end

      private

      def plan(list, print_full_bleed: false, pdf_cover: true, epub_cover: true)
        features = BuildFeatures.new(index: true, techbook_post_process: true, web_novel: false,
                                     print_full_bleed:, pdf_cover:, epub_cover:, whole_toc: false)
        BuildPlan.new(targets: targets_from(list), traits: BookTraits.resolve(nil), features:)
      end

      def targets_from(list)
        Build::Targets.new(pdf: list.include?('pdf'), print_pdf: list.include?('print_pdf'),
                           epub: list.include?('epub'), kindle: list.include?('kindle'))
      end

      def step_labels(mode, targets)
        command = Struct.new(:options).new({ clean: true, resize: true, compress: true })
        entries = mode == :single ? [single_entry] : []
        pipeline = BuildCommands::UnifiedBuildPipeline.new(command, entries:, mode:, targets:)
        pipeline.instance_variable_get(:@steps).map(&:label)
      end

      def single_entry
        TokenResolver::Entry.new(number: '11', slug: 'workflow', kind: :chapter, label: 'CHAPTERS',
                                 path: File.join(Common::CONTENTS_DIR, '11-workflow.md'),
                                 exists: true, in_catalog: true, valid: true)
      end
    end
  end
end
