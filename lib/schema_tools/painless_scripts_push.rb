require 'fileutils'

module SchemaTools
  def self.painless_scripts_push(client:)
    painless_scripts_path = Config.painless_scripts_path
    
    unless Dir.exist?(painless_scripts_path)
      puts "Painless scripts directory #{painless_scripts_path} does not exist."
      return
    end
    
    puts "Pushing all painless scripts from #{painless_scripts_path} to cluster..."
    
    script_files = Dir.glob(File.join(painless_scripts_path, '*.painless'))
    
    if script_files.empty?
      puts "No painless script files found in #{painless_scripts_path}"
      return
    end
    
    script_files.each do |script_file_path|
      script_name = File.basename(script_file_path, '.painless')
      script_content = File.read(script_file_path)
      
      client.put_script(script_name, script_content)
      puts "Pushed script: #{script_name}"
    end
    
    puts "Successfully pushed #{script_files.length} painless script(s) to cluster"
  end
end