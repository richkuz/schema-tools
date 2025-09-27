module SchemaTools
  def self.delete(index_name:, client:)
    raise "index_name parameter is required" unless index_name
    
    unless client.index_exists?(index_name)
      raise "Index does not exist: #{index_name}"
    end

    puts "Checking that index #{index_name} is closed before proceeding"
    unless client.index_closed?(index_name)
      raise "Hard delete only allowed on closed indexes. Please run rake 'schema:close[#{index_name}]' first."
    end
    puts "Index #{index_name} is closed"
    
    puts "Hard deleting index #{index_name}"
    
    if client.index_exists?(index_name)
      client.delete_index(index_name)
      puts "Index #{index_name} hard deleted"
    else
      puts "Index #{index_name} does not exist"
    end
  end
end