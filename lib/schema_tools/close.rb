module SchemaTools
  def self.close(name:, client:)
    raise "name parameter is required" unless name
    
    # Check if it's an alias
    if client.alias_exists?(name)
      indices = client.get_alias_indices(name)
      puts "Closing alias '#{name}' (points to: #{indices.join(', ')})"
      puts "This will close all underlying index(es)."
      
      indices.each do |index_name|
        if client.index_exists?(index_name)
          client.close_index(index_name)
          puts "✓ Index #{index_name} closed"
        else
          puts "⚠ Index #{index_name} does not exist"
        end
      end
      puts "✓ All index(es) in alias '#{name}' closed"
    elsif client.index_exists?(name)
      puts "Closing index #{name}"
      client.close_index(name)
      puts "✓ Index #{name} closed"
    else
      raise "Neither alias nor index exists: #{name}"
    end
  end
end