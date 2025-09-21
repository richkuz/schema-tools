require_relative '../spec_helper'
require 'schema_tools/client'
require 'schema_tools/schema_manager'
require 'schema_tools/schema_definer'
require 'tempfile'
require 'webmock/rspec'

RSpec.describe 'Schema Define Integration' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:client) { SchemaTools::Client.new('http://localhost:9200') }
  let(:schema_manager) { SchemaTools::SchemaManager.new(schemas_path) }
  let(:definer) { SchemaTools::SchemaDefiner.new(client, schema_manager) }
  
  before do
    FileUtils.mkdir_p(schemas_path)
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe 'define_schema_for_existing_index' do
    context 'when index exists and no schema definition' do
      before do
        stub_request(:get, 'http://localhost:9200/products')
          .to_return(status: 404)
        
        stub_request(:get, 'http://localhost:9200/_cat/indices/products*?format=json')
          .to_return(status: 200, body: [
            { 'index' => 'products-3' }
          ].to_json)
        
        stub_request(:get, 'http://localhost:9200/products-3')
          .to_return(status: 200, body: {
            'products-3' => {
              'settings' => {
                'index' => {
                  'number_of_shards' => 1,
                  'number_of_replicas' => 0
                }
              }
            }
          }.to_json)
        
        stub_request(:get, 'http://localhost:9200/products-3/_mapping')
          .to_return(status: 200, body: {
            'products-3' => {
              'mappings' => {
                'properties' => {
                  'id' => { 'type' => 'keyword' },
                  'name' => { 'type' => 'text' }
                }
              }
            }
          }.to_json)
        
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 200, body: {}.to_json)
      end

      it 'generates schema files for existing index' do
        expect { definer.define_schema_for_existing_index('products') }
          .to output(/Index "products" found at http:\/\/localhost:9200, latest index name is "products-3"/).to_stdout

        index_path = File.join(schemas_path, 'products-3')
        expect(File.exist?(File.join(index_path, 'index.json'))).to be true
        expect(File.exist?(File.join(index_path, 'reindex.painless'))).to be true
        expect(File.exist?(File.join(index_path, 'revisions', '1', 'settings.json'))).to be true
        expect(File.exist?(File.join(index_path, 'revisions', '1', 'mappings.json'))).to be true
      end
    end

    context 'when index not found' do
      before do
        stub_request(:get, 'http://localhost:9200/nonexistent')
          .to_return(status: 404)
        
        stub_request(:get, 'http://localhost:9200/_cat/indices/nonexistent*?format=json')
          .to_return(status: 200, body: [].to_json)
      end

      it 'reports index not found' do
        expect { definer.define_schema_for_existing_index('nonexistent') }
          .to output(/Index "nonexistent" not found at http:\/\/localhost:9200/).to_stdout
      end
    end

    context 'when schema exists and matches' do
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
            'id' => { 'type' => 'keyword' },
            'name' => { 'type' => 'text' }
          }
        }
        
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'settings.json'), settings.to_json)
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'mappings.json'), mappings.to_json)
        
        stub_request(:get, 'http://localhost:9200/products')
          .to_return(status: 404)
        
        stub_request(:get, 'http://localhost:9200/_cat/indices/products*?format=json')
          .to_return(status: 200, body: [
            { 'index' => 'products-3' }
          ].to_json)
        
        stub_request(:get, 'http://localhost:9200/products-3')
          .to_return(status: 200, body: {
            'products-3' => {
              'settings' => settings
            }
          }.to_json)
        
        stub_request(:get, 'http://localhost:9200/products-3/_mapping')
          .to_return(status: 200, body: {
            'products-3' => {
              'mappings' => mappings
            }
          }.to_json)
        
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 200, body: {}.to_json)
      end

      it 'reports schemas match' do
        expect { definer.define_schema_for_existing_index('products') }
          .to output(/Latest schema definition already matches the index/).to_stdout
      end
    end

    context 'when breaking change detected' do
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
            'id' => { 'type' => 'keyword' }
          }
        }
        
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'settings.json'), settings.to_json)
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'mappings.json'), mappings.to_json)
        
        stub_request(:get, 'http://localhost:9200/products')
          .to_return(status: 404)
        
        stub_request(:get, 'http://localhost:9200/_cat/indices/products*?format=json')
          .to_return(status: 200, body: [
            { 'index' => 'products-3' }
          ].to_json)
        
        stub_request(:get, 'http://localhost:9200/products-3')
          .to_return(status: 200, body: {
            'products-3' => {
              'settings' => settings
            }
          }.to_json)
        
        stub_request(:get, 'http://localhost:9200/products-3/_mapping')
          .to_return(status: 200, body: {
            'products-3' => {
              'mappings' => {
                'properties' => {
                  'id' => { 'type' => 'text' }
                }
              }
            }
          }.to_json)
        
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 200, body: {}.to_json)
      end

      it 'generates new index for breaking change' do
        expect { definer.define_schema_for_existing_index('products') }
          .to output(/Index settings and mappings constitute a breaking change/).to_stdout

        index_path = File.join(schemas_path, 'products-4')
        expect(File.exist?(File.join(index_path, 'index.json'))).to be true
      end
    end
  end

  describe 'define_example_schema_for_new_index' do
    context 'when no schema definition exists' do
      it 'generates example schema files' do
        expect { definer.define_example_schema_for_new_index('newindex') }
          .to output(/No schema definition exists for "newindex"/).to_stdout

        index_path = File.join(schemas_path, 'newindex')
        expect(File.exist?(File.join(index_path, 'index.json'))).to be true
        expect(File.exist?(File.join(index_path, 'reindex.painless'))).to be true
        expect(File.exist?(File.join(index_path, 'revisions', '1', 'settings.json'))).to be true
        expect(File.exist?(File.join(index_path, 'revisions', '1', 'mappings.json'))).to be true
      end
    end

    context 'when schema definition exists' do
      before do
        FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      end

      it 'reports existing schema' do
        expect { definer.define_example_schema_for_new_index('existing') }
          .to output(/Latest schema definition of "existing" is defined/).to_stdout
      end
    end
  end

  describe 'define_breaking_change_schema' do
    context 'when schema definition exists' do
      before do
        FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      end

      it 'generates breaking change schema' do
        expect { definer.define_breaking_change_schema('existing') }
          .to output(/Generated example schema definition files/).to_stdout

        index_path = File.join(schemas_path, 'existing-3')
        expect(File.exist?(File.join(index_path, 'index.json'))).to be true
      end
    end
  end

  describe 'define_non_breaking_change_schema' do
    context 'when schema definition exists' do
      before do
        FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
      end

      it 'generates non-breaking change schema' do
        expect { definer.define_non_breaking_change_schema('existing') }
          .to output(/Generated example schema definition files/).to_stdout

        revision_path = File.join(schemas_path, 'existing-2', 'revisions', '2')
        expect(File.exist?(File.join(revision_path, 'settings.json'))).to be true
        expect(File.exist?(File.join(revision_path, 'mappings.json'))).to be true
      end
    end
  end
end