require 'json'
require 'time'

module SchemaTools::Seeder
  class Seeder
    def initialize(index_or_alias_name:, client:)
      @client = client
      @index_or_alias_name = index_or_alias_name
      @doc_seeder = initialize_doc_seeder
    end

    def initialize_doc_seeder
      custom_doc_seeder_class = SchemaTools::SchemaFiles.get_doc_seeder_class(@index_or_alias_name)
      return custom_doc_seeder_class.new(@index_or_alias_name) if custom_doc_seeder_class

      sample_docs = SchemaTools::SchemaFiles.get_sample_docs(@index_or_alias_name)
      return SampleDocSeeder.new(sample_docs) if sample_docs

      mappings = @client.get_index_mappings(@index_or_alias_name)
      return MappingsDocSeeder.new(mappings) if mappings

      raise "No custom document seeder, sample documents, or mappings found for #{@index_or_alias_name}"
    end

    def seed(num_docs:, batch_size: 5)
      puts "Seeding #{num_docs} in batches of #{batch_size} documents from #{@index_or_alias_name} using #{@doc_seeder.class.name}"
    
      total_batches = (num_docs.to_f / batch_size).ceil
      total_seeded_docs = 0

      num_docs.times.each_slice(batch_size).with_index(1) do |batch_range, batch_num|
        docs_in_batch = batch_range.size

        puts "Generating batch #{batch_num}/#{total_batches} (#{docs_in_batch} documents)..."
        documents = Array.new(docs_in_batch) do
          @doc_seeder.generate_document
        end

        puts "Indexing batch #{batch_num}..."
        response = bulk_index(documents)
        seeded_docs = documents.length - print_errors(response)
        total_seeded_docs += seeded_docs
        puts "Indexed #{seeded_docs} documents for batch #{batch_num}" if seeded_docs

        sleep(0.1) if batch_num < total_batches # small delay to help with memory pressure
      rescue StandardError => e
        puts "Batch #{batch_num} failed: #{e.message}"
        handle_circuit_breaker_exception(e, batch_size)
        raise e
      end
      puts "Seeded #{total_seeded_docs} documents to #{@index_or_alias_name}"
    end

    def bulk_index(documents)
      @client.bulk_index(documents, @index_or_alias_name)
    end

    def handle_circuit_breaker_exception(error, batch_size)
      return unless error&.message&.match?(/circuit_breaking_exception|HTTP 429/)

      puts 'ERROR: Circuit breaker triggered - OpenSearch cluster is out of memory'
      puts 'Consider:'
      puts "  1. Reducing batch size further (currently #{batch_size})"
      puts '  2. Increasing OpenSearch heap size'
      puts '  3. Reducing document size/complexity'
      puts '  4. Adding delays between batches'
      puts ''
      raise StandardError, 'Circuit breaker triggered - OpenSearch cluster is out of memory'
    end

    def print_errors(response)
      return 0 unless response['errors']

      error_items = response['items'].select { |item| item.dig('index', 'status') >= 400 }
      error_count = error_items.length
      return 0 unless error_count.positive?

      puts "WARN: #{error_count} documents failed to index"

      # Print first few errors for debugging
      error_items.first(3).each_with_index do |item, index|
        error_info = item.dig('index', 'error')
        next unless error_info

        print_error_item(error_info, index)
      end

      puts "  ... and #{error_count - 3} more errors" if error_count > 3
      error_count
    end

    def print_error_item(error_info, index)
      puts "  Error #{index + 1}: #{error_info['type']} - #{error_info['reason']}"
      return unless error_info['caused_by']

      puts "    Caused by: #{error_info['caused_by']['type']} - #{error_info['caused_by']['reason']}"
    end
  end
end
