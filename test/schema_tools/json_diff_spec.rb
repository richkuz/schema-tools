require_relative '../spec_helper'
require 'schema_tools/json_diff'

RSpec.describe SchemaTools::JsonDiff do
  let(:diff) { SchemaTools::JsonDiff.new }

  describe '#generate_diff' do

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