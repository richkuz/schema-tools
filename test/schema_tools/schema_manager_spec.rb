require_relative '../spec_helper'
require 'schema_tools/schema_files'
require 'tempfile'

RSpec.describe SchemaTools::SchemaFiles do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config::SCHEMAS_PATH }
  let(:manager) { SchemaTools::SchemaFiles }
  
  before do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
  end
  
  after do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end
end