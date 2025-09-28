require_relative '../spec_helper'
require 'schema_tools/schema_definer'
require 'schema_tools/client'
require 'schema_tools/schema_manager'
require 'tempfile'
require 'webmock/rspec'

RSpec.describe SchemaTools::SchemaDefiner do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config::SCHEMAS_PATH }
  let(:client) { instance_double(SchemaTools::Client) }
  let(:schema_manager) { SchemaTools::SchemaManager.new() }
  let(:definer) { SchemaTools::SchemaDefiner.new(client, schema_manager) }
  
  before do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
    allow(client).to receive(:instance_variable_get).with(:@url).and_return('http://localhost:9200')
  end
  
  after do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end

  describe '#extract_base_name' do
    it 'removes version suffix from index name' do
      expect(definer.send(:extract_base_name, 'products-3')).to eq('products')
      expect(definer.send(:extract_base_name, 'users-1')).to eq('users')
      expect(definer.send(:extract_base_name, 'products')).to eq('products')
    end
  end

  describe '#find_latest_index_version' do
    before do
      allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([
        { 'index' => 'products' },
        { 'index' => 'products-1' },
        { 'index' => 'products-3' },
        { 'index' => 'products-2' }
      ])
    end

    it 'finds the latest version of an index' do
      result = definer.send(:find_latest_index_version, 'products')
      expect(result).to eq('products-3')
    end

    it 'returns nil when no indices found' do
      allow(client).to receive(:get).and_return([])
      result = definer.send(:find_latest_index_version, 'nonexistent')
      expect(result).to be_nil
    end
  end

  describe '#extract_live_index_data' do
    before do
      allow(client).to receive(:get_index_settings).with('test-index').and_return({
        'index' => { 'number_of_shards' => 1 }
      })
      allow(client).to receive(:get).with('/test-index/_mapping').and_return({
        'test-index' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'keyword' }
            }
          }
        }
      })
      allow(client).to receive(:get_stored_scripts).and_return({
        'script1' => 'ctx._source.test = "value"',
        'script2' => 'ctx._source.another = "test"'
      })
    end

    it 'extracts settings, mappings, and painless scripts from live index' do
      result = definer.send(:extract_live_index_data, 'test-index')
      
      expect(result[:settings]).to eq({ 'index' => { 'number_of_shards' => 1 } })
      expect(result[:mappings]).to eq({
        'properties' => {
          'id' => { 'type' => 'keyword' }
        }
      })
      expect(result[:painless_scripts]).to eq({
        'script1' => 'ctx._source.test = "value"',
        'script2' => 'ctx._source.another = "test"'
      })
    end
  end

  describe '#find_latest_schema_definition' do
    before do
      FileUtils.mkdir_p(File.join(schemas_path, 'products'))
      FileUtils.mkdir_p(File.join(schemas_path, 'products-1'))
      FileUtils.mkdir_p(File.join(schemas_path, 'products-3'))
      FileUtils.mkdir_p(File.join(schemas_path, 'products-2'))
    end

    it 'finds the latest schema definition by version number' do
      result = definer.send(:find_latest_schema_definition, 'products')
      expect(result).to eq(File.join(schemas_path, 'products-3'))
    end

    it 'returns nil when no schema definitions found' do
      result = definer.send(:find_latest_schema_definition, 'nonexistent')
      expect(result).to be_nil
    end
  end

  describe '#schemas_match?' do
    let(:live_data) do
      {
        settings: { 'index' => { 'number_of_shards' => 1 } },
        mappings: { 'properties' => { 'id' => { 'type' => 'keyword' } } }
      }
    end

    let(:schema_data) do
      {
        settings: { 'index' => { 'number_of_shards' => 1 } },
        mappings: { 'properties' => { 'id' => { 'type' => 'keyword' } } }
      }
    end

    it 'returns true when schemas match' do
      expect(definer.send(:schemas_match?, live_data, schema_data)).to be true
    end

    it 'returns false when settings differ' do
      schema_data[:settings] = { 'index' => { 'number_of_shards' => 2 } }
      expect(definer.send(:schemas_match?, live_data, schema_data)).to be false
    end

    it 'returns false when mappings differ' do
      schema_data[:mappings] = { 'properties' => { 'id' => { 'type' => 'text' } } }
      expect(definer.send(:schemas_match?, live_data, schema_data)).to be false
    end
  end


  describe '#generate_next_index_name' do
    before do
      FileUtils.mkdir_p(File.join(schemas_path, 'products-2'))
    end

    it 'generates next index name based on latest schema' do
      result = definer.send(:generate_next_index_name, 'products')
      expect(result).to eq('products-3')
    end

    it 'generates products-2 when no existing schema' do
      result = definer.send(:generate_next_index_name, 'newindex')
      expect(result).to eq('newindex-2')
    end
  end

  describe '#generate_next_revision_number' do
    before do
      FileUtils.mkdir_p(File.join(schemas_path, 'test-index', 'revisions', '1'))
      FileUtils.mkdir_p(File.join(schemas_path, 'test-index', 'revisions', '3'))
    end

    it 'generates next revision number' do
      result = definer.send(:generate_next_revision_number, File.join(schemas_path, 'test-index'))
      expect(result).to eq(4)
    end

    it 'returns 1 when no revisions exist' do
      result = definer.send(:generate_next_revision_number, File.join(schemas_path, 'new-index'))
      expect(result).to eq(1)
    end
  end

  describe '#generate_example_schema_files' do
    let(:data) do
      {
        settings: { 'index' => { 'number_of_shards' => 1 } },
        mappings: { 'properties' => { 'id' => { 'type' => 'keyword' } } },
        painless_scripts: {}
      }
    end

    it 'creates all necessary schema files' do
      expect { definer.send(:generate_example_schema_files, 'test-index', data) }
        .to output(/Generated example schema definition files/).to_stdout

      index_path = File.join(schemas_path, 'test-index')
      expect(File.exist?(File.join(index_path, 'index.json'))).to be true
      expect(File.exist?(File.join(index_path, 'reindex.painless'))).to be true
      expect(File.exist?(File.join(index_path, 'revisions', '1', 'settings.json'))).to be true
      expect(File.exist?(File.join(index_path, 'revisions', '1', 'mappings.json'))).to be true
      expect(File.exist?(File.join(index_path, 'revisions', '1', 'painless_scripts', 'README.txt'))).to be true
      expect(File.exist?(File.join(index_path, 'revisions', '1', 'diff_output.txt'))).to be true
    end

    it 'creates correct index.json content' do
      definer.send(:generate_example_schema_files, 'test-index', data)
      
      index_config = JSON.parse(File.read(File.join(schemas_path, 'test-index', 'index.json')))
      expect(index_config['index_name']).to eq('test-index')
      expect(index_config['from_index_name']).to be_nil
    end
  end

  describe '#generate_revision_files' do
    let(:data) do
      {
        settings: { 'index' => { 'number_of_shards' => 2 } },
        mappings: { 'properties' => { 'name' => { 'type' => 'text' } } },
        painless_scripts: {}
      }
    end

    before do
      FileUtils.mkdir_p(File.join(schemas_path, 'existing-index'))
    end

    it 'creates revision files in existing schema' do
      expect { definer.send(:generate_revision_files, File.join(schemas_path, 'existing-index'), 2, data) }
        .to output(/Generated example schema definition files/).to_stdout

      revision_path = File.join(schemas_path, 'existing-index', 'revisions', '2')
      expect(File.exist?(File.join(revision_path, 'settings.json'))).to be true
      expect(File.exist?(File.join(revision_path, 'mappings.json'))).to be true
      expect(File.exist?(File.join(revision_path, 'painless_scripts', 'README.txt'))).to be true
      expect(File.exist?(File.join(revision_path, 'diff_output.txt'))).to be true
    end
  end

  describe '#define_schema_for_existing_index' do
    before do
      allow(client).to receive(:index_exists?).with('products').and_return(false)
      allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([
        { 'index' => 'products-3' }
      ])
      allow(client).to receive(:get_index_settings).with('products-3').and_return({
        'index' => { 'number_of_shards' => 1 }
      })
      allow(client).to receive(:get).with('/products-3/_mapping').and_return({
        'products-3' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'keyword' }
            }
          }
        }
      })
      allow(client).to receive(:get_stored_scripts).and_return({})
    end

    it 'handles case when no schema definition exists' do
      expect { definer.define_schema_for_existing_index('products') }
        .to output(/No schema definition exists for "products-3"/).to_stdout
    end

    it 'handles case when index not found' do
      allow(client).to receive(:index_exists?).with('nonexistent').and_return(false)
      allow(client).to receive(:get).with('/_cat/indices/nonexistent*?format=json').and_return([])
      
      expect { definer.define_schema_for_existing_index('nonexistent') }
        .to output(/Index "nonexistent" not found/).to_stdout
    end
  end

  describe '#define_example_schema_for_new_index' do
    it 'handles case when no schema definition exists' do
      expect { definer.define_example_schema_for_new_index('newindex') }
        .to output(/No schema definition exists for "newindex"/).to_stdout
    end

    it 'handles case when schema definition exists' do
      FileUtils.mkdir_p(File.join(schemas_path, 'existing', 'revisions', '1'))
      
      expect { definer.define_example_schema_for_new_index('existing') }
        .to output(/Latest schema definition of "existing" is defined/).to_stdout
    end
  end

  describe '#define_breaking_change_schema' do
    it 'handles case when no schema definition exists' do
      expect { definer.define_breaking_change_schema('nonexistent') }
        .to output(/No schema definition exists for "nonexistent"/).to_stdout
    end

    it 'generates breaking change schema' do
      FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      
      expect { definer.define_breaking_change_schema('existing') }
        .to output(/Generated example schema definition files/).to_stdout
    end
  end

  describe '#define_non_breaking_change_schema' do
    it 'handles case when no schema definition exists' do
      expect { definer.define_non_breaking_change_schema('nonexistent') }
        .to output(/No schema definition exists for "nonexistent"/).to_stdout
    end

    it 'generates non-breaking change schema' do
      FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      
      expect { definer.define_non_breaking_change_schema('existing') }
        .to output(/Generated example schema definition files/).to_stdout
    end
  end

  describe '#write_painless_scripts' do
    let(:scripts_dir) { File.join(temp_dir, 'scripts') }

    it 'writes painless scripts when scripts are provided' do
      painless_scripts = {
        'script1' => 'ctx._source.test = "value"',
        'script2' => 'ctx._source.another = "test"'
      }
      
      definer.send(:write_painless_scripts, scripts_dir, painless_scripts)
      
      expect(File.exist?(File.join(scripts_dir, 'script1.painless'))).to be true
      expect(File.exist?(File.join(scripts_dir, 'script2.painless'))).to be true
      expect(File.read(File.join(scripts_dir, 'script1.painless'))).to eq('ctx._source.test = "value"')
      expect(File.read(File.join(scripts_dir, 'script2.painless'))).to eq('ctx._source.another = "test"')
    end

    it 'writes instruction file when no scripts provided' do
      definer.send(:write_painless_scripts, scripts_dir, {})
      
      expect(File.exist?(File.join(scripts_dir, 'README.txt'))).to be true
      expect(File.read(File.join(scripts_dir, 'README.txt'))).to include('Add into this folder all painless scripts')
      expect(File.read(File.join(scripts_dir, 'README.txt'))).to include('Painless script files must end with the extension .painless')
    end
  end
end