bundle exec ruby -W2 bin/vs clean --purge
RUBYOPT='-W0' bundle exec ruby -Itest test/vivlio/starter/version_test.rb