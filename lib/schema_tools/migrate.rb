module SchemaTools
  def self.migrate_all(revision_applied_by:, client:, schema_manager:)
    puts "Discovering all schemas and migrating each to their latest revisions..."
    
    schemas = SchemaTools::Utils.discover_latest_schema_versions_only(SchemaTools::Config::SCHEMAS_PATH)
    
    if schemas.empty?
      puts "No schemas found in #{SchemaTools::Config::SCHEMAS_PATH}"
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
        migrate_one_schema(schema[:index_name], revision_applied_by, schema_manager, client)
        puts "✓ Migration completed successfully for #{schema[:index_name]}"
      rescue => e
        puts "✗ Migration failed for #{schema[:index_name]}: #{e.message}"
        puts "Continuing with next schema..."
      end
      puts
    end
    
    puts "All migrations completed!"
  end

  def self.migrate_one_schema(index_name, revision_applied_by, schema_manager, client)
    puts "=" * 60
    puts "Migrating to index #{index_name}, revision_applied_by=#{revision_applied_by}"
    
    index_config = schema_manager.get_index_config(index_name)
    raise "Index configuration not found for #{index_name}" unless index_config
    
    latest_revision = schema_manager.get_latest_revision_path(index_name)
    raise "No revisions found for #{index_name}" unless latest_revision
    
    schema_manager.generate_diff_output_for_index_name_or_revision(index_name)

    revision_name = "#{index_name}/revisions/#{File.basename(latest_revision)}"

    if !client.index_exists?(index_name)
      SchemaTools.create(index_name:, client:, schema_manager:)
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
    
    SchemaTools.upload_painless(index_name:, client:, schema_manager:)

    from_index = index_config['from_index_name']
    if !from_index
      puts "No from_index_name specified; will not reindex data from a previous index."
    else
      SchemaTools.reindex(index_name:, client:, schema_manager:)
      SchemaTools.catchup(index_name:, client:, schema_manager:)
    end
    
    metadata = {
      revision: revision_name,
      revision_applied_at: Time.now.iso8601,
      revision_applied_by: revision_applied_by
    }
    SchemaTools.update_metadata(index_name:, metadata:, client:, schema_manager:)

    puts "=" * 60
    
    puts "Migration completed successfully"
    puts "=" * 60
  end
end