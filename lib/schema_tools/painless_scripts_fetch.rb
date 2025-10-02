require 'fileutils'

module SchemaTools
  def self.painless_scripts_fetch(client:)
    painless_scripts_path = Config.painless_scripts_path
    
    puts "Fetching all painless scripts from cluster..."
    
    scripts = client.get_stored_scripts
    
    if scripts.empty?
      puts "No painless scripts found in cluster."
      return
    end
    
    FileUtils.mkdir_p(painless_scripts_path)
    
    scripts.each do |script_name, script_content|
      script_file_path = File.join(painless_scripts_path, "#{script_name}.painless")
      File.write(script_file_path, script_content)
      puts "Fetched script: #{script_name}"
    end
    
    puts "Successfully fetched #{scripts.length} painless script(s) to #{painless_scripts_path}"
  end
end