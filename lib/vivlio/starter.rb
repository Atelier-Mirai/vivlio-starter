# frozen_string_literal: true

require 'rake'

module Vivlio
  module Starter
    module CLI
      module_function

      def load_tasks
        # Prefer the project's Rakefile if present; otherwise, load gem-bundled tasks.
        app = Rake.application
        app.init
        if app.have_rakefile
          app.load_rakefile
        else
          # Load tasks packaged within this gem
          gem_root = File.expand_path('../../..', __FILE__)
          rakelib_dir = File.join(gem_root, 'rakelib')
          # Load helper Ruby files first, then .rake task files
          Dir[File.join(rakelib_dir, '*.rb')].sort.each { |f| load f }
          Dir[File.join(rakelib_dir, '*.rake')].sort.each { |f| load f }
        end
      end

      def start(argv)
        load_tasks

        # Extract global flags
        verbose = false
        argv = argv.reject do |a|
          case a
          when '-v', '--verbose'
            verbose = true
            true
          else
            false
          end
        end
        ENV['VERBOSE'] = '1' if verbose

        # Default to help if no command
        cmd = argv.shift
        if cmd.nil? || %w[help -h --help].include?(cmd)
          if Rake::Task.task_defined?('help')
            Rake::Task['help'].invoke
          else
            Rake::Task.tasks.each { |t| puts sprintf('%-24s %s', t.name, t.comment).rstrip }
          end
          return 0
        end

        # Allow shorthand alias mapping if needed in the future
        task_name = cmd

        # Forward remaining args as Rake task arguments if defined like task[:arg]
        if task_with_args?(task_name)
          Rake::Task[task_name].invoke(*argv)
        else
          Rake::Task[task_name].invoke
        end
        0
      rescue SystemExit => e
        e.status
      rescue Exception => e
        warn "❌ #{e.class}: #{e.message}"
        warn e.backtrace.join("\n") if ENV['VS_DEBUG']
        1
      ensure
        # Re-enable tasks for subsequent runs within same process
        Rake::Task.tasks.each(&:reenable)
      end

      def task_with_args?(name)
        Rake::Task[name].arg_names&.any?
      rescue
        false
      end
    end
  end
end
