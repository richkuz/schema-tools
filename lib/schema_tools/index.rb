require 'fileutils'
require_relative 'config'
require_relative 'utils'

module SchemaTools
  # Describes a live index or index on disk
  class Index

    include SchemaTools::Utils

    attr_reader 
      :index_name     # "products-3"
      :base_name      # "products"
      :version_number # nil for "products", 1 for "products-1", etc.

    # index_name: Exact name of the index, e.g. "products-3"
    def initialize(index_name)
      @index_name = index_name
      @base_name = extract_base_name(index_name)
      @version_number = extract_version_number(index_name)
    end

    # Generate the next index name in the sequence after this Index
    # Example: "products" -> "products-2", "products-5" -> "products-6"
    def generate_next_index_name(index)
      next_version_number = @version_number ? @version_number + 1 : 2
      "#{@base_name}-#{next_version_number}"
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
      schema_dirs = Dir.glob(File.join(SCHEMAS_PATH, "#{base_name}*"))
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
  end
end