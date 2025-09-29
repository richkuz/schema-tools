require 'fileutils'
require_relative 'config'
require_relative 'utils'
require_relative 'schema_files'
require_relative 'schema_revision'

module SchemaTools
  # Describes a live index or index on disk
  class Index

    attr_reader :index_name, :base_name, :version_number
      # index_name: "products-3"
      # base_name: "products" 
      # version_number: nil for "products", 1 for "products-1", etc.

    # index_name: Exact name of the index, e.g. "products-3"
    def initialize(index_name)
      @index_name = index_name
      @base_name = Utils.extract_base_name(index_name)
      @version_number = Utils.extract_version_number(index_name)
    end

    # Generate the next index name in the sequence after this Index
    # Example: "products" -> "products-2", "products-5" -> "products-6"
    def generate_next_index_name
      next_version_number = @version_number ? @version_number + 1 : 2
      "#{@base_name}-#{next_version_number}"
    end

    # index_name: Exact name of the index to find, e.g. "products-3"
    # client: Client instance to query OpenSearch/Elasticsearch
    # Returns: Index object if found, nil if not found
    def self.find_live_index(index_name, client)
      return nil unless client.index_exists?(index_name)
      Index.new(index_name)
    rescue => e
      # If client raises an error, return nil
      nil
    end

    # index_name: Exact name of the index folder to find, e.g. "products-3"
    # Returns: Index object if folder exists, nil if not found
    def self.find_file_index(index_name)
      schema_dir = File.join(Config.schemas_path, index_name)
      return nil unless Dir.exist?(schema_dir)
      Index.new(index_name)
    end

    # base_name: The base name of an index to search for, e.g., "products" NOT "products-2".
    # Returns: An array of matching Index objects found live in OpenSearch/Elasticsearch,
    #          sorted by version_number (nil first), or [].
    def self.find_matching_live_indexes(base_name, client)
      response = client.get("/_cat/indices/#{base_name}*?format=json")
      return [] unless response && response.is_a?(Array)

      matching_indexes = response.map do |index_data|
        index_name = index_data['index']
        # match "products" or "products-3", not "products_dev")
        next unless index_name.match?(/^#{Regexp.escape(base_name)}(-\d+)?$/)
        Index.new(index_name)
      end.compact

      sort_by_version(matching_indexes)
    end

    # base_name: The base name of an index to search for, e.g., "products" NOT "products-2".
    # Returns: An array of matching Index objects found in SCHEMAS_PATH,
    #          sorted by version_number (nil first), or [].
    def self.find_matching_file_indexes(base_name)
      schema_dirs = Dir.glob(File.join(Config.schemas_path, "#{base_name}*"))
                       .select { |d| File.directory?(d) }

      matching_indexes = schema_dirs.map do |dir|
        index_name = File.basename(dir)
        # match "products" or "products-3", not "products_dev"
        next unless index_name.match?(/^#{Regexp.escape(base_name)}(-\d+)?$/)
        Index.new(index_name)
      end.compact

      sort_by_version(matching_indexes)
    end

    # Sort by version number, lowest to highest
    # # [3, 1, 2, nil, 0] becomes: [nil, 0, 1, 2, 3]
    def self.sort_by_version(indexes)
      indexes.sort do |a, b|
        comparison_value = lambda do |v|
          v.nil? ? -Float::INFINITY : v
        end
        comparison_value.call(a.version_number) <=> comparison_value.call(b.version_number)
      end
    end

    # Find all latest schema versions across all schema families
    # Returns array of { index_name, latest_revision, revision_number, version_number }
    def self.discover_latest_schema_versions_only
      schemas_path = Config.schemas_path
      return [] unless Dir.exist?(schemas_path)
      
      # Get all schema directories
      schema_dirs = Dir.glob(File.join(schemas_path, '*'))
                        .select { |d| File.directory?(d) }
      
      # Group schemas by base name and find the latest version of each
      schema_groups = {}
      
      schema_dirs.each do |schema_dir|
        schema_name = File.basename(schema_dir)
        base_name = Utils.extract_base_name(schema_name)
        version_number = Utils.extract_version_number(schema_name)
        
        # Check if this schema has an index.json and revisions
        index_config = SchemaFiles.get_index_config(schema_name)
        latest_schema_revision = SchemaRevision.find_latest_revision(schema_name)
        
        if index_config && latest_schema_revision
          # Handle nil version_number comparison explicitly
          should_update = schema_groups[base_name].nil? || 
                         (version_number && schema_groups[base_name][:version_number] && version_number > schema_groups[base_name][:version_number]) ||
                         (version_number && schema_groups[base_name][:version_number].nil?)
          
          if should_update
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