module SchemaTools
  module Config
    CONNECTION_URL = ENV['OPENSEARCH_URL'] || ENV['ELASTICSEARCH_URL']
    SCHEMAS_PATH = ENV['SCHEMAS_PATH'] || 'schemas'
  end
end