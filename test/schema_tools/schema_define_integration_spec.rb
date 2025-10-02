require_relative '../spec_helper'
require 'schema_tools/client'
require 'schema_tools/schema_files'
require 'schema_tools/schema_definer'
require 'tempfile'
require 'webmock/rspec'

RSpec.describe 'Schema Define Integration' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config.schemas_path }
  let(:client) { SchemaTools::Client.new('http://localhost:9200') }
  let(:definer) { SchemaTools::SchemaDefiner.new(client) }
  
  before do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
  end
  
  after do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end

  describe 'define_schema_for_existing_live_index' do
    context 'when index exists and no schema definition' do
      before do
        stub_request(:get, 'http://localhost:9200/products')
          .to_return(status: 200, body: {
            'products' => {
              'settings' => {
                'index' => {
                  'number_of_shards' => 1,
                  'number_of_replicas' => 0
                }
              }
            }
          }.to_json)
        
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
        
        stub_request(:get, 'http://localhost:9200/products/_mapping')
          .to_return(status: 200, body: {
            'products' => {
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
        expect { definer.define_schema_for_existing_live_index('products') }
          .to output(/Extracting live settings, mappings, and painless scripts from index "products"/).to_stdout

        index_path = File.join(schemas_path, 'products')
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
        expect { definer.define_schema_for_existing_live_index('nonexistent') }
          .to output(/Could not find a live index named nonexistent for which to define a schema revision/).to_stdout
      end
    end

    context 'when schema exists and matches' do
      before do
        FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1', 'painless_scripts'))
        
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
        
        painless_scripts = {
          'script1' => 'ctx._source.test = "value"',
          'script2' => 'ctx._source.another = "test"'
        }
        
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'settings.json'), settings.to_json)
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'mappings.json'), mappings.to_json)
        
        # Write painless scripts to files
        painless_scripts.each do |script_name, script_content|
          File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'painless_scripts', "#{script_name}.painless"), script_content)
        end
        
        stub_request(:get, 'http://localhost:9200/products-3')
          .to_return(status: 200, body: {
            'products-3' => {
              'settings' => settings
            }
          }.to_json)
        
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
        
        # Format the scripts response to match Elasticsearch API structure
        scripts_response = {}
        painless_scripts.each do |script_name, script_content|
          scripts_response[script_name] = {
            'script' => {
              'source' => script_content
            }
          }
        end
        
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 200, body: scripts_response.to_json)
      end

      it 'reports schemas and painless scripts match' do
        expect { definer.define_schema_for_existing_live_index('products-3') }
          .to output(/Latest schema definition and any painless scripts already match the live index/).to_stdout
      end
    end

    context 'when painless scripts differ' do
      before do
        FileUtils.mkdir_p(File.join(schemas_path, 'products-3', 'revisions', '1', 'painless_scripts'))
        
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
        
        # Schema has different painless scripts
        schema_painless_scripts = {
          'script1' => 'ctx._source.test = "old_value"',
          'script2' => 'ctx._source.another = "test"'
        }
        
        # Live index has different painless scripts
        live_painless_scripts = {
          'script1' => 'ctx._source.test = "new_value"',
          'script2' => 'ctx._source.another = "test"'
        }
        
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'settings.json'), settings.to_json)
        File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'mappings.json'), mappings.to_json)
        
        # Write schema painless scripts to files
        schema_painless_scripts.each do |script_name, script_content|
          File.write(File.join(schemas_path, 'products-3', 'revisions', '1', 'painless_scripts', "#{script_name}.painless"), script_content)
        end
        
        stub_request(:get, 'http://localhost:9200/products-3')
          .to_return(status: 200, body: {
            'products-3' => {
              'settings' => settings
            }
          }.to_json)
        
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
        
        # Format the live scripts response to match Elasticsearch API structure
        live_scripts_response = {}
        live_painless_scripts.each do |script_name, script_content|
          live_scripts_response[script_name] = {
            'script' => {
              'source' => script_content
            }
          }
        end
        
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 200, body: live_scripts_response.to_json)
      end

      it 'detects painless scripts difference and creates new revision' do
        expect { definer.define_schema_for_existing_live_index('products-3') }
          .to output(/Index settings and mappings constitute a non-breaking change/).to_stdout

        # Should create a new revision
        revision_path = File.join(schemas_path, 'products-3', 'revisions', '2')
        expect(File.exist?(File.join(revision_path, 'settings.json'))).to be true
        expect(File.exist?(File.join(revision_path, 'mappings.json'))).to be true
        expect(File.exist?(File.join(revision_path, 'painless_scripts', 'script1.painless'))).to be true
        expect(File.exist?(File.join(revision_path, 'painless_scripts', 'script2.painless'))).to be true
        
        # Verify the new revision has the updated painless scripts
        new_script_content = File.read(File.join(revision_path, 'painless_scripts', 'script1.painless'))
        expect(new_script_content).to eq('ctx._source.test = "new_value"')
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
        
        stub_request(:get, 'http://localhost:9200/products-3')
          .to_return(status: 200, body: {
            'products-3' => {
              'settings' => settings
            }
          }.to_json)
        
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
        expect { definer.define_schema_for_existing_live_index('products-3') }
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
        revision_dir = FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
        File.write(File.join(revision_dir, 'settings.json'), { 'settings' => {} }.to_json)
        File.write(File.join(revision_dir, 'mappings.json'), { 'mappings' => {} }.to_json)
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
        revision_dir = FileUtils.mkdir_p(File.join(schemas_path, 'existing-2', 'revisions', '1'))
        File.write(File.join(revision_dir, 'settings.json'), { 'settings' => {} }.to_json)
        File.write(File.join(revision_dir, 'mappings.json'), { 'mappings' => {} }.to_json)
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