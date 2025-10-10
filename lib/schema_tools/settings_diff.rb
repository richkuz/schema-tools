require 'json'
require_relative 'diff'

module SchemaTools
  class SettingsDiff
    def initialize(local_schema, remote_schema)
      @local_schema = local_schema
      @remote_schema = remote_schema
    end

    def generate_minimal_changes
      return {} unless @local_schema.is_a?(Hash)
      
      # Normalize local schema to always have "index" wrapper
      local_index = normalize_local_schema(@local_schema)
      return {} if local_index.nil?
      
      # Extract remote index settings
      remote_index = @remote_schema.is_a?(Hash) && @remote_schema.key?("index") ? @remote_schema["index"] : {}
      
    # Normalize both sides to ensure consistent comparison
    normalized_remote = Diff.normalize_values(remote_index)
    normalized_local = Diff.normalize_values(local_index)
      
      changes = find_changes(normalized_remote, normalized_local)
      changes.empty? ? {} : { "index" => changes }
    end

    private

    def normalize_local_schema(local_schema)
      # If local schema already has "index" wrapper, use it only if it's a valid hash
      if local_schema.key?("index")
        return local_schema["index"] if local_schema["index"].is_a?(Hash)
        # If index exists but is not a hash, return nil to indicate invalid schema
        return nil
      end
      
      # If local schema doesn't have "index" wrapper, treat the entire schema as index settings
      # This handles cases like { "number_of_shards": 1 } which is equivalent to { "index": { "number_of_shards": 1 } }
      return local_schema
    end

    def find_changes(remote, local)
      changes = {}
      
      return changes unless local.is_a?(Hash) && remote.is_a?(Hash)
      
      local.each do |key, value|
        if !remote.key?(key)
          changes[key] = value
        elsif value != remote[key]
          if value.is_a?(Hash) && remote[key].is_a?(Hash)
            nested_changes = find_changes(remote[key], value)
            changes[key] = nested_changes unless nested_changes.empty?
          else
            changes[key] = value
          end
        end
      end
      
      changes
    end
  end
end