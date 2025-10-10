require_relative '../schema_files'
require_relative 'migrate_breaking_change'
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

  private

  def self.migrate_to_new_alias(alias_name, client)
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    new_index_name = "#{alias_name}-#{timestamp}"
    
    settings = SchemaFiles.get_settings(alias_name)
    mappings = SchemaFiles.get_mappings(alias_name)
    
    if settings.nil? || mappings.nil?
      schema_path = File.join(Config.schemas_path, alias_name)
      puts "ERROR: Could not load schema files for #{alias_name}"
      puts "  Make sure settings.json and mappings.json exist in #{schema_path}"
      raise "Could not load schema files for #{alias_name}"
    end
    
    puts "Creating new index '#{new_index_name}' with provided schema..."
    client.create_index(new_index_name, settings, mappings)
    puts "✓ Index '#{new_index_name}' created"
    
    puts "Creating alias '#{alias_name}' pointing to '#{new_index_name}'..."
    client.create_alias(alias_name, new_index_name)
    puts "✓ Alias '#{alias_name}' created and configured"
    
    puts "Migration completed successfully!"
  end

  def self.attempt_non_breaking_migration(alias_name:, index_name:, client:)
    settings = SchemaFiles.get_settings(alias_name)
    mappings = SchemaFiles.get_mappings(alias_name)
    
    if settings.nil? || mappings.nil?
      schema_path = File.join(Config.schemas_path, alias_name)
      puts "ERROR: Could not load schema files for #{alias_name}"
      puts "  Make sure settings.json and mappings.json exist in #{schema_path}"
      raise "Could not load schema files for #{alias_name}"
    end
    
    puts "Checking for differences between local schema and live alias..."
    diff_result = Diff.generate_schema_diff(alias_name, client)
    
    if diff_result[:status] == :no_changes
      puts "✓ No differences detected between local schema and live alias"
      puts "✓ Migration skipped - index is already up to date"
      return
    end
    
    puts "Showing diff between local schema and live alias before migration:"
    puts "-" * 60
    Diff.print_schema_diff(diff_result)
    puts "-" * 60
    
    puts "Attempting to update index '#{index_name}' in place with new schema as a non-breaking change..."
    begin
      remote_settings = client.get_index_settings(index_name)
      filtered_remote_settings = SettingsFilter.filter_internal_settings(remote_settings)
      
      settings_diff = SettingsDiff.new(settings, filtered_remote_settings)
      minimal_settings_changes = settings_diff.generate_minimal_changes
      
      if minimal_settings_changes.empty?
        puts "✓ No settings changes needed - settings are already up to date"
      else
        puts "Applying minimal settings changes"
        client.update_index_settings(index_name, minimal_settings_changes)
        puts "✓ Settings updated successfully"
      end
      
      remote_mappings = client.get_index_mappings(index_name)
      mappings_diff = ApiAwareMappingsDiff.new(mappings, remote_mappings)
      minimal_mappings_changes = mappings_diff.generate_minimal_changes
      
      if minimal_mappings_changes.empty?
        puts "✓ No mappings changes needed - mappings are already up to date"
      else
        puts "Applying minimal mappings changes"
        client.update_index_mappings(index_name, minimal_mappings_changes)
        puts "✓ Mappings updated successfully"
      end
      
      puts "✓ Index '#{index_name}' updated successfully"

      verify_migration(alias_name, client)
    rescue => e
      if e.message.include?("no settings to update")
        puts "✓ No settings changes needed - index is already up to date"
        puts "Migration completed successfully!"
      else
        raise e
      end
    end
  end

  def self.verify_migration(alias_name, client)
    puts "Verifying migration by comparing local schema with remote index..."
    diff_result = Diff.generate_schema_diff(alias_name, client)
    
    if diff_result[:status] == :no_changes
      puts "✓ Migration verification successful - no differences detected"
      puts "Migration completed successfully!"
    else
      puts "⚠️  Migration verification failed - differences detected:"
      puts "-" * 60
      Diff.print_schema_diff(diff_result)
      puts "-" * 60
      raise "Migration verification failed - local schema does not match remote index after migration"
    end
  end
end