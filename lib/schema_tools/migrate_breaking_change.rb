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
      log_step(migration_log_index, "Starting breaking change migration", client)
      puts "📝 Logging to '#{migration_log_index}'"
      
      new_timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      new_index = "#{alias_name}-#{new_timestamp}"
      catchup1_index = "#{new_index}-catchup-1"
      catchup2_index = "#{new_index}-catchup-2"
      
      begin
        log_step(migration_log_index, "STEP 1 started: Create catchup-1 index", client)
        step1_create_catchup1(alias_name, catchup1_index, client)
        log_step(migration_log_index, "STEP 1 completed", client)
        
        log_step(migration_log_index, "STEP 2 started: Configure alias for write to catchup-1", client)
        step2_configure_alias_write_catchup1_read_both(alias_name, current_index, catchup1_index, client)
        log_step(migration_log_index, "STEP 2 completed", client)
        
        log_step(migration_log_index, "STEP 3 started: Reindex to new index", client)
        step3_reindex_to_new_index(alias_name, current_index, new_index, client)
        log_step(migration_log_index, "STEP 3 completed", client)
        
        log_step(migration_log_index, "STEP 4 started: Create catchup-2 index", client)
        step4_create_catchup2(alias_name, catchup2_index, client)
        log_step(migration_log_index, "STEP 4 completed", client)
        
        log_step(migration_log_index, "STEP 5 started: Configure alias for write to catchup-2", client)
        step5_configure_alias_write_catchup2_read_all(alias_name, current_index, new_index, catchup1_index, catchup2_index, client)
        log_step(migration_log_index, "STEP 5 completed", client)
        
        log_step(migration_log_index, "STEP 6 started: Merge catchup-1 to new index", client)
        step6_merge_catchup1_to_new(alias_name, catchup1_index, new_index, client)
        log_step(migration_log_index, "STEP 6 completed", client)
        
        log_step(migration_log_index, "STEP 7 started: Configure alias with no write indexes", client)
        step7_configure_alias_no_write(alias_name, current_index, new_index, catchup1_index, catchup2_index, client)
        log_step(migration_log_index, "STEP 7 completed", client)
        
        log_step(migration_log_index, "STEP 8 started: Merge catchup-2 to new index", client)
        step8_merge_catchup2_to_new(catchup2_index, new_index, client)
        log_step(migration_log_index, "STEP 8 completed", client)
        
        log_step(migration_log_index, "STEP 9 started: Configure alias to new index only", client)
        step9_configure_alias_final(alias_name, new_index, client)
        log_step(migration_log_index, "STEP 9 completed", client)
        
        log_step(migration_log_index, "STEP 10 started: Close unused indexes", client)
        step10_close_unused_indexes(current_index, catchup1_index, catchup2_index, client)
        log_step(migration_log_index, "STEP 10 completed", client)
        
        log_step(migration_log_index, "Migration completed successfully", client)
        puts "✅ Breaking change migration completed successfully!"
        
      rescue => e
        log_step(migration_log_index, "Migration failed: #{e.message}", client)
        raise e
      end
    end

    private

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

    
    def self.step3_reindex_to_new_index(alias_name, current_index, new_index, client)
      settings = SchemaFiles.get_settings(alias_name)
      mappings = SchemaFiles.get_mappings(alias_name)
      reindex_script = SchemaFiles.get_reindex_script(alias_name)
      
      client.create_index(new_index, settings, mappings)

      reindex(current_index, new_index, reindex_script, client)
    end

    def self.reindex(current_index, new_index, reindex_script, client)
      response = client.reindex(current_index, new_index, reindex_script)
      puts response

      if response['took']
        puts "Reindex task complete. Took: #{response['took']}"
        return true
      end
      
      task_id = response['task']
      if !task_id
        raise "No task ID from reindex. Reindex incomplete."
      end

      puts "Reindex task started at #{Time.now}. task_id is #{task_id}. Fetch task status with GET #{client.url}/_tasks/#{task_id}"
      
      timeout = 604800 # 1 week
      client.wait_for_task(response['task'], timeout)
      puts "Reindex complete"
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
        add: {
          index: catchup2_index,
          alias: alias_name,
          is_write_index: true
        },
        add: {
          index: catchup1_index,
          alias: alias_name,
          is_write_index: false
        }
      ]
      
      client.update_aliases(actions)
      puts "Configured alias #{alias_name} to write to #{catchup2_index} and continue reading from current and catchup1 indexes"
    end

    def self.step6_merge_catchup1_to_new(alias_name, catchup1_index, new_index, client)
      reindex_script = SchemaFiles.get_reindex_script(alias_name)
      
      reindex(reindex_script, new_index, client)
      puts "Catchup-1 merged to new index"
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

    def self.step8_merge_catchup2_to_new(alias_name, catchup2_index, new_index client)
      self.reindex(catchup2_index, new_index, client)
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