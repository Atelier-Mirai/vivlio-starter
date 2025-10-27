# frozen_string_literal: true

require_relative 'lib/vivlio/starter/version'

Gem::Specification.new do |spec|
  spec.name          = 'vivlio-starter'
  spec.version       = Vivlio::Starter::VERSION
  spec.authors       = ['Atelier Mirai']
  spec.email         = ['contact@atelier-mirai.net']

  spec.summary       = 'Vivlio Starter: Build pipeline and CLI for Vivliostyle-based books'
  spec.description   = 'Provides Rake tasks and a CLI to preprocess, convert, and build books using Vivliostyle.'
  spec.homepage      = 'https://github.com/Atelier-Mirai/vivlio-starter'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.0'

  # Files (robust to uncommitted deletions): prefer git, filter to paths that exist
  files = nil
  if File.directory?('.git') && system('git --version > /dev/null 2>&1')
    begin
      files = `git ls-files -z`.split("\x0")
    rescue StandardError
      files = nil
    end
  end

  if files.nil? || files.empty?
    files = Dir.glob('{bin,lib,config,rakelib}/**/*', File::FNM_DOTMATCH)
    files += %w[README.md LICENSE Rakefile Gemfile]
  end

  # Keep only real files, exclude directories and missing paths
  spec.files = files.select { |f| File.file?(f) }
  spec.bindir        = 'bin'
  spec.executables   = %w[vivlio-starter vs]
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'hexapdf', '~> 1.0'
  spec.add_dependency 'kramdown', '~> 2.4'
  spec.add_dependency 'mini_magick', '~> 4.12'
  spec.add_dependency 'nokogiri', '~> 1.16'
  spec.add_dependency 'thor', '~> 1.2'

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.5'
  spec.add_development_dependency 'rake', '~> 13.2'
  spec.add_development_dependency 'rubocop', '~> 1.65'
  spec.add_development_dependency 'minitest', '~> 5.22'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
