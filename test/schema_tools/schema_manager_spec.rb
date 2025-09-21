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

  describe '#load_painless_scripts' do
    it 'only loads .painless files and ignores other files' do
      scripts_dir = File.join(temp_dir, 'scripts')
      FileUtils.mkdir_p(scripts_dir)
      
      # Create various file types
      File.write(File.join(scripts_dir, 'script1.painless'), 'ctx._source.test = "value1"')
      File.write(File.join(scripts_dir, 'script2.painless'), 'ctx._source.test = "value2"')
      File.write(File.join(scripts_dir, 'README.txt'), 'Instructions for scripts')
      File.write(File.join(scripts_dir, 'config.json'), '{"setting": "value"}')
      File.write(File.join(scripts_dir, 'script3.txt'), 'This is not a painless script')
      
      result = manager.send(:load_painless_scripts, scripts_dir)
      
      expect(result).to eq({
        'script1' => 'ctx._source.test = "value1"',
        'script2' => 'ctx._source.test = "value2"'
      })
      expect(result.keys).not_to include('README')
      expect(result.keys).not_to include('config')
      expect(result.keys).not_to include('script3')
    end
  end

  describe '#generate_scripts_diff' do
    it 'only diffs .painless files' do
      old_scripts = {
        'script1' => 'ctx._source.test = "value1"',
        'script2' => 'ctx._source.test = "value2"'
      }
      new_scripts = {
        'script1' => 'ctx._source.test = "value1"',
        'script2' => 'ctx._source.test = "value2_modified"',
        'script3' => 'ctx._source.test = "value3"'
      }
      
      result = manager.send(:generate_scripts_diff, old_scripts, new_scripts)
      
      expect(result).to include('Modified script: script2')
      expect(result).to include('Added script: script3')
      expect(result).not_to include('README')
      expect(result).not_to include('config')
    end
  end
end