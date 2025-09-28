require_relative 'spec_helper'
require 'schema_tools/client'
require 'schema_tools/schema_manager'
require 'schema_tools/schema_revision'
require 'schema_tools/config'
require 'tempfile'

RSpec.describe 'Integration Tests' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:client) { SchemaTools::Client.new('http://localhost:9200') }
  let(:manager) { SchemaTools::SchemaManager.new(schemas_path) }
  
  before do
    FileUtils.mkdir_p(schemas_path)
    # Mock the SCHEMAS_PATH for testing
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    allow(SchemaTools::SchemaRevision).to receive(:schemas_path).and_return(schemas_path)
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  describe 'end-to-end migration flow' do
    it 'simulates a complete migration workflow' do
      index_name = 'test-products-1'
      index_dir = File.join(schemas_path, index_name)
      revisions_dir = File.join(index_dir, 'revisions', '1')
      FileUtils.mkdir_p(revisions_dir)
      
      index_config = {
        'index_name' => index_name,
        'from_index_name' => nil
      }
      
      settings = {
        'index' => {
          'number_of_shards' => 1,
          'number_of_replicas' => 0
        }
      }
      
      mappings = {
        'properties' => {
          'id' => { 'type' => 'keyword' },
          'name' => { 'type' => 'text' }
        }
      }
      
      File.write(File.join(index_dir, 'index.json'), index_config.to_json)
      File.write(File.join(revisions_dir, 'settings.json'), settings.to_json)
      File.write(File.join(revisions_dir, 'mappings.json'), mappings.to_json)
      
      stub_request(:get, "http://localhost:9200/#{index_name}")
        .to_return(status: 404)
      
      stub_request(:put, "http://localhost:9200/#{index_name}")
        .with(body: { settings: settings, mappings: mappings }.to_json)
        .to_return(status: 200, body: { 'acknowledged' => true }.to_json)
      
      stub_request(:put, "http://localhost:9200/#{index_name}/_settings")
        .to_return(status: 200, body: { 'acknowledged' => true }.to_json)
      
      config = manager.get_index_config(index_name)
      expect(config).to eq(index_config)
      
      latest_schema_revision = SchemaTools::SchemaRevision.for_latest_revision(index_name)
      expect(latest_schema_revision.revision_absolute_path).to eq(revisions_dir)
      
      revision_files = manager.get_revision_files(latest_schema_revision.revision_absolute_path)
      expect(revision_files[:settings]).to eq(settings)
      expect(revision_files[:mappings]).to eq(mappings)
      
      expect(client.index_exists?(index_name)).to be false
      
      response = client.create_index(index_name, settings, mappings)
      expect(response).to eq({ 'acknowledged' => true })
    end
  end
  
  describe 'reindex workflow' do
    it 'simulates reindexing from one index to another' do
      source_index = 'products-1'
      dest_index = 'products-2'
      
      index_dir = File.join(schemas_path, dest_index)
      FileUtils.mkdir_p(index_dir)
      
      index_config = {
        'index_name' => dest_index,
        'from_index_name' => source_index
      }
      
      File.write(File.join(index_dir, 'index.json'), index_config.to_json)
      
      reindex_script = 'ctx._source.new_field = "value"'
      File.write(File.join(index_dir, 'reindex.painless'), reindex_script)
      
      stub_request(:post, 'http://localhost:9200/_reindex')
        .with(body: {
          source: { index: source_index },
          dest: { index: dest_index },
          script: { source: reindex_script }
        }.to_json)
        .to_return(status: 200, body: { 'task' => 'task_id_123' }.to_json)
      
      stub_request(:get, 'http://localhost:9200/_tasks/task_id_123')
        .to_return(status: 200, body: { 'completed' => true }.to_json)
      
      config = manager.get_index_config(dest_index)
      expect(config).to eq(index_config)
      
      script = manager.get_reindex_script(dest_index)
      expect(script).to eq(reindex_script)
      
      response = client.reindex(source_index, dest_index, script)
      expect(response).to eq({ 'task' => 'task_id_123' })
      
      task_status = client.get_task_status('task_id_123')
      expect(task_status).to eq({ 'completed' => true })
    end
  end
end