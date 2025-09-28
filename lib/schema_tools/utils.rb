require_relative 'schema_manager'
require_relative 'schema_revision'

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

    # Find the latest schema definition for a given base name
    # Example: "products" -> "schemas/products-3" (if products-3 is the latest)
    def self.find_latest_schema_definition(base_name, schemas_path)
      schema_dirs = Dir.glob(File.join(schemas_path, "#{base_name}*"))
                      .select { |d| File.directory?(d) }
                      .sort_by { |d| extract_version_number(File.basename(d)) }
      
      schema_dirs.last
    end

    # Find all latest schema versions across all schema families
    # Returns array of { index_name, latest_revision, revision_number, version_number }
    def self.discover_latest_schema_versions_only(schemas_path)
      return [] unless Dir.exist?(schemas_path)
      
      # Get all schema directories
      schema_dirs = Dir.glob(File.join(schemas_path, '*'))
                       .select { |d| File.directory?(d) }
      
      # Group schemas by base name and find the latest version of each
      schema_groups = {}
      
      schema_dirs.each do |schema_dir|
        schema_name = File.basename(schema_dir)
        base_name = extract_base_name(schema_name)
        version_number = extract_version_number(schema_name)
        
        # Check if this schema has an index.json and revisions
        schema_manager = SchemaTools::SchemaManager.new(schemas_path)
        index_config = schema_manager.get_index_config(schema_name)
        latest_schema_revision = SchemaRevision.for_latest_revision(schema_name)
        
        if index_config && latest_schema_revision
          if schema_groups[base_name].nil? || version_number > schema_groups[base_name][:version_number]
            schema_groups[base_name] = {
              index_name: schema_name,
              latest_revision: latest_schema_revision.revision_absolute_path,
              revision_number: latest_schema_revision.revision_number,
              version_number: version_number
            }
          end
        end
      end
      
      # Return only the latest version of each schema family
      schema_groups.values
    end
  end
end