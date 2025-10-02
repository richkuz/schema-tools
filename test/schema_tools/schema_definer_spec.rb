require_relative '../spec_helper'
require 'schema_tools/schema_definer'
require 'schema_tools/client'
require 'schema_tools/schema_files'
require 'tempfile'
require 'webmock/rspec'

RSpec.describe SchemaTools::SchemaDefiner do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config.schemas_path }
  let(:client) { instance_double(SchemaTools::Client) }
  let(:definer) { SchemaTools::SchemaDefiner.new(client) }
  
  before do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
    allow(client).to receive(:url).and_return('http://localhost:9200')
  end
  
  after do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end

  describe '#define_schema_for_existing_live_index' do
    context 'when no live indices exist' do
      before do
        allow(client).to receive(:index_exists?).with('products').and_return(false)
        allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([])
      end

      it 'reports no live indexes found' do
        expect { definer.define_schema_for_existing_live_index('products') }
          .to output(/Could not find a live index named products for which to define a schema revision/).to_stdout
      end
    end

    context 'when live indices exist' do
      before do
        allow(client).to receive(:index_exists?).with('products').and_return(true)
        allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([
          { 'index' => 'products' },
          { 'index' => 'products-1' },
          { 'index' => 'products-3' },
          { 'index' => 'products-2' }
        ])
        allow(client).to receive(:get_index_settings).with('products').and_return({
          'index' => { 'number_of_shards' => 1 }
        })
        allow(client).to receive(:get).with('/products/_mapping').and_return({
          'products' => { 'mappings' => { 'properties' => { 'id' => { 'type' => 'keyword' } } } }
        })
      end

      it 'identifies the latest versioned index' do
        expect { definer.define_schema_for_existing_live_index('products') }
          .to output(/Extracting live settings and mappings from index "products"/).to_stdout
      end
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
    end

    it 'extracts settings and mappings from live index' do
      result = definer.send(:extract_live_index_data, 'test-index')
      
      expect(result[:settings]).to eq({ 'index' => { 'number_of_shards' => 1 } })
      expect(result[:mappings]).to eq({
        'properties' => {
          'id' => { 'type' => 'keyword' }
        }
      })
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

    context 'when all components match' do
      it 'returns true' do
        expect(definer.send(:schemas_match?, live_data, schema_data)).to be true
      end
    end

    context 'when settings differ' do
      before do
        schema_data[:settings] = { 'index' => { 'number_of_shards' => 2 } }
      end

      it 'returns false' do
        expect(definer.send(:schemas_match?, live_data, schema_data)).to be false
      end
    end

    context 'when mappings differ' do
      before do
        schema_data[:mappings] = { 'properties' => { 'id' => { 'type' => 'text' } } }
      end

      it 'returns false' do
        expect(definer.send(:schemas_match?, live_data, schema_data)).to be false
      end
    end
  end

  describe '#define_example_schema_for_new_index' do
    context 'when no schema definition exists' do
      it 'creates new schema files' do
        expect { definer.define_example_schema_for_new_index('newindex') }
          .to output(/No schema definition exists for "newindex"/).to_stdout

        # Verify files were created
        index_path = File.join(schemas_path, 'newindex')
        expect(File.exist?(File.join(index_path, 'index.json'))).to be true
        expect(File.exist?(File.join(index_path, 'revisions', '1', 'settings.json'))).to be true
        expect(File.exist?(File.join(index_path, 'revisions', '1', 'mappings.json'))).to be true
      end
    end

    context 'when schema definition exists' do
      before do
        FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1'))
      end

      it 'reports existing schema' do
        expect { definer.define_example_schema_for_new_index('products') }
          .to output(/Latest schema definition of "products" is defined/).to_stdout
      end
    end
  end


  describe '#define_breaking_change_schema' do
    context 'when schema definition exists' do
      before do
        revision_dir = FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1'))
        File.write(File.join(revision_dir, 'settings.json'), { 'settings' => {} }.to_json)
        File.write(File.join(revision_dir, 'mappings.json'), { 'mappings' => {} }.to_json)
      end

      it 'generates breaking change schema' do
        expect { definer.define_breaking_change_schema('products') }
          .to output(/Latest schema definition found/).to_stdout

        # Should create a new index with next version number
        expect(File.exist?(File.join(schemas_path, 'products-4', 'index.json'))).to be true
      end

      it 'sets from_index_name to the previous index name' do
        expect { definer.define_breaking_change_schema('products') }
          .to output(/Latest schema definition found/).to_stdout

        # Read the generated index.json and verify from_index_name is set
        index_json_path = File.join(schemas_path, 'products-4', 'index.json')
        index_config = JSON.parse(File.read(index_json_path))
        
        expect(index_config['index_name']).to eq('products-4')
        expect(index_config['from_index_name']).to eq('products-3')
      end
    end

    context 'when no schema definition exists' do
      it 'reports no index folder exists' do
        expect { definer.define_breaking_change_schema('nonexistent') }
          .to output(/No index folder exists starting with "nonexistent"/).to_stdout
      end
    end
  end

  describe '#define_non_breaking_change_schema' do
    context 'when schema definition exists' do
      before do
        revision_dir = FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1'))
        File.write(File.join(revision_dir, 'settings.json'), { 'settings' => {} }.to_json)
        File.write(File.join(revision_dir, 'mappings.json'), { 'mappings' => {} }.to_json)
      end

      it 'generates non-breaking change schema' do
        expect { definer.define_non_breaking_change_schema('products') }
          .to output(/Latest schema definition found/).to_stdout

        # Should create a new revision in the same index
        expect(File.exist?(File.join(schemas_path, 'products-3', 'revisions', '2', 'settings.json'))).to be true
      end
    end

    context 'when no schema definition exists' do
      it 'reports no index folder exists' do
        expect { definer.define_non_breaking_change_schema('nonexistent') }
          .to output(/No index folder exists starting with "nonexistent"/).to_stdout
      end
    end
  end


  describe '#define_schema_for_existing_live_index' do
    before do
      allow(client).to receive(:index_exists?).with('products').and_return(true)
      allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([
        { 'index' => 'products-3' }
      ])
      allow(client).to receive(:get_index_settings).with('products').and_return({
        'index' => { 'number_of_shards' => 1 }
      })
      allow(client).to receive(:get).with('/products/_mapping').and_return({
        'products' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'keyword' }
            }
          }
        }
      })
    end

    it 'handles case when no schema definition exists' do
      expect { definer.define_schema_for_existing_live_index('products') }
        .to output(/Extracting live settings and mappings from index "products"/).to_stdout
    end

    it 'handles case when index not found' do
      allow(client).to receive(:index_exists?).with('nonexistent').and_return(false)
      allow(client).to receive(:get).with('/_cat/indices/nonexistent*?format=json').and_return([])
      
      expect { definer.define_schema_for_existing_live_index('nonexistent') }
        .to output(/Could not find a live index named nonexistent for which to define a schema revision/).to_stdout
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
        .to output(/No index folder exists starting with "nonexistent"/).to_stdout
    end

    it 'generates breaking change schema' do
      revision_dir = FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      File.write(File.join(revision_dir, 'settings.json'), { 'settings' => {} }.to_json)
      File.write(File.join(revision_dir, 'mappings.json'), { 'mappings' => {} }.to_json)

      expect { definer.define_breaking_change_schema('existing') }
        .to output(/Generated example schema definition files/).to_stdout
    end
  end

  describe '#define_non_breaking_change_schema' do
    it 'handles case when no schema definition exists' do
      expect { definer.define_non_breaking_change_schema('nonexistent') }
        .to output(/No index folder exists starting with "nonexistent"/).to_stdout
    end

    it 'generates non-breaking change schema' do
      revision_dir = FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      File.write(File.join(revision_dir, 'settings.json'), { 'settings' => {} }.to_json)
      File.write(File.join(revision_dir, 'mappings.json'), { 'mappings' => {} }.to_json)
      
      expect { definer.define_non_breaking_change_schema('existing') }
        .to output(/Generated example schema definition files/).to_stdout
    end
  end

  describe '#filter_schemurai_metadata' do
    it 'removes schemurai_revision from _meta section' do
      mappings = {
        'properties' => { 'id' => { 'type' => 'keyword' } },
        '_meta' => {
          'schemurai_revision' => { 'revision' => 'test/revisions/1' },
          'custom_metadata' => 'value'
        }
      }
      
      filtered = definer.send(:filter_schemurai_metadata, mappings)
      
      expect(filtered['_meta']['schemurai_revision']).to be_nil
      expect(filtered['_meta']['custom_metadata']).to eq('value')
    end

    it 'removes entire _meta section when it becomes empty after removing schemurai_revision' do
      mappings = {
        'properties' => { 'id' => { 'type' => 'keyword' } },
        '_meta' => {
          'schemurai_revision' => { 'revision' => 'test/revisions/1' }
        }
      }
      
      filtered = definer.send(:filter_schemurai_metadata, mappings)
      
      expect(filtered['_meta']).to be_nil
    end

    it 'preserves other _meta content when removing schemurai_revision' do
      mappings = {
        'properties' => { 'id' => { 'type' => 'keyword' } },
        '_meta' => {
          'schemurai_revision' => { 'revision' => 'test/revisions/1' },
          'custom_field' => 'custom_value',
          'another_field' => 'another_value'
        }
      }
      
      filtered = definer.send(:filter_schemurai_metadata, mappings)
      
      expect(filtered['_meta']['schemurai_revision']).to be_nil
      expect(filtered['_meta']['custom_field']).to eq('custom_value')
      expect(filtered['_meta']['another_field']).to eq('another_value')
    end
  end

end