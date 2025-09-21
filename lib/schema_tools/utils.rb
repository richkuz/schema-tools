module SchemaTools
  module Utils
    # Extract the base name from an index name by removing the version suffix
    # Example: "products-3" -> "products"
    def self.extract_base_name(index_name)
      index_name.gsub(/-\d+$/, '')
    end

    # Extract the version number from an index name
    # Example: "products-3" -> 3, "products" -> 1
    def self.extract_version_number(index_name)
      match = index_name.match(/-(\d+)$/)
      match ? match[1].to_i : 1
    end

    # Generate the next version name for a given base name
    # Example: "products" -> "products-2", "products-3" -> "products-4"
    def self.generate_next_version_name(base_name, current_version = nil)
      if current_version.nil?
        "#{base_name}-2"
      else
        "#{base_name}-#{current_version + 1}"
      end
    end

    # Generate the previous version name for a given index name
    # Example: "products-3" -> "products-2", "products-2" -> "products-1"
    def self.generate_previous_version_name(index_name)
      base_name = extract_base_name(index_name)
      version_number = extract_version_number(index_name)
      
      if version_number > 1
        "#{base_name}-#{version_number - 1}"
      else
        nil
      end
    end
  end
end