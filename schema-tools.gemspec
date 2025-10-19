Gem::Specification.new do |spec|
  spec.name          = "schema-tools"
  spec.version       = "1.0.10"
  spec.authors       = ["Rich Kuzsma"]
  spec.email         = ["rkuzsma@gmail.com"]
  
  spec.summary       = "Schema management tools for OpenSearch and Elasticsearch"
  spec.description   = "Manage Elasticsearch or OpenSearch index schemas and migrations using discplined version controls."
  spec.homepage      = "https://github.com/richkuz/schema-tools"
  spec.license       = "Apache-2.0"
  
  spec.files         = Dir.glob("{lib,bin}/**/*") + %w[README.md LICENSE]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  
  spec.add_dependency "rake", ">= 12.0"
  
  spec.add_development_dependency "rspec", ">= 3.0"
  spec.add_development_dependency "webmock", ">= 3.0"
  
  spec.required_ruby_version = ">= 2.7"
end
