require 'json'
require_relative 'json_diff'
require_relative 'schema_files'
require_relative 'client'
require_relative 'settings_filter'

module SchemaTools
  def self.diff_all_schemas(client:)
    Diff.diff_all_schemas(client)
  end

  def self.diff_schema(alias_name, client:)
    print_schema_diff(Diff.generate_schema_diff(alias_name, client))
    nil  # Console output method, returns nil
  end

  class Diff
    # Compare all schemas to their corresponding downloaded alias settings and mappings
    def self.diff_all_schemas(client)
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
          print_schema_diff(generate_schema_diff(alias_name, client))
        rescue => e
          puts "✗ Diff failed for #{alias_name}: #{e.message}"
        end
        puts
      end
    end

    # Generate a nicely formatted diff representation for a single schema
    # Compare a single schema to its corresponding downloaded alias settings and mappings
    def self.generate_schema_diff(alias_name, client)
      result = {
        alias_name: alias_name,
        status: nil,
        settings_diff: nil,
        mappings_diff: nil,
        error: nil
      }
      json_diff = JsonDiff.new

      begin
        unless client.alias_exists?(alias_name)
          result[:status] = :alias_not_found
          result[:error] = "Alias '#{alias_name}' not found in cluster"
          return result
        end

        alias_indices = client.get_alias_indices(alias_name)
        
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

        remote_settings = client.get_index_settings(index_name)
        remote_mappings = client.get_index_mappings(index_name)

        if remote_settings.nil? || remote_mappings.nil?
          result[:status] = :remote_fetch_failed
          result[:error] = "Failed to retrieve remote settings or mappings for #{index_name}"
          return result
        end

        # Filter remote settings to match local format
        filtered_remote_settings = SettingsFilter.filter_internal_settings(remote_settings)

        # Normalize local settings to ensure consistent comparison
        normalized_local_settings = self.normalize_local_settings(local_settings)

        result[:settings_diff] = json_diff.generate_diff(filtered_remote_settings, normalized_local_settings)
        result[:mappings_diff] = json_diff.generate_diff(remote_mappings, local_mappings)
        
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

    # print_schema_diff(generate_schema_diff(alias_name))
    def self.print_schema_diff(schema_diff)
      puts "=" * 60
      puts "Comparing schema: #{schema_diff[:alias_name]}"
      puts "=" * 60

      # Handle errors by printing and returning
      if schema_diff[:status] == :alias_not_found
        puts "❌ #{schema_diff[:error]}"
        return
      elsif schema_diff[:status] == :multiple_indices
        puts "⚠️  #{schema_diff[:error]}"
        return
      elsif schema_diff[:status] == :local_files_not_found
        puts "❌ #{schema_diff[:error]}"
        return
      elsif schema_diff[:status] == :remote_fetch_failed
        puts "❌ #{schema_diff[:error]}"
        return
      elsif schema_diff[:status] == :error
        puts "❌ Error: #{schema_diff[:error]}"
        return
      end

      # Show what's being compared
      puts "New (Local Files):"
      puts "   #{schema_diff[:comparison_context][:new_files][:settings]}"
      puts "   #{schema_diff[:comparison_context][:new_files][:mappings]}"
      puts
      puts "Old (Remote API):"
      puts "   #{schema_diff[:comparison_context][:old_api][:settings]}"
      puts "   #{schema_diff[:comparison_context][:old_api][:mappings]}"
      puts

      # Display the diffs
      puts "Settings Comparison:"
      puts schema_diff[:settings_diff]
      puts

      puts "Mappings Comparison:"
      puts schema_diff[:mappings_diff]
    end

    private

    def self.normalize_local_settings(local_settings)
      return local_settings unless local_settings.is_a?(Hash)
      
      # If local settings already have "index" wrapper, use it
      if local_settings.key?("index")
        if local_settings["index"].is_a?(Hash)
          # Normalize the index settings and return
          normalized_index = normalize_values(local_settings["index"])
          return { "index" => normalized_index }
        else
          # If index exists but is not a hash, return as-is (invalid format)
          return local_settings
        end
      end
      
      # If local settings are empty, don't add index wrapper
      # This prevents empty {} from becoming { "index" => {} }
      return local_settings if local_settings.empty?
      
      # If local settings don't have "index" wrapper, wrap them in "index"
      # This handles cases like { "number_of_shards": 1 } which should be compared as { "index": { "number_of_shards": 1 } }
      normalized_settings = normalize_values(local_settings)
      { "index" => normalized_settings }
    end

    # Normalize string values to their proper types for Elasticsearch comparison
    # Handles the gotcha cases where ES accepts string inputs but returns canonical types
    def self.normalize_values(obj)
      case obj
      when Hash
        normalized = {}
        obj.each do |key, value|
          normalized[key] = normalize_values(value)
        end
        normalized
      when Array
        obj.map { |item| normalize_values(item) }
      when String
        normalize_string_value(obj)
      else
        obj
      end
    end

    # Convert string values to their proper types based on Elasticsearch behavior
    def self.normalize_string_value(str)
      # Handle boolean values
      case str.downcase
      when "true"
        true
      when "false"
        false
      when "1"
        # Could be boolean true or numeric 1, default to numeric for settings
        1
      when "0"
        # Could be boolean false or numeric 0, default to numeric for settings
        0
      else
        # Handle numeric strings
        if str.match?(/\A-?\d+\z/)
          # Integer string
          str.to_i
        elsif str.match?(/\A-?\d*\.\d+\z/)
          # Float string
          str.to_f
        else
          # Keep as string if it doesn't match any pattern
          str
        end
      end
    end
  end
end