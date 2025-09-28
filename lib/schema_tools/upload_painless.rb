require_relative 'schema_revision'

module SchemaTools
  def self.upload_painless(index_name:, client:, schema_manager:)
    raise "index_name parameter is required" unless index_name
    
    latest_schema_revision = SchemaRevision.for_latest_revision(index_name)
    raise "No revisions found for #{index_name}" unless latest_schema_revision
    
    revision_files = schema_manager.get_revision_files(latest_schema_revision.revision_absolute_path)
    
    revision_files[:painless_scripts].each do |script_name, script_content|
      puts "Uploading script: #{script_name}"
      client.put_script(script_name, script_content)
    end
  end
end