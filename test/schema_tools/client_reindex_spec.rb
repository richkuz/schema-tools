require_relative '../spec_helper'
require 'schema_tools/client'

RSpec.describe SchemaTools::Client do
  let(:client) { SchemaTools::Client.new('http://localhost:9200') }
  let(:source_index) { 'source-index' }
  let(:dest_index) { 'dest-index' }
  let(:script) { 'ctx._source.new_field = "transformed"' }

  describe '#reindex' do
    context 'without script' do
      it 'sends correct reindex request' do
        expected_body = {
          source: { index: source_index },
          dest: { index: dest_index },
          conflicts: "proceed"
        }
        
        response_body = { 'task' => 'FEl-TdjcTpmIvnE5_1fv4Q:164963' }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=false&refresh=false')
          .with(body: expected_body.to_json)
          .to_return(status: 200, body: response_body)
        
        result = client.reindex(source_index, dest_index)
        expect(result).to eq({ 'task' => 'FEl-TdjcTpmIvnE5_1fv4Q:164963' })
      end
    end

    context 'with script' do
      it 'includes script in reindex request' do
        expected_body = {
          source: { index: source_index },
          dest: { index: dest_index },
          conflicts: "proceed",
          script: { lang: 'painless', source: script }
        }
        
        response_body = { 'task' => 'FEl-TdjcTpmIvnE5_1fv4Q:164963' }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=false&refresh=false')
          .with(body: expected_body.to_json)
          .to_return(status: 200, body: response_body)
        
        result = client.reindex(source_index, dest_index, script)
        expect(result).to eq({ 'task' => 'FEl-TdjcTpmIvnE5_1fv4Q:164963' })
      end
    end

    context 'with empty script' do
      it 'does not include script when script is nil' do
        expected_body = {
          source: { index: source_index },
          dest: { index: dest_index },
          conflicts: "proceed"
        }
        
        response_body = { 'task' => 'FEl-TdjcTpmIvnE5_1fv4Q:164963' }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=false&refresh=false')
          .with(body: expected_body.to_json)
          .to_return(status: 200, body: response_body)
        
        result = client.reindex(source_index, dest_index, nil)
        expect(result).to eq({ 'task' => 'FEl-TdjcTpmIvnE5_1fv4Q:164963' })
      end
    end

    it 'raises error for non-200 responses' do
      stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=false&refresh=false')
        .to_return(status: 500, body: 'Internal Server Error')
      
      expect { client.reindex(source_index, dest_index) }
        .to raise_error(/HTTP 500/)
    end

    context 'in dry run mode' do
      let(:dry_run_client) { SchemaTools::Client.new('http://localhost:9200', dryrun: true) }

      it 'returns mock response without making actual request' do
        result = dry_run_client.reindex(source_index, dest_index)
        expect(result).to eq({ 'task' => 'FEl-TdjcTpmIvnE5_1fv4Q:164963' })
      end

      it 'logs dry run message' do
        expect { dry_run_client.reindex(source_index, dest_index) }
          .to output(/DRYRUN=true, simulation only/).to_stdout_from_any_process
      end
    end
  end

  describe '#reindex_one_doc' do
    context 'successful reindex' do
      it 'sends correct reindex request with single document query' do
        expected_body = {
          source: {
            index: source_index,
            query: { match_all: {} }
          },
          max_docs: 1,
          dest: { index: dest_index },
          conflicts: "proceed"
        }
        
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .with(body: expected_body.to_json)
          .to_return(status: 200, body: response_body)
        
        result = client.reindex_one_doc(source_index, dest_index)
        expect(result['total']).to eq(1)
        expect(result['created']).to eq(1)
      end

      it 'includes script when provided' do
        expected_body = {
          source: {
            index: source_index,
            query: { match_all: {} }
          },
          max_docs: 1,
          dest: { index: dest_index },
          conflicts: "proceed",
          script: { lang: 'painless', source: script }
        }
        
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .with(body: expected_body.to_json)
          .to_return(status: 200, body: response_body)
        
        result = client.reindex_one_doc(source_index, dest_index, script)
        expect(result['total']).to eq(1)
        expect(result['created']).to eq(1)
      end
    end

    context 'error handling' do
      it 'raises error when reindex has failures' do
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => [
            {
              'cause' => {
                'reason' => 'Document mapping type mismatch'
              }
            }
          ]
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        expect { client.reindex_one_doc(source_index, dest_index) }
          .to raise_error(/Reindex failed with internal errors. Failures: Document mapping type mismatch/)
      end

      it 'raises error when no documents found' do
        response_body = {
          'took' => 5,
          'total' => 0,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        expect { client.reindex_one_doc(source_index, dest_index) }
          .to raise_error(/Reindex query found 0 documents. Expected to find 1./)
      end

      it 'raises error when too many documents found' do
        response_body = {
          'took' => 15,
          'total' => 5,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        expect { client.reindex_one_doc(source_index, dest_index) }
          .to raise_error(/Reindex query found 5 documents. Expected to find 1./)
      end

      it 'raises error when document not indexed (created + updated != 1)' do
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 0,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 1,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        expect { client.reindex_one_doc(source_index, dest_index) }
          .to raise_error(/Reindex failed to index the document \(created: 0, updated: 0\). Noops: 1./)
      end

      it 'raises error when operation times out' do
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => true,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        expect { client.reindex_one_doc(source_index, dest_index) }
          .to raise_error(/Reindex operation timed out./)
      end

      it 'raises error for non-200 responses' do
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 500, body: 'Internal Server Error')
        
        expect { client.reindex_one_doc(source_index, dest_index) }
          .to raise_error(/HTTP 500/)
      end
    end

    context 'edge cases' do
      it 'handles document updated instead of created' do
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 0,
          'updated' => 1,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        result = client.reindex_one_doc(source_index, dest_index)
        expect(result['total']).to eq(1)
        expect(result['updated']).to eq(1)
        expect(result['created']).to eq(0)
      end

      it 'handles mixed created and updated' do
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        result = client.reindex_one_doc(source_index, dest_index)
        expect(result['total']).to eq(1)
        expect(result['created'] + result['updated']).to eq(1)
      end
    end

    context 'in dry run mode' do
      let(:dry_run_client) { SchemaTools::Client.new('http://localhost:9200', dryrun: true) }

      it 'raises error because dry run response is not valid for reindex_one_doc validation' do
        # The dry run mode returns a task response, but reindex_one_doc expects
        # a completed response with total, created, updated fields
        expect { dry_run_client.reindex_one_doc(source_index, dest_index) }
          .to raise_error(/Reindex query found 0 documents. Expected to find 1./)
      end
    end

    context 'interactive mode' do
      let(:interactive_client) { SchemaTools::Client.new('http://localhost:9200', interactive: true) }

      it 'awaits user input before making request' do
        response_body = {
          'took' => 15,
          'total' => 1,
          'created' => 1,
          'updated' => 0,
          'deleted' => 0,
          'noops' => 0,
          'timed_out' => false,
          'failures' => []
        }.to_json
        
        stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
          .to_return(status: 200, body: response_body)
        
        # Mock STDIN.gets to simulate user pressing Enter
        allow(STDIN).to receive(:gets).and_return("\n")
        
        expect { interactive_client.reindex_one_doc(source_index, dest_index) }
          .to output(/Press Enter to continue/).to_stdout
      end
    end
  end

  describe 'reindex vs reindex_one_doc differences' do
    it 'reindex uses async mode with wait_for_completion=false' do
      expected_url = '/_reindex?wait_for_completion=false&refresh=false'
      response_body = { 'task' => 'test-task-id' }.to_json
      
      stub_request(:post, "http://localhost:9200#{expected_url}")
        .to_return(status: 200, body: response_body)
      
      client.reindex(source_index, dest_index)
      
      expect(WebMock).to have_requested(:post, "http://localhost:9200#{expected_url}")
    end

    it 'reindex_one_doc uses sync mode with wait_for_completion=true' do
      expected_url = '/_reindex?wait_for_completion=true&refresh=true'
      response_body = {
        'took' => 15,
        'total' => 1,
        'created' => 1,
        'updated' => 0,
        'deleted' => 0,
        'noops' => 0,
        'timed_out' => false,
        'failures' => []
      }.to_json
      
      stub_request(:post, "http://localhost:9200#{expected_url}")
        .to_return(status: 200, body: response_body)
      
      client.reindex_one_doc(source_index, dest_index)
      
      expect(WebMock).to have_requested(:post, "http://localhost:9200#{expected_url}")
    end

    it 'reindex_one_doc includes max_docs=1 and match_all query' do
      expected_body = {
        source: {
          index: source_index,
          query: { match_all: {} }
        },
        max_docs: 1,
        dest: { index: dest_index },
        conflicts: "proceed"
      }
      
      response_body = {
        'took' => 15,
        'total' => 1,
        'created' => 1,
        'updated' => 0,
        'deleted' => 0,
        'noops' => 0,
        'timed_out' => false,
        'failures' => []
      }.to_json
      
      stub_request(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
        .with(body: expected_body.to_json)
        .to_return(status: 200, body: response_body)
      
      client.reindex_one_doc(source_index, dest_index)
      
      expect(WebMock).to have_requested(:post, 'http://localhost:9200/_reindex?wait_for_completion=true&refresh=true')
        .with(body: expected_body.to_json)
    end
  end
end