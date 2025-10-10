require_relative '../schema_files'
require_relative 'migrate_breaking_change'
require_relative '../diff'
require_relative '../settings_diff'
require_relative '../api_aware_mappings_diff'
require 'json'

module SchemaTools
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
end