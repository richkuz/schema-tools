require_relative 'schema_files'
require 'json'

module SchemaTools
  class MigrateBreakingChange
    def self.migrate(alias_name:, client:)
      new(alias_name: alias_name, client: client).migrate
    end

    def initialize(alias_name:, client:)
      @alias_name = alias_name
      @client = client
      @migration_log_index = nil
    end

    def migrate
      log "=" * 60
      log "Breaking Change Migration for #{@alias_name}"
      log "=" * 60
      
      unless @client.alias_exists?(@alias_name)
        raise "Alias '#{@alias_name}' does not exist"
      end
      
      indices = @client.get_alias_indices(@alias_name)
      if indices.length != 1
        log "ERROR: Alias '#{@alias_name}' must point to exactly one index"
        log "  Currently points to: #{indices.join(', ')}"
        raise "Alias '#{@alias_name}' must point to exactly one index"
      end
      
      @migration_log_index = "#{@alias_name}-migration-log-#{Time.now.strftime('%Y%m%d%H%M%S')}"
      log "Logging to '#{@migration_log_index}'"

      @current_index = indices.first
      log "Alias '#{@alias_name}' points to index '#{@current_index}'"
      
      new_timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      @new_index = "#{@alias_name}-#{new_timestamp}"
      log "new_index: #{@new_index}"

      @catchup1_index = "#{@new_index}-catchup-1"
      log "catchup1_index: #{@catchup1_index}"

      @catchup2_index = "#{@new_index}-catchup-2"
      log "catchup2_index: #{@catchup2_index}"

      # Use current index settings and mappings when creating catchup indexes
      # so that any reindex painless script logic will apply correctly to them.
      @current_settings = @client.get_index_settings(@current_index)
      @current_mappings = @client.get_index_mappings(@current_index)
      raise "Schema files not found for #{@current_index}" unless @current_settings && @current_mappings
      # Filter read-only settings
      @current_settings = SettingsFilter.filter_internal_settings(@current_settings)
      log "Current settings: #{JSON.generate(@current_settings)}"
      log "Current mappings: #{JSON.generate(@current_mappings)}"

      @new_settings = SchemaFiles.get_settings(@alias_name)
      @new_mappings = SchemaFiles.get_mappings(@alias_name)
      raise "Schema files not found for #{@alias_name}" unless @new_settings && @new_mappings
      log "New settings: #{JSON.generate(@new_settings)}"
      log "New mappings: #{JSON.generate(@new_mappings)}"

      @reindex_script = SchemaFiles.get_reindex_script(@alias_name)
      if @reindex_script
        log "Using reindex painless script defined for #{@alias_name}"
        log "reindex.painless script: #{@reindex_script}"
      end
      
      begin
        log("STEP 1 started: Create catchup-1 index")
        step1_create_catchup1
        log("STEP 1 completed")
        
        log("STEP 2 started: Configure alias for write to catchup-1")
        step2_configure_alias_write_catchup1_read_both
        log("STEP 2 completed")
        
        log("STEP 3 started: Reindex to new index")
        step3_reindex_to_new_index
        log("STEP 3 completed")
        
        log("STEP 4 started: Create catchup-2 index")
        step4_create_catchup2
        log("STEP 4 completed")
        
        log("STEP 5 started: Configure alias for write to catchup-2")
        step5_configure_alias_write_catchup2_read_all
        log("STEP 5 completed")
        
        log("STEP 6 started: Merge catchup-1 to new index")
        step6_merge_catchup1_to_new
        log("STEP 6 completed")
        
        log("STEP 7 started: Configure alias with no write indexes")
        step7_configure_alias_no_write
        log("STEP 7 completed")
        
        log("STEP 8 started: Merge catchup-2 to new index")
        step8_merge_catchup2_to_new
        log("STEP 8 completed")
        
        log("STEP 9 started: Configure alias to new index only")
        step9_configure_alias_final
        log("STEP 9 completed")
        
        log("STEP 10 started: Close unused indexes")
        step10_close_unused_indexes
        log("STEP 10 completed")
        
        log("Migration completed successfully")
        log "Breaking change migration completed successfully!"
        
      rescue => e
        log("Migration failed: #{e.message}")
        raise e
      end
    end

    private

    def log(message)
      puts message
      log_to_log_index(message)
    end

    def log_to_log_index(message)
      return unless @migration_log_index
      doc = {
        timestamp: Time.now.iso8601,
        message: message
      }
      @client.post("/#{@migration_log_index}/_doc", doc)
    end

    def step1_create_catchup1
      @client.create_index(@catchup1_index, @current_settings, @current_mappings)
      log "Created catchup-1 index: #{@catchup1_index}"
    end

    def step2_configure_alias_write_catchup1_read_both
      actions = [
        {
          add: {
            index: @catchup1_index,
            alias: @alias_name,
            is_write_index: true
          }
        },
        {
          add: {
            index: @current_index,
            alias: @alias_name,
            is_write_index: false
          }
        }
      ]
      update_aliases(actions)
      log "Configured alias #{@alias_name} to write to #{@catchup1_index} and read from both indexes"
    end

    def update_aliases(actions)
      response = @client.update_aliases(actions)
      if response['errors']
        log "ERROR: Failed to update aliases"
        log actions
        log response
        raise "Failed to update aliases"
      end
    end
    
    def step3_reindex_to_new_index
      @client.create_index(@new_index, @new_settings, @new_mappings)
      reindex(@current_index, @new_index, @reindex_script)
    end

    def reindex(current_index, new_index, reindex_script)
      response = @client.reindex(current_index, new_index, reindex_script)
      log response

      if response['took']
        log "Reindex task complete. Took: #{response['took']}"
        return true
      end
      
      task_id = response['task']
      if !task_id
        raise "No task ID from reindex. Reindex incomplete."
      end

      log "Reindex task started at #{Time.now}. task_id is #{task_id}. Fetch task status with GET #{@client.url}/_tasks/#{task_id}"
      
      timeout = 604800 # 1 week
      @client.wait_for_task(response['task'], timeout)
      log "Reindex complete"
    end

    def step4_create_catchup2
      @client.create_index(@catchup2_index, @current_settings, @current_mappings)
      log "Created catchup-2 index: #{@catchup2_index}"
    end

    def step5_configure_alias_write_catchup2_read_all
      actions = [
        # keep reading from current_index and catchup1_index
        # add a new catchup2_index for writes
        {
          add: {
            index: @catchup2_index,
            alias: @alias_name,
            is_write_index: true
          }
        },
        {
          add: {
            index: @catchup1_index,
            alias: @alias_name,
            is_write_index: false
          }
        },
        {
          add: {
            index: @current_index,
            alias: @alias_name,
            is_write_index: false
          }
        }
      ]
      update_aliases(actions)
      log "Configured alias #{@alias_name} to write to #{@catchup2_index} and continue reading from current and catchup1 indexes"
    end

    def step6_merge_catchup1_to_new
      reindex(@catchup1_index, @new_index, @reindex_script)
      log "Catchup-1 merged to new index"
    end

    def step7_configure_alias_no_write
      actions = [
        {
          add: {
            index: @catchup2_index,
            alias: @alias_name,
            is_write_index: false
          }
        },
        {
          add: {
            index: @catchup1_index,
            alias: @alias_name,
            is_write_index: false
          }
        },
        {
          add: {
            index: @current_index,
            alias: @alias_name,
            is_write_index: false
          }
        }
      ]
      update_aliases(actions)
      log "Configured alias #{@alias_name} with NO write indexes - writes will fail temporarily"
    end

    def step8_merge_catchup2_to_new
      reindex_script = SchemaFiles.get_reindex_script(@alias_name)
      reindex(@catchup2_index, @new_index, reindex_script)
    end

    def step9_configure_alias_final
      actions = [
        {
          remove: {
            index: @catchup2_index,
            alias: @alias_name
          }
        },
        {
          remove: {
            index: @catchup1_index,
            alias: @alias_name
          }
        },
        {
          add: {
            index: @new_index,
            alias: @alias_name,
            is_write_index: true
          }
        }
      ]
      update_aliases(actions)
      log "Configured alias #{@alias_name} to write and read from #{@new_index} only"
    end

    def step10_close_unused_indexes
      [@current_index, @catchup1_index, @catchup2_index].each do |index|
        if @client.index_exists?(index)
          @client.close_index(index)
          log "Closed index: #{index}"
        end
      end
    end
  end
end