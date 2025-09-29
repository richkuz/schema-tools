require_relative 'schema_files'
require_relative 'schema_revision'

module SchemaTools
  module Utils
    # Extract the base name from an index name by removing the version suffix
    # Example: "products-3" -> "products"
    def self.extract_base_name(index_name)
      index_name.gsub(/-\d+$/, '')
    end

    # Extract the version number from an index name
    # Example: "products-3" -> 3, "products" -> nil
    def self.extract_version_number(index_name)
      match = index_name.match(/-(\d+)$/)
      match ? match[1].to_i : nil
    end
  end
end