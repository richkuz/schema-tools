module SchemaTools
  def self.migrate(to_index:, dryrun:, revision_applied_by:, client:, schema_manager:)
    # If no to_index is provided, discover and migrate all schemas
    if to_index.nil?
      puts "No specific index provided. Discovering all schemas and migrating to latest revisions..."
      puts "Dry run: #{dryrun}"
      
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
          migrate_single_schema(schema[:index_name], dryrun, revision_applied_by, schema_manager, client)
          puts "✓ Migration completed successfully for #{schema[:index_name]}"
        rescue => e
          puts "✗ Migration failed for #{schema[:index_name]}: #{e.message}"
          puts "Continuing with next schema..."
        end
        puts
      end
      
      puts "All migrations completed!"
    else
      migrate_single_schema(to_index, dryrun, revision_applied_by, schema_manager, client)
    end
  end

  private

  def self.migrate_single_schema(to_index, dryrun, revision_applied_by, schema_manager, client)
    puts "=" * 60
    puts "Migrating to index #{to_index}, dryrun=#{dryrun}, revision_applied_by=#{revision_applied_by}"
    
    index_config = schema_manager.get_index_config(to_index)
    raise "Index configuration not found for #{to_index}" unless index_config
    
    latest_revision = schema_manager.get_latest_revision_path(to_index)
    raise "No revisions found for #{to_index}" unless latest_revision
    
    revision_name = "#{to_index}/revisions/#{File.basename(latest_revision)}"
    
    if client.index_exists?(to_index)
      current_revision = client.get_schema_revision(to_index)
      
      if current_revision == revision_name
        puts "Already at revision #{revision_name}."
        puts "To re-create this index and re-migrate, run: rake 'schema:close[#{to_index}]' && rake 'schema:delete[#{to_index}]' && rake 'schema:migrate[#{to_index}]'"
        return
      end
      
      if current_revision.nil?
        puts "Unable to determine the current schema revision of #{to_index} by inspecting the live index's _meta mappings.
The index was likely created outside this tool.
Will attempt to migrate anyway as a non-breaking, in-place update to the index.
If this operation fails, you may need to run rake 'schema:delete[#{to_index}]' and then re-run rake 'schema:migrate[#{to_index}]'"
      end
    end
    
    if !index_config['from_index_name']
      puts "No from_index_name specified; will not reindex data from a previous index."
    end

    # Check for reindex requirements before creating the index
    if index_config['from_index_name'] && !client.index_exists?(to_index)
      from_index = index_config['from_index_name']
      
      if client.index_exists?(from_index)
        puts "Reindexing from #{from_index} to #{to_index}"
        unless dryrun
          Rake::Task['schema:reindex'].invoke(to_index)
          Rake::Task['schema:catchup'].invoke(to_index)
        end
      else
        puts "Source index #{from_index} does not exist. Skipping reindex for #{to_index}."
        puts "Note: #{to_index} will be created as a new index without data migration."
      end
    end
    
    unless dryrun
      schema_manager.generate_diff_output_for_index_name_or_revision(to_index)
      Rake::Task['schema:create'].invoke(to_index)
      Rake::Task['schema:painless'].invoke(to_index)
      
      metadata = {
        revision: revision_name,
        revision_applied_at: Time.now.iso8601,
        revision_applied_by: revision_applied_by
      }
      schema_manager.update_revision_metadata(to_index, latest_revision, metadata)
      
      mappings_update = {
        _meta: {
          schemurai_revision: metadata
        }
      }
      client.update_index_mappings(to_index, mappings_update)
      puts "=" * 60
    end
    
    puts "Migration completed successfully"
    puts "=" * 60
  end
end