require 'schema_tools/rake_tasks'

if defined?(Rails)
  module SchemaTools
    class Railtie < Rails::Railtie
      rake_tasks do
        # This will automatically load the rake tasks when Rails starts
        SchemaTools::RakeTasks.load_tasks
      end
    end
  end
end