require_relative '../schema_files'
require_relative 'migrate_breaking_change'
require_relative 'migrate_non_breaking_change'
require_relative 'migrate_new'
require_relative '../diff'
require_relative '../settings_diff'
require_relative '../api_aware_mappings_diff'
require 'json'

module SchemaTools
  def self.migrate_all(client:)
    puts "Discovering all schemas and migrating each to their latest revisions..."
    
    schemas = SchemaFiles.discover_all_schemas
    
    if schemas.empty?
      puts "No schemas found in #{Config.schemas_path}"
      return
    end
    
    puts "Found #{schemas.length} schema(s) to migrate:"
    schemas.each do |schema|
      puts "  - #{schema}"
    end
    puts
    
    schemas.each do |alias_name|
      begin
        migrate_one_schema(alias_name: alias_name, client: client)
      rescue => e
        puts "✗ Migration failed for #{alias_name}: #{e.message}"
        raise e
      end
      puts
    end
  end

  def self.migrate_one_schema(alias_name:, client:)
    puts "=" * 60
    puts "Migrating alias #{alias_name}"
    puts "=" * 60
    
    schema_path = File.join(Config.schemas_path, alias_name)
    unless Dir.exist?(schema_path)
      raise "Schema folder not found: #{schema_path}"
    end
    
    # Check if it's an index name (not an alias)
    if !client.alias_exists?(alias_name) && client.index_exists?(alias_name)
      puts "ERROR: Migration not run for index \"#{alias_name}\""
      puts "  To prevent downtime, this tool only migrates aliased indexes."
      puts ""
      puts "  Create a new alias for your index by running:"
      puts "  rake schema:alias"
      puts ""
      puts "  Then rename the schema folder to the alias name and re-run:"
      puts "  rake schema:migrate"
      puts ""
      puts "  Then change your application to read and write to the alias name instead of the index name `#{alias_name}`."
      raise "Migration not run for alias #{alias_name} because #{alias_name} is an index, not an alias"
    end
    
    unless client.alias_exists?(alias_name)
      puts "Alias '#{alias_name}' not found. Creating new index and alias..."
      migrate_to_new_alias(alias_name, client)
      return
    end
    
    indices = client.get_alias_indices(alias_name)
    if indices.length > 1
      puts "This tool can only migrate aliases that point at one index."
      raise "Alias '#{alias_name}' points to multiple indices: #{indices.join(', ')}"
    end
    
    if indices.length == 0
      raise "Alias '#{alias_name}' points to no indices."
    end
    
    index_name = indices.first
    puts "Alias '#{alias_name}' points to index '#{index_name}'"
    begin
      attempt_non_breaking_migration(alias_name:, index_name:, client:)
    rescue => e
      puts "✗ Failed to update index '#{index_name}': #{e.message}"
      puts "This appears to be a breaking change. Starting breaking change migration..."
      
      MigrateBreakingChange.migrate(alias_name:, client:)
    end
  end
end