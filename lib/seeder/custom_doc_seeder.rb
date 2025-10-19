module SchemaTools::Seeder
  # To add a custom document seeder for a schema, add a file called
  # schemas/{alias_name}/doc_seeder.rb with a class DocSeeder that extends from CustomDocSeeder
  class CustomDocSeeder < BaseDocSeeder
    attr_reader :index_or_alias_name

    def initialize(index_or_alias_name)
      @index_or_alias_name = index_or_alias_name
    end

    def generate_document
      raise NotImplementedError, "Subclasses must implement #generate_document"
    end
  end
end