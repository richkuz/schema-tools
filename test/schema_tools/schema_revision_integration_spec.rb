require_relative '../spec_helper'
require 'fileutils'
require 'tempfile'
require_relative '../../lib/schema_tools/schema_revision'
require_relative '../../lib/schema_tools/config'
require_relative '../../lib/schema_tools/schema_manager'
require_relative '../../lib/schema_tools/utils'
require_relative '../../lib/schema_tools/migrate'
require_relative '../../lib/schema_tools/create'
require_relative '../../lib/schema_tools/upload_painless'
require_relative '../../lib/schema_tools/update_metadata'

describe 'SchemaRevision Integration' do
  let(:temp_dir) { Dir.mktmpdir('schemurai_integration_test') }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config::SCHEMAS_PATH }

  before do
    # Set up test schemas directory
    FileUtils.mkdir_p(schemas_path)
    
    # Mock the SCHEMAS_PATH for testing
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    allow(SchemaTools::SchemaRevision).to receive(:schemas_path).and_return(schemas_path)
    
    # Create comprehensive test schema structure
    setup_comprehensive_test_schemas
  end

  after do
    # Restore original SCHEMAS_PATH
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
    
    # Clean up temp directory
    FileUtils.rm_rf(temp_dir)
  end

  def setup_comprehensive_test_schemas
    # Create products-1 with revision 1
    products1_path = File.join(schemas_path, 'products-1')
    FileUtils.mkdir_p(File.join(products1_path, 'revisions', '1'))
    File.write(File.join(products1_path, 'index.json'), '{"index_name": "products-1", "from_index_name": null}')
    File.write(File.join(products1_path, 'revisions', '1', 'settings.json'), '{"index": {"number_of_shards": 1}}')
    File.write(File.join(products1_path, 'revisions', '1', 'mappings.json'), '{"properties": {"id": {"type": "keyword"}}}')

    # Create products-2 with revisions 1 and 2
    products2_path = File.join(schemas_path, 'products-2')
    FileUtils.mkdir_p(File.join(products2_path, 'revisions', '1'))
    FileUtils.mkdir_p(File.join(products2_path, 'revisions', '2'))
    File.write(File.join(products2_path, 'index.json'), '{"index_name": "products-2", "from_index_name": "products-1"}')
    File.write(File.join(products2_path, 'revisions', '1', 'settings.json'), '{"index": {"number_of_shards": 2}}')
    File.write(File.join(products2_path, 'revisions', '1', 'mappings.json'), '{"properties": {"id": {"type": "keyword"}, "name": {"type": "text"}}}')
    File.write(File.join(products2_path, 'revisions', '2', 'settings.json'), '{"index": {"number_of_shards": 2}}')
    File.write(File.join(products2_path, 'revisions', '2', 'mappings.json'), '{"properties": {"id": {"type": "keyword"}, "name": {"type": "text"}, "description": {"type": "text"}}}')

    # Create products-3 with revision 1
    products3_path = File.join(schemas_path, 'products-3')
    FileUtils.mkdir_p(File.join(products3_path, 'revisions', '1'))
    File.write(File.join(products3_path, 'index.json'), '{"index_name": "products-3", "from_index_name": "products-2"}')
    File.write(File.join(products3_path, 'revisions', '1', 'settings.json'), '{"index": {"number_of_shards": 3}}')
    File.write(File.join(products3_path, 'revisions', '1', 'mappings.json'), '{"properties": {"id": {"type": "keyword"}, "name": {"type": "text"}, "description": {"type": "text"}, "price": {"type": "float"}}}')

    # Create users with revision 1 (no version number)
    users_path = File.join(schemas_path, 'users')
    FileUtils.mkdir_p(File.join(users_path, 'revisions', '1'))
    File.write(File.join(users_path, 'index.json'), '{"index_name": "users", "from_index_name": null}')
    File.write(File.join(users_path, 'revisions', '1', 'settings.json'), '{"index": {"number_of_shards": 1}}')
    File.write(File.join(users_path, 'revisions', '1', 'mappings.json'), '{"properties": {"id": {"type": "keyword"}, "email": {"type": "keyword"}}}')
  end

  describe 'SchemaManager integration' do
    let(:schema_manager) { SchemaTools::SchemaManager.new(schemas_path) }

    describe '#discover_all_schemas_with_latest_revisions' do
      it 'discovers all schemas with correct revision numbers' do
        schemas = schema_manager.discover_all_schemas_with_latest_revisions
        
        expect(schemas.length).to eq(4)
        
        products1_schema = schemas.find { |s| s[:index_name] == 'products-1' }
        expect(products1_schema[:revision_number]).to eq('1')
        
        products2_schema = schemas.find { |s| s[:index_name] == 'products-2' }
        expect(products2_schema[:revision_number]).to eq('2')
        
        products3_schema = schemas.find { |s| s[:index_name] == 'products-3' }
        expect(products3_schema[:revision_number]).to eq('1')
        
        users_schema = schemas.find { |s| s[:index_name] == 'users' }
        expect(users_schema[:revision_number]).to eq('1')
      end
    end

    describe '#generate_diff_output_for_index_name_or_revision' do
      it 'generates diff for index name' do
        expect {
          schema_manager.generate_diff_output_for_index_name_or_revision('products-2')
        }.not_to raise_error
        
        # Check that diff file was created
        diff_file = File.join(schemas_path, 'products-2/revisions/2/diff_output.txt')
        expect(File.exist?(diff_file)).to be true
      end

      it 'generates diff for specific revision' do
        expect {
          schema_manager.generate_diff_output_for_index_name_or_revision('products-2/revisions/2')
        }.not_to raise_error
        
        # Check that diff file was created
        diff_file = File.join(schemas_path, 'products-2/revisions/2/diff_output.txt')
        expect(File.exist?(diff_file)).to be true
      end
    end
  end

  describe 'Utils integration' do
    describe '.discover_latest_schema_versions_only' do
      it 'discovers latest schema versions correctly' do
        schemas = SchemaTools::Utils.discover_latest_schema_versions_only(schemas_path)
        
        # Should find the latest version of each schema family
        expect(schemas.length).to eq(2) # products-3 and users (latest versions)
        
        products_schema = schemas.find { |s| s[:index_name] == 'products-3' }
        expect(products_schema).not_to be_nil
        expect(products_schema[:revision_number]).to eq('1')
        expect(products_schema[:version_number]).to eq(3)
        
        users_schema = schemas.find { |s| s[:index_name] == 'users' }
        expect(users_schema).not_to be_nil
        expect(users_schema[:revision_number]).to eq('1')
        expect(users_schema[:version_number]).to eq(1)
      end
    end
  end

  describe 'Edge cases and error handling' do
    let(:schema_manager) { SchemaTools::SchemaManager.new(schemas_path) }

    context 'with malformed revision paths' do
      it 'handles invalid revision paths gracefully' do
        expect {
          SchemaTools::SchemaRevision.new('invalid/path/format')
        }.to raise_error(/Invalid revision path format/)
      end
    end

    context 'with missing revision directories' do
      it 'handles missing revision directories' do
        revision = SchemaTools::SchemaRevision.for_latest_revision('non-existent')
        expect(revision).to be_nil
      end
    end

    context 'with empty revision directories' do
      before do
        # Create an index with empty revisions directory
        empty_path = File.join(schemas_path, 'empty-index')
        FileUtils.mkdir_p(File.join(empty_path, 'revisions'))
        File.write(File.join(empty_path, 'index.json'), '{"index_name": "empty-index"}')
      end

      it 'handles empty revisions directory' do
        revision = SchemaTools::SchemaRevision.for_latest_revision('empty-index')
        expect(revision).to be_nil
      end
    end
  end
end