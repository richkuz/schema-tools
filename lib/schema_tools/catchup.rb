module SchemaTools
  def self.catchup(index_name:, client:, schema_manager:)
    raise "index_name parameter is required" unless index_name
    
    index_config = schema_manager.get_index_config(index_name)
    raise "Index configuration not found for #{index_name}" unless index_config
    
    from_index = index_config['from_index_name']
    raise "from_index_name not specified in index configuration" unless from_index
    
    unless client.index_exists?(from_index)
      raise "Source index #{from_index} does not exist. Cannot perform catchup reindex to #{index_name}."
    end
    
    reindex_script = schema_manager.get_reindex_script(index_name)
    
    puts "Starting catchup reindex from #{from_index} to #{index_name}"
    # TODO NOT IMPLEMENTED YET
    # Do a reindex by query
    puts "TODO IMPLEMENT ME"
    response = client.reindex(from_index, index_name, reindex_script)
  end
end