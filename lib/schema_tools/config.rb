module SchemaTools
  module Config
    # e.g. http://localhost:9200
    CONNECTION_URL = ENV['OPENSEARCH_URL'] || ENV['ELASTICSEARCH_URL']

    # Folder on disk where all schema definitions are stored
    SCHEMAS_PATH = ENV['SCHEMAS_PATH'] || 'schemas'

    # Descriptive name shown when writing revision_applied_by to index metadata
    SCHEMURAI_USER = ENV['SCHEMURAI_USER'] || 'rake task'

    def self.schemurai_user
      SCHEMURAI_USER
    end

    def self.connection_url
      CONNECTION_URL
    end
    
    def self.schemas_path
      SCHEMAS_PATH
    end

  end
end