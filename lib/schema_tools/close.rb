module SchemaTools
  def self.close(index_name:, client:)
    raise "index_name parameter is required" unless index_name
    
    puts "Closing index #{index_name}"
    
    if client.index_exists?(index_name)
      client.close_index(index_name)
      puts "Index #{index_name} closed"
    else
      puts "Index #{index_name} does not exist"
    end
  end
end