require 'rake'
require 'rake/tasklib'

module SchemaTools
  module RakeTasks
  def self.load_tasks
    # Load schema.rake
    schema_rake_file = File.join(File.dirname(__FILE__), '..', 'tasks', 'schema.rake')
    load schema_rake_file if File.exist?(schema_rake_file)
    
    # Load test.rake only when we're in the gem's own development environment
    # Check if we're in the gem's source directory (not a consuming app)
    gem_root = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
    if File.exist?(File.join(gem_root, 'test')) && File.exist?(File.join(gem_root, 'test', 'spec_helper.rb'))
      test_rake_file = File.join(File.dirname(__FILE__), '..', 'tasks', 'test.rake')
      load test_rake_file if File.exist?(test_rake_file)
    end
  end
  end
end

# Tasks are loaded automatically in Rails apps via Railtie
# For non-Rails usage, call SchemaTools::RakeTasks.load_tasks manually