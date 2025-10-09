require 'json'

module SchemaTools
  class ApiAwareMappingsDiff
    def initialize(local_mappings, remote_mappings)
      @local_mappings = local_mappings
      @remote_mappings = remote_mappings
    end

    def generate_minimal_changes
      return {} unless @local_mappings.is_a?(Hash) && @local_mappings.key?("properties")
      
      remote_properties = @remote_mappings.is_a?(Hash) && @remote_mappings.key?("properties") ? @remote_mappings["properties"] : {}
      changes = find_api_aware_changes(remote_properties, @local_mappings["properties"])
      
      # Check if dynamic setting is different
      dynamic_changed = false
      if @local_mappings.key?("dynamic")
        remote_dynamic = @remote_mappings.is_a?(Hash) && @remote_mappings.key?("dynamic") ? @remote_mappings["dynamic"] : nil
        dynamic_changed = @local_mappings["dynamic"] != remote_dynamic
      end
      
      if changes.empty? && !dynamic_changed
        {}
      else
        result = {}
        result["properties"] = changes unless changes.empty?
        result["dynamic"] = @local_mappings["dynamic"] if dynamic_changed
        result
      end
    end

    private

    def find_api_aware_changes(remote, local)
      changes = {}
      
      return changes unless local.is_a?(Hash) && remote.is_a?(Hash)
      
      local.each do |key, value|
        if !remote.key?(key)
          # New field - include complete definition
          changes[key] = value
        elsif value != remote[key]
          if value.is_a?(Hash) && remote[key].is_a?(Hash)
            # Field exists but has changes
            if is_field_definition?(value)
              # For field definitions, always include complete definition for API compatibility
              changes[key] = value
            else
              # For nested objects, try to be more selective
              nested_changes = find_api_aware_changes(remote[key], value)
              if nested_changes.empty?
                # No nested changes, but the values are different
                # Only include if this is a significant change
                changes[key] = value
              else
                changes[key] = nested_changes
              end
            end
          else
            # Simple value change
            changes[key] = value
          end
        end
      end
      
      changes
    end

    def is_field_definition?(field_value)
      return false unless field_value.is_a?(Hash)
      
      # Field definitions are objects that have a "type" property
      # These require complete definitions for OpenSearch/Elasticsearch API compatibility
      field_value.key?("type")
    end
  end
end