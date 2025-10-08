require 'json'

module SchemaTools
  class MappingsDiff
    def initialize(local_mappings, remote_mappings)
      @local_mappings = local_mappings
      @remote_mappings = remote_mappings
    end

    def generate_minimal_changes
      return {} unless @local_mappings.is_a?(Hash) && @local_mappings.key?("properties")
      
      remote_properties = @remote_mappings.is_a?(Hash) && @remote_mappings.key?("properties") ? @remote_mappings["properties"] : {}
      changes = find_changes(remote_properties, @local_mappings["properties"])
      
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