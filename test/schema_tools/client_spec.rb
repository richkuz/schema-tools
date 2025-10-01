require_relative '../spec_helper'
require 'schema_tools/client'

RSpec.describe SchemaTools::Client do
  let(:client) { SchemaTools::Client.new('http://localhost:9200') }
  
  describe '#get' do
    it 'returns parsed JSON for successful requests' do
      response_body = { 'test' => 'data' }.to_json
      stub_request(:get, 'http://localhost:9200/test')
        .to_return(status: 200, body: response_body)
      
      result = client.get('/test')
      expect(result).to eq({ 'test' => 'data' })
    end
    
    it 'returns nil for 404 responses' do
      stub_request(:get, 'http://localhost:9200/test')
        .to_return(status: 404)
      
      result = client.get('/test')
      expect(result).to be_nil
    end
    
    it 'raises error for non-200/404 responses' do
      stub_request(:get, 'http://localhost:9200/test')
        .to_return(status: 500, body: 'Internal Server Error')
      
      expect { client.get('/test') }.to raise_error(/HTTP 500/)
    end
  end
  
  describe '#put' do
    it 'returns parsed JSON for successful requests' do
      response_body = { 'acknowledged' => true }.to_json
      stub_request(:put, 'http://localhost:9200/test')
        .with(body: { 'data' => 'test' }.to_json)
        .to_return(status: 200, body: response_body)
      
      result = client.put('/test', { 'data' => 'test' })
      expect(result).to eq({ 'acknowledged' => true })
    end
  end
  
  describe '#index_exists?' do
    it 'returns true when index exists' do
      response_body = { 'test-index' => { 'settings' => {} } }.to_json
      stub_request(:get, 'http://localhost:9200/test-index')
        .to_return(status: 200, body: response_body)
      
      expect(client.index_exists?('test-index')).to be true
    end
    
    it 'returns false when index does not exist' do
      stub_request(:get, 'http://localhost:9200/test-index')
        .to_return(status: 404)
      
      expect(client.index_exists?('test-index')).to be false
    end
  end
  
  describe '#get_schema_revision' do
    it 'returns revision when present' do
      response_body = {
        'test-index' => {
          'mappings' => {
            '_meta' => {
              'schemurai_revision' => {
                'revision' => 'test-index/revisions/1'
              }
            }
          }
        }
      }.to_json
      
      stub_request(:get, 'http://localhost:9200/test-index')
        .to_return(status: 200, body: response_body)
      
      expect(client.get_schema_revision('test-index')).to eq('test-index/revisions/1')
    end
    
    it 'returns nil when revision not present' do
      response_body = {
        'test-index' => {
          'settings' => {
            'index' => {}
          }
        }
      }.to_json
      
      stub_request(:get, 'http://localhost:9200/test-index')
        .to_return(status: 200, body: response_body)
      
      expect(client.get_schema_revision('test-index')).to be_nil
    end
  end

  describe '#get_stored_scripts' do
    context 'when legacy API works (Elasticsearch/older OpenSearch)' do
      it 'returns stored scripts when present' do
        response_body = {
          'script1' => {
            'script' => {
              'source' => 'ctx._source.test = "value"'
            }
          },
          'script2' => {
            'script' => {
              'source' => 'ctx._source.another = "test"'
            }
          }
        }.to_json
        
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 200, body: response_body)
        
        result = client.get_stored_scripts
        expect(result).to eq({
          'script1' => 'ctx._source.test = "value"',
          'script2' => 'ctx._source.another = "test"'
        })
      end
      
      it 'returns empty hash when no scripts present' do
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 404)
        
        result = client.get_stored_scripts
        expect(result).to eq({})
      end
    end

    context 'when legacy API fails (OpenSearch 2.x)' do
      it 'falls back to new API and returns stored scripts' do
        # Legacy API fails with invalid index name error
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 400, body: '{"error":{"type":"invalid_index_name_exception","reason":"Invalid index name [_scripts], must not start with \'_\'."}}')
        
        # New API succeeds
        new_api_response = {
          'metadata' => {
            'stored_scripts' => {
              'script1' => {
                'source' => 'ctx._source.test = "value"'
              },
              'script2' => {
                'source' => 'ctx._source.another = "test"'
              }
            }
          }
        }.to_json
        
        stub_request(:get, 'http://localhost:9200/_cluster/state/metadata?filter_path=metadata.stored_scripts')
          .to_return(status: 200, body: new_api_response)
        
        result = client.get_stored_scripts
        expect(result).to eq({
          'script1' => 'ctx._source.test = "value"',
          'script2' => 'ctx._source.another = "test"'
        })
      end

      it 'returns empty hash when new API has no stored scripts' do
        # Legacy API fails
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 400, body: '{"error":{"type":"invalid_index_name_exception"}}')
        
        # New API returns empty stored_scripts
        new_api_response = {
          'metadata' => {
            'stored_scripts' => {}
          }
        }.to_json
        
        stub_request(:get, 'http://localhost:9200/_cluster/state/metadata?filter_path=metadata.stored_scripts')
          .to_return(status: 200, body: new_api_response)
        
        result = client.get_stored_scripts
        expect(result).to eq({})
      end

      it 'returns empty hash when new API has no stored_scripts field' do
        # Legacy API fails
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 400, body: '{"error":{"type":"invalid_index_name_exception"}}')
        
        # New API returns metadata without stored_scripts field
        new_api_response = {
          'metadata' => {
            'indices' => {}
          }
        }.to_json
        
        stub_request(:get, 'http://localhost:9200/_cluster/state/metadata?filter_path=metadata.stored_scripts')
          .to_return(status: 200, body: new_api_response)
        
        result = client.get_stored_scripts
        expect(result).to eq({})
      end

      it 'returns empty hash when both APIs fail' do
        # Legacy API fails
        stub_request(:get, 'http://localhost:9200/_scripts')
          .to_return(status: 400, body: '{"error":{"type":"invalid_index_name_exception"}}')
        
        # New API also fails
        stub_request(:get, 'http://localhost:9200/_cluster/state/metadata?filter_path=metadata.stored_scripts')
          .to_return(status: 500, body: 'Internal Server Error')
        
        # Should not raise an error, just return empty hash
        result = client.get_stored_scripts
        expect(result).to eq({})
      end
    end
  end

  describe '#bulk_index' do
    let(:documents) do
      [
        { 'title' => 'Document 1', 'content' => 'This is the first document' },
        { 'title' => 'Document 2', 'content' => 'This is the second document' }
      ]
    end

    let(:index_name) { 'test-index' }

    it 'formats documents correctly for bulk API' do
      expected_body = [
        { index: { _index: index_name } },
        documents[0],
        { index: { _index: index_name } },
        documents[1]
      ].map(&:to_json).join("\n") + "\n"

      response_body = {
        'took' => 5,
        'errors' => false,
        'items' => [
          { 'index' => { '_index' => index_name, '_id' => '1', 'status' => 201 } },
          { 'index' => { '_index' => index_name, '_id' => '2', 'status' => 201 } }
        ]
      }.to_json

      stub_request(:post, 'http://localhost:9200/_bulk')
        .with(
          body: expected_body,
          headers: { 'Content-Type' => 'application/x-ndjson' }
        )
        .to_return(status: 200, body: response_body)

      result = client.bulk_index(documents, index_name)
      expect(result['errors']).to be false
      expect(result['items'].length).to eq(2)
    end

    it 'handles bulk indexing errors' do
      response_body = {
        'took' => 5,
        'errors' => true,
        'items' => [
          { 'index' => { '_index' => index_name, '_id' => '1', 'status' => 201 } },
          { 'index' => { '_index' => index_name, '_id' => '2', 'status' => 400, 'error' => { 'type' => 'mapper_parsing_exception' } } }
        ]
      }.to_json

      stub_request(:post, 'http://localhost:9200/_bulk')
        .to_return(status: 200, body: response_body)

      result = client.bulk_index(documents, index_name)
      expect(result['errors']).to be true
      expect(result['items'].length).to eq(2)
    end

    it 'raises error for non-200 responses' do
      stub_request(:post, 'http://localhost:9200/_bulk')
        .to_return(status: 500, body: 'Internal Server Error')

      expect { client.bulk_index(documents, index_name) }
        .to raise_error(/HTTP 500/)
    end

    it 'handles empty document array' do
      response_body = {
        'took' => 0,
        'errors' => false,
        'items' => []
      }.to_json

      stub_request(:post, 'http://localhost:9200/_bulk')
        .to_return(status: 200, body: response_body)

      result = client.bulk_index([], index_name)
      expect(result['errors']).to be false
      expect(result['items']).to be_empty
    end

    context 'in dry run mode' do
      let(:dry_run_client) { SchemaTools::Client.new('http://localhost:9200', dryrun: true) }

      it 'prints curl command instead of making request' do
        expect { dry_run_client.bulk_index(documents, index_name) }
          .to output(/🔍 DRY RUN - Would execute: curl -X POST/).to_stdout_from_any_process
      end

      it 'returns mock response in dry run mode' do
        result = dry_run_client.bulk_index(documents, index_name)
        expect(result['items'].length).to eq(2)
        expect(result['items'].all? { |item| item.dig('index', 'status') == 201 }).to be true
      end
    end
  end
end