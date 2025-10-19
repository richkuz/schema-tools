#!/usr/bin/env ruby

require 'fileutils'
require 'open3'

class GemBumper
  GEMSPEC_FILE = 'schema-tools.gemspec'
  
  def initialize
    @current_version = extract_current_version
    puts "Current version: #{@current_version}"
  end
  
  def run
    puts "🚀 Starting gem bump and publish process..."
    
    bump_version
    build_gem
    publish_gem
    cleanup_gem_files
    
    puts "✅ Successfully bumped to version #{@new_version} and published to RubyGems!"
  end
  
  private
  
  def extract_current_version
    content = File.read(GEMSPEC_FILE)
    match = content.match(/spec\.version\s*=\s*["']([^"']+)["']/)
    raise "Could not find version in #{GEMSPEC_FILE}" unless match
    match[1]
  end
  
  def bump_version
    puts "📈 Bumping version..."
    
    # Parse current version (assuming semantic versioning: major.minor.patch)
    parts = @current_version.split('.').map(&:to_i)
    
    # Bump patch version
    parts[2] += 1
    @new_version = parts.join('.')
    
    puts "Bumping from #{@current_version} to #{@new_version}"
    
    # Update the gemspec file
    content = File.read(GEMSPEC_FILE)
    updated_content = content.gsub(
      /spec\.version\s*=\s*["'][^"']+["']/,
      "spec.version       = \"#{@new_version}\""
    )
    
    File.write(GEMSPEC_FILE, updated_content)
    puts "✅ Updated #{GEMSPEC_FILE} with new version"
  end
  
  def build_gem
    puts "🔨 Building gem..."
    
    # Clean up any existing gem files
    Dir.glob("*.gem").each { |file| File.delete(file) }
    
    # Build the gem
    result = run_command("gem build #{GEMSPEC_FILE}")
    
    unless result[:success]
      puts "❌ Failed to build gem:"
      puts result[:stderr]
      exit 1
    end
    
    @gem_file = "schema-tools-#{@new_version}.gem"
    puts "✅ Built gem: #{@gem_file}"
  end
  
  def publish_gem
    puts "📤 Publishing gem to RubyGems..."
    
    result = run_command("gem push #{@gem_file}")
    
    unless result[:success]
      puts "❌ Failed to publish gem:"
      puts result[:stderr]
      exit 1
    end
    
    puts "✅ Successfully published #{@gem_file} to RubyGems!"
  end
  
  def cleanup_gem_files
    puts "🧹 Cleaning up gem files..."
    
    Dir.glob("*.gem").each do |file|
      File.delete(file)
      puts "Deleted #{file}"
    end
    
    puts "✅ Cleanup complete"
  end
  
  def run_command(command)
    puts "Running: #{command}"
    
    stdout, stderr, status = Open3.capture3(command)
    
    {
      success: status.success?,
      stdout: stdout,
      stderr: stderr
    }
  end
end

# Main execution
if __FILE__ == $0
  begin
    bumper = GemBumper.new
    bumper.run
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end