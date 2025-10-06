require_relative 'schema_files'

module SchemaTools
  class MigrateBreakingChange
    def self.migrate(alias_name:, client:)
      puts "=" * 60
      puts "Breaking Change Migration for #{alias_name}"
      puts "=" * 60
      
      unless client.alias_exists?(alias_name)
        raise "Alias '#{alias_name}' does not exist"
      end
      
      indices = client.get_alias_indices(alias_name)
      if indices.length != 1
        puts "ERROR: Alias '#{alias_name}' must point to exactly one index"
        puts "  Currently points to: #{indices.join(', ')}"
        raise "Alias '#{alias_name}' must point to exactly one index"
      end
      
      current_index = indices.first
      puts "Alias '#{alias_name}' points to index '#{current_index}'"
      
      migration_log_index = "#{alias_name}-migration-log-#{Time.now.strftime('%Y%m%d%H%M%S')}"
      
      if in_progress_migration_exists?(alias_name, client)
        puts "ERROR: An in-progress migration already exists for #{alias_name}"
        puts "If the migration has failed, retry it from the last successful step by running:"
        puts "rake 'schema:migrate_retry[#{alias_name}]'"
        raise "In-progress migration exists for #{alias_name}"
      end
      
      log_step(migration_log_index, "Starting breaking change migration", client)
      
      new_timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      new_index = "#{alias_name}-#{new_timestamp}"
      catchup1_index = "#{new_index}-catchup-1"
      catchup2_index = "#{new_index}-catchup-2"
      
      begin
        step1_create_catchup1(alias_name, catchup1_index, client)
        log_step(migration_log_index, "STEP 1 completed: Created catchup-1 index", client)
        
        step2_configure_alias_write_catchup1_read_both(alias_name, current_index, catchup1_index, client)
        log_step(migration_log_index, "STEP 2 completed: Configured alias for write to catchup-1", client)
        
        step3_reindex_to_new_index(current_index, new_index, alias_name, client)
        log_step(migration_log_index, "STEP 3 completed: Reindexed to new index", client)
        
        step4_create_catchup2(alias_name, catchup2_index, client)
        log_step(migration_log_index, "STEP 4 completed: Created catchup-2 index", client)
        
        step5_configure_alias_write_catchup2_read_all(alias_name, current_index, new_index, catchup1_index, catchup2_index, client)
        log_step(migration_log_index, "STEP 5 completed: Configured alias for write to catchup-2", client)
        
        step6_merge_catchup1_to_new(catchup1_index, new_index, client)
        log_step(migration_log_index, "STEP 6 completed: Merged catchup-1 to new index", client)
        
        step7_configure_alias_no_write(alias_name, current_index, new_index, catchup1_index, catchup2_index, client)
        log_step(migration_log_index, "STEP 7 completed: Configured alias with no write indexes", client)
        
        step8_merge_catchup2_to_new(catchup2_index, new_index, client)
        log_step(migration_log_index, "STEP 8 completed: Merged catchup-2 to new index", client)
        
        step9_configure_alias_final(alias_name, new_index, client)
        log_step(migration_log_index, "STEP 9 completed: Configured alias to new index only", client)
        
        step10_close_unused_indexes(current_index, catchup1_index, catchup2_index, client)
        log_step(migration_log_index, "STEP 10 completed: Closed unused indexes", client)
        
        log_step(migration_log_index, "Migration completed successfully", client)
        puts "✅ Breaking change migration completed successfully!"
        
      rescue => e
        log_step(migration_log_index, "Migration failed: #{e.message}", client)
        raise e
      end
    end

    def self.retry(alias_name:, client:)
      puts "=" * 60
      puts "Resuming Breaking Change Migration for #{alias_name}"
      puts "=" * 60
      
      migration_logs = find_migration_logs(alias_name, client)
      if migration_logs.empty?
        raise "No migration logs found for #{alias_name}"
      end
      
      latest_log = migration_logs.last
      puts "Resuming from migration log: #{latest_log}"
      
      # Implementation would need to parse the log and determine where to resume
      # This is a simplified version - in practice, you'd need more sophisticated state tracking
      puts "Resume functionality requires parsing migration log state"
      puts "For now, please run the full migration again"
    end

    private

    def self.in_progress_migration_exists?(alias_name, client)
      migration_logs = find_migration_logs(alias_name, client)
      return false if migration_logs.empty?
      
      latest_log = migration_logs.last
      log_docs = get_migration_log_docs(latest_log, client)
      
      last_entry = log_docs.last
      return false unless last_entry
      
      !last_entry['message'].include?('completed successfully') && 
      !last_entry['message'].include?('Migration failed')
    end

    def self.find_migration_logs(alias_name, client)
      pattern = "#{alias_name}-migration-log-*"
      indices = client.list_indices
      indices.select { |idx| idx.match?(/^#{Regexp.escape(alias_name)}-migration-log-\d{14}$/) }
             .sort
    end

    def self.get_migration_log_docs(log_index, client)
      response = client.get("/#{log_index}/_search")
      return [] unless response && response['hits']
      
      response['hits']['hits'].map { |hit| hit['_source'] }
    end

    def self.log_step(migration_log_index, message, client)
      doc = {
        timestamp: Time.now.iso8601,
        message: message
      }
      
      client.post("/#{migration_log_index}/_doc", doc)
      puts "📝 #{message}"
    end

    def self.step1_create_catchup1(alias_name, catchup1_index, client)
      settings = SchemaFiles.get_settings(alias_name)
      mappings = SchemaFiles.get_mappings(alias_name)
      
      raise "Schema files not found for #{alias_name}" unless settings && mappings
      
      client.create_index(catchup1_index, settings, mappings)
      puts "Created catchup-1 index: #{catchup1_index}"
    end

    def self.step2_configure_alias_write_catchup1_read_both(alias_name, current_index, catchup1_index, client)
      actions = [
        {
          add: {
            index: catchup1_index,
            alias: alias_name,
            is_write_index: true
          }
        },
        {
          add: {
            index: current_index,
            alias: alias_name
          }
        }
      ]
      
      client.update_aliases(actions)
      puts "Configured alias #{alias_name} to write to #{catchup1_index} and read from both indexes"
    end

    def self.step3_reindex_to_new_index(current_index, new_index, alias_name, client)
      settings = SchemaFiles.get_settings(alias_name)
      mappings = SchemaFiles.get_mappings(alias_name)
      reindex_script = SchemaFiles.get_reindex_script(alias_name)
      
      client.create_index(new_index, settings, mappings)
      
      body = {
        source: { index: current_index },
        dest: { index: new_index },
        conflicts: "proceed",
        refresh: false
      }
      body[:script] = { source: reindex_script } if reindex_script
      
      response = client.post("/_reindex?wait_for_completion=false", body)
      
      if response['task']
        puts "Reindex task started: #{response['task']}"
        client.wait_for_task(response['task'])
        puts "Reindex completed"
      else
        puts "Reindex completed immediately"
      end
    end

    def self.step4_create_catchup2(alias_name, catchup2_index, client)
      settings = SchemaFiles.get_settings(alias_name)
      mappings = SchemaFiles.get_mappings(alias_name)
      
      client.create_index(catchup2_index, settings, mappings)
      puts "Created catchup-2 index: #{catchup2_index}"
    end

    def self.step5_configure_alias_write_catchup2_read_all(alias_name, current_index, new_index, catchup1_index, catchup2_index, client)
      actions = [
        # keep reading from current_index and catchup1_index, add a new catchup2_index
        {
          add: {
            index: catchup2_index,
            alias: alias_name,
            is_write_index: true
          }
        }
      ]
      
      client.update_aliases(actions)
      puts "Configured alias #{alias_name} to write to #{catchup2_index} and continue reading from current and catchup1 indexes"
    end

    def self.step6_merge_catchup1_to_new(catchup1_index, new_index, client)
      body = {
        source: { index: catchup1_index },
        dest: { index: new_index },
        conflicts: "proceed"
      }
      
      response = client.post("/_update_by_query?wait_for_completion=false", body)
      
      if response['task']
        puts "Update by query task started: #{response['task']}"
        client.wait_for_task(response['task'])
        puts "Catchup-1 merged to new index"
      else
        puts "Catchup-1 merged to new index immediately"
      end
    end

    def self.step7_configure_alias_no_write(alias_name, current_index, new_index, catchup1_index, catchup2_index, client)
      actions = [
        {
          remove: {
            index: catchup2_index,
            alias: alias_name
          }
        }
      ]
      
      client.update_aliases(actions)
      puts "Configured alias #{alias_name} with NO write indexes - writes will fail temporarily"
    end

    def self.step8_merge_catchup2_to_new(catchup2_index, new_index, client)
      body = {
        source: { index: catchup2_index },
        dest: { index: new_index },
        conflicts: "proceed"
      }
      
      response = client.post("/_update_by_query?wait_for_completion=false", body)
      
      if response['task']
        puts "Update by query task started: #{response['task']}"
        client.wait_for_task(response['task'])
        puts "Catchup-2 merged to new index"
      else
        puts "Catchup-2 merged to new index immediately"
      end
    end

    def self.step9_configure_alias_final(alias_name, new_index, client)
      actions = [
        {
          add: {
            index: new_index,
            alias: alias_name,
            is_write_index: true
          }
        }
      ]
      
      client.update_aliases(actions)
      puts "Configured alias #{alias_name} to write and read from #{new_index} only"
    end

    def self.step10_close_unused_indexes(current_index, catchup1_index, catchup2_index, client)
      [current_index, catchup1_index, catchup2_index].each do |index|
        if client.index_exists?(index)
          client.close_index(index)
          puts "Closed index: #{index}"
        end
      end
    end
  end
end