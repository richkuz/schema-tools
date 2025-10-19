require 'securerandom'

module SchemaTools::Seeder
  # Generate a document by choosing a document at random from an array of sample documents
  class SampleDocSeeder < BaseDocSeeder

    # sample_docs: Array of sample documents to pull from at random
    def initialize(sample_docs)
      @sample_docs = sample_docs
    end

    def generate_document
      @sample_docs.sample
    end
  end
end
