require_relative 'schema_files'

module SchemaTools
  def self.migrate_all(client:)
    puts "Discovering all schemas and migrating each to their latest revisions..."
    
    schemas = find_all_schemas
    
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
        puts "Continuing with next schema..."
      end
      puts
    end
  end

  def self.migrate_one_schema(alias_name:, client:)
    puts "=" * 60
    puts "Migrating alias #{alias_name}"
    puts "=" * 60
    
    # Check if the folder exists
    schema_path = File.join(Config.schemas_path, alias_name)
    unless Dir.exist?(schema_path)
      puts "Schema folder not found: #{schema_path}"
      return
    end
    
    # Check if it's an index name (not an alias)
    if !client.alias_exists?(alias_name) && client.index_exists?(alias_name)
      puts "To prevent downtime, this tool only migrates aliased indexes."
      puts "Create a new alias with a new name and point it at your index:"
      puts "```"
      puts "POST /_aliases"
      puts "{"
      puts "  \"actions\": ["
      puts "    {"
      puts "      \"add\": {"
      puts "        \"index\": \"#{alias_name}\","
      puts "        \"alias\": \"new_alias_name\""
      puts "      }"
      puts "    }"
      puts "  ]"
      puts "}"
      puts "```"
      puts "Change your application to read and write to `new_alias_name` instead of `#{alias_name}`."
      return
    end
    
    # Check if it's an alias
    unless client.alias_exists?(alias_name)
      puts "Alias '#{alias_name}' not found."
      return
    end
    
    # Check if alias points to multiple indices
    indices = client.get_alias_indices(alias_name)
    if indices.length > 1
      puts "This tool can only migrate aliases that point at one index."
      puts "Alias '#{alias_name}' points to: #{indices.join(', ')}"
      return
    end
    
    if indices.length == 0
      puts "Alias '#{alias_name}' points to no indices."
      return
    end
    
    index_name = indices.first
    puts "Alias '#{alias_name}' points to index '#{index_name}'"
    puts "Migration implementation will be added later."
  end

  private

  def self.find_all_schemas
    SchemaFiles.discover_all_schemas
  end
end