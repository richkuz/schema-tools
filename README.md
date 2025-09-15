# Schema Tools for OpenSearch and Elasticsearch

An opinionated collection of Ruby Rake tasks and naming conventions for managing Elasticsearch or OpenSearch index schemas and migrations.

Features:
- Specify index settings, mappings, and analyzers in versioned `.json` files.
- Migrate and reindex to a new index with zero downtime without modifying schemas by hand on live instances.
- Audit the trail of index schema changes through index metadata and GitHub Actions.

## Manage schemas

Follow this directory structure to manage schemas.

```
schemas/myindex-1
schemas/myindex-2
schemas/myindex-3
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

The schema folder name should match the name of the index.

### Add a schema change

Always copy and edit a new JSON files to change the schema. Never change an existing JSON file directly.

If your schema change requires reindexing, such as changing a field type or analyzers:

- Add a new versioned index name folder, e.g. `schemas/myindex-2`
- Set `index_name` to e.g. `myindex-2` and `from_index_name` to `myindex-1` in `index.json`
- Modify the `mappings.json`, `settings.json`, and add painless scripts as needed


If your schema change does _not_ require a reindex, such as changing the refresh interval, number of replicas, or boosts:

- Add a new revisions folder to an existing index, e.g. `schemas/myindex-1/revisions/2`
- Modify the `mappings.json`, `settings.json`, and add painless scripts as needed

The `opensearch:migrate` task will alert and exit if you attempt to add a new revision that requires reindexing.

### Migrate to a new schema revision

Run `rake opensearch:migrate[to_index=index_name]` to:
- Migrate to the latest schema revision of `index_name`
- Reindex data as needed
- Upload any painless scripts
- Generate a `diff_output.txt` with changes
- Update index settings  `_meta.schema_tools_revision` with applied revision details

### View which schema revision is applied to an index

The `opensearch:migrate` task writes metadata into index settings to denote the revision. Fetch this metadata via `GET /myindex-1/`:

```
"settings": {
    "index": {
      "_meta": {
        "schema_tools_revision": {
	      "revision": "myindex-2/revisions/1",
	      "revision_applied_at": TIMESTAMP,
	      "revision_applied_by": "...",
	      "reindex_started_at": TIMESTAMP,
	      "reindex_completed_at": TIMESTAMP,
	      "catchup_started_at": TIMESTAMP,
	      "catchup_completed_at": TIMESTAMP,
        }
```

### Transform data during migration

You can change the data itself when migrating to a new schema, for example when renaming a field.

See the examples in `reindex.painless` script. This script runs once when reindexing into a new index.

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

Run `rake opensearch:softdelete` to rename an index to `deleted-$index_name-$timestamp`.

Run `rake opensearch:delete` to hard-delete an index. For safety, this task only hard-deletes indexes with names prefixed with `deleted-`.

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

The `opensearch:*` tasks work the same for Elasticsearch. Create aliases for all `opensearch:*` tasks using `elasticsearch:*` as the prefix.

Provide a `docker-compose.yml` that runs OpenSearch locally. Provide several example schemas. Provide an integration test automation suite.

Underneath, `rake opensearch:migrate[to_index=index_name]` does the following:
- If `index_name` exists and is at the latest revision, this task aborts with a message: `Already at revision ${revision}. To re-create this index and re-migrate, run rake opensearch:softdelete[${index_name}] and then re-run opensearch:migrate[to_index=${index_name}]`.
- If `index_name` exists and does not contain revision details in `_meta.schema_tools_revision`, this task aborts with a message: `Unable to determine the current schema revision of ${index_name}. To re-create this index and re-migrate, run rake opensearch:softdelete[${index_name}] and then re-run opensearch:migrate[to_index=${index_name}]`
- Runs `rake opensearch:diff` to generate a `diff_output.txt` with a readable diff between the schema files at the latest revision and the previous revision. This task does not touch OpenSearch. The only purpose is to ease PR reviews.
- Runs `rake opensearch:create` to create `index_name` in OpenSearch using the associated schema definition, if the index doesn't exist.
- Runs `rake opensearch:painless` to `PUT` any painless scripts defined for `index_name` for this revision.
- If this is a new revision of an existing index:
	- Directly updates the existing index settings.
- If this is the first revision of the index:
	- Runs `rake opensearch:reindex` to reindex `from_index_name` to `index_name`.
	- Applies any `reindex.painless` script.
	- Polls the reindex task ID until reindexing complete.
	- Runs `rake opensearch:catchup` to reindex any documents that came in after the reindex task started.
- Updates the index settings for `_meta.schema_tools_revision` with revision details along the way.
	- `revision_applied_by` can be an optional parameter passed to the task. GitHub Actions should set this to the action run URL.

The `opensearch:diff` task should diff the JSON files intelligently, by ignoring whitespace, sorting keys, and outputting the minimal diff. Also diff any changes to painless scripts in the painless_scripts folder. If a painless script doesn't exist anymore, note this as a diff as well.

The `opensearch:migrate` task should take an optional `dryrun=true` parameter to print out exactly what it will do without actually making any changes to the system.

The GitHub Migrate actions should take as parameter an index name to migrate to. And take a dryrun parameter, default to true. Use ENV variables for the OPENSEARCH_URL. Don't worry about OpenSearch auth for now. It's OK to use:
```
opensearch:
  image: opensearchproject/opensearch:2.19.0
  container_name: opensearch-node
  environment:
    - discovery.type=single-node
    - "DISABLE_INSTALL_DEMO_CONFIG=true"
    - "DISABLE_SECURITY_PLUGIN=true"
    - OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m
```

All functions should be written in a self-documenting way.
Do not add comments.
All functions should be less than 150 lines each.
