module SchemaTools
  module Config
    OPENSEARCH_URL = ENV['OPENSEARCH_URL'] || 'http://localhost:9200'
    ELASTICSEARCH_URL = ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200'
    SCHEMAS_PATH = ENV['SCHEMAS_PATH'] || 'schemas'
  end
end