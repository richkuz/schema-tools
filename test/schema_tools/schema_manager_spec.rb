require_relative '../spec_helper'
require 'schema_tools/schema_manager'
require 'tempfile'

RSpec.describe SchemaTools::SchemaManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:manager) { SchemaTools::SchemaManager.new(schemas_path) }
  
  before do
    FileUtils.mkdir_p(schemas_path)
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  describe '#get_index_config' do
    it 'returns index configuration when present' do
      index_dir = File.join(schemas_path, 'test-index')
      FileUtils.mkdir_p(index_dir)
      
      config = { 'index_name' => 'test-index', 'from_index_name' => nil }
      File.write(File.join(index_dir, 'index.json'), config.to_json)
      
      result = manager.get_index_config('test-index')
      expect(result).to eq(config)
    end
    
    it 'returns nil when index configuration not found' do
      result = manager.get_index_config('nonexistent')
      expect(result).to be_nil
    end
  end
  
  describe '#get_latest_revision_path' do
    it 'returns latest revision path' do
      index_dir = File.join(schemas_path, 'test-index')
      revisions_dir = File.join(index_dir, 'revisions')
      FileUtils.mkdir_p(File.join(revisions_dir, '1'))
      FileUtils.mkdir_p(File.join(revisions_dir, '2'))
      
      result = manager.get_latest_revision_path('test-index')
      expect(result).to eq(File.join(revisions_dir, '2'))
    end
    
    it 'returns nil when no revisions found' do
      index_dir = File.join(schemas_path, 'test-index')
      FileUtils.mkdir_p(index_dir)
      
      result = manager.get_latest_revision_path('test-index')
      expect(result).to be_nil
    end
  end
  
  describe '#get_revision_files' do
    it 'loads revision files correctly' do
      revision_dir = File.join(temp_dir, 'revision')
      FileUtils.mkdir_p(revision_dir)
      FileUtils.mkdir_p(File.join(revision_dir, 'painless_scripts'))
      
      settings = { 'index' => { 'number_of_shards' => 1 } }
      mappings = { 'properties' => { 'id' => { 'type' => 'keyword' } } }
      
      File.write(File.join(revision_dir, 'settings.json'), settings.to_json)
      File.write(File.join(revision_dir, 'mappings.json'), mappings.to_json)
      File.write(File.join(revision_dir, 'painless_scripts', 'test.painless'), 'ctx._source.test = "value"')
      
      result = manager.get_revision_files(revision_dir)
      
      expect(result[:settings]).to eq(settings)
      expect(result[:mappings]).to eq(mappings)
      expect(result[:painless_scripts]).to eq({ 'test' => 'ctx._source.test = "value"' })
    end
  end
  
  describe '#generate_diff_output' do
    it 'generates diff output file' do
      current_dir = File.join(temp_dir, 'current')
      previous_dir = File.join(temp_dir, 'previous')
      FileUtils.mkdir_p(current_dir)
      FileUtils.mkdir_p(previous_dir)
      
      current_settings = { 'index' => { 'number_of_shards' => 2 } }
      previous_settings = { 'index' => { 'number_of_shards' => 1 } }
      
      File.write(File.join(current_dir, 'settings.json'), current_settings.to_json)
      File.write(File.join(current_dir, 'mappings.json'), {}.to_json)
      File.write(File.join(previous_dir, 'settings.json'), previous_settings.to_json)
      File.write(File.join(previous_dir, 'mappings.json'), {}.to_json)
      
      result = manager.generate_diff_output('test-index', current_dir, previous_dir)
      
      expect(result).to include('Settings Diff')
      expect(result).to include('Mappings Diff')
      expect(File.exist?(File.join(current_dir, 'diff_output.txt'))).to be true
    end
  end
end