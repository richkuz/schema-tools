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
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
    setup_comprehensive_test_schemas
  end

  after do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
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
end