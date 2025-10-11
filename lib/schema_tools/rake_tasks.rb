require 'rake'
require 'rake/tasklib'

module SchemaTools
  module RakeTasks
  def self.load_tasks
    # Load schema.rake
    schema_rake_file = File.join(File.dirname(__FILE__), '..', 'tasks', 'schema.rake')
    load schema_rake_file if File.exist?(schema_rake_file)
    
    # Load test.rake only in development/test environment
    if defined?(Rails) && (Rails.env.development? || Rails.env.test?) || 
       !defined?(Rails) && (ENV['RAILS_ENV'] == 'development' || ENV['RAILS_ENV'] == 'test' || ENV['RAILS_ENV'].nil?)
      test_rake_file = File.join(File.dirname(__FILE__), '..', 'tasks', 'test.rake')
      load test_rake_file if File.exist?(test_rake_file)
    end
  end
  end
end

# Tasks are loaded automatically in Rails apps via Railtie
# For non-Rails usage, call SchemaTools::RakeTasks.load_tasks manually