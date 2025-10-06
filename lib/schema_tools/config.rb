module SchemaTools
  module Config
    # e.g. http://localhost:9200
    CONNECTION_URL = ENV['OPENSEARCH_URL'] || ENV['ELASTICSEARCH_URL']

    # Optional username for HTTP basic authentication
    CONNECTION_USERNAME = ENV['OPENSEARCH_USERNAME'] || ENV['ELASTICSEARCH_USERNAME']

    # Optional password for HTTP basic authentication
    CONNECTION_PASSWORD = ENV['OPENSEARCH_PASSWORD'] || ENV['ELASTICSEARCH_PASSWORD']

    # Folder on disk where all schema definitions are stored
    SCHEMAS_PATH = ENV['SCHEMAS_PATH'] || 'schemas'

    # Folder on disk where painless scripts are stored
    PAINLESS_SCRIPTS_PATH = ENV['PAINLESS_SCRIPTS_PATH'] || 'painless_scripts'

    # Descriptive name for operations (kept for backward compatibility)
    SCHEMURAI_USER = ENV['SCHEMURAI_USER'] || 'rake task'

    def self.schemurai_user
      SCHEMURAI_USER
    end

    def self.connection_url
      CONNECTION_URL
    end

    def self.connection_username
      CONNECTION_USERNAME
    end

    def self.connection_password
      CONNECTION_PASSWORD
    end
    
    def self.schemas_path
      SCHEMAS_PATH
    end

    def self.painless_scripts_path
      PAINLESS_SCRIPTS_PATH
    end

  end
end