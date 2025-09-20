require 'rake'
require 'rake/tasklib'

module SchemaTools
  module RakeTasks
    def self.load_tasks
      Dir.glob(File.join(File.dirname(__FILE__), '..', 'tasks', '*.rake')).each do |rake_file|
        load rake_file
      end
    end
  end
end

# Auto-load tasks when this file is required
SchemaTools::RakeTasks.load_tasks