require_relative '../spec_helper'
require 'schema_tools/json_diff'

RSpec.describe SchemaTools::JsonDiff do
  let(:diff) { SchemaTools::JsonDiff.new }

  describe '#generate_diff' do
    context 'when ignoring noisy metadata keys' do
      it 'ignores _meta.schemurai_revision keys' do
        old_data = {
          'settings' => { 'index' => { 'number_of_shards' => 1 } },
          '_meta' => {
            'schemurai_revision' => {
              'revision' => '1',
              'reindex_started_at' => '2024-01-01T00:00:00Z',
              'reindex_completed_at' => '2024-01-01T00:01:00Z',
              'revision_applied_at' => '2024-01-01T00:00:30Z'
            }
          }
        }

        new_data = {
          'settings' => { 'index' => { 'number_of_shards' => 1 } },
          '_meta' => {
            'schemurai_revision' => {
              'revision' => '2',
              'reindex_started_at' => '2024-01-02T00:00:00Z',
              'reindex_completed_at' => '2024-01-02T00:01:00Z',
              'revision_applied_at' => '2024-01-02T00:00:30Z'
            }
          }
        }

        result = diff.generate_diff(old_data, new_data)
        expect(result).to eq("No changes detected")
      end

      it 'shows changes when non-ignored keys change' do
        old_data = {
          'settings' => { 'index' => { 'number_of_shards' => 1 } },
          '_meta' => {
            'schemurai_revision' => {
              'revision' => '1',
              'reindex_started_at' => '2024-01-01T00:00:00Z'
            }
          }
        }

        new_data = {
          'settings' => { 'index' => { 'number_of_shards' => 2 } },
          '_meta' => {
            'schemurai_revision' => {
              'revision' => '2',
              'reindex_started_at' => '2024-01-02T00:00:00Z'
            }
          }
        }

        result = diff.generate_diff(old_data, new_data)
        expect(result).to include("🔄 MODIFIED: settings.index.number_of_shards")
        expect(result).to include("Old value:")
        expect(result).to include("1")
        expect(result).to include("New value:")
        expect(result).to include("2")
      end

      it 'ignores all specified noisy keys' do
        ignored_keys = [
          '_meta.schemurai_revision.reindex_completed_at',
          '_meta.schemurai_revision.reindex_started_at', 
          '_meta.schemurai_revision.revision',
          '_meta.schemurai_revision.revision_applied_at'
        ]

        ignored_keys.each do |key_path|
          old_data = { 'settings' => { 'index' => { 'number_of_shards' => 1 } } }
          new_data = { 'settings' => { 'index' => { 'number_of_shards' => 1 } } }
          
          # Set the ignored key in both old and new data
          set_nested_value(old_data, key_path, 'old_value')
          set_nested_value(new_data, key_path, 'new_value')
          
          result = diff.generate_diff(old_data, new_data)
          expect(result).to eq("No changes detected"), "Expected #{key_path} to be ignored"
        end
      end
    end

    context 'when no changes exist' do
      it 'returns no changes detected' do
        data = { 'settings' => { 'index' => { 'number_of_shards' => 1 } } }
        result = diff.generate_diff(data, data)
        expect(result).to eq("No changes detected")
      end
    end

    context 'when changes exist' do
      it 'shows added fields' do
        old_data = { 'settings' => { 'index' => { 'number_of_shards' => 1 } } }
        new_data = { 'settings' => { 'index' => { 'number_of_shards' => 1, 'number_of_replicas' => 2 } } }
        
        result = diff.generate_diff(old_data, new_data)
        expect(result).to include("➕ ADDED: settings.index.number_of_replicas")
      end

      it 'shows removed fields' do
        old_data = { 'settings' => { 'index' => { 'number_of_shards' => 1, 'number_of_replicas' => 2 } } }
        new_data = { 'settings' => { 'index' => { 'number_of_shards' => 1 } } }
        
        result = diff.generate_diff(old_data, new_data)
        expect(result).to include("➖ REMOVED: settings.index.number_of_replicas")
      end
    end
  end

  private

  def set_nested_value(obj, key_path, value)
    keys = key_path.split('.')
    current = obj
    
    keys[0...-1].each do |key|
      current[key] ||= {}
      current = current[key]
    end
    
    current[keys.last] = value
  end
end