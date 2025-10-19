module SchemaTools::Seeder
  class BaseDocSeeder
    def generate_document
      raise NotImplementedError, "Subclasses must implement #generate_document"
    end
  end
end