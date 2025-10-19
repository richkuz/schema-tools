module SchemaTools
  def self.seed(client:)
    # List available indices and aliases (connection already validated during client initialization)
    puts "Connecting to #{Config.connection_url}..."
    aliases = client.list_aliases
    indices = client.list_indices
    
    single_aliases = aliases.select { |alias_name, indices| indices.length == 1 && !alias_name.start_with?('.') }
    unaliased_indices = indices.reject { |index| aliases.values.flatten.include?(index) || index.start_with?('.') || client.index_closed?(index) }
    
    # Create a combined list with sequential numbering
    options = []
    
    if single_aliases.empty? && unaliased_indices.empty?
      puts "No indices or aliases found in the cluster."
      puts "Please create an index first."
      exit 0
    end
    
    puts "Available indices and aliases:"
    
    # Show aliases first
    if single_aliases.any?
      single_aliases.each do |alias_name, indices|
        option_number = options.length + 1
        options << { type: :alias, name: alias_name, index: indices.first }
        puts "#{option_number}. #{alias_name} -> #{indices.first}"
      end
    end
    
    # Show unaliased indices
    if unaliased_indices.any?
      unaliased_indices.each do |index_name|
        option_number = options.length + 1
        options << { type: :index, name: index_name, index: index_name }
        puts "#{option_number}. #{index_name}"
      end
    end
    
    puts "\nPlease select an index or alias by number (1-#{options.length}):"
    selection_input = STDIN.gets&.chomp
    if selection_input.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    selection = selection_input.to_i
    
    if selection < 1 || selection > options.length
      puts "Invalid selection. Please run the task again and select a valid number."
      exit 1
    end
    
    selected_option = options[selection - 1]
    puts "Selected #{selected_option[:type]}: #{selected_option[:name]}"
    
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
    
    seeder = Seeder::Seeder.new(index_or_alias_name: selected_option[:name], client: client)
    seeder.seed(num_docs: num_docs, batch_size: 5)
  end
end