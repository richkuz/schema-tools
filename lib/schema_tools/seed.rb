module SchemaTools
  def self.seed(client:)
    # List available indices and aliases (connection already validated during client initialization)
    puts "Connecting to #{Config.connection_url}..."
    
    options = print_aliases_and_indices(client)
    if options.empty?
      puts "No indices or aliases found in the cluster."
      puts "Please create an index first."
      exit 0
    end

    selected_option = prompt_for_selection(options)
    puts "Selected #{selected_option[:type]}: #{selected_option[:name]}"
    
    num_docs = prompt_for_positive_integer("How many documents would you like to seed?")
    
    batch_size = prompt_for_positive_integer("What batch size would you like to use? \nUse a higher number for faster speed, lower number if you hit memory errors.", default: 50)
    
    seeder = Seeder::Seeder.new(index_or_alias_name: selected_option[:name], client: client)
    seeder.seed(num_docs: num_docs, batch_size: batch_size)
  end

  private

  def self.print_aliases_and_indices(client)
    aliases = client.list_aliases
    indices = client.list_indices
    
    single_aliases = aliases.select { |alias_name, indices| indices.length == 1 && !alias_name.start_with?('.') }
    unaliased_indices = indices.reject { |index| aliases.values.flatten.include?(index) || index.start_with?('.') || client.index_closed?(index) }
    
    return [] if single_aliases.empty? && unaliased_indices.empty?

    # Create a combined list with sequential numbering
    options = []
    
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

    options
  end

  def self.prompt_for_selection(options)
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
    
    options[selection - 1]
  end

  def self.prompt_for_positive_integer(message, default: nil)
    if default
      puts "\n#{message}"
      puts "Press Enter to use default value (#{default}) or enter a custom value:"
    else
      puts "\n#{message}"
    end
    
    input = STDIN.gets&.chomp
    if input.nil?
      puts "No input provided. Exiting."
      exit 1
    end
    
    # Use default if input is empty and default is provided
    if input.empty? && default
      return default
    end
    
    value = input.to_i
    if value <= 0
      puts "Invalid input. Please enter a positive integer."
      exit 1
    end
    
    value
  end
end