require_relative '../spec_helper'
require 'schema_tools/schema_definer'
require 'schema_tools/client'
require 'schema_tools/schema_files'
require 'tempfile'
require 'webmock/rspec'

RSpec.describe 'Breaking Change Detection Integration' do
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

  describe 'breaking change detection in schema definer' do
    before do
      FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1'))
      
      settings = {
        'index' => {
          'number_of_shards' => 1,
          'number_of_replicas' => 0
        }
      }
      
      mappings = {
        'properties' => {
          'id' => { 'type' => 'keyword', 'index' => true },
          'name' => { 'type' => 'text' }
        }
      }
      
      File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'settings.json'), settings.to_json)
      File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'mappings.json'), mappings.to_json)
      
      allow(client).to receive(:index_exists?).with('products').and_return(false)
      allow(client).to receive(:get).with('/_cat/indices/products*?format=json').and_return([
        { 'index' => 'products-3' }
      ])
      allow(client).to receive(:get_index_settings).with('products-3').and_return(settings)
      allow(client).to receive(:get).with('/products-3/_mapping').and_return({
        'products-3' => {
          'mappings' => mappings
        }
      })
      allow(client).to receive(:get_stored_scripts).and_return({})
    end

    it 'detects breaking changes in field types' do
      allow(client).to receive(:get_index_settings).with('products-3').and_return({
        'index' => {
          'number_of_shards' => 1,
          'number_of_replicas' => 0
        }
      })
      
      allow(client).to receive(:get).with('/products-3/_mapping').and_return({
        'products-3' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'text' },  # Changed from keyword to text
              'name' => { 'type' => 'text' }
            }
          }
        }
      })

      expect { definer.define_schema_for_existing_index('products') }
        .to output(/Index settings and mappings constitute a breaking change/).to_stdout

      # Should generate new index for breaking change
      index_path = File.join(schemas_path, 'products-4')
      expect(File.exist?(File.join(index_path, 'index.json'))).to be true
    end

    it 'detects breaking changes in immutable index settings' do
      allow(client).to receive(:get_index_settings).with('products-3').and_return({
        'index' => {
          'number_of_shards' => 2,  # Changed from 1 to 2
          'number_of_replicas' => 0
        }
      })
      
      allow(client).to receive(:get).with('/products-3/_mapping').and_return({
        'products-3' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'keyword', 'index' => true },
              'name' => { 'type' => 'text' }
            }
          }
        }
      })

      expect { definer.define_schema_for_existing_index('products') }
        .to output(/Index settings and mappings constitute a breaking change/).to_stdout

      # Should generate new index for breaking change
      index_path = File.join(schemas_path, 'products-4')
      expect(File.exist?(File.join(index_path, 'index.json'))).to be true
    end

    it 'detects breaking changes in field properties' do
      allow(client).to receive(:get_index_settings).with('products-3').and_return({
        'index' => {
          'number_of_shards' => 1,
          'number_of_replicas' => 0
        }
      })
      
      allow(client).to receive(:get).with('/products-3/_mapping').and_return({
        'products-3' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'keyword', 'index' => false },  # Changed index property
              'name' => { 'type' => 'text' }
            }
          }
        }
      })

      expect { definer.define_schema_for_existing_index('products') }
        .to output(/Index settings and mappings constitute a breaking change/).to_stdout

      # Should generate new index for breaking change
      index_path = File.join(schemas_path, 'products-4')
      expect(File.exist?(File.join(index_path, 'index.json'))).to be true
    end

    it 'allows non-breaking changes like number_of_replicas' do
      allow(client).to receive(:get_index_settings).with('products-3').and_return({
        'index' => {
          'number_of_shards' => 1,
          'number_of_replicas' => 1  # Changed from 0 to 1 (non-breaking)
        }
      })
      
      allow(client).to receive(:get).with('/products-3/_mapping').and_return({
        'products-3' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'keyword', 'index' => true },
              'name' => { 'type' => 'text' }
            }
          }
        }
      })

      expect { definer.define_schema_for_existing_index('products') }
        .to output(/Index settings and mappings constitute a non-breaking change/).to_stdout

      # Should generate new revision for non-breaking change
      revision_path = File.join(schemas_path, 'products-3', 'revisions', '2')
      expect(File.exist?(File.join(revision_path, 'settings.json'))).to be true
    end

    it 'allows non-breaking changes like boost modifications' do
      allow(client).to receive(:get_index_settings).with('products-3').and_return({
        'index' => {
          'number_of_shards' => 1,
          'number_of_replicas' => 0
        }
      })
      
      allow(client).to receive(:get).with('/products-3/_mapping').and_return({
        'products-3' => {
          'mappings' => {
            'properties' => {
              'id' => { 'type' => 'keyword', 'index' => true },
              'name' => { 'type' => 'text', 'boost' => 2.0 }  # Added boost (non-breaking)
            }
          }
        }
      })

      expect { definer.define_schema_for_existing_index('products') }
        .to output(/Index settings and mappings constitute a non-breaking change/).to_stdout

      # Should generate new revision for non-breaking change
      revision_path = File.join(schemas_path, 'products-3', 'revisions', '2')
      expect(File.exist?(File.join(revision_path, 'settings.json'))).to be true
    end
  end
end