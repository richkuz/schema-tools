require_relative '../spec_helper'
require 'seeder/seeder'

RSpec.describe Seed do
  describe '.seed_data' do
    let(:mock_client) { double('client') }
    let(:index_name) { 'test-index' }
    let(:num_docs) { 5 }
    
    let(:sample_mappings) do
      {
        'properties' => {
          'title' => { 'type' => 'text' },
          'status' => { 'type' => 'keyword' },
          'count' => { 'type' => 'integer' },
          'price' => { 'type' => 'float' },
          'active' => { 'type' => 'boolean' },
          'created_at' => { 'type' => 'date' },
          'location' => { 'type' => 'geo_point' },
          'ip_address' => { 'type' => 'ip' },
          'metadata' => {
            'type' => 'object',
            'properties' => {
              'author' => { 'type' => 'keyword' },
              'tags' => { 'type' => 'text' }
            }
          }
        }
      }
    end

    before do
      allow(mock_client).to receive(:bulk_index).and_return({
        'items' => num_docs.times.map { { 'index' => { 'status' => 201 } } },
        'errors' => false
      })
    end

    it 'parses mappings and generates documents' do
      expect(mock_client).to receive(:bulk_index).with(
        array_including(hash_including('title', 'status', 'count')),
        index_name
      ).and_return({ 'items' => [], 'errors' => false })

      expect { Seed.seed_data(num_docs, sample_mappings, mock_client, index_name) }
        .to output(/Seeding 5 documents to index: test-index/).to_stdout
    end

    it 'handles bulk indexing errors gracefully' do
      allow(mock_client).to receive(:bulk_index).and_return({
        'items' => [
          { 'index' => { 'status' => 201 } },
          { 'index' => { 'status' => 400, 'error' => { 'type' => 'mapper_parsing_exception', 'reason' => 'failed to parse field' } } }
        ],
        'errors' => true
      })

      expect { Seed.seed_data(2, sample_mappings, mock_client, index_name) }
        .to output(/WARN: 1 documents failed to index/).to_stdout
    end

    it 'shows nested error details when available' do
      allow(mock_client).to receive(:bulk_index).and_return({
        'items' => [
          { 'index' => { 
            'status' => 400, 
            'error' => { 
              'type' => 'mapper_parsing_exception', 
              'reason' => 'failed to parse field',
              'caused_by' => {
                'type' => 'number_format_exception',
                'reason' => 'invalid number format'
              }
            } 
          } }
        ],
        'errors' => true
      })

      expect { Seed.seed_data(1, sample_mappings, mock_client, index_name) }
        .to output(/WARN: 1 documents failed to index/).to_stdout
    end

    it 'raises error when bulk indexing fails completely' do
      allow(mock_client).to receive(:bulk_index).and_raise(StandardError.new('Connection failed'))

      expect { Seed.seed_data(num_docs, sample_mappings, mock_client, index_name) }
        .to raise_error(StandardError, 'Connection failed')
    end

    it 'handles circuit breaker exceptions with helpful error message' do
      circuit_breaker_error = StandardError.new('HTTP 429: {"error":{"type":"circuit_breaking_exception"}}')
      allow(mock_client).to receive(:bulk_index).and_raise(circuit_breaker_error)

      expect { Seed.seed_data(num_docs, sample_mappings, mock_client, index_name) }
        .to raise_error(StandardError, /Circuit breaker triggered/)
    end

    it 'processes documents in batches' do
      expect(mock_client).to receive(:bulk_index).exactly(2).times  # 50 docs / 25 batch_size = 2 batches

      Seed.seed_data(50, sample_mappings, mock_client, index_name)
    end

    it 'handles large document counts with multiple batches' do
      expect(mock_client).to receive(:bulk_index).exactly(10).times  # 250 docs / 25 batch_size = 10 batches

      Seed.seed_data(250, sample_mappings, mock_client, index_name)
    end
  end

  describe '.parse_mappings' do
    let(:mappings_with_properties) do
      {
        'properties' => {
          'name' => { 'type' => 'text' },
          'age' => { 'type' => 'integer' }
        }
      }
    end

    let(:empty_mappings) { {} }

    it 'parses mappings with properties' do
      result = Seed.send(:parse_mappings, mappings_with_properties)
      
      expect(result).to eq({
        'name' => { type: 'text', properties: nil, format: nil },
        'age' => { type: 'integer', properties: nil, format: nil }
      })
    end

    it 'handles empty mappings' do
      result = Seed.send(:parse_mappings, empty_mappings)
      expect(result).to eq({})
    end

    it 'handles nested object properties' do
      nested_mappings = {
        'properties' => {
          'user' => {
            'type' => 'object',
            'properties' => {
              'name' => { 'type' => 'text' },
              'email' => { 'type' => 'keyword' }
            }
          }
        }
      }

      result = Seed.send(:parse_mappings, nested_mappings)
      
      expect(result['user'][:properties]).to eq({
        'name' => { 'type' => 'text' },
        'email' => { 'type' => 'keyword' }
      })
    end
  end

  describe '.generate_field_value' do
    context 'text fields' do
      it 'generates text content' do
        field_config = { type: 'text' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result.split.length).to be_between(10, 50)
      end
    end

    context 'keyword fields' do
      it 'generates keyword content' do
        field_config = { type: 'keyword' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end

    context 'integer fields' do
      it 'generates integer values' do
        field_config = { type: 'integer' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-100, 999_999_999)
      end
    end

    context 'long fields' do
      it 'generates long values' do
        field_config = { type: 'long' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-100, 999_999_999)
      end
    end

    context 'short fields' do
      it 'generates short values within valid range' do
        field_config = { type: 'short' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-100, 100) # Within Java short range
      end
    end

    context 'float fields' do
      it 'generates float values' do
        field_config = { type: 'float' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(-5.0, 1000.0)
      end
    end

    context 'double fields' do
      it 'generates double values' do
        field_config = { type: 'double' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(-5.0, 1000.0)
      end
    end

    context 'boolean fields' do
      it 'generates boolean values' do
        field_config = { type: 'boolean' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect([true, false]).to include(result)
      end
    end

    context 'date fields' do
      it 'generates ISO 8601 date strings by default' do
        field_config = { type: 'date' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'generates epoch_millis format when specified' do
        field_config = { type: 'date', format: 'epoch_millis' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be > 1_000_000_000_000 # Should be milliseconds since epoch
      end

      it 'generates epoch_second format when specified' do
        field_config = { type: 'date', format: 'epoch_second' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be > 1_000_000_000 # Should be seconds since epoch
      end

      it 'generates yyyy-MM-dd format when specified' do
        field_config = { type: 'date', format: 'yyyy-MM-dd' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d{4}-\d{2}-\d{2}/)
      end
    end

    context 'object fields' do
      it 'generates nested object values' do
        field_config = {
          type: 'object',
          properties: {
            'name' => { 'type' => 'text' },
            'age' => { 'type' => 'integer' }
          }
        }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('name')
        expect(result).to have_key('age')
        expect(result['name']).to be_a(String)
        expect(result['age']).to be_a(Integer)
      end

      it 'handles empty object properties' do
        field_config = { type: 'object', properties: nil }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to eq({})
      end
    end

    context 'nested fields' do
      it 'generates array of nested objects' do
        field_config = {
          type: 'nested',
          properties: {
            'chunk_id' => { 'type' => 'keyword' },
            'content' => { 'type' => 'text' }
          }
        }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_an(Array)
        expect(result.length).to be_between(1, 3)
        result.each do |nested_obj|
          expect(nested_obj).to be_a(Hash)
          expect(nested_obj).to have_key('chunk_id')
          expect(nested_obj).to have_key('content')
          expect(nested_obj['chunk_id']).to be_a(String)
          expect(nested_obj['content']).to be_a(String)
        end
      end

      it 'handles empty nested properties' do
        field_config = { type: 'nested', properties: nil }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to eq([])
      end
    end

    context 'rank_features fields' do
      it 'generates rank features object' do
        field_config = { type: 'rank_features' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result.keys.length).to be_between(3, 8)
        result.each do |feature_name, score|
          expect(feature_name).to be_a(String)
          expect(score).to be_a(Float)
          # OpenSearch requires positive normal floats with minimum value of 1.17549435E-38
          # We use 1.0e-30 to avoid floating-point precision issues
          expect(score).to be_between(1.0e-30, 1.0)
        end
      end
    end

    context 'completion fields' do
      it 'generates completion suggestions' do
        field_config = { type: 'completion' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('input')
        expect(result).to have_key('weight')
        expect(result['input']).to be_an(Array)
        expect(result['input'].length).to be_between(1, 2)
        expect(result['weight']).to be_a(Integer)
        expect(result['weight']).to be_between(1, 100)
      end
    end

    context 'search_as_you_type fields' do
      it 'generates search-as-you-type text' do
        field_config = { type: 'search_as_you_type' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result.split.length).to be_between(1, 3)
      end
    end

    context 'token_count fields' do
      it 'generates token count values' do
        field_config = { type: 'token_count' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(1, 50)
      end
    end

    context 'alias fields' do
      it 'returns nil for alias fields' do
        field_config = { type: 'alias' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_nil
      end
    end

    context 'byte fields' do
      it 'generates byte values within valid range' do
        field_config = { type: 'byte' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-128, 127)
      end
    end

    context 'half_float fields' do
      it 'generates half-float values' do
        field_config = { type: 'half_float' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(-50.0, 50.0)
      end
    end

    context 'scaled_float fields' do
      it 'generates scaled float values' do
        field_config = { type: 'scaled_float' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(0.0, 100.0)
      end
    end

    context 'unsigned_long fields' do
      it 'generates unsigned long values' do
        field_config = { type: 'unsigned_long' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(0, 999_999_999)
      end
    end

    context 'date_nanos fields' do
      it 'generates date with nanosecond precision' do
        field_config = { type: 'date_nanos' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}/)
      end
    end

    context 'wildcard fields' do
      it 'generates wildcard text' do
        field_config = { type: 'wildcard' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\w+_\d+/)
      end
    end

    context 'constant_keyword fields' do
      it 'generates constant keyword value' do
        field_config = { type: 'constant_keyword' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to eq('constant_value')
      end
    end

    context 'geo_shape fields' do
      it 'generates geo shape objects' do
        field_config = { type: 'geo_shape' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('type')
        expect(result).to have_key('coordinates')
        expect(result['type']).to eq('point')
        expect(result['coordinates']).to be_an(Array)
        expect(result['coordinates'].length).to eq(2)
        expect(result['coordinates'][0]).to be_between(-180.0, 180.0)
        expect(result['coordinates'][1]).to be_between(-90.0, 90.0)
      end
    end

    context 'date_range fields' do
      it 'generates date range objects' do
        field_config = { type: 'date_range' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('gte')
        expect(result).to have_key('lte')
        expect(result['gte']).to be_a(String)
        expect(result['lte']).to be_a(String)
        expect(result['gte']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(result['lte']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'integer_range fields' do
      it 'generates integer range objects' do
        field_config = { type: 'integer_range' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('gte')
        expect(result).to have_key('lte')
        expect(result['gte']).to be_a(Integer)
        expect(result['lte']).to be_a(Integer)
        expect(result['gte']).to be <= result['lte']
      end
    end

    context 'float_range fields' do
      it 'generates float range objects' do
        field_config = { type: 'float_range' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('gte')
        expect(result).to have_key('lte')
        expect(result['gte']).to be_a(Float)
        expect(result['lte']).to be_a(Float)
        expect(result['gte']).to be <= result['lte']
      end
    end

    context 'long_range fields' do
      it 'generates long range objects' do
        field_config = { type: 'long_range' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('gte')
        expect(result).to have_key('lte')
        expect(result['gte']).to be_a(Integer)
        expect(result['lte']).to be_a(Integer)
        expect(result['gte']).to be <= result['lte']
      end
    end

    context 'double_range fields' do
      it 'generates double range objects' do
        field_config = { type: 'double_range' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('gte')
        expect(result).to have_key('lte')
        expect(result['gte']).to be_a(Float)
        expect(result['lte']).to be_a(Float)
        expect(result['gte']).to be <= result['lte']
      end
    end

    context 'ip_range fields' do
      it 'generates IP range objects' do
        field_config = { type: 'ip_range' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('gte')
        expect(result).to have_key('lte')
        expect(result['gte']).to be_a(String)
        expect(result['lte']).to be_a(String)
        expect(result['gte']).to match(/\d+\.\d+\.\d+\.\d+/)
        expect(result['lte']).to match(/\d+\.\d+\.\d+\.\d+/)
      end
    end

    context 'geo_point fields' do
      it 'generates valid geo_point coordinates' do
        field_config = { type: 'geo_point' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key(:lat)
        expect(result).to have_key(:lon)
        expect(result[:lat]).to be_between(-90.0, 90.0)
        expect(result[:lon]).to be_between(-180.0, 180.0)
      end
    end

    context 'ip fields' do
      it 'generates valid IP addresses' do
        field_config = { type: 'ip' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d+\.\d+\.\d+\.\d+|2001:db8::/)
      end
    end

    context 'binary fields' do
      it 'generates base64 encoded data' do
        field_config = { type: 'binary' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result.length).to be > 0
        # Base64 strings should only contain valid base64 characters
        expect(result).to match(/^[A-Za-z0-9+\/]*={0,2}$/)
      end
    end

    context 'unknown field types' do
      it 'defaults to keyword for unknown types' do
        field_config = { type: 'unknown_type' }
        result = Seed.send(:generate_field_value, field_config)
        
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end
  end

  describe '.generate_document' do
    let(:simple_schema) do
      {
        'name' => { type: 'text', properties: nil, format: nil },
        'age' => { type: 'integer', properties: nil, format: nil },
        'active' => { type: 'boolean', properties: nil, format: nil }
      }
    end

    it 'generates a complete document' do
      result = Seed.send(:generate_document, simple_schema)
      
      expect(result).to be_a(Hash)
      expect(result).to have_key('name')
      expect(result).to have_key('age')
      expect(result).to have_key('active')
      expect(result['name']).to be_a(String)
      expect(result['age']).to be_a(Integer)
        expect([true, false]).to include(result['active'])
    end

    it 'generates different documents each time' do
      doc1 = Seed.send(:generate_document, simple_schema)
      doc2 = Seed.send(:generate_document, simple_schema)
      
      # While it's possible they could be the same by chance, it's very unlikely
      expect(doc1).not_to eq(doc2)
    end
  end

  describe '.generate_document_batch' do
    let(:simple_schema) do
      {
        'name' => { type: 'text', properties: nil, format: nil }
      }
    end

    it 'generates the correct number of documents' do
      result = Seed.send(:generate_document_batch, 5, simple_schema)
      
      expect(result).to be_an(Array)
      expect(result.length).to eq(5)
      result.each do |doc|
        expect(doc).to be_a(Hash)
        expect(doc).to have_key('name')
      end
    end

    it 'generates unique documents' do
      result = Seed.send(:generate_document_batch, 10, simple_schema)
      
      # All documents should be different
      expect(result.uniq.length).to eq(10)
    end
  end

  describe 'WORD_LIST constant' do
    it 'contains a substantial word list' do
      expect(Seed::WORD_LIST).to be_an(Array)
      expect(Seed::WORD_LIST.length).to be > 100
    end

    it 'contains technical terms' do
      expect(Seed::WORD_LIST).to include('elasticsearch', 'opensearch', 'ruby', 'document')
    end

    it 'contains common words' do
      expect(Seed::WORD_LIST).to include('lorem', 'ipsum', 'dolor', 'sit')
    end
  end

  describe 'integration with real mappings' do
    let(:real_mappings) do
      {
        'properties' => {
          'id' => { 'type' => 'keyword' },
          'title' => { 'type' => 'text' },
          'description' => { 'type' => 'text' },
          'price' => { 'type' => 'float' },
          'in_stock' => { 'type' => 'boolean' },
          'created_at' => { 'type' => 'date' },
          'tags' => { 'type' => 'keyword' },
          'metadata' => {
            'type' => 'object',
            'properties' => {
              'category' => { 'type' => 'keyword' },
              'weight' => { 'type' => 'float' },
              'dimensions' => {
                'type' => 'object',
                'properties' => {
                  'width' => { 'type' => 'integer' },
                  'height' => { 'type' => 'integer' },
                  'depth' => { 'type' => 'integer' }
                }
              }
            }
          }
        }
      }
    end

    it 'handles complex nested structures' do
      result = Seed.send(:generate_document, Seed.send(:parse_mappings, real_mappings))
      
      expect(result).to have_key('metadata')
      expect(result['metadata']).to be_a(Hash)
      expect(result['metadata']).to have_key('dimensions')
      expect(result['metadata']['dimensions']).to be_a(Hash)
      expect(result['metadata']['dimensions']).to have_key('width')
      expect(result['metadata']['dimensions']['width']).to be_a(Integer)
    end
  end
end