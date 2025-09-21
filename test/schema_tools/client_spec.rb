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
          'settings' => {
            'index' => {
              '_meta' => {
                'schema_tools_revision' => {
                  'revision' => 'test-index/revisions/1'
                }
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
end