# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.warning = false
end

task default: :test

# gem のアンインストール → ビルド → インストールを一括実行
task :reinstall do
  gemspec = Dir['*.gemspec'].first
  raise 'gemspec が見つかりません' unless gemspec

  require_relative 'lib/vivlio_starter/version'
  version = VivlioStarter::VERSION
  gem_name = 'vivlio-starter'

  sh "gem uninstall #{gem_name} --version #{version} --executables --ignore-dependencies 2>/dev/null || true"
  sh "gem build #{gemspec}"

  # RubyGems がバージョンを変換する可能性があるため、実際にビルドされたファイルを検出
  gem_file = Dir["#{gem_name}-*.gem"].max_by { |f| File.mtime(f) }
  raise "ビルドされた gem ファイルが見つかりません" unless gem_file

  sh "gem install #{gem_file}"
end
