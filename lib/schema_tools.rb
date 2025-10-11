require 'schema_tools/rake_tasks'

# Load Railtie for automatic rake task loading in Rails apps
if defined?(Rails)
  require 'schema_tools/railtie'
else
  # For non-Rails usage, load tasks immediately
  SchemaTools::RakeTasks.load_tasks
end