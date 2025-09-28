require 'fileutils'

module SchemaTools
  class SchemaRevision
    attr_reader :revision_relative_path, :revision_absolute_path

    def self.schemas_path
      SchemaTools::Config::SCHEMAS_PATH
    end

    # revision_relative_path: A revision path relative to the schemas folder, e.g. "products-3/revisions/2"
    def initialize(revision_relative_path)
      @revision_relative_path = revision_relative_path
      
      # Validate the path format first: should be "{index_name}/revisions/{revision_number}"
      unless @revision_relative_path.match?(/\A[^\/]+\/revisions\/\d+\z/)
        raise "Invalid revision path format. Expected '{index_name}/revisions/{revision_number}', got: #{@revision_relative_path}"
      end
      
      @revision_absolute_path = File.join(self.class.schemas_path, revision_relative_path)
      
      # Validate that the revision path exists on disk
      unless Dir.exist?(@revision_absolute_path)
        raise "Revision path does not exist: #{@revision_absolute_path}"
      end
    end

    # e.g. A SchemaRevision for "products-3/revisions/2" returns "2"
    def revision_number
      File.basename(@revision_relative_path.split('/revisions/').last)
    end

    # e.g. A SchemaRevision for "products-3/revisions/2" returns "products-3"
    def index_name
      @revision_relative_path.split('/revisions/').first
    end

    # e.g. "products-3" returns a SchemaRevision for "products-3/revisions/5" (whatever the highest revision number is),
    # or returns nil if none exists.
    def self.for_latest_revision(index_name)
      index_path = File.join(schemas_path, index_name)
      return nil unless Dir.exist?(index_path)
      
      revisions_path = File.join(index_path, 'revisions')
      return nil unless Dir.exist?(revisions_path)
      
      revision_dirs = Dir.glob(File.join(revisions_path, '*'))
                        .select { |d| File.directory?(d) }
                        .sort_by { |d| File.basename(d).to_i }
      
      latest_revision_dir = revision_dirs.last
      return nil unless latest_revision_dir
      
      revision_relative_path = File.join(index_name, 'revisions', File.basename(latest_revision_dir))
      new(revision_relative_path)
    end

    # Given a SchemaRevision, "products-3/revisions/2", returns a SchemaRevision "products-3/revisions/1"
    # Given a SchemaRevision,  "products-3/revisions/1", returns nil.
    def self.previous_revision_within_index(schema_revision)
      index_name = schema_revision.index_name
      current_revision_number = schema_revision.revision_number.to_i
      
      # Can't go to previous revision if we're at revision 1
      return nil if current_revision_number <= 1
      
      previous_revision_number = current_revision_number - 1
      revision_relative_path = "#{index_name}/revisions/#{previous_revision_number}"
      
      # Check if the previous revision exists on disk
      revision_absolute_path = File.join(schemas_path, revision_relative_path)
      return nil unless Dir.exist?(revision_absolute_path)
      
      new(revision_relative_path)
    end

    # Given a SchemaRevision, "products-3/revisions/2", returns a SchemaRevision "products-3/revisions/1"
    # Given a SchemaRevision, "products-3/revisions/1", returns a SchemaRevision "products-2/revisions/5"
    # Returns nil if at revision 1 of the earliest index name.
    def self.previous_revision_across_indexes(schema_revision)
      # First try to find a previous revision within the same index
      previous_within_index = previous_revision_within_index(schema_revision)
      return previous_within_index if previous_within_index

      # If no previous revision within the same index, look for the latest revision
      # of the previous index version
      index_name = schema_revision.index_name
      base_name = extract_base_name(index_name)
      current_version = extract_version_number(index_name)
      
      # Can't go to previous index if we're at version 1
      return nil if current_version <= 1
      
      # Try the previous versioned index first (e.g., products-2 -> products-1)
      previous_index_name = "#{base_name}-#{current_version - 1}"
      previous_revision = for_latest_revision(previous_index_name)
      return previous_revision if previous_revision
      
      # If no previous versioned index exists, try the base name without version (e.g., products-2 -> products)
      # This handles the case where the earliest index name doesn't have a version number
      base_revision = for_latest_revision(base_name)
      base_revision
    end

    private

    def self.extract_base_name(index_name)
      index_name.gsub(/-\d+$/, '')
    end

    def self.extract_version_number(index_name)
      match = index_name.match(/-(\d+)$/)
      match ? match[1].to_i : 1
    end
  end
end