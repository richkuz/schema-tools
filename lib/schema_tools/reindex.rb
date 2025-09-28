module SchemaTools
  def self.reindex(index_name:, client:)
    raise "index_name parameter is required" unless index_name
    raise "client is required" unless client
    
    schema_manager = SchemaTools::SchemaManager.new()
    index_config = schema_manager.get_index_config(index_name)
    raise "Index configuration not found for #{index_name}" unless index_config
    
    from_index = index_config['from_index_name']
    raise "from_index_name not specified in index configuration" unless from_index
    
    unless client.index_exists?(from_index)
      raise "Source index #{from_index} does not exist. Cannot reindex to #{index_name}."
    end
    
    reindex_script = schema_manager.get_reindex_script(index_name)
    
    puts "Starting reindex from #{from_index} to #{index_name}"
    begin
      SchemaTools.update_metadata(index_name:, metadata: { reindex_started_at: Time.now.iso8601 }, client:)
      response = client.reindex(from_index, index_name, reindex_script)
      puts response

      if response['took']
        puts "Reindex task complete. Took: #{response['took']}"
        return true
      end
      
      task_id = response['task']
      if !task_id
        puts "No task ID from reindex. Reindex incomplete."
        return false
      end

      puts "Reindex task started at #{Time.now}. task_id is #{task_id}. Fetch task status with GET /tasks/#{task_id}"
      
      loop do
        sleep 5
        task_status = client.get_task_status(task_id)
        puts task_status
        
        if task_status['took']
          puts "Reindex completed successfully"
          return true
        end
      end
    ensure
      SchemaTools.update_metadata(index_name:, metadata: { reindex_completed_at: Time.now.iso8601 }, client:)
    end
  end
end