# Schemurai - Schema tools for OpenSearch and Elasticsearch

Ruby Rake tasks to manage Elasticsearch or OpenSearch index schemas and migrations using discplined version controls.

<p align="center">
  <img src="schemurai.png" alt="Schemurai Logo" width="250"/>
</p>

## Features
- Specify index settings, mappings, and analyzers in versioned `.json` files.
- Migrate and reindex to a new index with zero downtime without modifying schemas by hand on live instances.
- Audit the trail of index schema changes through index metadata and GitHub Actions.
- Update your local schemas to the latest revisions with one command.

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

Run `rake schema:define` to define your schema as source files. Point at an existing OpenSearch/Elasticsearch index or let the task create examples for you.

```sh
$ rake schema:define

# Please choose:
# 1. Define a schema for an index that exists in OpenSearch or Elasticsearch
# 2. Define an example schema for an index that doesn't exist
# 3. Define an example schema for a breaking change to an existing defined schema
# 4. Define an example schema for a non-breaking change to an existing defined schema
```

The task will generate schema definition files in a folder layout like this:

```
schemas/users                  # Folder name matches the index name
  index.json                   # Specifies index_name and from_index_name
  reindex.painless.            # Optional reindexing data transformation logic
  revisions/1                  # Index schema definition
    settings.json              # OpenSearch/Elasticsearch index settings and analyzers
    mappings.json              # OpenSearch/Elasticsearch index mappings
    diff_output.txt            # Auto-generated diff since from_index_name
```


To migrate your OpenSearch/Elasticsearch indexes to the latest versions defined in the `schemas/` folder:

```sh
rake schema:migrate
```

To seed data from a live index for development or testing:

```sh
rake schema:seed
```

This task will:
- List available live indexes for you to choose from
- Fetch the mappings from the selected index
- Prompt you for the number of documents to seed
- Call the seeding function with the mappings and document count

Use `rake schema:define` to create new schema versions and `rake schema:migrate` to migrate to them.

Index names follow the pattern `indexname-$number`, where `$number` increments by 1 for every breaking schema change. The first version of an index does not require a number in the name.

Schema tools do not operate on index aliases.


## Documentation

### Directory structure reference

Example directory structure with multiple indexes, breaking revisions, and non-breaking revisions.

```
schemas/products
schemas/products-2             # Define breaking changes in new version-numbered index names
schemas/users
schemas/users-2
schemas/users-3
  index.json
  reindex.painless
  revisions/1
    settings.json
    mappings.json
    diff_output.txt            # Auto-generated diff since users-2
  revisions/2                  # Define non-breaking changes as revisions
    settings.json
    mappings.json
    diff_output.txt            # Auto-generated diff since revisions/1
```

The schema folder name matches the name of the index.

The `schema:migrate` task will alert and exit if you attempt to add a new revision to an existing index that would require reindexing.

### Migrate a specific index to the latest version

Run `rake 'schema:migrate[index_name]'` to migrate to the latest schema revision of `index_name`.

The `schema:migrate` task will:
- Reindex data as needed
- Generate a `diff_output.txt` with changes
- Update index mappings `_meta.schemurai_revision` with applied revision details


### Handle breaking versus non-breaking schema changes

Breaking changes are changes that would require a reindex or have a high risk of breaking an application.

`schema:define` will always propose that breaking changes be defined in a new index. Non-breaking changes will be defined as revisions on an existing index.

When `schema:migrate` updates an existing index, it will try the operation and rely on OpenSearch/Elasticsearch to accept or reject the change. It enforces no judgment of breaking/non-breaking changes on its own.

Breaking changes (reindex required):
- Immutable index settings (number_of_shards, index.codec, etc.)
- Analysis settings changes (analyzers, tokenizers, filters, char_filters)
- Dynamic mapping changes (dynamic: true ↔ dynamic: strict)
- Field type changes
- Field analyzer changes (index-time analyzer)
- Immutable field properties:
  - index, store, doc_values, fielddata, norms
  - enabled, format, copy_to, term_vector, index_options
  - null_value, ignore_z_value, precision
- Multi-field subfield removal or changes

Breaking changes (reindex not required, but still considered breaking)
- Removing fields
- Narrowing fields
  - ignore_above (breaking when decreasing, non-breaking when increasing)
  - Date format (breaking when removing formats, non-breaking when adding formats)
  - term_vector
  - Copy from multiple fields to single field
  - Disabling object fields

Non-breaking changes (dynamic updates):
- Mutable index settings (number_of_replicas, refresh_interval)
- Adding new fields
- Adding new subfields
- Adding dynamic mapping settings
- Mutable field properties (boost, search_analyzer, search_quote_analyzer, ignore_malformed)


### View which schema revision is applied to an index

The `schema:migrate` task writes metadata into index mappings to denote the revision. Fetch this metadata via `GET /products-2/`:

```
{
  "index_name": {
    "setting": { ... },
    "mappings": {
      "_meta": {
        "schemurai_revision": {
          "revision": "products-2/revisions/3",
          "revision_applied_at": TIMESTAMP,
          "revision_applied_by": "rake task", # Descriptive name, see Config.SCHEMURAI_USER
          "reindex_started_at": TIMESTAMP,
          "reindex_completed_at": TIMESTAMP,
          "catchup_started_at": TIMESTAMP,
          "catchup_completed_at": TIMESTAMP,
        }
      }
    }
  }
}
```

### Transform data during migration

Change the data when migrating to a new schema via the `reindex.painless` script. For example, when renaming a field, the `reindex.painless` script can specify how to modify data when migrating. See more examples in the `reindex.painless` script.

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

### Generate a diff_output.txt for a given index

The `diff_output.txt` is helpful to see schema change diffs across revisions when opening PRs.

Run `rake 'schema:diff[products-3]'` to generate a new `diff_output.txt` file between the latest revision of `products-3` and the previous revision.

Run `rake 'schema:diff[products-3/revisions/5]'` to generate a new `diff_output.txt` file between revision 5 of `products-3` and the previous revision.

Running `rake schema:migrate` will also generate a `diff_output.txt` for each index it migrates.

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

Why doesn't this use index aliases?
- Using an alias circumvents pinning applications to a specific index schema version.
- When migrating to a new index, applications often need to deploy new code to support reading/writing to the new index. Explicit index names enable applications to pin to a specific version of an index and switch to new versions when they are ready.
