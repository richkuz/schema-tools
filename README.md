# Schema Tools for OpenSearch and Elasticsearch

## Features
- Specify index settings and mappings in simple `.json` files.
- Migrate and reindex to a new index with zero downtime using aliases.
- Download schemas from existing aliases or indices.
- Create new aliases with sample schemas.
- Manage painless scripts independently from schema migrations.

## Quick start

Install this Ruby gem.

```sh
gem install schema-tools
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
schemas/products         # Folder name matches the alias name
  settings.json          # OpenSearch/Elasticsearch index settings
  mappings.json          # OpenSearch/Elasticsearch index mappings
  reindex.painless       # Optional reindexing data transformation logic
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

### Create a new alias

Run `rake schema:new` to create a new alias with an index and a sample schema:

```sh
$ rake schema:new

# Enter a new alias name:
# products
# ✓ Created index 'products-20241201120000' with alias 'products'
# ✓ Sample schema created at schemas/products
#   - settings.json
#   - mappings.json
```

## Directory structure reference

Example directory structure with multiple aliases:

```
schemas/products
  settings.json
  mappings.json
  reindex.painless    # Optional reindexing data transformation logic
schemas/users
  settings.json
  mappings.json
```

Each schema folder name matches the name of an alias.

## Other settings and tasks

Use `rake schema:seed` to seed an index with sample documents that conform to your schema.

Use `DRYRUN` to simulate but not apply any POST/PUT/DELETE operations to your index:

```
DRYRUN=true rake schema:migrate
```

Use `INTERACTIVE` to prompt to proceed before applying any POST/PUT/DELETE operations to your index:

```
INTERACTIVE=true rake schema:migrate
```


## How migrations work

When possible, `rake schema:migrate` will update settings and mappings in-place on an aliased index, without reindexing. Only breaking changes require a reindex.

Migrating breaking changes requires careful orchestration of reads and writes to ensure documents that are created/updated/deleted during the migration are not lost.

Use case:
- I have an alias `products` pointing at index `products-20250301000000`.
- I have heavy reads and writes with 100M+ documents in the index
- I want to reindex `products-20250301000000` into a new index and update the `products` alias to reference it, without losing any creates/updates/deletes during the process.

Rake `schema:migrate` solves this use case through the following procedure.

First, some terms:
- `alias_name`: Alias containing the index to migrate
	- `products`
- `current_index`: First and only index in the alias
	- `products-20250301000000`
- `new_index`: Final canonical index into which to migrate `current_index`
	- `products-20250601000000`
- `catchup1_index`: Temp index to preserve writes during reindex
	- `products-20250601000000-catchup-1`
- `catchup2_index`: Temp index to preserve writes while flushing `catchup1_index`
	- `products-20250601000000-catchup-2`
- `log_index`: Index to log the migration state, not stored with `alias_name`
	- `products-migration-log-202506010000000`

SETUP

Create `log_index` to log the migration state.
- The migration logs when it starts and completes a step along with a description.

STEP 1

Create `catchup1_index` using the new schema.
- This index will preserve writes during the reindex.

STEP 2

Configure `alias_name` to only write to `catchup1_index` and read from `current_index` and `catchup1_index`.

STEP 3

Create `new_index` using the new schema.

Reindex `current_index` into `new_index`.

```
POST _reindex
{
  "source": { "index": "#{current_index}" },
  "dest": { "index": "#{new_index}" },
  "conflicts": "proceed",
  "refresh": false
}
```

STEP 4

Create `catchup2_index` using the new schema.
- This index ensures a place for ongoing writes while flushing `catchup1_index`.

STEP 5

Configure `alias_name` to only write to `catchup2_index` and continue reading from `current_index` and `catchup1_index`.

STEP 6

Reindex `catchup1_index` into `new_index`.
- Merge the first catchup index into the new canonical index.

STEP 7

Configure `alias_name` so there are NO write indexes
- This guarantees that no writes can sneak into an obsolete catchup index during the second (quick) merge.
- Any write operations will fail during this time with: `"reason": "Alias [FOO] has more than one index associated with it [...], can't execute a single index op"`
- Clients must retry any failed writes.

STEP 8

Reindex `catchup2_index` into `new_index`
- Final sync to merge the second catchup index into the new canonical index.

STEP 9

Configure `alias_name` to write to and read from `new_index` only.
- Writes resume to the single new index. All data and deletes are consistent.

STEP 10

Close unused indexes to avoid accidental writes.
- Close `catchup1_index`
- Close `catchup2_index`
- Close `current_index`
Operation complete.

Users can safely delete closed indexes anytime after they are closed.

Caveats for clients that perform writes during the migration:
- Clients MUST retry failed creates/updates/deletes for up to a minute.
	- Writes will be temporarily disabled for up to a few seconds during the procedure to ensure no data loss.
- Clients MUST use `delete_by_query` when deleting documents to ensure documents are deleted from all indexes in the alias during reindexing.
	- If using `DELETE` to delete a single document from an alias, clients might delete from the wrong index and receive a successful response containing "result: not_found". The new index will _not_ reflect such a deletion.
- Clients MUST read and write to an alias, not directly to an index.
	- To prevent downtime, the migration procedure only operates on aliased indexes.
	- Run `rake schema:alias` to create a new alias pointed at an index.
	- Client applications must read and write to alias_name instead of index_name.

### Diagnosing a failed or aborted migration

If a migration fails or aborts, check status logs in the index named `#{alias_name}-migration-log-#{timestamp}`

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

Run GitHub Actions for your branch to prepare a given environment. The actions use the  `schema:migrate` task underneath.

GitHub Actions:
- OpenSearch Staging Migrate
- OpenSearch Production Migrate

### Delete an index

Run `rake 'schema:close[index_name]'` to close an index. This will prevent reads and writes to the index. Verify that the application can operate with the index in a closed state before deleting it.

Run `rake 'schema:delete[index_name]'` to hard-delete an index. For safety, this task only hard-deletes indexes that are closed.

Run `rake 'schema:close[alias_name]'` to close all indexes in an alias.

Run `rake 'schema:delete[alias_name]'` to delete an alias and leave its indexes untouched.

GitHub Actions:
- OpenSearch Staging Close Index
- OpenSearch Production Close Index
- OpenSearch Staging Delete Index
- OpenSearch Production Delete Index
