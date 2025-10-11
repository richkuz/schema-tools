require 'rake'
require 'rake/tasklib'

module SchemaTools
  module RakeTasks
  def self.load_tasks
    # Only load schema.rake, not test.rake which requires development dependencies
    schema_rake_file = File.join(File.dirname(__FILE__), '..', 'tasks', 'schema.rake')
    load schema_rake_file if File.exist?(schema_rake_file)
  end
  end
end

# Auto-load tasks when this file is required
SchemaTools::RakeTasks.load_tasks