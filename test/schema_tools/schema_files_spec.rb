require_relative '../spec_helper'
require 'schema_tools/schema_files'
require 'schema_tools/config'
require 'tempfile'

RSpec.describe SchemaTools::SchemaFiles do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config.schemas_path }
  
  before do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
  end
  
  after do
    allow(SchemaTools::Config).to receive(:schemas_path).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end

  describe '.get_settings' do
    context 'when settings.json exists' do
      let(:alias_name) { 'products' }
      let(:settings) { { 'number_of_shards' => 1, 'number_of_replicas' => 0 } }

      before do
        schema_dir = File.join(schemas_path, alias_name)
        FileUtils.mkdir_p(schema_dir)
        File.write(File.join(schema_dir, 'settings.json'), settings.to_json)
      end

      it 'returns parsed settings' do
        result = described_class.get_settings(alias_name)
        expect(result).to eq(settings)
      end
    end

    context 'when settings.json does not exist' do
      it 'returns nil' do
        result = described_class.get_settings('nonexistent')
        expect(result).to be_nil
      end
    end

    context 'when settings.json contains invalid JSON' do
      let(:alias_name) { 'products' }

      before do
        schema_dir = File.join(schemas_path, alias_name)
        FileUtils.mkdir_p(schema_dir)
        File.write(File.join(schema_dir, 'settings.json'), 'invalid json')
      end

      it 'raises JSON parse error' do
        expect { described_class.get_settings(alias_name) }.to raise_error(JSON::ParserError)
      end
    end
  end

  describe '.get_mappings' do
    context 'when mappings.json exists' do
      let(:alias_name) { 'products' }
      let(:mappings) { { 'properties' => { 'name' => { 'type' => 'text' } } } }

      before do
        schema_dir = File.join(schemas_path, alias_name)
        FileUtils.mkdir_p(schema_dir)
        File.write(File.join(schema_dir, 'mappings.json'), mappings.to_json)
      end

      it 'returns parsed mappings' do
        result = described_class.get_mappings(alias_name)
        expect(result).to eq(mappings)
      end
    end

    context 'when mappings.json does not exist' do
      it 'returns nil' do
        result = described_class.get_mappings('nonexistent')
        expect(result).to be_nil
      end
    end

    context 'when mappings.json contains invalid JSON' do
      let(:alias_name) { 'products' }

      before do
        schema_dir = File.join(schemas_path, alias_name)
        FileUtils.mkdir_p(schema_dir)
        File.write(File.join(schema_dir, 'mappings.json'), 'invalid json')
      end

      it 'raises JSON parse error' do
        expect { described_class.get_mappings(alias_name) }.to raise_error(JSON::ParserError)
      end
    end
  end

  describe '.get_reindex_script' do
    let(:alias_name) { 'products' }
    let(:schema_dir) { File.join(schemas_path, alias_name) }

    before do
      FileUtils.mkdir_p(schema_dir)
    end

    context 'when reindex.painless exists' do
      let(:script_content) { 'ctx._source.reindexed = true' }

      before do
        File.write(File.join(schema_dir, 'reindex.painless'), script_content)
      end

      it 'returns the script content' do
        result = described_class.get_reindex_script(alias_name)
        expect(result).to eq(script_content)
      end
    end

    context 'when reindex.painless does not exist' do
      it 'returns nil' do
        result = described_class.get_reindex_script(alias_name)
        expect(result).to be_nil
      end
    end
  end

  describe '.discover_all_schemas' do
    context 'when schemas directory does not exist' do
      before do
        FileUtils.rm_rf(schemas_path)
      end

      it 'returns empty array' do
        result = described_class.discover_all_schemas
        expect(result).to eq([])
      end
    end

    context 'when schemas directory exists' do
      let(:alias1_name) { 'products' }
      let(:alias2_name) { 'users' }
      let(:alias1_dir) { File.join(schemas_path, alias1_name) }
      let(:alias2_dir) { File.join(schemas_path, alias2_name) }
      let(:settings) { { 'number_of_shards' => 1 } }
      let(:mappings) { { 'properties' => { 'name' => { 'type' => 'text' } } } }

      before do
        # Create valid schema 1
        FileUtils.mkdir_p(alias1_dir)
        File.write(File.join(alias1_dir, 'settings.json'), settings.to_json)
        File.write(File.join(alias1_dir, 'mappings.json'), mappings.to_json)
        
        # Create valid schema 2
        FileUtils.mkdir_p(alias2_dir)
        File.write(File.join(alias2_dir, 'settings.json'), settings.to_json)
        File.write(File.join(alias2_dir, 'mappings.json'), mappings.to_json)
        
        # Create invalid schema (missing files)
        FileUtils.mkdir_p(File.join(schemas_path, 'invalid_schema'))
      end

      it 'returns only valid schemas' do
        result = described_class.discover_all_schemas
        
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result).to contain_exactly('products', 'users')
      end
    end

    context 'when schema has only settings.json' do
      let(:alias_name) { 'products' }
      let(:schema_dir) { File.join(schemas_path, alias_name) }

      before do
        FileUtils.mkdir_p(schema_dir)
        File.write(File.join(schema_dir, 'settings.json'), {}.to_json)
        # No mappings.json
      end

      it 'excludes schema from results' do
        result = described_class.discover_all_schemas
        expect(result).to eq([])
      end
    end

    context 'when schema has only mappings.json' do
      let(:alias_name) { 'products' }
      let(:schema_dir) { File.join(schemas_path, alias_name) }

      before do
        FileUtils.mkdir_p(schema_dir)
        File.write(File.join(schema_dir, 'mappings.json'), {}.to_json)
        # No settings.json
      end

      it 'excludes schema from results' do
        result = described_class.discover_all_schemas
        expect(result).to eq([])
      end
    end
  end
end