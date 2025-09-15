require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'test/**/*_spec.rb'
  t.rspec_opts = '--require ./test/spec_helper'
end

task :default => :spec