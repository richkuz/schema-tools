require_relative '../spec_helper'
require 'schema_tools'
require 'seeder/base_doc_seeder'
require 'seeder/mappings_doc_seeder'
require 'seeder/sample_doc_seeder'
require 'seeder/seeder'

RSpec.describe SchemaTools::Seeder::Seeder do
  let(:mock_client) { double('client') }
  let(:index_name) { 'test-index' }
  let(:num_docs) { 5 }
  let(:batch_size) { 5 }
  
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

  let(:mock_doc_seeder) { double('doc_seeder') }
  let(:seeder) { described_class.new(index_or_alias_name: index_name, client: mock_client) }

  before do
    allow(mock_client).to receive(:alias_exists?).with(index_name).and_return(false)
    allow(mock_client).to receive(:get_index_mappings).with(index_name).and_return(sample_mappings)
    allow(SchemaTools::Seeder::MappingsDocSeeder).to receive(:new).with(sample_mappings).and_return(mock_doc_seeder)
    allow(mock_doc_seeder).to receive(:generate_document).and_return({ 'title' => 'Test Document', 'count' => 42 })
    allow(mock_client).to receive(:bulk_index).and_return({
      'items' => num_docs.times.map { { 'index' => { 'status' => 201 } } },
      'errors' => false
    })
  end

  describe '#initialize' do
    it 'stores client and index name' do
      expect(seeder.instance_variable_get(:@client)).to eq(mock_client)
      expect(seeder.instance_variable_get(:@index_or_alias_name)).to eq(index_name)
    end

    it 'initializes doc seeder with mappings' do
      expect(SchemaTools::Seeder::MappingsDocSeeder).to receive(:new).with(sample_mappings)
      described_class.new(index_or_alias_name: index_name, client: mock_client)
    end

    context 'with alias' do
      let(:alias_name) { 'test-alias' }
      let(:actual_index) { 'test-index-20250101' }

      before do
        allow(mock_client).to receive(:alias_exists?).with(alias_name).and_return(true)
        allow(mock_client).to receive(:get_alias_indices).with(alias_name).and_return([actual_index])
        allow(mock_client).to receive(:get_index_mappings).with(actual_index).and_return(sample_mappings)
      end

      it 'resolves alias to actual index name' do
        expect(mock_client).to receive(:get_index_mappings).with(actual_index)
        described_class.new(index_or_alias_name: alias_name, client: mock_client)
      end

      it 'raises error for aliases pointing to multiple indices' do
        allow(mock_client).to receive(:get_alias_indices).with(alias_name).and_return(['index1', 'index2'])
        
        expect {
          described_class.new(index_or_alias_name: alias_name, client: mock_client)
        }.to raise_error(/Alias 'test-alias' points to multiple indices/)
      end
    end

    context 'with custom doc seeder' do
      let(:custom_seeder_class) { double('CustomDocSeeder') }
      let(:custom_seeder_instance) { double('custom_seeder_instance') }

      before do
        allow(SchemaTools::SchemaFiles).to receive(:get_doc_seeder_class).with(index_name).and_return(custom_seeder_class)
        allow(custom_seeder_class).to receive(:new).with(index_name).and_return(custom_seeder_instance)
      end

      it 'uses custom doc seeder when available' do
        expect(custom_seeder_class).to receive(:new).with(index_name)
        described_class.new(index_or_alias_name: index_name, client: mock_client)
      end
    end

    context 'with sample documents' do
      let(:sample_docs) { [{ 'title' => 'Sample 1' }, { 'title' => 'Sample 2' }] }
      let(:sample_doc_seeder) { double('SampleDocSeeder') }

      before do
        allow(SchemaTools::SchemaFiles).to receive(:get_doc_seeder_class).with(index_name).and_return(nil)
        allow(SchemaTools::SchemaFiles).to receive(:get_sample_docs).with(index_name).and_return(sample_docs)
        allow(SchemaTools::Seeder::SampleDocSeeder).to receive(:new).with(sample_docs).and_return(sample_doc_seeder)
      end

      it 'uses sample doc seeder when available' do
        expect(SchemaTools::Seeder::SampleDocSeeder).to receive(:new).with(sample_docs)
        described_class.new(index_or_alias_name: index_name, client: mock_client)
      end
    end

    context 'when no seeder can be created' do
      before do
        allow(mock_client).to receive(:get_index_mappings).with(index_name).and_return(nil)
        allow(SchemaTools::SchemaFiles).to receive(:get_doc_seeder_class).with(index_name).and_return(nil)
        allow(SchemaTools::SchemaFiles).to receive(:get_sample_docs).with(index_name).and_return(nil)
      end

      it 'raises error when no seeder can be created' do
        expect {
          described_class.new(index_or_alias_name: index_name, client: mock_client)
        }.to raise_error(/No custom document seeder, sample documents, or mappings found/)
      end
    end
  end

  describe '#seed' do
    it 'seeds documents in batches' do
      expect(mock_doc_seeder).to receive(:generate_document).exactly(num_docs).times
      expect(mock_client).to receive(:bulk_index).once

      seeder.seed(num_docs: num_docs, batch_size: batch_size)
    end

    it 'shows progress messages' do
      expect { seeder.seed(num_docs: num_docs, batch_size: batch_size) }
        .to output(/Seeding #{num_docs} in batches of #{batch_size} documents from #{index_name}/).to_stdout
    end

    it 'handles multiple batches' do
      large_num_docs = 12
      large_batch_size = 5
      
      expect(mock_doc_seeder).to receive(:generate_document).exactly(large_num_docs).times
      expect(mock_client).to receive(:bulk_index).exactly(3).times # 12 docs / 5 batch_size = 3 batches
      
      seeder.seed(num_docs: large_num_docs, batch_size: large_batch_size)
    end

    it 'handles bulk indexing errors gracefully' do
      allow(mock_client).to receive(:bulk_index).and_return({
        'items' => [
          { 'index' => { 'status' => 201 } },
          { 'index' => { 'status' => 400, 'error' => { 'type' => 'mapper_parsing_exception', 'reason' => 'failed to parse field' } } }
        ],
        'errors' => true
      })

      expect { seeder.seed(num_docs: 2, batch_size: 2) }
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

      expect { seeder.seed(num_docs: 1, batch_size: 1) }
        .to output(/WARN: 1 documents failed to index/).to_stdout
    end

    it 'raises error when bulk indexing fails completely' do
      allow(mock_client).to receive(:bulk_index).and_raise(StandardError.new('Connection failed'))

      expect { seeder.seed(num_docs: num_docs, batch_size: batch_size) }
        .to raise_error(StandardError, 'Connection failed')
    end

    it 'handles circuit breaker exceptions with helpful error message' do
      circuit_breaker_error = StandardError.new('HTTP 429: {"error":{"type":"circuit_breaking_exception"}}')
      allow(mock_client).to receive(:bulk_index).and_raise(circuit_breaker_error)

      expect { seeder.seed(num_docs: num_docs, batch_size: batch_size) }
        .to raise_error(StandardError, /Circuit breaker triggered/)
    end

    it 'adds small delay between batches' do
      large_num_docs = 10
      large_batch_size = 3
      
      expect(seeder).to receive(:sleep).with(0.1).exactly(3).times # 4 batches, sleep between first 3
      
      seeder.seed(num_docs: large_num_docs, batch_size: large_batch_size)
    end

    it 'handles batch failures and re-raises error' do
      allow(mock_client).to receive(:bulk_index).and_raise(StandardError.new('Batch failed'))
      
      expect { seeder.seed(num_docs: num_docs, batch_size: batch_size) }
        .to raise_error(StandardError, 'Batch failed')
    end

    it 'shows final summary' do
      expect { seeder.seed(num_docs: num_docs, batch_size: batch_size) }
        .to output(/Seeded #{num_docs} documents to #{index_name}/).to_stdout
    end
  end

  describe '#bulk_index' do
    it 'calls client bulk_index with documents and index name' do
      documents = [{ 'title' => 'Test' }, { 'title' => 'Test2' }]
      
      expect(mock_client).to receive(:bulk_index).with(documents, index_name)
      
      seeder.bulk_index(documents)
    end
  end

  describe '#handle_circuit_breaker_exception' do
    it 'handles circuit breaker exceptions' do
      error = StandardError.new('circuit_breaking_exception')
      
      expect { seeder.send(:handle_circuit_breaker_exception, error, 5) }
        .to raise_error(StandardError, /Circuit breaker triggered/)
    end

    it 'handles HTTP 429 errors' do
      error = StandardError.new('HTTP 429: Too Many Requests')
      
      expect { seeder.send(:handle_circuit_breaker_exception, error, 5) }
        .to raise_error(StandardError, /Circuit breaker triggered/)
    end

    it 'ignores non-circuit breaker errors' do
      error = StandardError.new('Some other error')
      
      expect { seeder.send(:handle_circuit_breaker_exception, error, 5) }
        .not_to raise_error
    end
  end

  describe '#print_errors' do
    it 'returns 0 when no errors' do
      response = { 'errors' => false }
      result = seeder.send(:print_errors, response)
      
      expect(result).to eq(0)
    end

    it 'returns 0 when no error items' do
      response = { 'errors' => true, 'items' => [] }
      result = seeder.send(:print_errors, response)
      
      expect(result).to eq(0)
    end

    it 'prints error details' do
      response = {
        'errors' => true,
        'items' => [
          { 'index' => { 'status' => 201 } },
          { 'index' => { 'status' => 400, 'error' => { 'type' => 'mapper_error', 'reason' => 'test error' } } }
        ]
      }
      
      expect { seeder.print_errors(response) }
        .to output(/WARN: 1 documents failed to index/).to_stdout
    end

    it 'limits error output to first 3 errors' do
      response = {
        'errors' => true,
        'items' => 5.times.map do |i|
          { 'index' => { 'status' => 400, 'error' => { 'type' => "error_#{i}", 'reason' => "reason_#{i}" } } }
        end
      }
      
      expect { seeder.print_errors(response) }
        .to output(/WARN: 5 documents failed to index/).to_stdout
    end
  end

  describe '#resolve_to_index_name' do
    it 'returns index name as-is when not an alias' do
      result = seeder.send(:resolve_to_index_name, 'test-index')
      expect(result).to eq('test-index')
    end

    it 'resolves alias to actual index name' do
      allow(mock_client).to receive(:alias_exists?).with('test-alias').and_return(true)
      allow(mock_client).to receive(:get_alias_indices).with('test-alias').and_return(['actual-index'])
      
      result = seeder.send(:resolve_to_index_name, 'test-alias')
      expect(result).to eq('actual-index')
    end

    it 'raises error for aliases pointing to multiple indices' do
      allow(mock_client).to receive(:alias_exists?).with('multi-alias').and_return(true)
      allow(mock_client).to receive(:get_alias_indices).with('multi-alias').and_return(['index1', 'index2'])
      
      expect { seeder.send(:resolve_to_index_name, 'multi-alias') }
        .to raise_error(/Alias 'multi-alias' points to multiple indices/)
    end
  end
end