require 'json'
require 'time'

module Seed
  # Word list for generating realistic text content
  WORD_LIST = %w[
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor
    incididunt ut labore et dolore magna aliqua enim ad minim veniam quis nostrud
    exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute
    irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat
    nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa
    qui officia deserunt mollit anim id est laborum search engine data ruby
    document index mapping schema elasticsearch opensearch cluster node shard
    replica primary secondary analysis tokenizer filter analyzer query filter
    aggregation pipeline script painless groovy mustache template kibana
    logstash beats metricbeat filebeat packetbeat heartbeat auditbeat
    functionbeat winlogbeat journalbeat apm agent apm server fleet agent
    policy enrollment token integration package endpoint security detection
    rule machine learning anomaly detection forecasting classification
    regression clustering outlier detection natural language processing
    vector search semantic search neural search transformer embedding
    vector database similarity search recommendation system personalization
    real-time streaming batch processing event sourcing cqrs microservices
    distributed system scalability performance optimization monitoring
    observability logging metrics tracing alerting notification dashboard
    visualization reporting analytics business intelligence data science
    machine learning artificial intelligence deep learning neural network
    algorithm model training inference prediction classification regression
    clustering dimensionality reduction feature engineering data preprocessing
    validation testing deployment production staging development environment
    configuration management version control continuous integration continuous
    deployment devops infrastructure as code containerization orchestration
    kubernetes docker swarm mesos nomad consul etcd zookeeper redis memcached
    rabbitmq kafka pulsar nats jetstream grpc rest api graphql websocket
    http https tls ssl certificate authentication authorization oauth jwt
    saml ldap active directory kerberos rbac abac policy enforcement
    compliance governance security audit vulnerability assessment penetration
    testing threat modeling risk management incident response disaster recovery
    backup restore high availability fault tolerance load balancing auto-scaling
    horizontal scaling vertical scaling sharding partitioning replication
    consistency eventual consistency strong consistency cap theorem acid
    base distributed consensus raft paxos byzantine fault tolerance
  ].freeze

  def self.seed_data(num_docs, mappings_json, client, index_name)
    puts "Seeding #{num_docs} documents to index: #{index_name}"
    
    # Parse the mappings to understand the schema
    schema = parse_mappings(mappings_json)
    puts "Parsed schema with #{schema.keys.length} top-level fields"
    
    # Generate documents in batches for efficiency
    batch_size = 100
    total_batches = (num_docs.to_f / batch_size).ceil
    
    (1..total_batches).each do |batch_num|
      docs_in_batch = [batch_size, num_docs - (batch_num - 1) * batch_size].min
      puts "Generating batch #{batch_num}/#{total_batches} (#{docs_in_batch} documents)..."
      
      documents = generate_document_batch(docs_in_batch, schema)
      
      puts "Indexing batch #{batch_num}..."
      begin
        response = client.bulk_index(documents, index_name)
        
        # Check for errors in bulk response
        if response['errors']
          error_count = response['items'].count { |item| item.dig('index', 'status') >= 400 }
          if error_count > 0
            puts "Warning: #{error_count} documents failed to index in batch #{batch_num}"
          end
        end
        
        puts "Successfully indexed batch #{batch_num}"
      rescue => e
        puts "Error indexing batch #{batch_num}: #{e.message}"
        raise e
      end
    end
    
    puts "Successfully seeded #{num_docs} documents to #{index_name}"
  end

  private

  def self.parse_mappings(mappings_json)
    # Extract the properties from the mappings
    properties = mappings_json.dig('properties') || {}
    parse_properties(properties)
  end

  def self.parse_properties(properties)
    schema = {}
    
    properties.each do |field_name, field_config|
      schema[field_name] = {
        type: field_config['type'],
        properties: field_config['properties'],
        format: field_config['format']
      }
    end
    
    schema
  end

  def self.generate_document_batch(count, schema)
    count.times.map do
      generate_document(schema)
    end
  end

  def self.generate_document(schema)
    document = {}
    
    schema.each do |field_name, field_config|
      document[field_name] = generate_field_value(field_config)
    end
    
    document
  end

  def self.generate_field_value(field_config)
    field_type = field_config[:type]
    
    case field_type
    when 'text'
      generate_text_value
    when 'keyword'
      generate_keyword_value
    when 'long', 'integer'
      generate_integer_value
    when 'float', 'double'
      generate_float_value
    when 'boolean'
      generate_boolean_value
    when 'date'
      generate_date_value(field_config[:format])
    when 'object'
      generate_object_value(field_config[:properties])
    when 'geo_point'
      generate_geo_point_value
    when 'ip'
      generate_ip_value
    when 'binary'
      generate_binary_value
    else
      # Default to keyword for unknown types
      generate_keyword_value
    end
  end

  def self.generate_text_value
    # Generate a paragraph of 10-50 words
    word_count = rand(10..50)
    word_count.times.map { WORD_LIST.sample }.join(' ')
  end

  def self.generate_keyword_value
    # Generate a short phrase or single word
    case rand(1..4)
    when 1
      WORD_LIST.sample
    when 2
      "#{WORD_LIST.sample}_#{rand(1000..9999)}"
    when 3
      "#{WORD_LIST.sample} #{WORD_LIST.sample}"
    when 4
      "#{WORD_LIST.sample}-#{WORD_LIST.sample}"
    end
  end

  def self.generate_integer_value
    # Generate reasonable integer values based on common use cases
    case rand(1..5)
    when 1
      rand(1..1000) # Small positive numbers
    when 2
      rand(1_000_000..999_999_999) # Large IDs
    when 3
      rand(-100..100) # Small range including negatives
    when 4
      rand(1..100) # Percentages/scores
    when 5
      rand(1..365) # Days/periods
    end
  end

  def self.generate_float_value
    # Generate decimal numbers
    case rand(1..3)
    when 1
      (rand * 100).round(2) # 0-100 with 2 decimal places
    when 2
      (rand * 1000).round(4) # 0-1000 with 4 decimal places
    when 3
      (rand * 10 - 5).round(3) # -5 to 5 with 3 decimal places
    end
  end

  def self.generate_boolean_value
    [true, false].sample
  end

  def self.generate_date_value(format = nil)
    # Generate a random date within the last year
    start_time = Time.now - (365 * 24 * 60 * 60) # one year ago
    random_time = Time.at(start_time.to_i + rand(Time.now.to_i - start_time.to_i))
    
    case format
    when 'epoch_millis'
      (random_time.to_f * 1000).to_i
    when 'epoch_second'
      random_time.to_i
    else
      # Default to ISO 8601 format
      random_time.iso8601
    end
  end

  def self.generate_object_value(properties)
    return {} unless properties
    
    object = {}
    properties.each do |nested_field_name, nested_field_config|
      object[nested_field_name] = generate_field_value(nested_field_config)
    end
    object
  end

  def self.generate_geo_point_value
    # Generate random latitude/longitude coordinates
    {
      lat: (rand * 180 - 90).round(6), # -90 to 90
      lon: (rand * 360 - 180).round(6)  # -180 to 180
    }
  end

  def self.generate_ip_value
    # Generate random IP addresses
    case rand(1..2)
    when 1
      # IPv4
      "#{rand(1..254)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(1..254)}"
    when 2
      # IPv6 (simplified)
      "2001:db8::#{rand(1000..9999)}:#{rand(1000..9999)}:#{rand(1000..9999)}:#{rand(1000..9999)}"
    end
  end

  def self.generate_binary_value
    # Generate base64 encoded random data
    require 'base64'
    random_bytes = (0...32).map { rand(256) }.pack('C*')
    Base64.encode64(random_bytes).strip
  end
end