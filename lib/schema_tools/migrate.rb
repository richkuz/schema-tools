require_relative 'schema_revision'
require_relative 'utils'
require_relative 'diff'

module SchemaTools
  def self.migrate_all(client:)
    puts "Discovering all schemas and migrating each to their latest revisions..."
    
    schemas = discover_latest_schema_versions_only(Config.schemas_path)
    
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
      puts "=" * 60
      puts "Migrating #{schema[:index_name]} to revision #{schema[:revision_number]}"
      puts "=" * 60
      
      begin
        migrate_one_schema(index_name: schema[:index_name], client: client)
        puts "✓ Migration completed successfully for #{schema[:index_name]}"
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
    
    SchemaTools.upload_painless(index_name:, client:)

    SchemaTools.update_metadata(index_name:, metadata: {}, client:)

    from_index = index_config['from_index_name']
    if !from_index
      puts "No from_index_name specified; will not reindex data from a previous index."
    else
      SchemaTools.reindex(index_name:, client:)
      SchemaTools.catchup(index_name:, client:)
    end
    

    puts "=" * 60
    
    puts "Migration completed successfully"
    puts "=" * 60
  end

  private
  
  # Find all latest schema versions across all schema families
  # Returns array of { index_name, latest_revision, revision_number, version_number }
  def self.discover_latest_schema_versions_only(schemas_path)
    return [] unless Dir.exist?(schemas_path)
    
    # Get all schema directories
    schema_dirs = Dir.glob(File.join(schemas_path, '*'))
                      .select { |d| File.directory?(d) }
    
    # Group schemas by base name and find the latest version of each
    schema_groups = {}
    
    schema_dirs.each do |schema_dir|
      schema_name = File.basename(schema_dir)
      base_name = Utils.extract_base_name(schema_name)
      version_number = Utils.extract_version_number(schema_name)
      
      # Check if this schema has an index.json and revisions
      index_config = SchemaFiles.get_index_config(schema_name)
      latest_schema_revision = SchemaRevision.find_latest_revision(schema_name)
      
      if index_config && latest_schema_revision
        # Handle nil version_number comparison explicitly
        should_update = schema_groups[base_name].nil? || 
                       (version_number && schema_groups[base_name][:version_number] && version_number > schema_groups[base_name][:version_number]) ||
                       (version_number && schema_groups[base_name][:version_number].nil?)
        
        if should_update
          schema_groups[base_name] = {
            index_name: schema_name,
            latest_revision: latest_schema_revision.revision_absolute_path,
            revision_number: latest_schema_revision.revision_number,
            version_number: version_number
          }
        end
      end
    end
    
    # Return only the latest version of each schema family
    schema_groups.values
  end
end