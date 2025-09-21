# Integrating Schema Tools into Your Project

There are several ways to use Schema Tools from another project. Here are the recommended approaches:

## Option 1: Git Submodule (Recommended)

This approach keeps schema tools as a separate repository while allowing you to pin to specific versions.

### Setup

1. **Add as submodule:**
   ```bash
   git submodule add https://github.com/your-org/schema-tools.git vendor/schema-tools
   git submodule update --init --recursive
   ```

2. **Create a wrapper Rakefile in your project:**
   ```ruby
   # Rakefile
   require_relative 'vendor/schema-tools/Rakefile'
   
   # Your project's custom tasks
   namespace :myapp do
     desc "Deploy to staging with schema migration"
     task :deploy_staging, [:index_name] do |t, args|
       puts "Deploying to staging..."
       
      # Run schema migration
      Rake::Task['schema:migrate'].invoke(args[:index_name], 'false', "myapp-deploy-#{ENV['BUILD_NUMBER']}")
       
       # Your deployment logic here
       puts "Deployment complete!"
     end
   end
   ```

3. **Configure environment:**
   ```bash
   # .env or environment variables
   export OPENSEARCH_URL="https://your-opensearch-cluster.com"
   export SCHEMAS_PATH="db/schemas"
   ```

4. **Use in your project:**
  ```bash
  rake 'myapp:deploy_staging[products-v2]'
  rake 'schema:migrate[users-v1]'
  rake 'schema:diff[products-v1]'
  ```

### Benefits
- ✅ Version control for schema tools
- ✅ Easy updates: `git submodule update --remote`
- ✅ Pin to specific versions
- ✅ Clean separation of concerns

## Option 2: Ruby Gem

Package schema tools as a gem for easy distribution.

### Create a gemspec:

```ruby
# schema-tools.gemspec
Gem::Specification.new do |spec|
  spec.name          = "schema-tools"
  spec.version       = "1.0.0"
  spec.authors       = ["Your Team"]
  spec.summary       = "Schema management tools for OpenSearch/Elasticsearch"
  
  spec.files         = Dir.glob("{lib,bin}/**/*") + %w[README.md LICENSE]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  
  spec.add_dependency "rake", "~> 13.0"
  spec.add_dependency "json", "~> 2.6"
  spec.add_dependency "net-http", "~> 0.3"
end
```

### Install in your project:

```ruby
# Gemfile
gem 'schema-tools', path: '../schema-tools'  # Local development
# gem 'schema-tools', '~> 1.0'               # Production
```

```ruby
# Rakefile
require 'schema-tools/rake_tasks'

namespace :myapp do
  desc "Full deployment pipeline"
  task :deploy, [:index_name] do |t, args|
    # Your custom deployment logic
    Rake::Task['schema:migrate'].invoke(args[:index_name])
  end
end
```

## Option 3: Copy and Customize

For projects that need heavy customization of the schema tools.

### Setup

1. **Copy schema tools into your project:**
   ```bash
   cp -r schema-tools/lib/schema_tools myapp/lib/
   cp schema-tools/lib/tasks/opensearch.rake myapp/lib/tasks/
   ```

2. **Customize for your needs:**
   ```ruby
   # lib/tasks/myapp_opensearch.rake
   require 'schema_tools/client'
   require 'schema_tools/schema_manager'
   
   namespace :myapp do
     namespace :opensearch do
       desc "Migrate with custom validation"
       task :migrate_with_validation, [:to_index] do |t, args|
         # Custom pre-migration validation
         puts "Running custom validation..."
         
        # Use schema tools
        Rake::Task['schema:migrate'].invoke(args[:to_index])
         
         # Custom post-migration steps
         puts "Running post-migration tasks..."
       end
     end
   end
   ```

## Option 4: Docker Container

Package schema tools as a Docker container for consistent environments.

### Dockerfile:

```dockerfile
FROM ruby:3.0-alpine

WORKDIR /app
COPY . .

RUN bundle install

ENTRYPOINT ["rake"]
```

### Usage:

```bash
# Build the container
docker build -t schema-tools .

# Run migrations
docker run --rm \
  -v $(pwd)/schemas:/app/schemas \
  -e OPENSEARCH_URL=https://your-cluster.com \
  schema-tools 'schema:migrate[products-v2]'
```

## Recommended Project Structure

```
myapp/
├── Rakefile                 # Wrapper tasks
├── Gemfile                  # Dependencies
├── .env                     # Environment config
├── db/
│   └── schemas/            # Your schema definitions
│       ├── products-v1/
│       └── users-v1/
├── vendor/
│   └── schema-tools/       # Git submodule
└── lib/
    └── tasks/
        └── myapp.rake      # Custom tasks
```

## Environment Configuration

```bash
# .env
OPENSEARCH_URL=https://your-opensearch-cluster.com
ELASTICSEARCH_URL=https://your-elasticsearch-cluster.com
SCHEMAS_PATH=db/schemas
```

## Custom Task Examples

```ruby
# lib/tasks/deployment.rake
namespace :deploy do
  desc "Deploy with zero downtime migration"
  task :zero_downtime, [:index_name] do |t, args|
    index_name = args[:index_name]
    
    puts "Starting zero downtime deployment..."
    
    # 1. Run migration in dry-run first
    Rake::Task['schema:migrate'].invoke(index_name, 'true')
    
    # 2. Run actual migration
    Rake::Task['schema:migrate'].invoke(index_name, 'false', "deploy-#{Time.now.to_i}")
    
    # 3. Update application configuration
    puts "Updating application to use #{index_name}..."
    
    # 4. Run catchup
    Rake::Task['schema:catchup'].invoke(index_name)
    
    puts "Zero downtime deployment complete!"
  end
  
  desc "Rollback to previous index"
  task :rollback, [:current_index] do |t, args|
    current_index = args[:current_index]
    
    # Extract version number and rollback
    if current_index.match(/(.+)-(\d+)$/)
      base_name, version = $1, $2.to_i
      previous_index = "#{base_name}-#{version - 1}"
      
      puts "Rolling back from #{current_index} to #{previous_index}"
      
      # Update application config
      puts "Application rolled back to #{previous_index}"
    end
  end
end
```

## CI/CD Integration

### GitHub Actions:

```yaml
# .github/workflows/deploy.yml
name: Deploy with Schema Migration

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.0'
          bundler-cache: true
      
      - name: Run schema migration
        run: rake 'schema:migrate[products-v2]'
        env:
          OPENSEARCH_URL: ${{ secrets.OPENSEARCH_URL }}
      
      - name: Deploy application
        run: rake 'deploy:zero_downtime[products-v2]'
```

## Best Practices

1. **Use Git Submodules** for most projects - clean and version-controlled
2. **Pin to specific versions** of schema tools for production
3. **Create wrapper tasks** for your specific deployment needs
4. **Use environment variables** for configuration
5. **Test migrations in staging** before production
6. **Document your schema evolution** process
7. **Use dry-run mode** in CI/CD pipelines

## Troubleshooting

### Common Issues:

1. **Submodule not initialized:**
   ```bash
   git submodule update --init --recursive
   ```

2. **Environment variables not set:**
   ```bash
   export OPENSEARCH_URL=https://your-cluster.com
   ```

3. **Schema path not found:**
   ```bash
   export SCHEMAS_PATH=path/to/your/schemas
   ```

4. **Permission issues:**
   ```bash
   chmod +x vendor/schema-tools/bin/setup
   ```