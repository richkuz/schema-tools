class DocSeeder
  def initialize(index_or_alias_name)
  end
  def generate_document
    return {
      'name' => ['Basketball', 'Football', 'Baseball'].sample,
      'description' => 'This is a cool toy!'
    }
  end
end