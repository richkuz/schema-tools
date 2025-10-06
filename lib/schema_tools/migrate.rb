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
      return
    end
    
    # Check if it's an alias
    unless client.alias_exists?(alias_name)
      puts "Alias '#{alias_name}' not found. Creating new index and alias..."
      
      # Create new index with timestamp
      timestamp = Time.now.strftime("%Y%m%d%H%M%S")
      new_index_name = "#{alias_name}-#{timestamp}"
      
      # Get schema files
      settings = SchemaFiles.get_settings(alias_name)
      mappings = SchemaFiles.get_mappings(alias_name)
      
      if settings.nil? || mappings.nil?
        puts "ERROR: Could not load schema files for #{alias_name}"
        puts "  Make sure settings.json and mappings.json exist in #{schema_path}"
        return
      end
      
      # Create the new index
      puts "Creating new index '#{new_index_name}' with provided schema..."
      client.create_index(new_index_name, settings, mappings)
      puts "✓ Index '#{new_index_name}' created"
      
      # Create the alias
      puts "Creating alias '#{alias_name}' pointing to '#{new_index_name}'..."
      client.create_alias(alias_name, new_index_name)
      puts "✓ Alias '#{alias_name}' created and configured"
      
      puts "Migration completed successfully!"
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
    
    # Get schema files
    settings = SchemaFiles.get_settings(alias_name)
    mappings = SchemaFiles.get_mappings(alias_name)
    
    if settings.nil? || mappings.nil?
      puts "ERROR: Could not load schema files for #{alias_name}"
      puts "  Make sure settings.json and mappings.json exist in #{schema_path}"
      return
    end
    
    # Try to update the existing index
    puts "Attempting to update index '#{index_name}' with new schema..."
    begin
      client.update_index_settings(index_name, settings)
      client.update_index_mappings(index_name, mappings)
      puts "✓ Index '#{index_name}' updated successfully"
      puts "Migration completed successfully!"
    rescue => e
      # Check if it's a "no settings to update" error - this is actually successful
      if e.message.include?("no settings to update")
        puts "✓ No settings changes needed - index is already up to date"
        puts "Migration completed successfully!"
      else
        puts "✗ Failed to update index '#{index_name}': #{e.message}"
        puts "This appears to be a breaking change. Starting breaking change migration..."
        
        # Call breaking change migration
        require_relative 'breaking_change_migration'
        BreakingChangeMigration.migrate(alias_name: alias_name, client: client)
      end
    end
  end

  private

  def self.find_all_schemas
    SchemaFiles.discover_all_schemas
  end
end