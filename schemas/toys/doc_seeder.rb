require 'securerandom'
require 'time'

# schema:seed invokes this class when seeding test data for this index
class DocSeeder
  def initialize(index_or_alias_name) end
  def generate_document
    return {
      'name' => ['Basketball', 'Football', 'Baseball'].sample,
      'description' => SchemaTools::Seeder::MappingsDocSeeder.generate_text_value,
      'id' => SecureRandom.uuid,
      'created_at' => (Time.now - (365 * 24 * 60 * 60)).iso8601,
      'updated_at' => Time.now.iso8601
    }
  end
end