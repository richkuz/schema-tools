module SchemaTools
  def self.painless_scripts_delete(script_name:, client:)
    raise "script_name parameter is required" unless script_name && !script_name.strip.empty?
    
    # Remove .painless extension if provided
    script_name = script_name.gsub(/\.painless$/, '')
    
    puts "Deleting painless script '#{script_name}' from cluster..."
    
    begin
      client.delete_script(script_name)
      puts "Successfully deleted painless script '#{script_name}' from cluster"
    rescue => e
      if e.message.include?('404') || e.message.include?('not found')
        puts "Script '#{script_name}' not found in cluster"
      else
        raise e
      end
    end
  end
end