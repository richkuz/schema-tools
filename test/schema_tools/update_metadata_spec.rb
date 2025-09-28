require_relative '../spec_helper'
require 'schema_tools/update_metadata'
require 'schema_tools/client'
require 'schema_tools/schema_revision'
require 'schema_tools/config'
require 'tempfile'
require 'webmock/rspec'

RSpec.describe SchemaTools do
  let(:temp_dir) { Dir.mktmpdir }
  let(:schemas_path) { File.join(temp_dir, 'schemas') }
  let(:original_schemas_path) { SchemaTools::Config::SCHEMAS_PATH }
  let(:original_schemurai_user) { SchemaTools::Config::SCHEMURAI_USER }
  let(:client) { instance_double(SchemaTools::Client) }
  let(:index_name) { 'products-2' }
  let(:revision_path) { File.join(schemas_path, index_name, 'revisions', '1') }
  let(:mappings_path) { File.join(revision_path, 'mappings.json') }
  
  before do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(schemas_path)
    allow(SchemaTools::Config).to receive(:SCHEMURAI_USER).and_return('test_user')
    FileUtils.mkdir_p(revision_path)
    
    initial_mappings = {
      'properties' => {
        'id' => { 'type' => 'keyword' },
        'name' => { 'type' => 'text' }
      }
    }
    File.write(mappings_path, JSON.pretty_generate(initial_mappings))
  end
  
  after do
    allow(SchemaTools::Config).to receive(:SCHEMAS_PATH).and_return(original_schemas_path)
    allow(SchemaTools::Config).to receive(:SCHEMURAI_USER).and_return(original_schemurai_user)
    FileUtils.rm_rf(temp_dir)
  end

  describe '.update_metadata' do
    context 'parameter validation' do
      it 'raises error when index_name is missing' do
        expect {
          SchemaTools.update_metadata(index_name: nil, metadata: {}, client: client)
        }.to raise_error('index_name parameter is required')
      end

      it 'raises error when metadata is missing' do
        expect {
          SchemaTools.update_metadata(index_name: index_name, metadata: nil, client: client)
        }.to raise_error('metadata parameter is required')
      end

      it 'raises error when client is missing' do
        expect {
          SchemaTools.update_metadata(index_name: index_name, metadata: {}, client: nil)
        }.to raise_error('client is required')
      end
    end

    context 'when no revisions exist' do
      before do
        FileUtils.rm_rf(revision_path)
      end

      it 'raises error when no revisions found' do
        expect {
          SchemaTools.update_metadata(index_name: index_name, metadata: {}, client: client)
        }.to raise_error("No revisions found for #{index_name}")
      end
    end

    context 'successful metadata update' do
      let(:existing_mappings) do
        {
          'properties' => {
            'id' => { 'type' => 'keyword' },
            'name' => { 'type' => 'text' }
          },
          '_meta' => {
            'schemurai_revision' => {
              'reindex_started_at' => '2023-01-01T10:00:00Z',
              'custom_field' => 'existing_value'
            }
          }
        }
      end

      let(:new_metadata) do
        {
          'reindex_completed_at' => '2023-01-01T11:00:00Z',
          'custom_field' => 'new_value'
        }
      end

      before do
        allow(client).to receive(:get_index_mappings).with(index_name).and_return(existing_mappings)
        allow(client).to receive(:update_index_mappings).with(index_name, anything)
      end

      it 'calls client.update_index_mappings with correct parameters' do
        SchemaTools.update_metadata(
          index_name: index_name,
          metadata: new_metadata,
          client: client
        )

        expect(client).to have_received(:update_index_mappings).with(index_name, anything)
      end

      it 'updates the mappings.json file on disk' do
        SchemaTools.update_metadata(
          index_name: index_name,
          metadata: new_metadata,
          client: client
        )

        updated_mappings = JSON.parse(File.read(mappings_path))
        metadata = updated_mappings['_meta']['schemurai_revision']
        
        expect(metadata).to include(
          'reindex_started_at' => '2023-01-01T10:00:00Z',
          'custom_field' => 'new_value', # new metadata takes precedence
          'reindex_completed_at' => '2023-01-01T11:00:00Z',
          'revision' => 'products-2/revisions/1',
          'revision_applied_by' => 'test_user'
        )
        
        # Check that revision_applied_at is a valid ISO8601 timestamp
        expect(metadata['revision_applied_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'when no existing metadata exists' do
      let(:empty_mappings) do
        {
          'properties' => {
            'id' => { 'type' => 'keyword' },
            'name' => { 'type' => 'text' }
          }
        }
      end

      let(:new_metadata) do
        {
          'reindex_started_at' => '2023-01-01T10:00:00Z'
        }
      end

      before do
        allow(client).to receive(:get_index_mappings).with(index_name).and_return(empty_mappings)
        allow(client).to receive(:update_index_mappings).with(index_name, anything)
      end

      it 'creates new metadata structure' do
        SchemaTools.update_metadata(
          index_name: index_name,
          metadata: new_metadata,
          client: client
        )

        expect(client).to have_received(:update_index_mappings).with(index_name, anything)
      end

      it 'creates _meta structure in mappings.json file' do
        SchemaTools.update_metadata(
          index_name: index_name,
          metadata: new_metadata,
          client: client
        )

        updated_mappings = JSON.parse(File.read(mappings_path))
        metadata = updated_mappings['_meta']['schemurai_revision']
        
        expect(metadata).to include(
          'reindex_started_at' => '2023-01-01T10:00:00Z',
          'revision' => 'products-2/revisions/1',
          'revision_applied_by' => 'test_user'
        )
        
        # Check that revision_applied_at is a valid ISO8601 timestamp
        expect(metadata['revision_applied_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'when mappings.json file does not exist' do
      before do
        File.delete(mappings_path)
        allow(client).to receive(:get_index_mappings).with(index_name).and_return({})
        allow(client).to receive(:update_index_mappings).with(index_name, anything)
      end

      it 'raises an error when mappings.json file does not exist' do
        new_metadata = { 'custom_field' => 'value' }
        
        expect {
          SchemaTools.update_metadata(
            index_name: index_name,
            metadata: new_metadata,
            client: client
          )
        }.to raise_error(Errno::ENOENT, /No such file or directory/)
      end
    end

    context 'persistent metadata' do
      before do
        allow(client).to receive(:get_index_mappings).with(index_name).and_return({})
        allow(client).to receive(:update_index_mappings).with(index_name, anything)
      end

      it 'always sets revision, revision_applied_at, and revision_applied_by' do
        SchemaTools.update_metadata(
          index_name: index_name,
          metadata: { 'custom_field' => 'value' },
          client: client
        )

        updated_mappings = JSON.parse(File.read(mappings_path))
        metadata = updated_mappings['_meta']['schemurai_revision']
        
        expect(metadata).to include(
          'custom_field' => 'value',
          'revision' => 'products-2/revisions/1',
          'revision_applied_by' => 'test_user'
        )
        
        # Check that revision_applied_at is a valid ISO8601 timestamp
        expect(metadata['revision_applied_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'overwrites persistent metadata if provided in input metadata' do
        input_metadata = {
          'revision' => 'custom_revision',
          'revision_applied_at' => '2023-01-01T12:00:00Z',
          'revision_applied_by' => 'custom_user'
        }

        SchemaTools.update_metadata(
          index_name: index_name,
          metadata: input_metadata,
          client: client
        )

        updated_mappings = JSON.parse(File.read(mappings_path))
        metadata = updated_mappings['_meta']['schemurai_revision']
        
        expect(metadata).to include(
          'revision' => 'products-2/revisions/1', # persistent metadata takes precedence
          'revision_applied_by' => 'test_user'
        )
        
        # Check that revision_applied_at is a valid ISO8601 timestamp
        expect(metadata['revision_applied_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'with multiple revisions' do
      let(:revision_2_path) { File.join(schemas_path, index_name, 'revisions', '2') }
      let(:mappings_2_path) { File.join(revision_2_path, 'mappings.json') }

      before do
        FileUtils.mkdir_p(revision_2_path)
        File.write(mappings_2_path, JSON.pretty_generate({
          'properties' => { 'id' => { 'type' => 'keyword' } }
        }))
        
        allow(client).to receive(:get_index_mappings).with(index_name).and_return({})
        allow(client).to receive(:update_index_mappings).with(index_name, anything)
      end

      it 'updates the latest revision (revision 2)' do
        SchemaTools.update_metadata(
          index_name: index_name,
          metadata: { 'custom_field' => 'value' },
          client: client
        )

        # Should update revision 2, not revision 1
        updated_mappings = JSON.parse(File.read(mappings_2_path))
        metadata = updated_mappings['_meta']['schemurai_revision']
        
        expect(metadata).to include(
          'custom_field' => 'value',
          'revision' => 'products-2/revisions/2',
          'revision_applied_by' => 'test_user'
        )
        
        # Check that revision_applied_at is a valid ISO8601 timestamp
        expect(metadata['revision_applied_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'error handling' do
      before do
        allow(client).to receive(:get_index_mappings).with(index_name).and_return({})
        allow(client).to receive(:update_index_mappings).with(index_name, anything)
      end

      it 'handles client errors gracefully' do
        allow(client).to receive(:update_index_mappings).and_raise('Connection error')

        expect {
          SchemaTools.update_metadata(
            index_name: index_name,
            metadata: { 'custom_field' => 'value' },
            client: client
          )
        }.to raise_error('Connection error')
      end
    end
  end
end