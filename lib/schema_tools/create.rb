require_relative 'schema_revision'

module SchemaTools
  def self.create(index_name:, client:)
    raise "index_name parameter is required" unless index_name
    
    latest_schema_revision = SchemaRevision.find_latest_revision(index_name)
    raise "No revisions found for #{index_name}" unless latest_schema_revision
    
    revision_files = SchemaFiles.get_revision_files(latest_schema_revision.revision_absolute_path)
    
    if client.index_exists?(index_name)
      puts "Index #{index_name} already exists, updating settings only"
      client.update_index_settings(index_name, revision_files[:settings])
    else
      puts "Creating index #{index_name}"
      client.create_index(index_name, revision_files[:settings], revision_files[:mappings])
    end
    SchemaTools.update_metadata(index_name:, metadata: { }, client:)
  end
end