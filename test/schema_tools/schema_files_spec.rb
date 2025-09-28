require_relative '../spec_helper'
require 'schema_tools/schema_files'
require 'schema_tools/schema_revision'
require 'tempfile'

RSpec.describe SchemaTools::SchemaFiles do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config::SCHEMAS_PATH }
  
  before do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    FileUtils.mkdir_p(schemas_path)
  end
  
  after do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
    FileUtils.rm_rf(temp_dir)
  end

  describe '.get_index_config' do
    context 'when index directory exists with valid index.json' do
      let(:index_name) { 'products' }
      let(:index_path) { File.join(schemas_path, index_name) }
      let(:index_config) { { 'name' => 'products', 'version' => 1 } }

      before do
        FileUtils.mkdir_p(index_path)
        File.write(File.join(index_path, 'index.json'), index_config.to_json)
      end

      it 'returns parsed JSON config' do
        result = described_class.get_index_config(index_name)
        expect(result).to eq(index_config)
      end
    end

    context 'when index directory does not exist' do
      it 'returns nil' do
        result = described_class.get_index_config('nonexistent')
        expect(result).to be_nil
      end
    end

    context 'when index.json does not exist' do
      let(:index_name) { 'products' }
      let(:index_path) { File.join(schemas_path, index_name) }

      before do
        FileUtils.mkdir_p(index_path)
      end

      it 'returns nil' do
        result = described_class.get_index_config(index_name)
        expect(result).to be_nil
      end
    end

    context 'when index.json contains invalid JSON' do
      let(:index_name) { 'products' }
      let(:index_path) { File.join(schemas_path, index_name) }

      before do
        FileUtils.mkdir_p(index_path)
        File.write(File.join(index_path, 'index.json'), 'invalid json')
      end

      it 'raises JSON parse error' do
        expect { described_class.get_index_config(index_name) }.to raise_error(JSON::ParserError)
      end
    end
  end

  describe '.get_revision_files' do
    let(:index_name) { 'products' }
    let(:revision_number) { '1' }
    let(:revision_path) { File.join(schemas_path, index_name, 'revisions', revision_number) }
    let(:schema_revision) { SchemaTools::SchemaRevision.new("#{index_name}/revisions/#{revision_number}") }
    let(:settings) { { 'number_of_shards' => 1 } }
    let(:mappings) { { 'properties' => { 'name' => { 'type' => 'text' } } } }

    before do
      FileUtils.mkdir_p(revision_path)
    end

    context 'when all files exist' do
      before do
        File.write(File.join(revision_path, 'settings.json'), settings.to_json)
        File.write(File.join(revision_path, 'mappings.json'), mappings.to_json)
        
        # Create painless scripts directory and files
        painless_dir = File.join(revision_path, 'painless_scripts')
        FileUtils.mkdir_p(painless_dir)
        File.write(File.join(painless_dir, 'script1.painless'), 'ctx._source.field = "value"')
        File.write(File.join(painless_dir, 'script2.painless'), 'ctx._source.other = "test"')
      end

      it 'returns all revision files' do
        result = described_class.get_revision_files(schema_revision)
        
        expect(result[:settings]).to eq(settings)
        expect(result[:mappings]).to eq(mappings)
        expect(result[:painless_scripts]).to eq({
          'script1' => 'ctx._source.field = "value"',
          'script2' => 'ctx._source.other = "test"'
        })
      end
    end

    context 'when painless_scripts directory does not exist' do
      before do
        File.write(File.join(revision_path, 'settings.json'), settings.to_json)
        File.write(File.join(revision_path, 'mappings.json'), mappings.to_json)
      end

      it 'returns empty painless_scripts hash' do
        result = described_class.get_revision_files(schema_revision)
        
        expect(result[:settings]).to eq(settings)
        expect(result[:mappings]).to eq(mappings)
        expect(result[:painless_scripts]).to eq({})
      end
    end

    context 'when settings.json is missing' do
      before do
        File.write(File.join(revision_path, 'mappings.json'), mappings.to_json)
      end

      it 'raises an error' do
        expect { described_class.get_revision_files(schema_revision) }.to raise_error(/#{File.join(revision_path, 'settings.json')} not found/)
      end
    end

    context 'when mappings.json is missing' do
      before do
        File.write(File.join(revision_path, 'settings.json'), settings.to_json)
      end

      it 'raises an error' do
        expect { described_class.get_revision_files(schema_revision) }.to raise_error(/#{File.join(revision_path, 'mappings.json')} not found/)
      end
    end

    context 'when JSON files contain invalid JSON' do
      before do
        File.write(File.join(revision_path, 'settings.json'), 'invalid json')
        File.write(File.join(revision_path, 'mappings.json'), mappings.to_json)
      end

      it 'raises JSON parse error' do
        expect { described_class.get_revision_files(schema_revision) }.to raise_error(JSON::ParserError)
      end
    end
  end

  describe '.get_reindex_script' do
    let(:index_name) { 'products' }
    let(:index_path) { File.join(schemas_path, index_name) }

    before do
      FileUtils.mkdir_p(index_path)
    end

    context 'when reindex.painless exists' do
      let(:script_content) { 'ctx._source.reindexed = true' }

      before do
        File.write(File.join(index_path, 'reindex.painless'), script_content)
      end

      it 'returns the script content' do
        result = described_class.get_reindex_script(index_name)
        expect(result).to eq(script_content)
      end
    end

    context 'when reindex.painless does not exist' do
      it 'returns nil' do
        result = described_class.get_reindex_script(index_name)
        expect(result).to be_nil
      end
    end
  end

  describe '.discover_all_schemas_with_latest_revisions' do
    context 'when schemas directory does not exist' do
      before do
        FileUtils.rm_rf(schemas_path)
      end

      it 'returns empty array' do
        result = described_class.discover_all_schemas_with_latest_revisions
        expect(result).to eq([])
      end
    end

    context 'when schemas directory exists' do
      let(:index1_name) { 'products' }
      let(:index2_name) { 'users' }
      let(:index1_path) { File.join(schemas_path, index1_name) }
      let(:index2_path) { File.join(schemas_path, index2_name) }
      let(:index1_config) { { 'name' => 'products', 'version' => 1 } }
      let(:index2_config) { { 'name' => 'users', 'version' => 1 } }

      before do
        # Create index1 with valid structure
        FileUtils.mkdir_p(index1_path)
        File.write(File.join(index1_path, 'index.json'), index1_config.to_json)
        
        revisions1_path = File.join(index1_path, 'revisions')
        FileUtils.mkdir_p(revisions1_path)
        FileUtils.mkdir_p(File.join(revisions1_path, '1'))
        FileUtils.mkdir_p(File.join(revisions1_path, '2'))
        
        # Create index2 with valid structure
        FileUtils.mkdir_p(index2_path)
        File.write(File.join(index2_path, 'index.json'), index2_config.to_json)
        
        revisions2_path = File.join(index2_path, 'revisions')
        FileUtils.mkdir_p(revisions2_path)
        FileUtils.mkdir_p(File.join(revisions2_path, '1'))
        
        # Create a directory without index.json (should be ignored)
        FileUtils.mkdir_p(File.join(schemas_path, 'invalid_schema'))
      end

      it 'returns schemas with latest revisions' do
        result = described_class.discover_all_schemas_with_latest_revisions
        
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        
        # Check that both schemas are included
        schema_names = result.map { |s| s[:index_name] }
        expect(schema_names).to contain_exactly('products', 'users')
        
        # Check products schema (should have revision 2 as latest)
        products_schema = result.find { |s| s[:index_name] == 'products' }
        expect(products_schema[:revision_number]).to eq('2')
        expect(products_schema[:latest_revision]).to eq(File.join(schemas_path, 'products', 'revisions', '2'))
        
        # Check users schema (should have revision 1 as latest)
        users_schema = result.find { |s| s[:index_name] == 'users' }
        expect(users_schema[:revision_number]).to eq('1')
        expect(users_schema[:latest_revision]).to eq(File.join(schemas_path, 'users', 'revisions', '1'))
      end
    end

    context 'when schema has no revisions' do
      let(:index_name) { 'products' }
      let(:index_path) { File.join(schemas_path, index_name) }
      let(:index_config) { { 'name' => 'products', 'version' => 1 } }

      before do
        FileUtils.mkdir_p(index_path)
        File.write(File.join(index_path, 'index.json'), index_config.to_json)
        # No revisions directory created
      end

      it 'excludes schema from results' do
        result = described_class.discover_all_schemas_with_latest_revisions
        expect(result).to eq([])
      end
    end
  end

  describe 'private methods' do
    describe '.load_json_file' do
      let(:temp_file) { Tempfile.new(['test', '.json']) }
      let(:valid_json) { { 'test' => 'value' } }

      after do
        temp_file.close
        temp_file.unlink
      end

      context 'when file exists with valid JSON' do
        before do
          temp_file.write(valid_json.to_json)
          temp_file.rewind
        end

        it 'returns parsed JSON' do
          result = described_class.send(:load_json_file, temp_file.path)
          expect(result).to eq(valid_json)
        end
      end

      context 'when file does not exist' do
        it 'raises an error' do
          expect { described_class.send(:load_json_file, '/nonexistent/file.json') }.to raise_error(/not found/)
        end
      end

      context 'when file contains invalid JSON' do
        before do
          temp_file.write('invalid json')
          temp_file.rewind
        end

        it 'raises JSON parse error' do
          expect { described_class.send(:load_json_file, temp_file.path) }.to raise_error(JSON::ParserError)
        end
      end
    end

    describe '.load_painless_scripts' do
      let(:scripts_dir) { File.join(temp_dir, 'scripts') }

      context 'when scripts directory does not exist' do
        it 'returns empty hash' do
          result = described_class.send(:load_painless_scripts, scripts_dir)
          expect(result).to eq({})
        end
      end

      context 'when scripts directory exists with painless files' do
        before do
          FileUtils.mkdir_p(scripts_dir)
          File.write(File.join(scripts_dir, 'script1.painless'), 'ctx._source.field = "value"')
          File.write(File.join(scripts_dir, 'script2.painless'), 'ctx._source.other = "test"')
          File.write(File.join(scripts_dir, 'not_painless.txt'), 'this should be ignored')
        end

        it 'returns hash of script names to content' do
          result = described_class.send(:load_painless_scripts, scripts_dir)
          expect(result).to eq({
            'script1' => 'ctx._source.field = "value"',
            'script2' => 'ctx._source.other = "test"'
          })
        end
      end

      context 'when scripts directory exists but is empty' do
        before do
          FileUtils.mkdir_p(scripts_dir)
        end

        it 'returns empty hash' do
          result = described_class.send(:load_painless_scripts, scripts_dir)
          expect(result).to eq({})
        end
      end
    end
  end
end