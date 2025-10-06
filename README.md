# Schemurai - Schema tools for OpenSearch and Elasticsearch

Ruby Rake tasks to manage Elasticsearch or OpenSearch index schemas and migrations using aliases for zero-downtime deployments.

<p align="center">
  <img src="schemurai.png" alt="Schemurai Logo" width="250"/>
</p>

## Features
- Specify index settings and mappings in simple `.json` files.
- Migrate and reindex to a new index with zero downtime using aliases.
- Download schemas from existing aliases or indices.
- Create new aliases with sample schemas.
- Manage painless scripts independently from schema migrations.

## Quick start

Install this Ruby gem.

```sh
gem install schemurai
```

### Configuration

Set the connection URL for your OpenSearch or Elasticsearch instance:

```sh
export OPENSEARCH_URL=http://localhost:9200
# or
export ELASTICSEARCH_URL=https://your-cluster.com
```

For authenticated instances, optionally set username and password:

```sh
export ELASTICSEARCH_USERNAME=your_username
export ELASTICSEARCH_PASSWORD=your_password
# or
export OPENSEARCH_USERNAME=your_username
export OPENSEARCH_PASSWORD=your_password
```

### Download an existing schema

Run `rake schema:download` to download a schema from an existing alias or index:

```sh
$ rake schema:download

# Aliases pointing to 1 index:
#   1. products -> products-20241201120000
#   2. users -> users-20241201120000

# Indexes not part of any aliases:
#   1. old-index
#   2. temp-index

# Please choose an alias or index to download:
# Enter 'alias:<name>' for an alias or 'index:<name>' for an index:
```

The task will generate schema definition files in a folder layout like this:

```
schemas/products                  # Folder name matches the alias name
  settings.json                  # OpenSearch/Elasticsearch index settings
  mappings.json                  # OpenSearch/Elasticsearch index mappings
  reindex.painless              # Optional reindexing data transformation logic
```

### Create a new alias

Run `rake schema:new` to create a new alias with a sample schema:

```sh
$ rake schema:new

# Enter a new alias name:
# products
# ✓ Created index 'products-20241201120000' with alias 'products'
# ✓ Sample schema created at schemas/products
#   - settings.json
#   - mappings.json
```

### Migrate schemas

To migrate your OpenSearch/Elasticsearch indexes to the latest versions defined in the `schemas/` folder:

```sh
rake schema:migrate
```

To migrate a specific alias:

```sh
rake 'schema:migrate[products]'
```

## Directory structure reference

Example directory structure with multiple aliases:

```
schemas/products
  settings.json
  mappings.json
  reindex.painless              # Optional reindexing data transformation logic
schemas/users
  settings.json
  mappings.json
```

Each schema folder name matches the name of an alias. The `schema:migrate` task will:

- Check if the folder name is an alias (not an index)
- Verify the alias points to exactly one index
- Migrate the alias to a new index with updated schema
- Update the alias to point to the new index

### Handle breaking versus non-breaking schema changes

All schema changes are handled the same way - by creating a new index and updating the alias. This ensures zero downtime for all changes, whether breaking or non-breaking.

### Transform data during migration

Change the data when migrating to a new schema via the `reindex.painless` script. For example, when renaming a field, the `reindex.painless` script can specify how to modify data when migrating.

`reindex.painless` runs one time when reindexing into a new index.

### Manage painless scripts

- Download, edit, and upload centrally managed painless scripts.
- Version control painless scripts alongside code
- Manage scripts independently from schema migrations
- Easily sync scripts between different environments
- Track changes to scripts over time

#### Download painless scripts from cluster

To download all painless scripts from a cluster and store them in the `painless_scripts/` directory (configurable via `PAINLESS_SCRIPTS_PATH` environment variable):

```sh
rake painless_scripts:download
```

#### Upload painless scripts to cluster

To upload all `*.painless` script files from the local `painless_scripts` directory into the cluster.

```sh
rake painless_scripts:upload
```

#### Delete a painless script from cluster

To delete a specific painless script from the cluster:

```sh
rake 'painless_scripts:delete[script_name]'
```

This will:
- Delete the specified script from the cluster
- Accept script names with or without the `.painless` extension
- Handle cases where the script doesn't exist gracefully

### Apply a schema change to Staging and Production 

Run GitHub Actions for your branch to prepare a given environment. The actions use the  `migrate` task underneath.

GitHub Actions:
- OpenSearch Staging Migrate
- OpenSearch Production Migrate

#### Migrate with zero downtime

To migrate with zero downtime:
- Run the migration action to reindex data to the new index
- Update your applications to use the new index
- Run `rake schema:catchup` to migrate any new data that came in since the migration last ran

GitHub Actions:
- OpenSearch Staging Catchup
- OpenSearch Production Catchup

### Delete an index

Run `rake 'schema:close[indexname]'` to close an index. This will prevent reads and writes to the index. Verify that the application can operate with the index in a closed state before deleting it.

Run `rake 'schema:delete[indexname]'` to hard-delete an index. For safety, this task only hard-deletes indexes that are closed.

GitHub Actions:
- OpenSearch Staging Close Index
- OpenSearch Production Close Index
- OpenSearch Staging Delete Index
- OpenSearch Production Delete Index

## FAQ

Why does this use index aliases?
- Using aliases enables zero-downtime migrations by allowing applications to continue using the same alias name while the underlying index is updated.
- When migrating to a new index, applications don't need to change their code - they continue using the same alias.
- Aliases can be atomically updated to point to a new index, ensuring no downtime during migrations.