module SchemaTools
  def self.painless(index_name:, client:, schema_manager:)
    raise "index_name parameter is required" unless index_name
    
    latest_revision = schema_manager.get_latest_revision_path(index_name)
    raise "No revisions found for #{index_name}" unless latest_revision
    
    revision_files = schema_manager.get_revision_files(latest_revision)
    
    revision_files[:painless_scripts].each do |script_name, script_content|
      puts "Uploading script: #{script_name}"
      client.put_script(script_name, script_content)
    end
  end
end