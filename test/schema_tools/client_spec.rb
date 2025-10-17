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
          .to output(/DRYRUN=true, simulation only/).to_stdout_from_any_process
      end

      it 'returns mock response in dry run mode' do
        result = dry_run_client.bulk_index(documents, index_name)
        expect(result['items'].length).to eq(2)
        expect(result['items'].all? { |item| item.dig('index', 'status') == 201 }).to be true
      end
    end
  end

  describe '#reindex_one_doc' do
    let(:source_index) { 'source-index' }
    let(:dest_index) { 'dest-index' }

    context 'when source index has 1 document' do
      it 'successfully reindexes the document' do
        response_body = {
          'took' => 10,
          'timed_out' => false,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 1,
          'noops' => 0,
          'failures' => []
        }.to_json

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)

        result = client.reindex_one_doc(source_index: source_index, dest_index: dest_index)
        expect(result['total']).to eq(1)
        expect(result['created']).to eq(1)
      end
    end

    context 'when source index has 0 documents' do
      it 'handles empty index gracefully' do
        # Mock the reindex response showing 0 documents found
        reindex_response = {
          'took' => 5,
          'timed_out' => false,
          'total' => 0,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 0,
          'noops' => 0,
          'failures' => []
        }.to_json

        # Mock the doc count check to confirm source index is actually empty
        doc_count_response = { 'count' => 0 }.to_json

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: reindex_response)

        stub_request(:get, "http://localhost:9200/#{source_index}/_count")
          .to_return(status: 200, body: doc_count_response)

        # Should not raise an error and should log the message
        # Should not raise an error
        result = client.reindex_one_doc(source_index: source_index, dest_index: dest_index)
        expect(result['total']).to eq(0)
      end
    end

    context 'when reindex finds 0 docs but source actually has documents' do
      it 'raises an error indicating configuration issue' do
        # Mock the reindex response showing 0 documents found
        reindex_response = {
          'took' => 5,
          'timed_out' => false,
          'total' => 0,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 0,
          'noops' => 0,
          'failures' => []
        }.to_json

        # Mock the doc count check to show source index actually has documents
        doc_count_response = { 'count' => 5 }.to_json

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: reindex_response)

        stub_request(:get, "http://localhost:9200/#{source_index}/_count")
          .to_return(status: 200, body: doc_count_response)

        expect { client.reindex_one_doc(source_index: source_index, dest_index: dest_index) }
          .to raise_error(/Reindex query found 0 documents but source index has 5 documents/)
      end
    end

    context 'when source index has more than 1 document' do
      it 'raises an error for unexpected document count' do
        response_body = {
          'took' => 10,
          'timed_out' => false,
          'total' => 3,
          'created' => 3,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 1,
          'noops' => 0,
          'failures' => []
        }.to_json

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)

        expect { client.reindex_one_doc(source_index: source_index, dest_index: dest_index) }
          .to raise_error(/Reindex query found 3 documents. Expected to find 1./)
      end
    end

    context 'when reindex fails to index the document' do
      it 'raises an error with details' do
        response_body = {
          'took' => 10,
          'timed_out' => false,
          'total' => 1,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 1,
          'noops' => 1,
          'failures' => []
        }.to_json

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)

        expect { client.reindex_one_doc(source_index: source_index, dest_index: dest_index) }
          .to raise_error(/Reindex failed to index the document \(created: 0, updated: 0\). Noops: 1./)
      end
    end

    context 'when reindex has internal failures' do
      it 'raises an error with failure details' do
        response_body = {
          'took' => 10,
          'timed_out' => false,
          'total' => 1,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 1,
          'noops' => 0,
          'failures' => [
            {
              'index' => 'dest-index',
              'type' => '_doc',
              'id' => '1',
              'cause' => {
                'type' => 'document_missing_exception',
                'reason' => 'document missing'
              }
            }
          ]
        }.to_json

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)

        expect { client.reindex_one_doc(source_index: source_index, dest_index: dest_index) }
          .to raise_error(/Reindex failed with internal errors. Failures: document missing/)
      end
    end

    context 'when reindex times out' do
      it 'raises an error for timeout' do
        response_body = {
          'took' => 30000,
          'timed_out' => true,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 1,
          'noops' => 0,
          'failures' => []
        }.to_json

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)

        expect { client.reindex_one_doc(source_index: source_index, dest_index: dest_index) }
          .to raise_error(/Reindex operation timed out./)
      end
    end

    context 'with painless script' do
      it 'includes script in the reindex request' do
        response_body = {
          'took' => 10,
          'timed_out' => false,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'batches' => 1,
          'noops' => 0,
          'failures' => []
        }.to_json

        script_content = 'ctx._source.new_field = "transformed"'
        expected_body = {
          source: {
            index: source_index,
            query: { match_all: {} }
          },
          max_docs: 1,
          dest: { index: dest_index },
          conflicts: "proceed",
          script: { lang: 'painless', source: script_content }
        }

        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .with(body: expected_body.to_json)
          .to_return(status: 200, body: response_body)

        client.reindex_one_doc(source_index: source_index, dest_index: dest_index, script: script_content)
      end
    end
  end

  describe 'HTTPS support' do
    let(:https_client) { SchemaTools::Client.new('https://example.com:9200') }
    
    it 'creates HTTPS client successfully' do
      expect(https_client.url).to eq('https://example.com:9200')
    end
    
    it 'uses HTTPS for requests' do
      response_body = { 'test' => 'data' }.to_json
      stub_request(:get, 'https://example.com:9200/test')
        .to_return(status: 200, body: response_body)
      
      result = https_client.get('/test')
      expect(result).to eq({ 'test' => 'data' })
    end
    
    it 'handles default HTTPS port' do
      client_default_port = SchemaTools::Client.new('https://example.com')
      expect(client_default_port.url).to eq('https://example.com')
    end
    
    it 'handles custom HTTPS port' do
      client_custom_port = SchemaTools::Client.new('https://example.com:9443')
      expect(client_custom_port.url).to eq('https://example.com:9443')
    end
  end
end