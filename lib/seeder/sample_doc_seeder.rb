require 'securerandom'
require 'active_support/all'

module SchemaTools::Seeder
  # Generate a document by choosing a document at random from an array of sample documents
  # 
  # The seeder looks for sample docs in schemas/{alias_name}/sample_docs.json
  # in the form: { "hits": [ { "_source": { "title": "Foo", "desc": "Bar" } }, ... ] }
  class SampleDocSeeder < BaseDocSeeder

    # sample_docs: Array of sample documents to pull from at random
    def initialize(sample_docs)
      @sample_docs = sample_docs['hits'].pluck('_source')
    end

    def generate_document
      @sample_docs.sample
    end
  end
end
