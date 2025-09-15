# Getting Started with Schema Tools

This guide will help you get up and running with Schema Tools for OpenSearch and Elasticsearch.

## Prerequisites

- Ruby 3.0 or higher
- Docker and Docker Compose
- Git

## Quick Start

1. **Clone and setup the project:**
   ```bash
   git clone <your-repo-url>
   cd schema-tools
   ./bin/setup
   ```

2. **Start OpenSearch locally:**
   ```bash
   docker-compose up -d
   ```

3. **Verify OpenSearch is running:**
   ```bash
   curl http://localhost:9200
   ```

4. **Run your first migration:**
   ```bash
   rake opensearch:migrate[to_index=products-1]
   ```

5. **Run tests:**
   ```bash
   rake spec
   ```

## Project Structure

```
schema-tools/
├── lib/
│   ├── schema_tools/          # Core library
│   │   ├── client.rb          # OpenSearch/Elasticsearch client
│   │   └── schema_manager.rb  # Schema file management
│   └── tasks/                 # Rake tasks
│       ├── opensearch.rake    # OpenSearch tasks
│       ├── elasticsearch.rake # Elasticsearch aliases
│       └── test.rake          # Test runner
├── schemas/                   # Your schema definitions
├── examples/                 # Example schemas
├── test/                     # Test suite
├── .github/workflows/        # GitHub Actions
└── docker-compose.yml        # Local OpenSearch setup
```

## Available Tasks

### OpenSearch Tasks
- `rake opensearch:migrate[to_index=index_name,dryrun=true]` - Migrate to schema revision
- `rake opensearch:diff[index_name]` - Generate diff between revisions
- `rake opensearch:create[index_name]` - Create index with schema
- `rake opensearch:painless[index_name]` - Upload painless scripts
- `rake opensearch:reindex[index_name]` - Reindex from source index
- `rake opensearch:catchup[index_name]` - Catchup reindex for new documents
- `rake opensearch:softdelete[index_name]` - Soft delete index
- `rake opensearch:delete[index_name]` - Hard delete index (deleted- prefix only)

### Elasticsearch Tasks
All `opensearch:*` tasks have `elasticsearch:*` aliases that work identically.

## Creating Your First Schema

1. **Create the schema directory:**
   ```bash
   mkdir -p schemas/my-index-1/revisions/1/painless_scripts
   ```

2. **Create index.json:**
   ```json
   {
     "index_name": "my-index-1",
     "from_index_name": null
   }
   ```

3. **Create settings.json:**
   ```json
   {
     "index": {
       "number_of_shards": 1,
       "number_of_replicas": 0,
       "refresh_interval": "1s"
     }
   }
   ```

4. **Create mappings.json:**
   ```json
   {
     "properties": {
       "id": { "type": "keyword" },
       "name": { "type": "text" },
       "created_at": { "type": "date" }
     }
   }
   ```

5. **Run the migration:**
   ```bash
   rake opensearch:migrate[to_index=my-index-1]
   ```

## Schema Evolution

### Adding a New Index Version (Requires Reindexing)

When you need to change field types or analyzers:

1. Create a new versioned directory: `schemas/my-index-2/`
2. Set `from_index_name` to the previous version in `index.json`
3. Update your schema files
4. Add a `reindex.painless` script if needed for data transformation
5. Run migration: `rake opensearch:migrate[to_index=my-index-2]`

### Adding a New Revision (No Reindexing Required)

For non-breaking changes like replica count or refresh interval:

1. Create a new revision: `schemas/my-index-1/revisions/2/`
2. Update your schema files
3. Run migration: `rake opensearch:migrate[to_index=my-index-1]`

## Environment Variables

- `OPENSEARCH_URL` - OpenSearch cluster URL (default: http://localhost:9200)
- `ELASTICSEARCH_URL` - Elasticsearch cluster URL (default: http://localhost:9200)
- `SCHEMAS_PATH` - Path to schemas directory (default: schemas)

## GitHub Actions

The project includes GitHub Actions workflows for:
- Staging and Production migrations
- Catchup operations
- Soft and hard deletions

Configure these secrets in your repository:
- `OPENSEARCH_STAGING_URL`
- `OPENSEARCH_PRODUCTION_URL`

## Testing

Run the test suite:
```bash
rake spec
```

The test suite includes:
- Unit tests for core components
- Integration tests simulating complete workflows
- WebMock for HTTP request stubbing

## Troubleshooting

### Common Issues

1. **"Index already exists"** - Use `rake opensearch:softdelete[index_name]` first
2. **"Unable to determine current revision"** - Index was created outside schema tools
3. **Connection refused** - Ensure OpenSearch is running: `docker-compose up -d`

### Debug Mode

Run migrations in dry-run mode to see what would happen:
```bash
rake opensearch:migrate[to_index=my-index,dryrun=true]
```

## Next Steps

- Explore the example schemas in `examples/`
- Read the full README.md for detailed documentation
- Set up GitHub Actions for your deployment pipeline
- Create your own schema definitions following the patterns shown