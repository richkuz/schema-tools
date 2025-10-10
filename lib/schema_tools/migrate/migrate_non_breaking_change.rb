require_relative '../schema_files'
require_relative 'migrate_verify'
require_relative '../diff'
require_relative '../settings_diff'
require_relative '../api_aware_mappings_diff'
require 'json'

module SchemaTools
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

      SchemaTools.verify_migration(alias_name, client)
    rescue => e
      if e.message.include?("no settings to update")
        puts "✓ No settings changes needed - index is already up to date"
        puts "Migration completed successfully!"
      else
        raise e
      end
    end
  end
end