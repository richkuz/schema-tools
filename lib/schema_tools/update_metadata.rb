require_relative 'schema_revision'

module SchemaTools
  # Merge a metadata hash into the index mappings._meta.schemurai hash on the live index.
  # Update associated mappings.json file on disk.
  # New metadata takes precedence over existing metadata.
  #
  # This method always sets these values: {
  #   revision: revision_path,
  #   revision_applied_at: Time.now.iso8601,
  #   revision_applied_by: Config.schemurai_user
  # }
  #
  # index_name: "products-2", exact index name to update live and in schema files
  # metadata: {} or { reindex_started_at: Time.now.iso8601 } or ...
  # client: SchemaTools::Client instance
  def self.update_metadata(index_name:, metadata:, client:)
    raise "index_name parameter is required" unless index_name
    raise "metadata parameter is required" unless metadata
    raise "client is required" unless client

    latest_schema_revision = SchemaRevision.find_latest_revision(index_name)
    raise "No revisions found for #{index_name}" unless latest_schema_revision
    
    # Fetch existing metadata
    existing_mappings = client.get_index_mappings(index_name)
    existing_metadata = existing_mappings&.dig('_meta', 'schemurai_revision') || {}

    # Insert any new metadata on top of existing (avoid duplicates)
    merged_metadata = existing_metadata.dup
    metadata.each { |key, value| merged_metadata[key.to_s] = value }
    
    # Insert persistent metadata on top of everything (only if not already present)
    persistent_metadata = {
      revision: latest_schema_revision.revision_relative_path,
      revision_applied_at: Time.now.iso8601,
      revision_applied_by: Config.schemurai_user
    }
    
    # Only add persistent metadata if revision is not already present
    unless merged_metadata.key?('revision')
      merged_metadata = merged_metadata.merge(persistent_metadata)
    else
      # Update only the timestamp fields if revision already exists, but don't duplicate
      merged_metadata['revision_applied_at'] = Time.now.iso8601
      merged_metadata['revision_applied_by'] = Config.schemurai_user
    end
    
    mappings_update = {
      _meta: {
        schemurai_revision: merged_metadata
      }
    }
    
    client.update_index_mappings(index_name, mappings_update)
    
    overwrite_revision_metadata(
      index_name,
      latest_schema_revision.revision_absolute_path,
      merged_metadata
    )
  end

  def self.overwrite_revision_metadata(index_name, revision_absolute_path, metadata)
    mappings_path = File.join(revision_absolute_path, 'mappings.json')
    current_mappings = JSON.parse(File.read(mappings_path)) # Raises if invalid/non-existent
    
    current_mappings['_meta'] ||= {}
    current_mappings['_meta']['schemurai_revision'] = metadata
    
    File.write(mappings_path, JSON.pretty_generate(current_mappings))
  end
end