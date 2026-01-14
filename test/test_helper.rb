require 'minitest/autorun'
require 'minitest/pride'
begin
  require 'minitest/mock'
rescue LoadError
  # Some environments (notably minimal Ruby installations) may not ship with minitest/mock.
  # Provide a lightweight fallback so that tests using Object#stub continue to work.
  module MinitestStubFallback
    def stub(method_name, val_or_callable = nil)
      singleton = class << self; self; end

      original_defined = true
      original_method = singleton.instance_method(method_name)
    rescue NameError
      original_defined = false
    ensure
      replacement = if val_or_callable.respond_to?(:call)
                      val_or_callable
                    else
                      ->(*, &) { val_or_callable }
                    end

      singleton.define_method(method_name) do |*args, **kwargs, &block|
        replacement.call(*args, **kwargs, &block)
      end

      begin
        return yield
      ensure
        if original_defined
          singleton.define_method(method_name, original_method)
        else
          singleton.remove_method(method_name)
        end
      end
    end
  end

  Object.include(MinitestStubFallback) unless Object.method_defined?(:stub)
end

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
