Gem::Specification.new do |spec|
  spec.name          = "schema-tools"
  spec.version       = "1.0.1"
  spec.authors       = ["Rich Kuzsma"]
  spec.email         = ["rkuzsma@gmail.com"]
  
  spec.summary       = "Schema management tools for OpenSearch and Elasticsearch"
  spec.description   = "Manage Elasticsearch or OpenSearch index schemas and migrations using discplined version controls."
  spec.homepage      = "https://github.com/richkuz/schema-tools"
  spec.license       = "Apache-2.0"
  
  spec.files         = Dir.glob("{lib,bin}/**/*") + %w[README.md LICENSE]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  
  spec.add_dependency "rake", "~> 13.0"
  spec.add_dependency "json", "~> 2.6"
  spec.add_dependency "net-http", "~> 0.3"
  spec.add_dependency "uri", "~> 0.12"
  spec.add_dependency "time", "~> 0.2"
  spec.add_dependency "logger", "~> 1.5"
  
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.19"
  
  spec.required_ruby_version = ">= 3.0"
end