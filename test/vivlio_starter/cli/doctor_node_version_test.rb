# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'

module VivlioStarter
  module CLI
    # vs doctor は Node.js が「在る」だけでなく、ビルドで使われる Vivliostyle CLI が
    # 求める版かを見る（改善案.md #52）。古い Node は ✅ のまま vivliostyle が動かないため。
    #
    # 下限は固定値ではなく、Vivliostyle の package.json（engines.node）から読む。
    # 著者の Vivliostyle は `npm install -g` で最新が入り、Vivlio Starter のリリースとは
    # 別に新しくなるので、固定値では追随できない。
    class DoctorNodeVersionTest < Minitest::Test
      REPO_VIVLIOSTYLE_PACKAGE = File.expand_path('../../../node_modules/@vivliostyle/cli/package.json', __dir__)

      # 予備の下限は、リポジトリの Vivliostyle CLI の engines.node と一致していること
      def test_fallback_min_version_should_match_repository_vivliostyle
        skip 'node_modules に @vivliostyle/cli がありません（npm install 前）' unless File.exist?(REPO_VIVLIOSTYLE_PACKAGE)

        engines = JSON.parse(File.read(REPO_VIVLIOSTYLE_PACKAGE)).dig('engines', 'node')

        assert_equal ">=#{DoctorCommands::NODE_MIN_VERSION}", engines
      end

      # プロジェクトの node_modules にある Vivliostyle の要求を読む（npx が使うのはこちら）
      def test_should_read_requirement_from_project_vivliostyle
        in_project(version: '12.0.0', engines: '>=24.0.0') do
          requirement = DoctorCommands.node_requirement

          assert_equal Gem::Version.new('24.0.0'), requirement.min_version
          assert_equal 'Vivliostyle CLI 12.0.0', requirement.requester
        end
      end

      # engines が想定外の書式なら、予備の下限に戻る（誤った下限で言い立てない）
      def test_should_fall_back_when_engines_is_not_a_simple_minimum
        in_project(version: '12.0.0', engines: '^20.11 || >=22') do
          requirement = DoctorCommands.node_requirement

          assert_equal Gem::Version.new(DoctorCommands::NODE_MIN_VERSION), requirement.min_version
          assert_equal 'Vivliostyle', requirement.requester
        end
      end

      # プロジェクトに無ければ、PATH 上の vivliostyle の実体から package.json をたどる
      # （グローバル導入の形: bin/vivliostyle → lib/node_modules/@vivliostyle/cli/dist/cli.js）
      def test_should_follow_global_vivliostyle_on_path
        Dir.mktmpdir('vs-node-global') do |root|
          package_dir = File.join(root, 'lib', 'node_modules', '@vivliostyle', 'cli')
          write_package(package_dir, version: '12.1.0', engines: '>=24.1.0')
          cli = File.join(package_dir, 'dist', 'cli.js')
          FileUtils.mkdir_p(File.dirname(cli))
          File.write(cli, "#!/usr/bin/env node\n")
          FileUtils.chmod(0o755, cli)
          bin_dir = File.join(root, 'bin')
          FileUtils.mkdir_p(bin_dir)
          File.symlink(cli, File.join(bin_dir, 'vivliostyle'))

          Dir.mktmpdir('vs-node-project') do |project|
            Dir.chdir(project) do
              with_path(bin_dir) do
                requirement = DoctorCommands.node_requirement

                assert_equal Gem::Version.new('24.1.0'), requirement.min_version
                assert_equal 'Vivliostyle CLI 12.1.0', requirement.requester
              end
            end
          end
        end
      end

      def test_should_judge_versions_below_the_minimum_as_too_old
        requirement = requirement_of('24.0.0')

        assert DoctorCommands.node_too_old?(Gem::Version.new('22.12.0'), requirement)
        refute DoctorCommands.node_too_old?(Gem::Version.new('24.0.0'), requirement)
        refute DoctorCommands.node_too_old?(Gem::Version.new('26.9.0'), requirement)
      end

      # 版が分からない（node が無い・出力を読めない）ときは言い立てない
      def test_should_not_judge_an_unknown_version_as_too_old
        refute DoctorCommands.node_too_old?(nil, requirement_of('24.0.0'))
      end

      # 案内には、誰の要求か・そのまま打てる更新コマンド・Homebrew 以外で入れた人への道筋を添える
      def test_should_tell_who_requires_it_and_how_to_update
        warned = nil
        Common.stub :log_warn, ->(msg, detail: nil) { warned = [msg, detail] } do
          DoctorCommands.report_node_outdated(Gem::Version.new('22.12.0'), requirement_of('24.0.0'))
        end

        assert_includes warned[0], '22.12.0'
        assert_includes warned[0], 'Vivliostyle CLI 12.0.0'
        assert_includes warned[0], '24.0.0'
        assert_includes warned[1], 'brew upgrade node'
        assert_includes warned[1], 'nvm'
      end

      private

      def requirement_of(minimum)
        DoctorCommands::NodeRequirement.new(min_version: Gem::Version.new(minimum),
                                            requester: 'Vivliostyle CLI 12.0.0')
      end

      # node_modules/@vivliostyle/cli/package.json を持つプロジェクトの中で実行する
      def in_project(version:, engines:, &)
        Dir.mktmpdir('vs-node-project') do |project|
          write_package(File.join(project, 'node_modules', '@vivliostyle', 'cli'), version:, engines:)
          Dir.chdir(project, &)
        end
      end

      def write_package(dir, version:, engines:)
        FileUtils.mkdir_p(dir)
        package = { 'name' => '@vivliostyle/cli', 'version' => version, 'engines' => { 'node' => engines } }
        File.write(File.join(dir, 'package.json'), JSON.generate(package))
      end

      # PATH を dir だけにして実行する（手元のグローバル vivliostyle を拾わないため）
      def with_path(dir)
        original = ENV.fetch('PATH', nil)
        ENV['PATH'] = dir
        yield
      ensure
        ENV['PATH'] = original
      end
    end
  end
end
