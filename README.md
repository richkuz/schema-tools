# Schemurai - Schema tools for OpenSearch and Elasticsearch

Ruby Rake tasks to manage Elasticsearch or OpenSearch index schemas and migrations using discplined version controls.
- Specify index settings, mappings, and analyzers in versioned `.json` files.
- Migrate and reindex to a new index with zero downtime without modifying schemas by hand on live instances.
- Audit the trail of index schema changes through index metadata and GitHub Actions.

<p align="center">
  <img src="schemurai.png" alt="Schemurai Logo" width="250"/>
</p>

## Quick start

```sh
gem install schemurai
```

To migrate your OpenSearch/Elasticsearch indexes to the latest versions defined in the `schemas/` folder:

```sh
rake schema:migrate
```

To define schema files for a new or existing index, run this command and follow the prompts:

```sh
rake schema:define
```

```
Please choose:
1. Define a schema for an index that exists in OpenSearch or Elasticsearch
2. Define an example schema for an index that doesn't exist
3. Define an example schema for a breaking change to an existing schema
4. Define an example schema for a non-breaking change to an existing schema
```

Index names follow the pattern `indexname-$number`, where `$number` increments by 1 for every breaking schema change. The first version of an index does not require a number in the name.

Schema tools do not operate on index aliases.

### Connect to OpenSearch or Elasticsearch

Connect to OpenSearch or Elasticsearch using:

```sh
OPENSEARCH_URL=http://localhost:9200
ELASTICSEARCH_URL=http://localhost:9200
```

Authenticate with:

```sh
OPENSEARCH_USERNAME
OPENSEARCH_PASSWORD
ELASTICSEARCH_USERNAME
ELASTICSEARCH_PASSWORD
```

## Documentation

### Directory structure reference

Example directory structure:

```
schemas/products
schemas/products-2
schemas/users
schemas/users-2
schemas/users-3
  index.json - Specify index_name and from_index_name
  reindex.painless - This script runs once when reindexing
  revisions/1 - Define the index schema
    settings.json
    mappings.json
    painless_scripts/ - Any painless scripts to be PUT into the index
      some_script.painless
    diff_output.txt - Auto-generated diff since from_index_name
  revisions/2 - Apply any additional non-breaking schema changes
    settings.json
    mappings.json
    painless_scripts/
	  some_script.painless
    diff_output.txt - Auto-generated diff since revisions/1
```

The schema folder name must match the name of the index.

The `schema:migrate` task will alert and exit if you attempt to add a new revision to an existing index that would require reindexing.

### Migrate a specific index to the latest version

Run `rake schema:migrate[index=index_name]` to migrate to the latest schema revision of `index_name`.

The `schema:migrate` task will:
- Reindex data as needed
- Upload any painless scripts
- Generate a `diff_output.txt` with changes
- Update index settings  `_meta.schemurai_revision` with applied revision details


### Handle breaking versus non-breaking schema changes

Breaking changes are changes that would require a reindex or have a high risk of breaking an application.

`schema:define` will always propose that breaking changes be defined in a new index. Non-breaking changes will be defined as revisions on an existing index.

When `schema:migrate` updates an existing index, it will try the operation and rely on OpenSearch/Elasticsearch to accept or reject the change. It enforces no judgment of breaking/non-breaking changes on its own.

Breaking changes (require reindex):
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

Breaking changes (does not require a reindex, but still treated as breaking)
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
- Changes/additions/removals of Painless scripts



### View which schema revision is applied to an index

The `schema:migrate` task writes metadata into index settings to denote the revision. Fetch this metadata via `GET /products-2/`:

```
"settings": {
    "index": {
      "_meta": {
        "schemurai_revision": {
          "revision": "products-2/revisions/3",
          "revision_applied_at": TIMESTAMP,
          "revision_applied_by": "...",
          "reindex_started_at": TIMESTAMP,
          "reindex_completed_at": TIMESTAMP,
          "catchup_started_at": TIMESTAMP,
          "catchup_completed_at": TIMESTAMP,
        }
```

### Transform data during migration

Change the data when migrating to a new schema via the `reindex.painless` script. For example, when renaming a field, the `reindex.painless` script can specify how to modify data when migrating. See more examples in the `reindex.painless` script.

`reindex.painless` runs one time when reindexing into a new index.

### Store any painless scripts in the index

Add into the `painless_scripts` folder all painless scripts that should be `PUT` into the index.

Each revision must specify all the painless scripts required, even if they haven't changed.

### Apply a schema change to Staging and Production 

Run GitHub Actions for your branch to prepare a given environment. The actions use the  `migrate` task underneath.

GitHub Actions:
- OpenSearch Staging Migrate
- OpenSearch Production Migrate

#### Migrate with zero downtime

To migrate with zero downtime:
- Run the migration action to reindex data to the new index
- Update your applications to use the new index
- Run `rake opensearch:catchup` to migrate any new data that came in since the migration last ran

GitHub Actions:
- OpenSearch Staging Catchup
- OpenSearch Production Catchup

### Delete an index

Run `rake schema:softdelete` to rename an index to `deleted-$index_name-$timestamp`.

Run `rake schema:delete` to hard-delete an index. For safety, this task only hard-deletes indexes with names prefixed with `deleted-`.

GitHub Actions:
- OpenSearch Staging Soft Delete
- OpenSearch Staging Hard Delete
- OpenSearch Production Soft Delete
- OpenSearch Production Hard Delete


## FAQ

Why doesn't this use index aliases?
- Using an alias circumvents pinning applications to a specific index schema version.
- When migrating to a new index, applications often need to deploy new code to support reading/writing to the new index. Explicit index names enable applications to pin to a specific version of an index and switch to new versions when they are ready.




# Implementation Notes

Instructions for AI:

The rake tasks work the same for Elasticsearch and OpenSearch.

All functions should be written in a self-documenting way.
Do not add comments.
All functions should be less than 150 lines each.




# Test scenarios for AI to consider

### When running rake schema:define

```sh
$ rake schema:define
```

Output:
```
Please choose:
1. Define a schema for an index that exists in OpenSearch or Elasticsearch
2. Define an example schema for an index that doesn't exist
3. Define an example schema for a breaking change to an existing schema
4. Define an example schema for a non-breaking change to an existing schema
```




When a user chooses Option 1: Define a schema for an index that exists in OpenSearch or Elasticsearch, output:

```
Type the name of an existing index in [OpenSearch|Elasticsearch] to define. A version number suffix is not required.
<products>

Checking [$OPENSEARCH_URL|$ELASTICSEARCH_URL] for the latest version of "products"
```

When it cannot connect to OpenSearch or Elasticsearch, output and abort:
```
Failed to connect to [OpenSearch|Elasticsearch] at [$OPENSEARCH_URL|$ELASTICSEARCH_URL]
```

When the specified index is not found with any version number suffix, output and abort:
```
Index "products" not found at [$OPENSEARCH_URL|$ELASTICSEARCH_URL]
```

When the specified index is found, output:
```
Index "products" found at $OPENSEARCH_URL, latest index name is "products-3"
Extracting live settings, mappings, and painless scripts from index "products-3"

Checking schemas/products* for the latest schema definition of "products"
```

When no schema definition is found, output and quit:
```
No schema definition exists for "products-3"

Generated example schema definition files:
schemas/products-3
  index.json
  reindex.painless
  revisions/1
    settings.json
    mappings.json
    painless_scripts/
      example_script.painless
    diff_output.txt

Create this index by running:
$ rake schema:migrate
```

When a schema definition is found, output:
```
Latest schema definition of "products" is defined in schemas/products-3/revisions/2.
```

When the index settings, mappings, and painless scripts match the latest schema, output and quit:
```
Latest schema definition already matches the index.
```

When the index settings and mappings constitute a breaking change from the latest schema, output and quit:

```
Index settings and mappings consitute a breaking change from the latest schema definition.

Generated schema definition files:
schemas/products-4
  index.json
  reindex.painless
  revisions/1
    settings.json
    mappings.json
    painless_scripts/
      example_script.painless
    diff_output.txt

Migrate to this schema definition by running:
$ rake schema:migrate
```

When the index settings and mappings constitute a non-breaking change from the latest schema, output and quit:

```
Index settings and mappings consitute a non-breaking change from the latest schema definition.

Generated schema definition files:
schemas/products-3
  revisions/3
    settings.json
    mappings.json
    painless_scripts/
      example_script.painless
    diff_output.txt

Migrate to this schema definition by running:
$ rake schema:migrate
```




When a user chooses Option 2: Define an example schema for an index that doesn't exist, output:

```
Type the name of a new index to define. A version number suffix is not required.
<products>

Checking schemas/products* for any schema definition of "products"
```

When no schema definition is found, output and quit:
```
No schema definition exists for "products"

Generated example schema definition files:
schemas/products
  index.json
  reindex.painless
  revisions/1
    settings.json
    mappings.json
    painless_scripts/
      example_script.painless
    diff_output.txt

Create this index by running:
$ rake schema:migrate
```

When a schema definition is found, output and quit:
```
Latest schema definition of "products" is defined in schemas/products-3/revisions/2

Create this index by running:
$ rake schema:migrate
```





When a user chooses Option 3: Define an example schema for a breaking change to an existing schema

```
Type the name of an existing schema to change. A version number suffix is not required.
<products>

Checking schemas/products* for the latest schema definition of "products"
```

When no schema definition is found, output and quit:
```
No schema definition exists for "products".
```

When a schema definition is found, output and quit:
```
Latest schema definition of "products" is defined in schemas/products-3/revisions/2

Generated example schema definition files to support a breaking change:
schemas/products-4
  index.json
  reindex.painless
  revisions/1
    settings.json
    mappings.json
    painless_scripts/
      example_script.painless
    diff_output.txt

Migrate to this schema definition by running:
$ rake schema:migrate
```




When a user chooses Option 4: Define an example schema for a non-breaking change to an existing schema

```
Type the name of an existing schema to change. A version number suffix is not required.
<products>

Checking schemas/products* for the latest schema definition of "products"
```

When no schema definition is found, output and quit:
```
No schema definition exists for "products".
```

When a schema definition is found, output and quit:
```
Latest schema definition of "products" is defined in schemas/products-3/revisions/2

Generated example schema definition files to support a non-breaking change:
schemas/products-3
  revisions/3
    settings.json
    mappings.json
    painless_scripts/
      example_script.painless
    diff_output.txt

Migrate to this schema definition by running:
$ rake schema:migrate
```
