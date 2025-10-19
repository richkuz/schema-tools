require_relative '../spec_helper'
require 'schema_tools'
require 'seeder/base_doc_seeder'
require 'seeder/mappings_doc_seeder'

RSpec.describe SchemaTools::Seeder::MappingsDocSeeder do
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

  let(:seeder) { described_class.new(sample_mappings) }

  describe '#initialize' do
    it 'stores mappings' do
      expect(seeder.instance_variable_get(:@mappings)).to eq(sample_mappings)
    end
  end

  describe '#generate_document' do
    it 'generates a document with all field types' do
      document = seeder.generate_document
      
      expect(document).to be_a(Hash)
      expect(document).to have_key('title')
      expect(document).to have_key('status')
      expect(document).to have_key('count')
      expect(document).to have_key('price')
      expect(document).to have_key('active')
      expect(document).to have_key('created_at')
      expect(document).to have_key('location')
      expect(document).to have_key('ip_address')
      expect(document).to have_key('metadata')
    end

    it 'generates different documents each time' do
      doc1 = seeder.generate_document
      doc2 = seeder.generate_document
      
      # While it's possible they could be the same by chance, it's very unlikely
      expect(doc1).not_to eq(doc2)
    end

    it 'skips alias fields' do
      mappings_with_alias = {
        'properties' => {
          'name' => { 'type' => 'text' },
          'alias_field' => { 'type' => 'alias', 'path' => 'name' }
        }
      }
      seeder_with_alias = described_class.new(mappings_with_alias)
      document = seeder_with_alias.generate_document
      
      expect(document).to have_key('name')
      expect(document).not_to have_key('alias_field')
    end

    it 'handles empty mappings' do
      empty_seeder = described_class.new({})
      document = empty_seeder.generate_document
      
      expect(document).to eq({})
    end
  end

  describe '.generate_field_value' do
    context 'text fields' do
      it 'generates text content' do
        field_config = { 'type' => 'text' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result.split.length).to be_between(10, 50)
      end
    end

    context 'keyword fields' do
      it 'generates keyword content' do
        field_config = { 'type' => 'keyword' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end

    context 'integer fields' do
      it 'generates integer values' do
        field_config = { 'type' => 'integer' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-100, 999_999_999)
      end
    end

    context 'long fields' do
      it 'generates long values' do
        field_config = { 'type' => 'long' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-100, 999_999_999)
      end
    end

    context 'short fields' do
      it 'generates short values within valid range' do
        field_config = { 'type' => 'short' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-100, 100) # Within Java short range
      end
    end

    context 'float fields' do
      it 'generates float values' do
        field_config = { 'type' => 'float' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(-5.0, 1000.0)
      end
    end

    context 'double fields' do
      it 'generates double values' do
        field_config = { 'type' => 'double' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(-5.0, 1000.0)
      end
    end

    context 'boolean fields' do
      it 'generates boolean values' do
        field_config = { 'type' => 'boolean' }
        result = described_class.generate_field_value(field_config)
        
        expect([true, false]).to include(result)
      end
    end

    context 'date fields' do
      it 'generates ISO 8601 date strings by default' do
        field_config = { 'type' => 'date' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'generates epoch_millis format when specified' do
        field_config = { 'type' => 'date', 'format' => 'epoch_millis' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be > 1_000_000_000_000 # Should be milliseconds since epoch
      end

      it 'generates epoch_second format when specified' do
        field_config = { 'type' => 'date', 'format' => 'epoch_second' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be > 1_000_000_000 # Should be seconds since epoch
      end

      it 'generates yyyy-MM-dd format when specified' do
        field_config = { 'type' => 'date', 'format' => 'yyyy-MM-dd' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d{4}-\d{2}-\d{2}/)
      end
    end

    context 'object fields' do
      it 'generates nested object values' do
        field_config = {
          'type' => 'object',
          'properties' => {
            'name' => { 'type' => 'text' },
            'age' => { 'type' => 'integer' }
          }
        }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key('name')
        expect(result).to have_key('age')
        expect(result['name']).to be_a(String)
        expect(result['age']).to be_a(Integer)
      end

      it 'handles empty object properties' do
        field_config = { 'type' => 'object', 'properties' => nil }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to eq({})
      end
    end

    context 'nested fields' do
      it 'generates array of nested objects' do
        field_config = {
          'type' => 'nested',
          'properties' => {
            'chunk_id' => { 'type' => 'keyword' },
            'content' => { 'type' => 'text' }
          }
        }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'nested', 'properties' => nil }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to eq([])
      end
    end

    context 'rank_features fields' do
      it 'generates rank features object' do
        field_config = { 'type' => 'rank_features' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'completion' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'search_as_you_type' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result.split.length).to be_between(1, 3)
      end
    end

    context 'token_count fields' do
      it 'generates token count values' do
        field_config = { 'type' => 'token_count' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(1, 50)
      end
    end

    context 'alias fields' do
      it 'returns nil for alias fields' do
        field_config = { 'type' => 'alias' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_nil
      end
    end

    context 'byte fields' do
      it 'generates byte values within valid range' do
        field_config = { 'type' => 'byte' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(-128, 127)
      end
    end

    context 'half_float fields' do
      it 'generates half-float values' do
        field_config = { 'type' => 'half_float' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(-50.0, 50.0)
      end
    end

    context 'scaled_float fields' do
      it 'generates scaled float values' do
        field_config = { 'type' => 'scaled_float' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Float)
        expect(result).to be_between(0.0, 100.0)
      end
    end

    context 'unsigned_long fields' do
      it 'generates unsigned long values' do
        field_config = { 'type' => 'unsigned_long' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Integer)
        expect(result).to be_between(0, 999_999_999)
      end
    end

    context 'date_nanos fields' do
      it 'generates date with nanosecond precision' do
        field_config = { 'type' => 'date_nanos' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}/)
      end
    end

    context 'wildcard fields' do
      it 'generates wildcard text' do
        field_config = { 'type' => 'wildcard' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\w+_\d+/)
      end
    end

    context 'constant_keyword fields' do
      it 'generates constant keyword value' do
        field_config = { 'type' => 'constant_keyword' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to eq('constant_value')
      end
    end

    context 'geo_shape fields' do
      it 'generates geo shape objects' do
        field_config = { 'type' => 'geo_shape' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'date_range' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'integer_range' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'float_range' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'long_range' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'double_range' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'ip_range' }
        result = described_class.generate_field_value(field_config)
        
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
        field_config = { 'type' => 'geo_point' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(Hash)
        expect(result).to have_key(:lat)
        expect(result).to have_key(:lon)
        expect(result[:lat]).to be_between(-90.0, 90.0)
        expect(result[:lon]).to be_between(-180.0, 180.0)
      end
    end

    context 'ip fields' do
      it 'generates valid IP addresses' do
        field_config = { 'type' => 'ip' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result).to match(/\d+\.\d+\.\d+\.\d+|2001:db8::/)
      end
    end

    context 'binary fields' do
      it 'generates base64 encoded data' do
        field_config = { 'type' => 'binary' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result.length).to be > 0
        # Base64 strings should only contain valid base64 characters
        expect(result).to match(/^[A-Za-z0-9+\/]*={0,2}$/)
      end
    end

    context 'unknown field types' do
      it 'defaults to keyword for unknown types' do
        field_config = { 'type' => 'unknown_type' }
        result = described_class.generate_field_value(field_config)
        
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
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
      real_seeder = described_class.new(real_mappings)
      result = real_seeder.generate_document
      
      expect(result).to have_key('metadata')
      expect(result['metadata']).to be_a(Hash)
      expect(result['metadata']).to have_key('dimensions')
      expect(result['metadata']['dimensions']).to be_a(Hash)
      expect(result['metadata']['dimensions']).to have_key('width')
      expect(result['metadata']['dimensions']['width']).to be_a(Integer)
    end
  end

  describe '.dictionary_words' do
    it 'contains a substantial word list' do
      words = described_class.dictionary_words
      expect(words).to be_an(Array)
      expect(words.length).to be > 100
    end

    it 'contains technical terms or fallback words' do
      words = described_class.dictionary_words
      # Either the system dictionary or fallback words should be present
      # The fallback word list includes these terms, system dict might not
      fallback_terms = ['elasticsearch', 'opensearch', 'ruby', 'document']
      system_terms = ['search', 'data', 'index', 'mapping']
      
      expect(words).to satisfy do |word_list|
        (fallback_terms.any? { |term| word_list.include?(term) }) ||
        (system_terms.any? { |term| word_list.include?(term) })
      end
    end

    it 'contains common words or fallback words' do
      words = described_class.dictionary_words
      # Either the system dictionary or fallback words should be present
      fallback_terms = ['lorem', 'ipsum', 'dolor', 'sit']
      system_terms = ['the', 'and', 'for', 'are']
      
      expect(words).to satisfy do |word_list|
        (fallback_terms.any? { |term| word_list.include?(term) }) ||
        (system_terms.any? { |term| word_list.include?(term) })
      end
    end
  end
end