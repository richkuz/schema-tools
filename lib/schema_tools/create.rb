module SchemaTools
  def self.create(index_name:, client:, schema_manager:)
    raise "index_name parameter is required" unless index_name
    
    latest_revision = schema_manager.get_latest_revision_path(index_name)
    raise "No revisions found for #{index_name}" unless latest_revision
    
    revision_files = schema_manager.get_revision_files(latest_revision)
    
    if client.index_exists?(index_name)
      puts "Index #{index_name} already exists, updating settings only"
      client.update_index_settings(index_name, revision_files[:settings])
    else
      puts "Creating index #{index_name}"
      client.create_index(index_name, revision_files[:settings], revision_files[:mappings])
    end
  end
end