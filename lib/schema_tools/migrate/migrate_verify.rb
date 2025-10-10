require_relative '../diff'

module SchemaTools
  def self.verify_migration(alias_name, client)
    puts "Verifying migration by comparing local schema with remote index..."
    diff_result = Diff.generate_schema_diff(alias_name, client)
    
    if diff_result[:status] == :no_changes
      puts "✓ Migration verification successful - no differences detected"
      puts "Migration completed successfully!"
    else
      puts "⚠️  Migration verification failed - differences detected:"
      puts "-" * 60
      Diff.print_schema_diff(diff_result)
      puts "-" * 60
      raise "Migration verification failed - local schema does not match remote index after migration"
    end
  end
end