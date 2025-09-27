module SchemaTools
  # Merge a metadata hash into the index mappings._meta.schemurai
  # and update the associated mappings.json file on disk.
  # New metadata takes precedence.
  # metadata = {
  #   revision: revision_name,
  #   revision_applied_at: Time.now.iso8601,
  #   revision_applied_by: revision_applied_by
  # }
  def self.update_metadata(index_name:, metadata:, client:, schema_manager:)
    raise "index_name parameter is required" unless index_name
    raise "metadata parameter is required" unless metadata
    raise "client is required" unless client
    raise "schema_manager is required" unless schema_manager

    # Fetch existing metadata and merge with the new metadata
    existing_mappings = client.get_index_mappings(index_name)
    existing_metadata = existing_mappings&.dig('_meta', 'schemurai_revision') || {}
    
    merged_metadata = existing_metadata.merge(metadata)
    
    latest_revision = schema_manager.get_latest_revision_path(index_name)
    raise "No revisions found for #{index_name}" unless latest_revision
    
    schema_manager.update_revision_metadata(index_name, latest_revision, merged_metadata)
    
    mappings_update = {
      _meta: {
        schemurai_revision: merged_metadata
      }
    }
    client.update_index_mappings(index_name, mappings_update)
    
  end
end