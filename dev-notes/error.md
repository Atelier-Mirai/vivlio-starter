bundle exec ruby -W2 bin/vs clean --purge
RUBYOPT='-W0' bundle exec ruby -Itest test/vivlio/starter/version_test.rb
VS_DEBUG=1 VS_NO_REEXEC=1 ruby -W2 bin/vs build --no-clean