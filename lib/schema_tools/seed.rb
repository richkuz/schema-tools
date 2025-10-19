module SchemaTools
  def self.seed(client:)
    # List available indices (connection already validated during client initialization)
    puts "Connecting to #{Config.connection_url}..."
    indices = client.list_indices
    
    if indices.empty?
      puts "No indices found in the cluster."
      puts "Please create an index first."
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
    
    # Prompt user for number of documents to seed
    puts "\nHow many documents would you like to seed?"
    num_docs_input = STDIN.gets&.chomp
    if num_docs_input.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    
    num_docs = num_docs_input.to_i
    if num_docs <= 0
      puts "Invalid number of documents. Please enter a positive integer."
      exit 1
    end
    
    seeder = Seeder::Seeder.new(index_or_alias_name: selected_index, client: client)
    seeder.seed(num_docs: num_docs, batch_size: 5)
  end
end