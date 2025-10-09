require_relative '../schema_files'
require_relative 'migration_step'
require_relative '../diff'
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
      @current_step = nil
      @rollback_attempted = false
    end

    def migrate
      log "=" * 60
      log "Breaking Change Migration for #{@alias_name}"
      log "=" * 60
      
      begin
        setup
        migration_steps.each do |step|
          @current_step = step
          step.execute(self)
        end
        
        # Verify migration by checking for differences after completion
        log "Verifying migration by comparing local schema with remote index..."
        diff = Diff.new(client: @client)
        diff_result = diff.generate_schema_diff(@alias_name)
        
        if diff_result[:status] == :no_changes
          log "✓ Migration verification successful - no differences detected"
          log "Breaking change migration completed successfully!"
        else
          log "⚠️  Migration verification failed - differences detected:"
          log "-" * 60
          diff.diff_schema(@alias_name)
          log "-" * 60
          raise "Migration verification failed - local schema does not match remote index after migration"
        end
      rescue => e
        log("Migration failed: #{e.message}")
        raise e
      end
    end

    def setup
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
    end

    def log(message)
      puts message
      log_to_log_index(message)
    end

    def log_to_log_index(message)
      return unless @migration_log_index
      doc = {
        timestamp: Time.now.iso8601,
        message: message.is_a?(String) ? message : message.to_json
      }
      @client.post("/#{@migration_log_index}/_doc", doc)
    end

    def migration_steps
      [
        MigrationStep.new(
          name: "STEP 1: Create catchup-1 index",
          run: ->(logger) { step1_create_catchup1 }
        ),
        MigrationStep.new(
          name: "STEP 2: Configure alias for write to catchup-1",
          run: ->(logger) { step2_configure_alias_write_catchup1_read_both }
        ),
        MigrationStep.new(
          name: "STEP 3: Reindex to new index",
          run: ->(logger) { step3_reindex_to_new_index }
        ),
        MigrationStep.new(
          name: "STEP 4: Create catchup-2 index",
          run: ->(logger) { step4_create_catchup2 }
        ),
        MigrationStep.new(
          name: "STEP 5: Configure alias for write to catchup-2",
          run: ->(logger) { step5_configure_alias_write_catchup2_read_all }
        ),
        MigrationStep.new(
          name: "STEP 6: Merge catchup-1 to new index",
          run: ->(logger) { step6_merge_catchup1_to_new }
        ),
        MigrationStep.new(
          name: "STEP 7: Configure alias with no write indexes",
          run: ->(logger) { step7_configure_alias_no_write }
        ),
        MigrationStep.new(
          name: "STEP 8: Merge catchup-2 to new index",
          run: ->(logger) { step8_merge_catchup2_to_new }
        ),
        MigrationStep.new(
          name: "STEP 9: Configure alias to new index only",
          run: ->(logger) { step9_configure_alias_final }
        ),
        MigrationStep.new(
          name: "STEP 10: Close unused indexes",
          run: ->(logger) { step10_close_unused_indexes }
        )
      ]
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
      begin
        reindex(@current_index, @new_index, @reindex_script)
      rescue => e
        attempt_rollback(e)
        raise e  # Re-raise the error after rollback
      end
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
          remove: {
            index: @current_index,
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

    private

    def attempt_rollback(original_error)
      log "=" * 60
      log "🔄 ATTEMPTING ROLLBACK DUE TO STEP 3 FAILURE"
      log "=" * 60
      log "Original error: #{original_error.message}"
      log ""
      log "Rolling back to original state..."
      log "This will preserve any data written during migration and restore the alias to the original index."
      log ""
      
      begin
        # Step 1: Stop writes by making alias read-only
        log "🔄 ROLLBACK STEP 1: Stopping writes to prevent data loss..."
        rollback_stop_writes
        
        # Step 2: Reindex catchup changes back to original index
        log "🔄 ROLLBACK STEP 2: Reindexing catchup changes back to original index..."
        rollback_reindex_catchup_to_original
        
        # Step 3: Restore alias to original state
        log "🔄 ROLLBACK STEP 3: Restoring alias to original index..."
        rollback_restore_alias_to_original
        
        # Step 4: Clean up created indexes
        log "🔄 ROLLBACK STEP 4: Cleaning up created indexes..."
        rollback_cleanup_indexes
        
        log "=" * 60
        log "✅ ROLLBACK COMPLETED SUCCESSFULLY"
        log "=" * 60
        log "The alias '#{@alias_name}' has been restored to point to the original index '#{@current_index}'"
        log "All data written during migration has been preserved in the original index."
        log "All created indexes have been cleaned up."
        log "You can now:"
        log "  1. Fix the issue that caused the reindex to fail"
        log "  2. Re-run the migration: rake 'schema:migrate[#{@alias_name}]'"
        log "  3. Check the migration log: #{@migration_log_index}"
        log ""
        
      rescue => rollback_error
        log "=" * 60
        log "❌ ROLLBACK FAILED"
        log "=" * 60
        log "Rollback error: #{rollback_error.message}"
        log ""
        log_rollback_instructions(original_error, rollback_error)
      end
    end

    def rollback_stop_writes
      # Configure alias to read-only: read from both original and catchup, write to neither
      actions = []
      
      # Remove write access from catchup-1 index
      actions << {
        remove: {
          index: @catchup1_index,
          alias: @alias_name
        }
      }
      
      # Add read-only access to original index
      actions << {
        add: {
          index: @current_index,
          alias: @alias_name,
          is_write_index: false
        }
      }
      
      # Add read-only access to catchup-1 index (if it exists)
      if @client.index_exists?(@catchup1_index)
        actions << {
          add: {
            index: @catchup1_index,
            alias: @alias_name,
            is_write_index: false
          }
        }
      end
      
      @client.update_aliases(actions)
      log "✓ Writes stopped - alias is now read-only"
    end

    def rollback_reindex_catchup_to_original
      # Only reindex if catchup-1 index exists and has data
      return unless @client.index_exists?(@catchup1_index)
      
      # Check if catchup-1 has any documents
      doc_count = @client.get_index_doc_count(@catchup1_index)
      
      if doc_count > 0
        log "📊 Found #{doc_count} documents in catchup-1 index - reindexing to original..."
        
        # Reindex from catchup-1 to original index
        reindex_body = {
          source: { index: @catchup1_index },
          dest: { index: @current_index }
        }
        
        result = @client.reindex(reindex_body)
        task_id = result['task']
        
        if task_id
          log "Reindex task started - task_id: #{task_id}"
          @client.wait_for_task(task_id)
          log "✓ Catchup data successfully reindexed to original index"
        else
          log "✓ Catchup data successfully reindexed to original index"
        end
      else
        log "✓ No documents in catchup-1 index - skipping reindex"
      end
    end

    def rollback_restore_alias_to_original
      # Remove all aliases and restore to original state only
      actions = []
      
      # Remove alias from catchup-1 index (if it exists)
      if @client.index_exists?(@catchup1_index)
        actions << {
          remove: {
            index: @catchup1_index,
            alias: @alias_name
          }
        }
      end
      
      # Add alias back to original index only
      actions << {
        add: {
          index: @current_index,
          alias: @alias_name,
          is_write_index: true
        }
      }
      
      @client.update_aliases(actions)
      log "✓ Alias restored to original index: #{@current_index}"
    end

    def rollback_cleanup_indexes
      # Clean up catchup-1 index
      if @client.index_exists?(@catchup1_index)
        @client.delete_index(@catchup1_index)
        log "✓ Deleted catchup-1 index: #{@catchup1_index}"
      else
        log "⚠️  Catchup-1 index does not exist: #{@catchup1_index}"
      end
      
      # Clean up new index if it was created
      if @client.index_exists?(@new_index)
        @client.delete_index(@new_index)
        log "✓ Deleted new index: #{@new_index}"
      else
        log "⚠️  New index does not exist: #{@new_index}"
      end
    end

    def log_rollback_instructions(original_error, rollback_error = nil)
      log "=" * 60
      log "🚨 MANUAL ROLLBACK REQUIRED"
      log "=" * 60
      log "The migration failed and automatic rollback could not be completed."
      log ""
      log "Original error: #{original_error.message}"
      if rollback_error
        log "Rollback error: #{rollback_error.message}"
        log ""
      end
      log "CURRENT STATE:"
      log "  - Alias: #{@alias_name}"
      log "  - Original index: #{@current_index}"
      log "  - Catchup-1 index: #{@catchup1_index}"
      log "  - New index: #{@new_index}"
      log ""
      log "MANUAL ROLLBACK STEPS:"
      log "1. Check current alias state:"
      log "   curl -X GET '#{@client.url}/_alias/#{@alias_name}'"
      log ""
      log "2. Restore alias to original index:"
      log "   curl -X POST '#{@client.url}/_aliases' -H 'Content-Type: application/json' -d '{"
      log "     \"actions\": ["
      log "       { \"remove\": { \"index\": \"#{@catchup1_index}\", \"alias\": \"#{@alias_name}\" } },"
      log "       { \"add\": { \"index\": \"#{@current_index}\", \"alias\": \"#{@alias_name}\", \"is_write_index\": true } }"
      log "     ]"
      log "   }'"
      log ""
      log "3. Clean up created indexes:"
      log "   curl -X DELETE '#{@client.url}/#{@catchup1_index}'"
      log "   curl -X DELETE '#{@client.url}/#{@new_index}'"
      log ""
      log "4. Verify alias is working:"
      log "   curl -X GET '#{@client.url}/#{@alias_name}/_search'"
      log ""
      log "5. Check migration log for details:"
      log "   curl -X GET '#{@client.url}/#{@migration_log_index}/_search?sort=timestamp:desc'"
      log ""
      log "After manual rollback, you can:"
      log "  - Fix the issue that caused the migration to fail"
      log "  - Re-run the migration: rake 'schema:migrate[#{@alias_name}]'"
      log "=" * 60
    end
  end
end