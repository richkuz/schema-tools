require_relative '../spec_helper'
require 'schema_tools/schema_definer'
require 'schema_tools/client'
require 'schema_tools/schema_files'
require 'tempfile'
require 'webmock/rspec'

RSpec.describe SchemaTools::SchemaDefiner do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config::SCHEMAS_PATH }
  let(:client) { instance_double(SchemaTools::Client) }
  let(:definer) { SchemaTools::SchemaDefiner.new(client) }
  
  before do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
    allow(client).to receive(:url).and_return('http://localhost:9200')
  end
  
  after do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end

  describe '#define_schema_for_existing_index' do
    context 'when no live indices exist' do
      before do
        allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([])
      end

      it 'reports no live indexes found' do
        expect { definer.define_schema_for_existing_index('products') }
          .to output(/No live indexes found starting with "products"/).to_stdout
      end
    end

    context 'when live indices exist' do
      before do
        allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([
          { 'index' => 'products' },
          { 'index' => 'products-1' },
          { 'index' => 'products-3' },
          { 'index' => 'products-2' }
        ])
        allow(client).to receive(:get_index_settings).with('products-3').and_return({
          'index' => { 'number_of_shards' => 1 }
        })
        allow(client).to receive(:get).with('/products-3/_mapping').and_return({
          'products-3' => { 'mappings' => { 'properties' => { 'id' => { 'type' => 'keyword' } } } }
        })
        allow(client).to receive(:get_stored_scripts).and_return({})
      end

      it 'identifies the latest versioned index' do
        expect { definer.define_schema_for_existing_index('products') }
          .to output(/Index "products-3" is the latest versioned index name found/).to_stdout
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
        FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1'))
      end

      it 'generates breaking change schema' do
        expect { definer.define_breaking_change_schema('products') }
          .to output(/Latest schema definition found/).to_stdout

        # Should create a new index with next version number
        expect(File.exist?(File.join(schemas_path, 'products-4', 'index.json'))).to be true
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
        FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1'))
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
        .to output(/Index "products-3" is the latest versioned index name found/).to_stdout
    end

    it 'handles case when index not found' do
      allow(client).to receive(:index_exists?).with('nonexistent').and_return(false)
      allow(client).to receive(:get).with('/_cat/indices/nonexistent*?format=json').and_return([])
      
      expect { definer.define_schema_for_existing_index('nonexistent') }
        .to output(/No live indexes found starting with "nonexistent"/).to_stdout
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
      FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      
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
      FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      
      expect { definer.define_non_breaking_change_schema('existing') }
        .to output(/Generated example schema definition files/).to_stdout
    end
  end

end