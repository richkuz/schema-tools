module SchemaTools
  def self.define(client:, schema_manager:)
    schema_definer = SchemaTools::SchemaDefiner.new(client, schema_manager)
    
    puts "Please choose:"
    puts "1. Define a schema for an index that exists in OpenSearch or Elasticsearch"
    puts "2. Define an example schema for an index that doesn't exist"
    puts "3. Define an example schema for a breaking change to an existing defined schema"
    puts "4. Define an example schema for a non-breaking change to an existing defined schema"
    
    choice = STDIN.gets&.chomp
    if choice.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    
    case choice
    when '1'
      # List available indices (connection already validated during client initialization)
      puts "Connecting to #{SchemaTools::Config::CONNECTION_URL}..."
      indices = client.list_indices
      
      if indices.empty?
        puts "No indices found in the cluster."
        puts "Please create an index first or choose option 2 to define a schema for a new index."
        exit 0
      end
      
      puts "Available indices:"
      indices.each_with_index do |index_name, index|
        puts "#{index + 1}. #{index_name}"
      end
      
      puts "\nPlease select an index by number (1-#{indices.length}):"
      selection_input = STDIN.gets&.chomp
      if selection_input.nil?
        puts "No input provided. Exiting."
        exit 1
      end
      selection = selection_input.to_i
      
      if selection < 1 || selection > indices.length
        puts "Invalid selection. Please run the task again and select a valid number."
        exit 1
      end
      
      selected_index = indices[selection - 1]
      puts "Selected index: #{selected_index}"
      puts "Checking #{SchemaTools::Config::CONNECTION_URL} for the latest version of \"#{selected_index}\""
      schema_definer.define_schema_for_existing_index(selected_index)
    when '2'
      puts "Type the name of a new index to define. A version number suffix is not required."
      index_name = STDIN.gets&.chomp
      if index_name.nil?
        puts "No input provided. Exiting."
        exit 1
      end
      schema_definer.define_example_schema_for_new_index(index_name)
    when '3'
      puts "Type the name of an existing schema to change. A version number suffix is not required."
      index_name = STDIN.gets&.chomp
      if index_name.nil?
        puts "No input provided. Exiting."
        exit 1
      end
      schema_definer.define_breaking_change_schema(index_name)
    when '4'
      puts "Type the name of an existing schema to change. A version number suffix is not required."
      index_name = STDIN.gets&.chomp
      if index_name.nil?
        puts "No input provided. Exiting."
        exit 1
      end
      schema_definer.define_non_breaking_change_schema(index_name)
    else
      puts "Invalid choice. Please run the task again and select 1, 2, 3, or 4."
    end
  end
end