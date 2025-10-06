require_relative '../spec_helper'
require 'schema_tools/migrate'
require 'schema_tools/schema_files'
require 'schema_tools/config'
require 'tempfile'
require 'fileutils'

RSpec.describe SchemaTools do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config.schemas_path }
  let(:client) { double('client') }
  
  before do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
  end
  
  after do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end

  describe '.migrate_all' do
    context 'when schemas are found' do
      before do
        create_test_schema('products')
        create_test_schema('users')
      end

      it 'discovers and migrates all schemas successfully' do
        expect(SchemaTools).to receive(:migrate_one_schema).with(alias_name: 'products', client: client)
        expect(SchemaTools).to receive(:migrate_one_schema).with(alias_name: 'users', client: client)
        
        expect { SchemaTools.migrate_all(client: client) }.to output(/Found 2 schema\(s\) to migrate/).to_stdout
      end

      it 'continues migration even if one schema fails' do
        expect(SchemaTools).to receive(:migrate_one_schema).with(alias_name: 'products', client: client).and_raise('Migration failed')
        expect(SchemaTools).to receive(:migrate_one_schema).with(alias_name: 'users', client: client)
        
        expect { SchemaTools.migrate_all(client: client) }.to output(/Migration failed for products/).to_stdout
      end
    end

    context 'when no schemas are found' do
      it 'prints appropriate message and returns early' do
        expect { SchemaTools.migrate_all(client: client) }.to output(/No schemas found in/).to_stdout
      end
    end
  end

  describe '.migrate_one_schema' do
    let(:alias_name) { 'test-alias' }

    before do
      create_test_schema(alias_name)
    end

    context 'when schema folder does not exist' do
      it 'prints error message and returns' do
        FileUtils.rm_rf(File.join(schemas_path, alias_name))
        
        expect { SchemaTools.migrate_one_schema(alias_name: alias_name, client: client) }.to output(/Schema folder not found/).to_stdout
      end
    end

    context 'when it is an index name (not an alias)' do
      it 'prints instructions and returns' do
        expect(client).to receive(:alias_exists?).with(alias_name).and_return(false)
        expect(client).to receive(:index_exists?).with(alias_name).and_return(true)
        
        expect { SchemaTools.migrate_one_schema(alias_name: alias_name, client: client) }.to output(/To prevent downtime, this tool only migrates aliased indexes/).to_stdout
      end
    end

    context 'when alias does not exist' do
      it 'prints error message and returns' do
        expect(client).to receive(:alias_exists?).with(alias_name).twice.and_return(false)
        expect(client).to receive(:index_exists?).with(alias_name).and_return(false)
        
        expect { SchemaTools.migrate_one_schema(alias_name: alias_name, client: client) }.to output(/Alias '#{alias_name}' not found/).to_stdout
      end
    end

    context 'when alias points to multiple indices' do
      it 'prints error message and returns' do
        expect(client).to receive(:alias_exists?).with(alias_name).twice.and_return(true)
        expect(client).to receive(:get_alias_indices).with(alias_name).and_return(['index1', 'index2'])
        
        expect { SchemaTools.migrate_one_schema(alias_name: alias_name, client: client) }.to output(/This tool can only migrate aliases that point at one index/).to_stdout
      end
    end

    context 'when alias points to no indices' do
      it 'prints error message and returns' do
        expect(client).to receive(:alias_exists?).with(alias_name).twice.and_return(true)
        expect(client).to receive(:get_alias_indices).with(alias_name).and_return([])
        
        expect { SchemaTools.migrate_one_schema(alias_name: alias_name, client: client) }.to output(/Alias '#{alias_name}' points to no indices/).to_stdout
      end
    end

    context 'when alias points to one index' do
      it 'prints the index name and returns' do
        expect(client).to receive(:alias_exists?).with(alias_name).twice.and_return(true)
        expect(client).to receive(:get_alias_indices).with(alias_name).and_return(['test-index-123'])
        
        expect { SchemaTools.migrate_one_schema(alias_name: alias_name, client: client) }.to output(/Alias '#{alias_name}' points to index 'test-index-123'/).to_stdout
      end
    end
  end

  private

  def create_test_schema(alias_name)
    schema_dir = File.join(schemas_path, alias_name)
    FileUtils.mkdir_p(schema_dir)
    
    settings = { 'number_of_shards' => 1, 'number_of_replicas' => 0 }
    mappings = { 'properties' => { 'id' => { 'type' => 'keyword' } } }
    
    File.write(File.join(schema_dir, 'settings.json'), settings.to_json)
    File.write(File.join(schema_dir, 'mappings.json'), mappings.to_json)
  end
end