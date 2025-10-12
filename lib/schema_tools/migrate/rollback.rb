module SchemaTools
  module Migrate
    class Rollback
      def initialize(alias_name, current_index, catchup1_index, new_index, client, logger)
        @alias_name = alias_name
        @current_index = current_index
        @catchup1_index = catchup1_index
        @new_index = new_index
        @client = client
        @logger = logger
      end

      def attempt_rollback(original_error)
        @logger.log "=" * 60
        @logger.log "🔄 ATTEMPTING ROLLBACK DUE TO STEP 3 FAILURE"
        @logger.log "=" * 60
        @logger.log "Original error: #{original_error.message}"
        @logger.log ""
        @logger.log "Rolling back to original state..."
        @logger.log "This will preserve any data written during migration and restore the alias to the original index."
        @logger.log ""
        
        begin
          # Step 1: Stop writes by making alias read-only
          @logger.log "🔄 ROLLBACK STEP 1: Stopping writes to prevent data loss..."
          stop_writes
          
          # Step 2: Reindex catchup changes back to original index
          @logger.log "🔄 ROLLBACK STEP 2: Reindexing catchup changes back to original index..."
          reindex_catchup_to_original
          
          # Step 3: Restore alias to original state
          @logger.log "🔄 ROLLBACK STEP 3: Restoring alias to original index..."
          restore_alias_to_original
          
          # Step 4: Clean up created indexes
          @logger.log "🔄 ROLLBACK STEP 4: Cleaning up created indexes..."
          cleanup_indexes
          
          @logger.log "=" * 60
          @logger.log "✅ ROLLBACK COMPLETED SUCCESSFULLY"
          @logger.log "=" * 60
          @logger.log "The alias '#{@alias_name}' has been restored to point to the original index '#{@current_index}'"
          @logger.log "All data written during migration has been preserved in the original index."
          @logger.log "All created indexes have been cleaned up."
          @logger.log "You can now:"
          @logger.log "  1. Fix the issue that caused the reindex to fail"
          @logger.log "  2. Re-run the migration: rake 'schema:migrate[#{@alias_name}]'"
          @logger.log "  3. Check the migration log: #{@logger.instance_variable_get(:@migration_log_index)}"
          @logger.log ""
          
        rescue => rollback_error
          @logger.log "=" * 60
          @logger.log "❌ ROLLBACK FAILED"
          @logger.log "=" * 60
          @logger.log "Rollback error: #{rollback_error.message}"
          @logger.log ""
          log_rollback_instructions(original_error, rollback_error)
        end
      end

      private

      def stop_writes
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
        @logger.log "✓ Writes stopped - alias is now read-only"
      end

      def reindex_catchup_to_original
        # Check if catchup-1 index has any documents
        doc_count = @client.get_index_doc_count(@catchup1_index)
        
        if doc_count > 0
          @logger.log "📊 Found #{doc_count} documents in catchup-1 index - reindexing to original..."
          
          # Reindex from catchup-1 to original index
          response = @client.reindex(source_index: @catchup1_index, dest_index: @current_index, script: nil)
          @logger.log "Reindex task started - task_id: #{response['task']}"
          
          # Wait for reindex to complete
          @client.wait_for_task(response['task'])
          @logger.log "✓ Catchup data successfully reindexed to original index"
        else
          @logger.log "✓ No documents in catchup-1 index - skipping reindex"
        end
      end

      def restore_alias_to_original
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
        @logger.log "✓ Alias restored to original index: #{@current_index}"
      end

      def cleanup_indexes
        # Clean up catchup-1 index
        if @client.index_exists?(@catchup1_index)
          @client.delete_index(@catchup1_index)
          @logger.log "✓ Deleted catchup-1 index: #{@catchup1_index}"
        else
          @logger.log "⚠️  Catchup-1 index does not exist: #{@catchup1_index}"
        end
        
        # Clean up new index if it was created
        if @client.index_exists?(@new_index)
          @client.delete_index(@new_index)
          @logger.log "✓ Deleted new index: #{@new_index}"
        else
          @logger.log "⚠️  New index does not exist: #{@new_index}"
        end
      end

      def log_rollback_instructions(original_error, rollback_error = nil)
        @logger.log "=" * 60
        @logger.log "❌ MANUAL ROLLBACK REQUIRED"
        @logger.log "=" * 60
        @logger.log "The automatic rollback failed. You need to manually restore the system."
        @logger.log ""
        @logger.log "Current state:"
        @logger.log "  - Alias: #{@alias_name}"
        @logger.log "  - Original index: #{@current_index}"
        @logger.log "  - Catchup-1 index: #{@catchup1_index}"
        @logger.log "  - New index: #{@new_index}"
        @logger.log ""
        @logger.log "Manual rollback steps:"
        @logger.log "1. Stop writes by making alias read-only:"
        @logger.log "   curl -X POST 'http://localhost:9200/_aliases' -H 'Content-Type: application/json' -d '{"
        @logger.log "     \"actions\": ["
        @logger.log "       { \"remove\": { \"index\": \"#{@catchup1_index}\", \"alias\": \"#{@alias_name}\" } },"
        @logger.log "       { \"add\": { \"index\": \"#{@current_index}\", \"alias\": \"#{@alias_name}\", \"is_write_index\": false } }"
        @logger.log "     ]"
        @logger.log "   }'"
        @logger.log ""
        @logger.log "2. Reindex catchup data to original (if needed):"
        @logger.log "   curl -X POST 'http://localhost:9200/_reindex' -H 'Content-Type: application/json' -d '{"
        @logger.log "     \"source\": { \"index\": \"#{@catchup1_index}\" },"
        @logger.log "     \"dest\": { \"index\": \"#{@current_index}\" }"
        @logger.log "   }'"
        @logger.log ""
        @logger.log "3. Restore alias to original index:"
        @logger.log "   curl -X POST 'http://localhost:9200/_aliases' -H 'Content-Type: application/json' -d '{"
        @logger.log "     \"actions\": ["
        @logger.log "       { \"remove\": { \"index\": \"#{@catchup1_index}\", \"alias\": \"#{@alias_name}\" } },"
        @logger.log "       { \"add\": { \"index\": \"#{@current_index}\", \"alias\": \"#{@alias_name}\", \"is_write_index\": true } }"
        @logger.log "     ]"
        @logger.log "   }'"
        @logger.log ""
        @logger.log "4. Clean up created indexes:"
        @logger.log "   curl -X DELETE 'http://localhost:9200/#{@catchup1_index}'"
        @logger.log "   curl -X DELETE 'http://localhost:9200/#{@new_index}'"
        @logger.log ""
        @logger.log "Original error: #{original_error.message}"
        if rollback_error
          @logger.log "Rollback error: #{rollback_error.message}"
        end
        @logger.log ""
      end
    end
  end
end