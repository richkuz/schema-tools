require_relative '../schema_files'
require_relative 'migration_step'
require_relative 'migrate_verify'
require_relative '../diff'
require_relative 'rollback'
require 'json'

module SchemaTools
  # Custom logger that uses the migration's log() method
  class MigrationLogger
    attr_writer :migration_log_index

    def initialize(migration_log_index, client)
      @migration_log_index = migration_log_index
      @client = client
    end

    def info(message)
      log(message)
    end

    def warn(message)
      log(message)
    end

    def error(message)
      log(message)
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
      @client.post("/#{@migration_log_index}/_doc", doc, suppress_logging: true)
    end
  end

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

      @logger = MigrationLogger.new(nil, client)
      @client.instance_variable_set(:@logger, @logger)
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
        SchemaTools.verify_migration(@alias_name, @client)
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

      @new_timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      @migration_log_index = "#{@alias_name}-#{@new_timestamp}-migration-log"
      log "Creating log index: #{@migration_log_index}"
      @client.create_index(@migration_log_index, {}, {})
      @logger.migration_log_index = @migration_log_index
      log "Logging to '#{@migration_log_index}'"
      
      @current_index = indices.first
      log "Alias '#{@alias_name}' points to index '#{@current_index}'"
      
      @new_index = "#{@alias_name}-#{@new_timestamp}"
      log "new_index: #{@new_index}"

      @catchup1_index = "#{@new_index}-catchup-1"
      log "catchup1_index: #{@catchup1_index}"

      @catchup2_index = "#{@new_index}-catchup-2"
      log "catchup2_index: #{@catchup2_index}"

      @throwaway_test_index = "#{@new_index}-throwaway-test"
      log "throwaway_test_index: #{@throwaway_test_index}}"

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
      @logger.info(message)
    end

    def migration_steps
      [
        MigrationStep.new(
          name: "STEP 0: Pre-test reindex with 1 document",
          run: ->(logger) { step0_test_reindex_one_doc }
        ),
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

    def step0_test_reindex_one_doc
      @client.create_index(@throwaway_test_index, @new_settings, @new_mappings)
      begin
        @client.reindex_one_doc(@current_index, @throwaway_test_index, @reindex_script)
      rescue => e
        log "Failed reindexing a test document"
        raise e
      ensure
        log "Deleting throwaway test index #{@throwaway_test_index}"
        @client.delete_index(@throwaway_test_index)
      end
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
      task_response = @client.reindex(current_index, new_index, reindex_script)
      log task_response
      if task_response['took']
        log "Reindex task complete. Took: #{task_response['took']}"
        if task_response['failures'] && !task_response['failures'].empty?
          failure_reason = task_response['failures'].map { |f| f['cause']['reason'] }.join("; ")
          raise "Reindex failed synchronously with internal errors. Failures: #{failure_reason}"
        end
        return true
      end
      task_id = task_response['task']
      unless task_id
        raise "Reindex response did not contain 'task' ID or 'took' time. Reindex incomplete."
      end
      log "Reindex task started at #{Time.now}. task_id is #{task_id}. Fetch task status with GET #{@client.url}/_tasks/#{task_id}"
      timeout = 604800 # 1 week
      completed_task_status = @client.wait_for_task(task_response['task'], timeout)
      final_result = completed_task_status.fetch('response', {})
      if final_result['failures'] && !final_result['failures'].empty?
        failure_reason = final_result['failures'].map { |f| f['cause']['reason'] }.join("; ")
        raise "Reindex FAILED during async processing. Failures: #{failure_reason}"
      end
      created = final_result.fetch('created', 0)
      updated = final_result.fetch('updated', 0)
      deleted = final_result.fetch('deleted', 0)
      log "Reindex complete." + \
        "\nTook: #{final_result['took']}ms." + \
        "\nCreated: #{created}" + \
        "\nUpdated: #{updated}" + \
        "\nDeleted: #{deleted}"
      return true
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
      [@current_index, @catchup1_index, @catchup2_index, @migration_log_index].each do |index|
        if @client.index_exists?(index)
          log "Closing index: #{index}"
          @client.close_index(index)
        end
      end
      @migration_log_index = nil
      @logger.migration_log_index = nil
    end

    private

    def attempt_rollback(original_error)
      rollback = Migrate::Rollback.new(@alias_name, @current_index, @catchup1_index, @new_index, @client, self)
      rollback.attempt_rollback(original_error)
    end

  end
end