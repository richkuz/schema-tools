require 'json'

module SchemaTools
  class JsonDiff
    def initialize()      
    end

    # Keys to ignore in diff comparisons (noisy metadata)
    IGNORED_KEYS = [].freeze

    # Generate a detailed diff between two JSON objects
    # Returns a formatted string showing additions, removals, and modifications
    def generate_diff(old_json, new_json, context: {})
      old_normalized = normalize_json(old_json)
      new_normalized = normalize_json(new_json)
      
      # Filter out ignored keys
      old_filtered = filter_ignored_keys(old_normalized)
      new_filtered = filter_ignored_keys(new_normalized)
      
      if old_filtered == new_filtered
        return "No changes detected"
      end

      diff_lines = []
      diff_lines << "=== Changes Detected ==="
      diff_lines << ""
      
      # Generate detailed diff
      changes = compare_objects(old_filtered, new_filtered, "")
      
      if changes.empty?
        diff_lines << "No changes detected"
      else
        changes.each { |change| diff_lines << change }
      end
      
      diff_lines.join("\n")
    end

    private

    def normalize_json(json_obj)
      return {} unless json_obj
      normalized = JSON.parse(JSON.generate(json_obj))
      
      # Normalize OpenSearch/Elasticsearch-specific behavior
      if normalized.is_a?(Hash) && normalized.key?('properties')
        normalized = normalize_mappings(normalized)
      end
      
      normalized
    end

    def normalize_mappings(mappings)
      return mappings unless mappings.is_a?(Hash) && mappings.key?('properties')
      
      normalized = mappings.dup
      normalized['properties'] = normalize_properties(mappings['properties'])
      normalized
    end

    def normalize_properties(properties)
      return properties unless properties.is_a?(Hash)
      
      normalized = {}
      properties.each do |key, value|
        if value.is_a?(Hash)
          # Remove implicit "type": "object" if the field has "properties"
          if value.key?('properties') && value['type'] == 'object'
            normalized_value = value.dup
            normalized_value.delete('type')
            normalized[key] = normalize_properties(normalized_value)
          else
            normalized[key] = normalize_properties(value)
          end
        else
          normalized[key] = value
        end
      end
      
      normalized
    end

    def filter_ignored_keys(obj, path_prefix = "")
      return obj unless obj.is_a?(Hash)
      
      filtered = {}
      obj.each do |key, value|
        current_path = path_prefix.empty? ? key : "#{path_prefix}.#{key}"
        
        # Skip ignored keys
        next if IGNORED_KEYS.any? { |ignored_key| current_path == ignored_key }
        
        # Recursively filter nested objects
        if value.is_a?(Hash)
          filtered[key] = filter_ignored_keys(value, current_path)
        else
          filtered[key] = value
        end
      end
      
      filtered
    end

    def compare_objects(old_obj, new_obj, path_prefix)
      changes = []
      
      # Handle different object types
      if old_obj.is_a?(Hash) && new_obj.is_a?(Hash)
        changes.concat(compare_hashes(old_obj, new_obj, path_prefix))
      elsif old_obj.is_a?(Array) && new_obj.is_a?(Array)
        changes.concat(compare_arrays(old_obj, new_obj, path_prefix))
      elsif old_obj != new_obj
        changes << format_change(path_prefix, old_obj, new_obj)
      end
      
      changes
    end

    def compare_hashes(old_hash, new_hash, path_prefix)
      changes = []
      all_keys = (old_hash.keys + new_hash.keys).uniq.sort
      
      all_keys.each do |key|
        current_path = path_prefix.empty? ? key : "#{path_prefix}.#{key}"
        
        # Skip ignored keys
        next if IGNORED_KEYS.any? { |ignored_key| current_path == ignored_key }
        
        old_value = old_hash[key]
        new_value = new_hash[key]
        
        if old_value.nil? && !new_value.nil?
          changes << "➕ ADDED: #{current_path}"
          changes.concat(format_value_details("New value", new_value, "  "))
        elsif !old_value.nil? && new_value.nil?
          changes << "➖ REMOVED: #{current_path}"
          changes.concat(format_value_details("Old value", old_value, "  "))
        elsif old_value != new_value
          if old_value.is_a?(Hash) && new_value.is_a?(Hash) ||
             old_value.is_a?(Array) && new_value.is_a?(Array)
            changes.concat(compare_objects(old_value, new_value, current_path))
          else
            changes << "🔄 MODIFIED: #{current_path}"
            changes.concat(format_value_details("Old value", old_value, "  "))
            changes.concat(format_value_details("New value", new_value, "  "))
          end
        end
      end
      
      changes
    end

    def compare_arrays(old_array, new_array, path_prefix)
      changes = []
      
      if old_array.length != new_array.length
        changes << "ARRAY LENGTH CHANGED: #{path_prefix} (#{old_array.length} → #{new_array.length})"
      end
      
      # Compare elements up to the minimum length
      min_length = [old_array.length, new_array.length].min
      (0...min_length).each do |index|
        current_path = "#{path_prefix}[#{index}]"
        old_value = old_array[index]
        new_value = new_array[index]
        
        if old_value != new_value
          if old_value.is_a?(Hash) && new_value.is_a?(Hash) ||
             old_value.is_a?(Array) && new_value.is_a?(Array)
            changes.concat(compare_objects(old_value, new_value, current_path))
          else
            changes << "🔄 MODIFIED: #{current_path}"
            changes.concat(format_value_details("Old value", old_value, "  "))
            changes.concat(format_value_details("New value", new_value, "  "))
          end
        end
      end
      
      # Handle added elements
      if new_array.length > old_array.length
        (old_array.length...new_array.length).each do |index|
          current_path = "#{path_prefix}[#{index}]"
          changes << "➕ ADDED: #{current_path}"
          changes.concat(format_value_details("New value", new_array[index], "  "))
        end
      end
      
      # Handle removed elements
      if old_array.length > new_array.length
        (new_array.length...old_array.length).each do |index|
          current_path = "#{path_prefix}[#{index}]"
          changes << "➖ REMOVED: #{current_path}"
          changes.concat(format_value_details("Old value", old_array[index], "  "))
        end
      end
      
      changes
    end

    def format_change(path, old_value, new_value)
      "🔄 MODIFIED: #{path}"
    end

    def format_value_details(label, value, indent)
      details = []
      details << "#{indent}#{label}:"
      
      if value.is_a?(String)
        # Handle multiline strings
        if value.include?("\n")
          details << "#{indent}  \"\"\""
          value.split("\n").each do |line|
            details << "#{indent}  #{line}"
          end
          details << "#{indent}  \"\"\""
        else
          details << "#{indent}  \"#{value}\""
        end
      elsif value.is_a?(Hash) || value.is_a?(Array)
        # Format complex objects with proper indentation
        formatted = JSON.pretty_generate(value)
        formatted.split("\n").each do |line|
          details << "#{indent}  #{line}"
        end
      else
        details << "#{indent}  #{value.inspect}"
      end
      
      details
    end
  end
end