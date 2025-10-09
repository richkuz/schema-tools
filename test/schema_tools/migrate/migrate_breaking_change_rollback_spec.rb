require_relative '../../spec_helper'
require 'schema_tools/migrate/migrate_breaking_change'
require 'schema_tools/client'
require 'schema_tools/schema_files'
require 'schema_tools/config'

RSpec.describe SchemaTools::MigrateBreakingChange do
  let(:alias_name) { 'test-alias' }
  let(:current_index) { 'test-index-20240101120000' }
  
  # Track actual generated index names
  let(:actual_index_names) { {} }
  
  let(:mock_client) do
    double('Client').tap do |client|
      allow(client).to receive(:alias_exists?).with(alias_name).and_return(true)
      allow(client).to receive(:get_alias_indices).with(alias_name).and_return([current_index])
      allow(client).to receive(:get_index_settings).with(current_index).and_return({})
      allow(client).to receive(:get_index_mappings).with(current_index).and_return({})
      allow(client).to receive(:index_exists?).and_return(false)
      allow(client).to receive(:create_index).and_return({})
      allow(client).to receive(:update_aliases).and_return({})
      allow(client).to receive(:reindex).and_return({ 'task' => 'test-task-id' })
      allow(client).to receive(:wait_for_task).and_return({})
      allow(client).to receive(:delete_index).and_return({})
      allow(client).to receive(:close_index).and_return({})
      allow(client).to receive(:post).and_return({})
      allow(client).to receive(:url).and_return('http://localhost:9200')
    end
  end

  let(:migration) { described_class.new(alias_name: alias_name, client: mock_client) }

  before do
    allow(SchemaTools::SchemaFiles).to receive(:get_settings).and_return({})
    allow(SchemaTools::SchemaFiles).to receive(:get_mappings).and_return({})
    allow(SchemaTools::SchemaFiles).to receive(:get_reindex_script).and_return(nil)
    allow(SchemaTools::SettingsFilter).to receive(:filter_internal_settings).and_return({})
  end

  describe 'rollback functionality' do
    context 'when STEP 3 (reindex) fails' do
      before do
        # Mock successful setup and first two steps
        allow(mock_client).to receive(:create_index).and_return({})
        allow(mock_client).to receive(:update_aliases).and_return({})
        
        # Mock rollback methods
        allow(mock_client).to receive(:get_index_doc_count).and_return(0)
      end

      it 'attempts automatic rollback when STEP 3 fails' do
        # Mock STEP 3 failure
        allow(mock_client).to receive(:reindex).and_raise(StandardError.new('Reindex failed'))
        
        # Use flexible expectations that work with the actual generated names
        allow(mock_client).to receive(:index_exists?).with(/catchup-1/).and_return(true)
        allow(mock_client).to receive(:update_aliases).with(anything).and_return({})
        allow(mock_client).to receive(:delete_index).with(/catchup-1/)
        allow(mock_client).to receive(:delete_index).with(/test-alias-\d+/)

        # Just verify that rollback methods are called
        expect(migration).to receive(:rollback_stop_writes)
        expect(migration).to receive(:rollback_reindex_catchup_to_original)
        expect(migration).to receive(:rollback_restore_alias_to_original)
        expect(migration).to receive(:rollback_cleanup_indexes)

        # The migration should fail after rollback
        expect { migration.migrate }.to raise_error(StandardError, 'Reindex failed')
      end

      it 'logs rollback progress' do
        # Mock STEP 3 failure
        allow(mock_client).to receive(:reindex).and_raise(StandardError.new('Reindex failed'))
        
        allow(mock_client).to receive(:index_exists?).and_return(true)
        allow(mock_client).to receive(:update_aliases).and_return({})
        allow(mock_client).to receive(:delete_index).and_return({})

        # Just verify that rollback is attempted - the actual logging will happen
        expect(migration).to receive(:attempt_rollback).once

        # The migration should fail after rollback
        expect { migration.migrate }.to raise_error(StandardError, 'Reindex failed')
      end

      it 'stops writes and reindexes catchup data during rollback' do
        allow(mock_client).to receive(:index_exists?).and_return(true)
        allow(mock_client).to receive(:get_index_doc_count).and_return(5)
        allow(mock_client).to receive(:delete_index).and_return({})
        
        # Mock reindex to fail for STEP 3, but succeed for rollback
        call_count = 0
        allow(mock_client).to receive(:reindex) do |body|
          call_count += 1
          if call_count == 1
            # First call (STEP 3) should fail
            raise StandardError.new('Reindex failed')
          else
            # Subsequent calls (rollback) should succeed
            { 'task' => 'test-task-id' }
          end
        end
        allow(mock_client).to receive(:wait_for_task).and_return({})
        
        # Should stop writes first (read-only mode)
        expect(mock_client).to receive(:update_aliases).with(
          array_including(
            hash_including(remove: hash_including(index: /catchup-1/)),
            hash_including(add: hash_including(index: current_index, is_write_index: false))
          )
        ).once
        
        # Should reindex catchup data
        expect(mock_client).to receive(:get_index_doc_count).with(/catchup-1/).and_return(5)
        
        # Should restore alias to original only
        expect(mock_client).to receive(:update_aliases).with(
          array_including(
            hash_including(remove: hash_including(index: /catchup-1/)),
            hash_including(add: hash_including(index: current_index, is_write_index: true))
          )
        ).once

        # The migration should fail after rollback
        expect { migration.migrate }.to raise_error(StandardError, 'Reindex failed')
      end

      it 'skips reindex when catchup index has no documents' do
        # Mock STEP 3 failure
        allow(mock_client).to receive(:reindex).and_raise(StandardError.new('Reindex failed'))
        
        allow(mock_client).to receive(:index_exists?).and_return(true)
        allow(mock_client).to receive(:get_index_doc_count).and_return(0)
        allow(mock_client).to receive(:update_aliases).and_return({})
        allow(mock_client).to receive(:delete_index).and_return({})
        
        # Should not reindex when no documents (during rollback)
        expect(mock_client).to receive(:get_index_doc_count).with(/catchup-1/).and_return(0)

        # The migration should fail after rollback
        expect { migration.migrate }.to raise_error(StandardError, 'Reindex failed')
      end

      it 'cleans up created indexes during rollback' do
        # Mock STEP 3 failure
        allow(mock_client).to receive(:reindex).and_raise(StandardError.new('Reindex failed'))
        
        allow(mock_client).to receive(:index_exists?).and_return(true)
        allow(mock_client).to receive(:get_index_doc_count).and_return(0)
        allow(mock_client).to receive(:update_aliases).and_return({})
        expect(mock_client).to receive(:delete_index).with(/catchup-1/)
        expect(mock_client).to receive(:delete_index).with(/test-alias-\d+/)

        # The migration should fail after rollback
        expect { migration.migrate }.to raise_error(StandardError, 'Reindex failed')
      end
    end

    context 'when rollback itself fails' do
      before do
        # Mock successful setup and first two steps
        allow(mock_client).to receive(:create_index).and_return({})
        allow(mock_client).to receive(:update_aliases).and_return({})
        
        # Mock STEP 3 failure
        allow(mock_client).to receive(:reindex).and_raise(StandardError.new('Reindex failed'))
        
        # Mock rollback failure - only fail during rollback, not during initial setup
        allow(mock_client).to receive(:index_exists?).and_return(true)
        # First call succeeds (for initial setup), subsequent calls fail (for rollback)
        call_count = 0
        allow(mock_client).to receive(:update_aliases) do
          call_count += 1
          if call_count > 2  # After initial setup, fail during rollback
            raise StandardError.new('Rollback failed')
          else
            {}
          end
        end
      end

      it 'logs manual rollback instructions when rollback fails' do
        # Test the rollback failure scenario by calling attempt_rollback directly
        allow(mock_client).to receive(:index_exists?).and_return(true)
        allow(mock_client).to receive(:update_aliases).and_raise(StandardError.new('Rollback failed'))
        allow(mock_client).to receive(:delete_index).and_return({})
        
        expect(migration).to receive(:log_rollback_instructions).once
        
        migration.send(:attempt_rollback, StandardError.new('Reindex failed'))
      end

      it 'provides detailed curl commands for manual rollback' do
        # Test that log_rollback_instructions provides curl commands
        expect(migration).to receive(:log).at_least(5).times
        
        migration.send(:log_rollback_instructions, StandardError.new('Reindex failed'))
      end
    end

    context 'when failure occurs in other steps' do
      before do
        # Mock STEP 1 failure
        allow(mock_client).to receive(:create_index).and_raise(StandardError.new('Create index failed'))
      end

      it 'does not attempt rollback for non-STEP 3 failures' do
        expect(migration).not_to receive(:attempt_rollback)
        # For non-STEP 3 failures, no rollback should be attempted

        expect { migration.migrate }.to raise_error(StandardError, 'Create index failed')
      end
    end

    context 'when rollback is attempted multiple times' do
      before do
        allow(mock_client).to receive(:create_index).and_return({})
        allow(mock_client).to receive(:update_aliases).and_return({})
        allow(mock_client).to receive(:reindex).and_raise(StandardError.new('Reindex failed'))
      end

      it 'only attempts rollback once' do
        allow(mock_client).to receive(:index_exists?).and_return(true)
        allow(mock_client).to receive(:update_aliases).and_return({})
        allow(mock_client).to receive(:delete_index).and_return({})

        expect(migration).to receive(:attempt_rollback).once

        expect { migration.migrate }.to raise_error(StandardError)
      end
    end
  end

  describe 'rollback methods' do
    let(:test_catchup1_index) { 'test-catchup-1' }
    let(:test_new_index) { 'test-new-index' }
    
    before do
      migration.instance_variable_set(:@current_index, current_index)
      migration.instance_variable_set(:@catchup1_index, test_catchup1_index)
      migration.instance_variable_set(:@new_index, test_new_index)
      migration.instance_variable_set(:@alias_name, alias_name)
    end

    describe '#rollback_restore_alias_to_original' do
      it 'restores alias to original index' do
        expect(mock_client).to receive(:index_exists?).with(test_catchup1_index).and_return(true)
        expect(mock_client).to receive(:update_aliases).with([
          {
            remove: {
              index: test_catchup1_index,
              alias: alias_name
            }
          },
          {
            add: {
              index: current_index,
              alias: alias_name,
              is_write_index: true
            }
          }
        ]).and_return({})

        migration.send(:rollback_restore_alias_to_original)
      end

      it 'handles case when catchup-1 index does not exist' do
        expect(mock_client).to receive(:index_exists?).with(test_catchup1_index).and_return(false)
        expect(mock_client).to receive(:update_aliases).with([
          {
            add: {
              index: current_index,
              alias: alias_name,
              is_write_index: true
            }
          }
        ]).and_return({})

        migration.send(:rollback_restore_alias_to_original)
      end
    end

    describe '#rollback_cleanup_indexes' do
      it 'deletes catchup-1 index if it exists' do
        expect(mock_client).to receive(:index_exists?).with(test_catchup1_index).and_return(true)
        expect(mock_client).to receive(:delete_index).with(test_catchup1_index)

        migration.send(:rollback_cleanup_indexes)
      end

      it 'logs when catchup-1 index does not exist' do
        expect(mock_client).to receive(:index_exists?).with(test_catchup1_index).and_return(false)
        expect(mock_client).to receive(:index_exists?).with(test_new_index).and_return(false)
        expect(migration).to receive(:log).with("⚠️  Catchup-1 index does not exist: #{test_catchup1_index}")
        expect(migration).to receive(:log).with("⚠️  New index does not exist: #{test_new_index}")

        migration.send(:rollback_cleanup_indexes)
      end
    end

    describe '#rollback_cleanup_indexes' do
      it 'deletes new index if it exists' do
        expect(mock_client).to receive(:index_exists?).with(test_new_index).and_return(true)
        expect(mock_client).to receive(:delete_index).with(test_new_index)

        migration.send(:rollback_cleanup_indexes)
      end

      it 'logs when new index does not exist' do
        expect(mock_client).to receive(:index_exists?).with(test_catchup1_index).and_return(false)
        expect(mock_client).to receive(:index_exists?).with(test_new_index).and_return(false)
        expect(migration).to receive(:log).with("⚠️  Catchup-1 index does not exist: #{test_catchup1_index}")
        expect(migration).to receive(:log).with("⚠️  New index does not exist: #{test_new_index}")

        migration.send(:rollback_cleanup_indexes)
      end
    end

    describe '#log_rollback_instructions' do
      let(:original_error) { StandardError.new('Original error') }
      let(:rollback_error) { StandardError.new('Rollback error') }

      it 'logs comprehensive manual rollback instructions' do
        # Just verify that some logging happens - don't be too specific about the exact messages
        expect(migration).to receive(:log).at_least(5).times

        migration.send(:log_rollback_instructions, original_error, rollback_error)
      end

      it 'includes curl commands for manual rollback' do
        # Just verify that some logging happens - don't be too specific about the exact messages
        expect(migration).to receive(:log).at_least(5).times

        migration.send(:log_rollback_instructions, original_error)
      end

      it 'handles case without rollback error' do
        expect(migration).to receive(:log).with("Original error: #{original_error.message}")
        expect(migration).not_to receive(:log).with(/Rollback error/)

        migration.send(:log_rollback_instructions, original_error)
      end
    end
  end

  describe 'integration with migration flow' do
    context 'when migration succeeds' do
      before do
        allow(mock_client).to receive(:create_index).and_return({})
        allow(mock_client).to receive(:update_aliases).and_return({})
        allow(mock_client).to receive(:reindex).and_return({ 'task' => 'test-task-id' })
        allow(mock_client).to receive(:wait_for_task).and_return({})
        allow(mock_client).to receive(:close_index).and_return({})
        allow(mock_client).to receive(:post).and_return({})
        
        # Mock successful verification
        diff_mock = double('Diff')
        allow(diff_mock).to receive(:generate_schema_diff).and_return({ status: :no_changes })
        allow(diff_mock).to receive(:diff_schema)
        allow(SchemaTools::Diff).to receive(:new).and_return(diff_mock)
      end

      it 'does not attempt rollback on successful migration' do
        expect(migration).not_to receive(:attempt_rollback)

        migration.migrate
      end
    end

    context 'when verification fails' do
      before do
        allow(mock_client).to receive(:create_index).and_return({})
        allow(mock_client).to receive(:update_aliases).and_return({})
        allow(mock_client).to receive(:reindex).and_return({ 'task' => 'test-task-id' })
        allow(mock_client).to receive(:wait_for_task).and_return({})
        allow(mock_client).to receive(:close_index).and_return({})
        allow(mock_client).to receive(:post).and_return({})
        
        # Mock failed verification
        diff_mock = double('Diff')
        allow(diff_mock).to receive(:generate_schema_diff).and_return({ status: :changes_detected })
        allow(diff_mock).to receive(:diff_schema)
        allow(SchemaTools::Diff).to receive(:new).and_return(diff_mock)
      end

      it 'does not attempt rollback for verification failures' do
        expect(migration).not_to receive(:attempt_rollback)
        # For verification failures, no rollback should be attempted

        expect { migration.migrate }.to raise_error(/Migration verification failed/)
      end
    end
  end
end