require_relative '../spec_helper'
require 'fileutils'
require 'tempfile'
require_relative '../../lib/schema_tools/schema_revision'
require_relative '../../lib/schema_tools/config'

describe SchemaTools::SchemaRevision do
  let(:temp_dir) { Dir.mktmpdir('schemurai_test') }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config::SCHEMAS_PATH }

  before do
    # Set up test schemas directory
    FileUtils.mkdir_p(schemas_path)
    
    # Mock the SCHEMAS_PATH for testing
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    allow(SchemaTools::SchemaRevision).to receive(:schemas_path).and_return(schemas_path)
    
    # Create test schema structure
    setup_test_schemas
  end

  after do
    # Restore original SCHEMAS_PATH
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
    
    # Clean up temp directory
    FileUtils.rm_rf(temp_dir)
  end

  def setup_test_schemas
    # Create products-1 with revision 1
    products1_path = File.join(schemas_path, 'products-1')
    FileUtils.mkdir_p(File.join(products1_path, 'revisions', '1'))
    File.write(File.join(products1_path, 'index.json'), '{"index_name": "products-1"}')
    File.write(File.join(products1_path, 'revisions', '1', 'settings.json'), '{}')
    File.write(File.join(products1_path, 'revisions', '1', 'mappings.json'), '{}')

    # Create products-2 with revisions 1 and 2
    products2_path = File.join(schemas_path, 'products-2')
    FileUtils.mkdir_p(File.join(products2_path, 'revisions', '1'))
    FileUtils.mkdir_p(File.join(products2_path, 'revisions', '2'))
    File.write(File.join(products2_path, 'index.json'), '{"index_name": "products-2"}')
    File.write(File.join(products2_path, 'revisions', '1', 'settings.json'), '{}')
    File.write(File.join(products2_path, 'revisions', '1', 'mappings.json'), '{}')
    File.write(File.join(products2_path, 'revisions', '2', 'settings.json'), '{}')
    File.write(File.join(products2_path, 'revisions', '2', 'mappings.json'), '{}')

    # Create products-3 with revision 1
    products3_path = File.join(schemas_path, 'products-3')
    FileUtils.mkdir_p(File.join(products3_path, 'revisions', '1'))
    File.write(File.join(products3_path, 'index.json'), '{"index_name": "products-3"}')
    File.write(File.join(products3_path, 'revisions', '1', 'settings.json'), '{}')
    File.write(File.join(products3_path, 'revisions', '1', 'mappings.json'), '{}')

    # Create users with revision 1 (no version number)
    users_path = File.join(schemas_path, 'users')
    FileUtils.mkdir_p(File.join(users_path, 'revisions', '1'))
    File.write(File.join(users_path, 'index.json'), '{"index_name": "users"}')
    File.write(File.join(users_path, 'revisions', '1', 'settings.json'), '{}')
    File.write(File.join(users_path, 'revisions', '1', 'mappings.json'), '{}')
  end

  describe '#initialize' do
    context 'with valid revision path' do
      it 'creates a SchemaRevision instance' do
        revision = SchemaTools::SchemaRevision.new('products-1/revisions/1')
        expect(revision).to be_a(SchemaTools::SchemaRevision)
        expect(revision.index_name).to eq('products-1')
        expect(revision.revision_number).to eq('1')
        expect(revision.revision_relative_path).to eq('products-1/revisions/1')
        expect(revision.revision_absolute_path).to eq(File.join(schemas_path, 'products-1/revisions/1'))
      end
    end

    context 'with invalid revision path format' do
      it 'raises an error for invalid format' do
        expect {
          SchemaTools::SchemaRevision.new('invalid-path')
        }.to raise_error(/Invalid revision path format/)
      end

      it 'raises an error for path without revisions' do
        expect {
          SchemaTools::SchemaRevision.new('products-1/settings')
        }.to raise_error(/Invalid revision path format/)
      end
    end

    context 'with non-existent revision path' do
      it 'raises an error for non-existent path' do
        expect {
          SchemaTools::SchemaRevision.new('products-1/revisions/999')
        }.to raise_error(/Revision path does not exist/)
      end
    end
  end

  describe '.find_latest_revision' do
    context 'with existing index' do
      it 'returns the latest revision for products-1' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('products-1')
        expect(revision).to be_a(SchemaTools::SchemaRevision)
        expect(revision.index_name).to eq('products-1')
        expect(revision.revision_number).to eq('1')
      end

      it 'returns the latest revision for products-2' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('products-2')
        expect(revision).to be_a(SchemaTools::SchemaRevision)
        expect(revision.index_name).to eq('products-2')
        expect(revision.revision_number).to eq('2')
      end

      it 'returns the latest revision for users (no version number)' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('users')
        expect(revision).to be_a(SchemaTools::SchemaRevision)
        expect(revision.index_name).to eq('users')
        expect(revision.revision_number).to eq('1')
      end
    end

    context 'with non-existent index' do
      it 'returns nil for non-existent index' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('non-existent')
        expect(revision).to be_nil
      end
    end

    context 'with index that has no revisions' do
      before do
        # Create an index directory without revisions
        empty_index_path = File.join(schemas_path, 'empty-index')
        FileUtils.mkdir_p(empty_index_path)
        File.write(File.join(empty_index_path, 'index.json'), '{"index_name": "empty-index"}')
      end

      it 'returns nil for index with no revisions' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('empty-index')
        expect(revision).to be_nil
      end
    end
  end

  describe '.previous_revision_within_index' do
    context 'with revision 2' do
      it 'returns revision 1' do
        current = SchemaTools::SchemaRevision.new('products-2/revisions/2')
        previous = SchemaTools::SchemaRevision.previous_revision_within_index(current)
        
        expect(previous).to be_a(SchemaTools::SchemaRevision)
        expect(previous.index_name).to eq('products-2')
        expect(previous.revision_number).to eq('1')
      end
    end

    context 'with revision 1' do
      it 'returns nil for revision 1' do
        current = SchemaTools::SchemaRevision.new('products-1/revisions/1')
        previous = SchemaTools::SchemaRevision.previous_revision_within_index(current)
        
        expect(previous).to be_nil
      end
    end
  end

  describe '.previous_revision_across_indexes' do
    context 'with products-2/revisions/1' do
      it 'returns products-1/revisions/1' do
        current = SchemaTools::SchemaRevision.new('products-2/revisions/1')
        previous = SchemaTools::SchemaRevision.previous_revision_across_indexes(current)
        
        expect(previous).to be_a(SchemaTools::SchemaRevision)
        expect(previous.index_name).to eq('products-1')
        expect(previous.revision_number).to eq('1')
      end
    end

    context 'with products-3/revisions/1' do
      it 'returns products-2/revisions/2 (latest revision of products-2)' do
        current = SchemaTools::SchemaRevision.new('products-3/revisions/1')
        previous = SchemaTools::SchemaRevision.previous_revision_across_indexes(current)
        
        expect(previous).to be_a(SchemaTools::SchemaRevision)
        expect(previous.index_name).to eq('products-2')
        expect(previous.revision_number).to eq('2')
      end
    end

    context 'with products-1/revisions/1' do
      it 'returns nil (no previous index)' do
        current = SchemaTools::SchemaRevision.new('products-1/revisions/1')
        previous = SchemaTools::SchemaRevision.previous_revision_across_indexes(current)
        
        expect(previous).to be_nil
      end
    end

    context 'with users/revisions/1' do
      it 'returns nil (no previous index)' do
        current = SchemaTools::SchemaRevision.new('users/revisions/1')
        previous = SchemaTools::SchemaRevision.previous_revision_across_indexes(current)
        
        expect(previous).to be_nil
      end
    end

    context 'with products-2/revisions/2' do
      it 'returns products-2/revisions/1 (previous within same index)' do
        current = SchemaTools::SchemaRevision.new('products-2/revisions/2')
        previous = SchemaTools::SchemaRevision.previous_revision_across_indexes(current)
        
        expect(previous).to be_a(SchemaTools::SchemaRevision)
        expect(previous.index_name).to eq('products-2')
        expect(previous.revision_number).to eq('1')
      end
    end
  end

  describe 'edge cases' do
    context 'with index that has gaps in revision numbers' do
      before do
        # Create products-4 with revisions 1 and 3 (missing revision 2)
        products4_path = File.join(schemas_path, 'products-4')
        FileUtils.mkdir_p(File.join(products4_path, 'revisions', '1'))
        FileUtils.mkdir_p(File.join(products4_path, 'revisions', '3'))
        File.write(File.join(products4_path, 'index.json'), '{"index_name": "products-4"}')
        File.write(File.join(products4_path, 'revisions', '1', 'settings.json'), '{}')
        File.write(File.join(products4_path, 'revisions', '1', 'mappings.json'), '{}')
        File.write(File.join(products4_path, 'revisions', '3', 'settings.json'), '{}')
        File.write(File.join(products4_path, 'revisions', '3', 'mappings.json'), '{}')
      end

      it 'finds the highest numbered revision as latest' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('products-4')
        expect(revision.revision_number).to eq('3')
      end

      it 'returns nil when previous revision number does not exist' do
        current = SchemaTools::SchemaRevision.new('products-4/revisions/3')
        previous = SchemaTools::SchemaRevision.previous_revision_within_index(current)
        
        # Should return nil because revision 2 doesn't exist
        expect(previous).to be_nil
      end
    end

    context 'with non-numeric revision directories' do
      before do
        # Create products-5 with non-numeric revision directories
        products5_path = File.join(schemas_path, 'products-5')
        FileUtils.mkdir_p(File.join(products5_path, 'revisions', 'alpha'))
        FileUtils.mkdir_p(File.join(products5_path, 'revisions', '1'))
        File.write(File.join(products5_path, 'index.json'), '{"index_name": "products-5"}')
        File.write(File.join(products5_path, 'revisions', 'alpha', 'settings.json'), '{}')
        File.write(File.join(products5_path, 'revisions', 'alpha', 'mappings.json'), '{}')
        File.write(File.join(products5_path, 'revisions', '1', 'settings.json'), '{}')
        File.write(File.join(products5_path, 'revisions', '1', 'mappings.json'), '{}')
      end

      it 'ignores non-numeric revision directories' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('products-5')
        expect(revision.revision_number).to eq('1')
      end
    end
  end

  describe 'integration with existing schemas' do
    context 'with real schema data' do
      before do
        # Restore original SCHEMAS_PATH for integration test
        allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
      end

      it 'works with existing products-1 schema' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('products-1')
        if revision
          expect(revision.index_name).to eq('products-1')
          expect(revision.revision_number).to eq('1')
          expect(revision.revision_absolute_path).to include('schemas/products-1/revisions/1')
        end
      end

      it 'works with existing users-1 schema' do
        revision = SchemaTools::SchemaRevision.find_latest_revision('users-1')
        if revision
          expect(revision.index_name).to eq('users-1')
          expect(revision.revision_number).to match(/\d+/)
          expect(revision.revision_absolute_path).to include('schemas/users-1/revisions/')
        end
      end
    end
  end
end