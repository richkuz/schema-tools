require 'json'

module SchemaTools
  class SettingsDiff
    def initialize(local_schema, remote_schema)
      @local_schema = local_schema
      @remote_schema = remote_schema
    end

    def generate_minimal_changes
      return {} unless @local_schema.is_a?(Hash) && @local_schema.key?("index")
      
      remote_index = @remote_schema.is_a?(Hash) && @remote_schema.key?("index") ? @remote_schema["index"] : {}
      changes = find_changes(remote_index, @local_schema["index"])
      changes.empty? ? {} : { "index" => changes }
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