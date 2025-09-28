require_relative 'schema_revision'

module SchemaTools
  # Merge a metadata hash into the index mappings._meta.schemurai
  # and update the associated mappings.json file on disk.
  # New metadata takes precedence.
  # metadata = {
  #   revision: revision_name,
  #   revision_applied_at: Time.now.iso8601,
  #   revision_applied_by: revision_applied_by
  # }
  def self.update_metadata(index_name:, metadata:, client:)
    raise "index_name parameter is required" unless index_name
    raise "metadata parameter is required" unless metadata
    raise "client is required" unless client
    schema_manager = SchemaTools::SchemaManager.new()
    
    # Fetch existing metadata and merge with the new metadata
    existing_mappings = client.get_index_mappings(index_name)
    existing_metadata = existing_mappings&.dig('_meta', 'schemurai_revision') || {}
    
    merged_metadata = existing_metadata.merge(metadata)
    
    latest_schema_revision = SchemaRevision.for_latest_revision(index_name)
    raise "No revisions found for #{index_name}" unless latest_schema_revision
    
    schema_manager.update_revision_metadata(index_name, latest_schema_revision.revision_absolute_path, merged_metadata)
    
    mappings_update = {
      _meta: {
        schemurai_revision: merged_metadata
      }
    }
    client.update_index_mappings(index_name, mappings_update)
    
  end
end