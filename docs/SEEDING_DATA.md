# Data Seeding Guide

This guide explains how to seed test data into your Elasticsearch/OpenSearch indices for testing long-running reindex operations.

## Quick Start

1. **Ensure OpenSearch/Elasticsearch is running:**
   ```bash
   docker-compose up -d
   ```

2. **Set your connection URL:**
   ```bash
   export OPENSEARCH_URL=http://localhost:9200
   # or
   export ELASTICSEARCH_URL=https://your-cluster.com
   ```

3. **Seed data into an index:**
   ```bash
   ./bin/seed_data products-1 5000
   ```

## Usage

```bash
./bin/seed_data <index_name> [count]
```

### Parameters

- `index_name`: The name of the index to seed (required)
- `count`: Number of documents to create (optional, defaults to 5000)

### Examples

```bash
# Seed 5000 documents (default)
./bin/seed_data products-1

# Seed 10000 documents
./bin/seed_data products-1 10000

# Seed 1000 documents for quick testing
./bin/seed_data products-1 1000
```

## Generated Data

The script generates realistic product data with the following fields:

- **id**: Unique product identifier (`product_1`, `product_2`, etc.)
- **name**: Realistic product names (e.g., "TechCorp Smartphone 1234")
- **description**: Detailed product descriptions
- **price**: Realistic prices based on category
- **category**: Product categories (Electronics, Clothing, Home & Garden, etc.)
- **tags**: Relevant tags for each product
- **created_at**: Random creation date within the last year
- **updated_at**: Random update date within 30 days of creation

## Data Categories

The script generates products across 12 categories:

1. Electronics
2. Clothing
3. Home & Garden
4. Sports & Outdoors
5. Books
6. Toys & Games
7. Health & Beauty
8. Automotive
9. Food & Beverages
10. Office Supplies
11. Jewelry
12. Pet Supplies

## Performance

- **Batch Size**: 1000 documents per batch
- **Rate Limiting**: Small delays between batches to avoid overwhelming the cluster
- **Error Handling**: Comprehensive error checking and reporting
- **Progress Tracking**: Real-time progress updates during seeding

## Testing Reindex Operations

After seeding data, you can test long-running reindex operations:

```bash
# Example: Reindex from products-1 to products-2
rake 'schema:migrate[products-2]'
```

## Verification

Check that your data was seeded successfully:

```bash
# Count documents
curl "http://localhost:9200/products-1/_count"

# View sample document
curl "http://localhost:9200/products-1/_search?size=1"
```

## Troubleshooting

### Connection Issues
- Ensure OpenSearch/Elasticsearch is running
- Verify the connection URL is correct
- Check that the index exists before seeding

### Index Not Found
If you get "Index does not exist" error:
```bash
# Create the index first
rake 'schema:migrate[products-1]'
```

### Bulk Insert Errors
- Check OpenSearch/Elasticsearch logs
- Verify the index mapping matches the generated data
- Ensure sufficient disk space and memory

## Customization

To modify the generated data, edit the `generate_product_document` method in `bin/seed_data`:

- Add new categories in the `categories` array
- Modify price ranges in `generate_realistic_price`
- Update product types in `generate_product_name`
- Customize tags in `generate_tags`