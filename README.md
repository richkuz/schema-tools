# Schema Tools for OpenSearch and Elasticsearch

## Features
- Specify index settings and mappings in simple `.json` files.
- Migrate and reindex to a new index with zero downtime using aliases.
- Download schemas from existing aliases or indices.
- Create new aliases with sample schemas.
- Manage painless scripts independently from schema migrations.

A sample app that uses schema-tools is available at: https://github.com/richkuz/schema-tools-sample-app

## Quick start

Install this Ruby gem.

```sh
gem install schema-tools
```

Add (or edit) a file called `Rakefile` and add this line:

```ruby
require 'schema_tools'
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

### View available rake tasks

```sh
rake -T | grep " schema:"
```

Available schema tasks:
- `schema:download` - Download schema from an existing alias or index
- `schema:migrate` - Migrate all schemas to match local schema files
- `schema:migrate[alias_name]` - Migrate a specific alias to match its local schema files
- `schema:new` - Create a new alias with sample schema
- `schema:alias` - Create an alias for an existing index
- `schema:diff` - Compare all schemas to their corresponding downloaded alias settings and mappings
- `schema:seed` - Seed data to a live index
- `schema:close[name]` - Close an index or alias
- `schema:delete[name]` - Hard delete an index (only works on closed indexes) or delete an alias
- `schema:drop[alias_name]` - Delete an alias (does not delete the index)

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

## Seed sample data

Use `rake schema:seed` to seed an index with sample documents that conform to your schema.

The seeder can generate sample docs for an index 3 ways:

1. (Default) Mappings-based seeder

The seeder generates random data that conforms to the index's mappings.

2. Sample-based seeder

Add a `sample_docs.json` file in the schema folder with example docs to randomly select from when seeding:

```json
{
  "hits": [
    {
      "_source": {
        "title": "Foo",
        "desc": "Bar"
      }
    },
    ...
  ]
}
```

3. Custom document seeder

Add a `doc_seeder.rb` file in the schema folder with a class DocSeeder

```ruby
# schema:seed invokes this class when seeding test data for this index
class DocSeeder
  def initialize(index_or_alias_name) end
  def generate_document
    return {
      'title' => 'Foo',
      'desc' => 'Bar'
    }
  end
end
```

The seeder first looks for a Custom document seeder. If none found, it falls back to a Sample seeder. If no sample documents found, it falls back to a Mappings seeder.

## Other settings and tasks

Use `DRYRUN` to simulate but not apply any POST/PUT/DELETE operations to your index:

```
DRYRUN=true rake schema:migrate
```

Use `INTERACTIVE` to prompt to proceed before applying any POST/PUT/DELETE operations to your index:

```
INTERACTIVE=true rake schema:migrate
```

Use `REINDEX_BATCH_SIZE` to control the batch size for reindexing operations (default: 1000):

```
REINDEX_BATCH_SIZE=500 rake schema:migrate
```

Use `REINDEX_REQUESTS_PER_SECOND` to throttle reindexing operations (default: -1, no throttling):

```
REINDEX_REQUESTS_PER_SECOND=100 rake schema:migrate
```


## Client responsibilities during breaking migrations

#### Clients MUST retry failed creates/updates/deletes for up to ~ 1 minute.

Writes will be temporarily disabled for a few seconds during the procedure to prevent data loss.

#### Clients MUST read and write to an **alias**. Clients must NOT write directly to an **index**.

To prevent downtime, the migration procedure only operates on aliased indexes.

Run `rake schema:alias` to create a new alias pointed at an index.

#### Hard-deletes during reindexing will NOT affect the migrated index.

Clients can mitigate the lack of hard-delete support two ways:

1. (Recommended) Implement soft-deletes (e.g. set `deleted_at`) with a recurring hard-delete job. Run the hard-delete job after reindexing.

2. Use RBAC to deny all `DELETE` operations during reindexing and implement continuous retries on failed `DELETE` operations to ensure eventual consistency.

#### During reindexing, searches will return **duplicate results** for updated documents.

After reindexing, only the latest update will appear in search results.

Clients can mitigate seeing duplicate documents in two ways:

1. (Recommended) Clients may hide duplicate documents by implementing `collapse` on all searches. `collapse` incurs a small performance cost to each query. Clients may choose to `collapse` only when the alias is configured to read from multiple indices. For a reference implementation of conditionally de-duping using a `collapse` query while reindexing, see: https://github.com/richkuz/schema-tools-sample-app/blob/fc60718f5784e52d55b0c009e863f8b1c8303662/demo_script.rb#L255

2. Use RBAC to deny all `UPDATE` operations during reindexing and implement continuous retries on failed `UPDATE` operations to ensure eventual consistency. This approach is suitable only for clients that can tolerate not seeing documents updated during reindexing.

Why there are duplicate updated documents during reindexing:
- The migration task configures an alias to read from both the original index and a catchup index, and write to the catchup index.
- `UPDATE` operations produce an additional document in the catchup index.
- When clients `_search` the alias for an updated document, they will see two results: one result from the original index, and one result from the catchup index.


#### Theoretical Alternatives for UPDATE and DELETE

In theory, the migrate task could support alternative reindexing modes when constrainted by native Elasticsearch/OpenSearch capabilities.

1. Preserve Hard-Deletes and Show All Duplicates

The migrate task could support clients that require hard-deletes during reindexing by adding the new index into the alias during migration. Clients would have to use `_refresh` and `delete_by_query` when deleting documents to ensure documents are deleted from all indexes in the alias during reindexing. If using `DELETE` to delete a single document from an alias, clients might delete from the wrong index and receive a successful response containing "result: not_found". The new index would _not_ reflect such a deletion. With this approach, clients would see duplicate documents in search results for all documents during reindexing, not just updated documents. Clients could hide duplicate documents by implementing `collapse` on all searches. 

2. Ignore Hard-Deletes and Hide All Duplicates

Some clients might not be able to filter out duplicate documents during reindexing. The migrate task could support such clients by not returning any INSERTED or UPDATED documents until after the reindexing completes. This approach would not support hard-deletes. To support re-updating the same document during reindexing, clients would have to find documents to upsert based on a consistent ID, not based on a changing field.


### Diagnosing a failed or aborted migration

If a migration fails or aborts, check status logs in the index named `#{alias_name}-#{timestamp}-migration-log`

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

Run `rake 'schema:drop[alias_name]'` to delete an alias (does not delete the underlying index).

GitHub Actions:
- OpenSearch Staging Close Index
- OpenSearch Production Close Index
- OpenSearch Staging Delete Index
- OpenSearch Production Delete Index


## How migrations work

When possible, `rake schema:migrate` will update settings and mappings in-place on an aliased index, without reindexing. Only breaking changes require a reindex.

Migrating breaking changes requires careful orchestration of reads and writes to ensure documents that are created/updated during the migration are not lost.

Hard-delete operations are not preserved during a breaking migration. See "Client responsibilities" above for how to mitigate this.

Use case:
- I have an alias `products` pointing at index `products-20250301000000`.
- I have heavy reads and writes with 100M+ documents in the index
- I want to reindex `products-20250301000000` into a new index and update the `products` alias to reference it, without losing any creates/updates during the process.

Rake `schema:migrate` solves this use case through the following procedure.

See: [Migration Procedure Diagram](https://github.com/richkuz/schema-tools/blob/main/docs/schema-tools-migration.svg)

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
	- `products-20250601000000-migration-log`

SETUP

Create `log_index` to log the migration state.
- The migration logs when it starts and completes a step along with a description.

STEP 0

Attempt to reindex 1 document to a throwaway index to catch obvious configuration errors and abort early if possible.

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