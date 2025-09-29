require_relative '../spec_helper'
require 'schema_tools/migrate'
require 'schema_tools/schema_files'
require 'schema_tools/schema_revision'
require 'schema_tools/utils'
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
        # Create a test schema structure
        create_test_schema('products', 1)
        create_test_schema('users', 2)
      end

      it 'discovers and migrates all schemas successfully' do
        # Mock the schema discovery to return our test schemas
        allow(SchemaTools).to receive(:find_latest_file_indexes).and_return([
          { index_name: 'products', revision_number: 1 },
          { index_name: 'users', revision_number: 1 }
        ])
        
        # Mock the migration process for each schema
        expect(SchemaTools).to receive(:migrate_one_schema).with(index_name: 'products', client: client)
        expect(SchemaTools).to receive(:migrate_one_schema).with(index_name: 'users', client: client)
        
        expect { SchemaTools.migrate_all(client: client) }.to output(/Found 2 schema\(s\) to migrate/).to_stdout
      end

      it 'continues migration even if one schema fails' do
        # Mock the schema discovery to return our test schemas
        allow(SchemaTools).to receive(:find_latest_file_indexes).and_return([
          { index_name: 'products', revision_number: 1 },
          { index_name: 'users', revision_number: 1 }
        ])
        
        # First schema fails, second succeeds
        expect(SchemaTools).to receive(:migrate_one_schema).with(index_name: 'products', client: client).and_raise('Migration failed')
        expect(SchemaTools).to receive(:migrate_one_schema).with(index_name: 'users', client: client)
        
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
    let(:index_name) { 'test-index' }
    let(:index_config) { { 'from_index_name' => 'old-index' } }
    let(:schema_revision) { double('schema_revision', index_name: index_name, revision_relative_path: "#{index_name}/revisions/1", revision_absolute_path: "/path/to/#{index_name}/revisions/1") }

    before do
      create_test_schema(index_name, 1)
      
      allow(SchemaTools::SchemaFiles).to receive(:get_index_config).with(index_name).and_return(index_config)
      allow(SchemaTools::SchemaFiles).to receive(:get_revision_files).and_return({ settings: {}, mappings: {}, painless_scripts: {} })
      allow(SchemaTools::SchemaRevision).to receive(:find_latest_revision).with(index_name).and_return(schema_revision)
      allow(SchemaTools::SchemaRevision).to receive(:find_previous_revision_across_indexes).with(schema_revision).and_return(nil)
      allow(schema_revision).to receive(:revision_relative_path).and_return("#{index_name}/revisions/1")
      allow(File).to receive(:write)
    end

    context 'when index does not exist' do
      it 'creates the index and performs migration' do
        expect(client).to receive(:index_exists?).with(index_name).and_return(false)
        expect(SchemaTools).to receive(:diff).with(schema_revision: schema_revision)
        expect(SchemaTools).to receive(:create).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:upload_painless).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:update_metadata).with(index_name: index_name, metadata: {}, client: client)
        expect(SchemaTools).to receive(:reindex).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:catchup).with(index_name: index_name, client: client)
        
        expect { SchemaTools.migrate_one_schema(index_name: index_name, client: client) }.to output(/Migration completed successfully/).to_stdout
      end
    end

    context 'when index exists and is up to date' do
      it 'skips migration and prints appropriate message' do
        expect(client).to receive(:index_exists?).with(index_name).and_return(true)
        expect(client).to receive(:get_schema_revision).with(index_name).and_return("#{index_name}/revisions/1")
        
        expect { SchemaTools.migrate_one_schema(index_name: index_name, client: client) }.to output(/Already at revision/).to_stdout
      end
    end

    context 'when index exists but needs migration' do
      it 'performs migration without creating index' do
        expect(client).to receive(:index_exists?).with(index_name).and_return(true)
        expect(client).to receive(:get_schema_revision).with(index_name).and_return("#{index_name}/revisions/0")
        expect(SchemaTools).to receive(:diff).with(schema_revision: schema_revision)
        expect(SchemaTools).to receive(:upload_painless).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:update_metadata).with(index_name: index_name, metadata: {}, client: client)
        expect(SchemaTools).to receive(:reindex).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:catchup).with(index_name: index_name, client: client)
        
        expect { SchemaTools.migrate_one_schema(index_name: index_name, client: client) }.to output(/Migration completed successfully/).to_stdout
      end
    end

    context 'when index exists but has no revision metadata' do
      it 'attempts migration with warning message' do
        expect(client).to receive(:index_exists?).with(index_name).and_return(true)
        expect(client).to receive(:get_schema_revision).with(index_name).and_return(nil)
        expect(SchemaTools).to receive(:diff).with(schema_revision: schema_revision)
        expect(SchemaTools).to receive(:upload_painless).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:update_metadata).with(index_name: index_name, metadata: {}, client: client)
        expect(SchemaTools).to receive(:reindex).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:catchup).with(index_name: index_name, client: client)
        
        expect { SchemaTools.migrate_one_schema(index_name: index_name, client: client) }.to output(/Unable to determine the current schema revision/).to_stdout
      end
    end

    context 'when index config is missing' do
      it 'raises appropriate error' do
        allow(SchemaTools::SchemaFiles).to receive(:get_index_config).with(index_name).and_return(nil)
        
        expect { SchemaTools.migrate_one_schema(index_name: index_name, client: client) }.to raise_error(/Index configuration not found/)
      end
    end

    context 'when no revisions are found' do
      it 'raises appropriate error' do
        allow(SchemaTools::SchemaRevision).to receive(:find_latest_revision).with(index_name).and_return(nil)
        
        expect { SchemaTools.migrate_one_schema(index_name: index_name, client: client) }.to raise_error(/No revisions found/)
      end
    end

    context 'when no from_index_name is specified' do
      let(:index_config) { {} }

      it 'skips reindexing and catchup' do
        expect(client).to receive(:index_exists?).with(index_name).and_return(false)
        expect(SchemaTools).to receive(:diff).with(schema_revision: schema_revision)
        expect(SchemaTools).to receive(:create).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:upload_painless).with(index_name: index_name, client: client)
        expect(SchemaTools).to receive(:update_metadata).with(index_name: index_name, metadata: {}, client: client)
        expect(SchemaTools).not_to receive(:reindex)
        expect(SchemaTools).not_to receive(:catchup)
        
        expect { SchemaTools.migrate_one_schema(index_name: index_name, client: client) }.to output(/No from_index_name specified/).to_stdout
      end
    end
  end

  describe '.find_latest_file_indexes' do
    context 'when schemas directory does not exist' do
      it 'returns empty array' do
        FileUtils.rm_rf(schemas_path)
        result = SchemaTools::Index.find_latest_file_indexes
        expect(result).to eq([])
      end
    end

    context 'when schemas exist' do
      let(:schema_revision) { double('schema_revision', revision_absolute_path: '/path/to/revision', revision_number: '1') }

      before do
        create_test_schema('products', 1)
        create_test_schema('products-2', 2)
        create_test_schema('users', 1)
        create_test_schema('users-2', 2)
        create_test_schema('users-3', 3)
        
        # Mock SchemaFiles to return valid configs
        allow(SchemaTools::SchemaFiles).to receive(:get_index_config).and_return({ 'index_name' => 'test' })
        allow(SchemaTools::SchemaRevision).to receive(:find_latest_revision).and_return(schema_revision)
      end

      it 'returns only the latest version of each schema family' do
        result = SchemaTools::Index.find_latest_file_indexes
        
        expect(result.length).to eq(2)
        
        products_schema = result.find { |s| s[:index_name] == 'products-2' }
        users_schema = result.find { |s| s[:index_name] == 'users-3' }
        
        expect(products_schema).not_to be_nil
        expect(products_schema[:version_number]).to eq(2)
        
        expect(users_schema).not_to be_nil
        expect(users_schema[:version_number]).to eq(3)
      end

      it 'includes correct revision information' do
        result = SchemaTools::Index.find_latest_file_indexes
        
        products_schema = result.find { |s| s[:index_name] == 'products-2' }
        expect(products_schema[:revision_number]).to eq("1")
        expect(products_schema[:latest_revision]).to eq('/path/to/revision')
      end
    end

    context 'when schemas have no valid configuration' do
      before do
        # Create directory without proper schema files
        FileUtils.mkdir_p(File.join(schemas_path, 'invalid-schema'))
        
        # Mock SchemaFiles to return nil for invalid schemas
        allow(SchemaTools::SchemaFiles).to receive(:get_index_config).and_return(nil)
        allow(SchemaTools::SchemaRevision).to receive(:find_latest_revision).and_return(nil)
      end

      it 'excludes invalid schemas' do
        result = SchemaTools::Index.find_latest_file_indexes
        expect(result).to eq([])
      end
    end
  end

  private

  def create_test_schema(name, version)
    schema_dir = File.join(schemas_path, name)
    FileUtils.mkdir_p(schema_dir)
    
    # Create index.json
    index_config = {
      'index_name' => name,
      'from_index_name' => version > 1 ? "#{name.split('-')[0]}-#{version - 1}" : nil
    }
    File.write(File.join(schema_dir, 'index.json'), index_config.to_json)
    
    # Create revision directory and files
    revision_dir = File.join(schema_dir, 'revisions', '1')
    FileUtils.mkdir_p(revision_dir)
    
    File.write(File.join(revision_dir, 'settings.json'), { 'settings' => {} }.to_json)
    File.write(File.join(revision_dir, 'mappings.json'), { 'mappings' => {} }.to_json)
  end
end