require_relative 'schema_revision'
require_relative 'utils'
require_relative 'diff'
require_relative 'index'

module SchemaTools
  def self.migrate_all(client:)
    puts "Discovering all schemas and migrating each to their latest revisions..."
    
    schemas = Index.find_latest_file_indexes
    
    if schemas.empty?
      puts "No schemas found in #{Config.schemas_path}"
      return
    end
    
    puts "Found #{schemas.length} schema(s) to migrate:"
    schemas.each do |schema|
      puts "  - #{schema[:index_name]} (latest revision: #{schema[:revision_number]})"
    end
    puts
    
    schemas.each do |schema|
      begin
        migrate_one_schema(index_name: schema[:index_name], client: client)
      rescue => e
        puts "✗ Migration failed for #{schema[:index_name]}: #{e.message}"
        puts "Continuing with next schema..."
      end
      puts
    end
  end

  def self.migrate_one_schema(index_name:, client:)
    puts "=" * 60
    puts "Migrating to index #{index_name}"
    puts "=" * 60
    
    index_config = SchemaFiles.get_index_config(index_name)
    raise "Index configuration not found for #{index_name}" unless index_config
    
    latest_schema_revision = SchemaRevision.find_latest_revision(index_name)
    raise "No revisions found for #{index_name}" unless latest_schema_revision
    
    SchemaTools.diff(schema_revision: latest_schema_revision)

    revision_name = latest_schema_revision.revision_relative_path # products-3/revisions/2

    if !client.index_exists?(index_name)
      SchemaTools.create(index_name:, client:)
    else
      current_revision = client.get_schema_revision(index_name)
      if current_revision == revision_name
        puts "Already at revision #{revision_name}."
        puts "To re-create this index and re-migrate, run: rake 'schema:close[#{index_name}]' && rake 'schema:delete[#{index_name}]' && rake 'schema:migrate[#{index_name}]'"
        return
      end
      
      if current_revision.nil?
        puts "Unable to determine the current schema revision of #{index_name} by inspecting the live index's _meta mappings.
  The index was likely created outside this tool.
  Will attempt to migrate anyway as a non-breaking, in-place update to the index.
  If this operation fails, you may want to re-create the index by running: rake 'schema:delete[#{index_name}]' && rake 'schema:migrate[#{index_name}]'"
      end
    end
    

    SchemaTools.update_metadata(index_name:, metadata: {}, client:)

    from_index = index_config['from_index_name']
    if !from_index
      puts "No from_index_name specified; will not reindex data from a previous index."
    else
      SchemaTools.reindex(index_name:, client:)
      SchemaTools.catchup(index_name:, client:)
    end
    
    puts "✓ Migration completed successfully for #{index_name}"
  end

  private
  
end