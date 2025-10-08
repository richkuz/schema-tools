require 'json'
require_relative 'json_diff'
require_relative 'schema_files'
require_relative 'client'
require_relative 'settings_filter'

module SchemaTools
  def self.diff_all_schemas(client:)
    diff = Diff.new(client: client)
    diff.diff_all_schemas
  end

  def self.diff_schema(alias_name, client:)
    diff = Diff.new(client: client)
    diff.generate_schema_diff(alias_name)
  end

  class Diff
    def initialize(client:)
      @client = client
      @json_diff = JsonDiff.new
    end

    # Compare all schemas to their corresponding downloaded alias settings and mappings
    def diff_all_schemas
      schemas = SchemaFiles.discover_all_schemas
      
      if schemas.empty?
        puts "No schemas found in #{Config.schemas_path}"
        return
      end

      puts "Found #{schemas.length} schema(s) to compare:"
      schemas.each do |schema|
        puts "  - #{schema}"
      end
      puts

      schemas.each do |alias_name|
        begin
          diff_schema(alias_name)
        rescue => e
          puts "✗ Diff failed for #{alias_name}: #{e.message}"
        end
        puts
      end
    end

    # Compare a single schema to its corresponding downloaded alias settings and mappings
    def diff_schema(alias_name)
      puts "=" * 60
      puts "Comparing schema: #{alias_name}"
      puts "=" * 60

      # Check if alias exists
      unless @client.alias_exists?(alias_name)
        puts "❌ Alias '#{alias_name}' not found in cluster"
        return
      end

      # Get alias indices
      alias_indices = @client.get_alias_indices(alias_name)
      
      if alias_indices.length > 1
        puts "⚠️  Alias '#{alias_name}' points to multiple indices: #{alias_indices.join(', ')}"
        puts "   This configuration is not supported for diffing."
        return
      end

      index_name = alias_indices.first

      # Get local schema files
      local_settings = SchemaFiles.get_settings(alias_name)
      local_mappings = SchemaFiles.get_mappings(alias_name)

      if local_settings.nil? || local_mappings.nil?
        puts "❌ Local schema files not found for #{alias_name}"
        return
      end

      # Get remote settings and mappings
      remote_settings = @client.get_index_settings(index_name)
      remote_mappings = @client.get_index_mappings(index_name)

      if remote_settings.nil? || remote_mappings.nil?
        puts "❌ Failed to retrieve remote settings or mappings for #{index_name}"
        return
      end

      # Filter remote settings to match local format
      filtered_remote_settings = SettingsFilter.filter_internal_settings(remote_settings)

      # Compare settings
      puts "📊 Settings Comparison:"
      settings_diff = @json_diff.generate_diff(local_settings, filtered_remote_settings)
      puts settings_diff
      puts

      # Compare mappings
      puts "🗺️  Mappings Comparison:"
      mappings_diff = @json_diff.generate_diff(local_mappings, remote_mappings)
      puts mappings_diff
    end

    # Generate a nicely formatted diff representation for a single schema
    # This method can be called independently for individual schema diffing
    def generate_schema_diff(alias_name)
      result = {
        alias_name: alias_name,
        status: nil,
        settings_diff: nil,
        mappings_diff: nil,
        error: nil
      }

      begin
        # Check if alias exists
        unless @client.alias_exists?(alias_name)
          result[:status] = :alias_not_found
          result[:error] = "Alias '#{alias_name}' not found in cluster"
          return result
        end

        # Get alias indices
        alias_indices = @client.get_alias_indices(alias_name)
        
        if alias_indices.length > 1
          result[:status] = :multiple_indices
          result[:error] = "Alias '#{alias_name}' points to multiple indices: #{alias_indices.join(', ')}. This configuration is not supported for diffing."
          return result
        end

        index_name = alias_indices.first

        # Get local schema files
        local_settings = SchemaFiles.get_settings(alias_name)
        local_mappings = SchemaFiles.get_mappings(alias_name)

        if local_settings.nil? || local_mappings.nil?
          result[:status] = :local_files_not_found
          result[:error] = "Local schema files not found for #{alias_name}"
          return result
        end

        # Get remote settings and mappings
        remote_settings = @client.get_index_settings(index_name)
        remote_mappings = @client.get_index_mappings(index_name)

        if remote_settings.nil? || remote_mappings.nil?
          result[:status] = :remote_fetch_failed
          result[:error] = "Failed to retrieve remote settings or mappings for #{index_name}"
          return result
        end

        # Filter remote settings to match local format
        filtered_remote_settings = SettingsFilter.filter_internal_settings(remote_settings)

        # Generate diffs
        result[:settings_diff] = @json_diff.generate_diff(local_settings, filtered_remote_settings)
        result[:mappings_diff] = @json_diff.generate_diff(local_mappings, remote_mappings)
        
        # Determine overall status
        if result[:settings_diff] == "No changes detected" && result[:mappings_diff] == "No changes detected"
          result[:status] = :no_changes
        else
          result[:status] = :changes_detected
        end

      rescue => e
        result[:status] = :error
        result[:error] = e.message
      end

      result
    end
  end
end