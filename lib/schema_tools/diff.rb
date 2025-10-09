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

      local_settings = SchemaFiles.get_settings(alias_name)
      local_mappings = SchemaFiles.get_mappings(alias_name)

      if local_settings.nil? || local_mappings.nil?
        puts "❌ Local schema files not found for #{alias_name}"
        return
      end

      remote_settings = @client.get_index_settings(index_name)
      remote_mappings = @client.get_index_mappings(index_name)

      if remote_settings.nil? || remote_mappings.nil?
        puts "❌ Failed to retrieve remote settings or mappings for #{index_name}"
        return
      end

      # Show what's being compared
      puts "Old (Remote API):"
      puts "   GET /#{index_name}/_settings"
      puts "   GET /#{index_name}/_mappings"
      puts
      puts "New (Local Files):"
      puts "   #{alias_name}/settings.json"
      puts "   #{alias_name}/mappings.json"
      puts

      # Filter remote settings to match local format
      old_settings = SettingsFilter.filter_internal_settings(remote_settings)

      # Normalize local settings to ensure consistent comparison
      new_settings = normalize_local_settings(local_settings)

      puts "Settings Comparison:"
      settings_diff = @json_diff.generate_diff(old_settings, new_settings)
      puts settings_diff
      puts

      puts "Mappings Comparison:"
      mappings_diff = @json_diff.generate_diff(remote_mappings, local_mappings)
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
        unless @client.alias_exists?(alias_name)
          result[:status] = :alias_not_found
          result[:error] = "Alias '#{alias_name}' not found in cluster"
          return result
        end

        alias_indices = @client.get_alias_indices(alias_name)
        
        if alias_indices.length > 1
          result[:status] = :multiple_indices
          result[:error] = "Alias '#{alias_name}' points to multiple indices: #{alias_indices.join(', ')}. This configuration is not supported for diffing."
          return result
        end

        index_name = alias_indices.first

        local_settings = SchemaFiles.get_settings(alias_name)
        local_mappings = SchemaFiles.get_mappings(alias_name)

        if local_settings.nil? || local_mappings.nil?
          result[:status] = :local_files_not_found
          result[:error] = "Local schema files not found for #{alias_name}"
          return result
        end

        remote_settings = @client.get_index_settings(index_name)
        remote_mappings = @client.get_index_mappings(index_name)

        if remote_settings.nil? || remote_mappings.nil?
          result[:status] = :remote_fetch_failed
          result[:error] = "Failed to retrieve remote settings or mappings for #{index_name}"
          return result
        end

        # Filter remote settings to match local format
        filtered_remote_settings = SettingsFilter.filter_internal_settings(remote_settings)

        # Normalize local settings to ensure consistent comparison
        normalized_local_settings = normalize_local_settings(local_settings)

        result[:settings_diff] = @json_diff.generate_diff(filtered_remote_settings, normalized_local_settings)
        result[:mappings_diff] = @json_diff.generate_diff(remote_mappings, local_mappings)
        
        result[:comparison_context] = {
          new_files: {
            settings: "#{alias_name}/settings.json",
            mappings: "#{alias_name}/mappings.json"
          },
          old_api: {
            settings: "GET /#{index_name}/_settings",
            mappings: "GET /#{index_name}/_mappings"
          }
        }
        
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

    private

    def normalize_local_settings(local_settings)
      return local_settings unless local_settings.is_a?(Hash)
      
      # If local settings already have "index" wrapper, use it
      if local_settings.key?("index")
        return local_settings if local_settings["index"].is_a?(Hash)
        # If index exists but is not a hash, return as-is (invalid format)
        return local_settings
      end
      
      # If local settings don't have "index" wrapper, wrap them in "index"
      # This handles cases like { "number_of_shards": 1 } which should be compared as { "index": { "number_of_shards": 1 } }
      { "index" => local_settings }
    end
  end
end