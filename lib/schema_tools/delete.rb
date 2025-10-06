module SchemaTools
  def self.delete(name:, client:)
    raise "name parameter is required" unless name
    
    # Check if it's an alias
    if client.alias_exists?(name)
      indices = client.get_alias_indices(name)
      puts "Deleting alias '#{name}' (points to: #{indices.join(', ')})"
      puts "The underlying index(es) will remain intact."
      
      client.delete_alias(name)
      puts "✓ Alias '#{name}' deleted"
      puts "Index(es) #{indices.join(', ')} remain(s) intact"
    elsif client.index_exists?(name)
      puts "Checking that index #{name} is closed before proceeding"
      unless client.index_closed?(name)
        raise "Hard delete only allowed on closed indexes. Please run rake 'schema:close[#{name}]' first."
      end
      puts "Index #{name} is closed"
      
      puts "Hard deleting index #{name}"
      client.delete_index(name)
      puts "✓ Index #{name} hard deleted"
    else
      raise "Neither alias nor index exists: #{name}"
    end
  end
end