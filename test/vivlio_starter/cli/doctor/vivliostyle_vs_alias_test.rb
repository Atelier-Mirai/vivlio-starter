# frozen_string_literal: true

# =============================================================================
# test/vivlio_starter/cli/doctor/vivliostyle_vs_alias_test.rb
#
# Vivliostyle CLI が `vivliostyle` の別名として入れる `vs` を、doctor が見つけて外すこと。
#
# Vivlio Starter の vs と同じ名前なので、zsh が覚えた場所しだいで Vivliostyle が動き、
# `vs build` が「No input is set」で落ちた（改善案.md #87）。本物の PATH には触らず、
# 一時フォルダに偽の Vivliostyle CLI と偽の Vivlio Starter の vs を作って確かめる。
# =============================================================================

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require 'vivlio_starter/cli'
require 'vivlio_starter/cli/doctor'

module VivlioStarter
  module CLI
    class VivliostyleVsAliasTest < Minitest::Test
      def test_should_remove_only_the_vivliostyle_alias_on_fix
        with_fake_path do |npm_bin, starter_bin|
          logged = []
          Common.stub(:log_always, ->(msg) { logged << msg }) do
            DoctorCommands.send(:handle_vivliostyle_vs_aliases, { fix: true })
          end

          refute File.exist?(File.join(npm_bin, 'vs')), 'Vivliostyle の別名 vs は外す'
          assert File.symlink?(File.join(npm_bin, 'vivliostyle')), 'vivliostyle そのものは残す'
          assert File.exist?(File.join(starter_bin, 'vs')), 'Vivlio Starter の vs には触らない'
          assert logged.any? { it.include?('別名 vs を外しました') }, '外したことを知らせる'
          assert logged.any? { it.include?('vivliostyle で使えます') }, '代わりの打ち方を添える'
        end
      end

      def test_should_only_warn_without_fix
        with_fake_path do |npm_bin, _starter_bin|
          warnings = []
          Common.stub(:log_warn, ->(msg, detail: nil) { warnings << [msg, detail] }) do
            DoctorCommands.send(:handle_vivliostyle_vs_aliases, { fix: false })
          end

          assert File.symlink?(File.join(npm_bin, 'vs')), '--fix でなければ外さない'
          message, detail = warnings.last
          assert_includes message, 'ぶつかります'
          assert_includes detail, 'vs doctor --fix'
        end
      end

      def test_should_find_nothing_when_vs_is_not_vivliostyle
        with_fake_path(vivliostyle_alias: false) do
          assert_empty DoctorCommands.send(:vivliostyle_vs_aliases)
        end
      end

      private

      # PATH を「Vivlio Starter の bin → npm の bin」の順にした一時環境を作る。
      # npm の bin には Vivliostyle CLI の vivliostyle と（指定があれば）別名の vs を、
      # 本物の npm と同じく node_modules/@vivliostyle/cli/dist/cli.js へのリンクとして置く。
      def with_fake_path(vivliostyle_alias: true)
        Dir.mktmpdir do |root|
          cli = File.join(root, 'lib', 'node_modules', '@vivliostyle', 'cli', 'dist', 'cli.js')
          FileUtils.mkdir_p(File.dirname(cli))
          File.write(cli, "#!/usr/bin/env node\n")
          npm_bin = File.join(root, 'bin')
          FileUtils.mkdir_p(npm_bin)
          File.symlink('../lib/node_modules/@vivliostyle/cli/dist/cli.js', File.join(npm_bin, 'vivliostyle'))
          File.symlink('../lib/node_modules/@vivliostyle/cli/dist/cli.js', File.join(npm_bin, 'vs')) if vivliostyle_alias

          starter_bin = File.join(root, 'shims')
          FileUtils.mkdir_p(starter_bin)
          File.write(File.join(starter_bin, 'vs'), "#!/bin/sh\n")

          original = ENV.fetch('PATH', nil)
          ENV['PATH'] = [starter_bin, npm_bin].join(File::PATH_SEPARATOR)
          yield npm_bin, starter_bin
        ensure
          ENV['PATH'] = original
        end
      end
    end
  end
end
