Add into this folder all painless scripts you want uploaded into the index.
Painless script files must end with the extension .painless

Example:
  my_script.painless
  another_script.painless

Scripts will be uploaded to the index when you run:
  rake schema:painless[index_name]
  rake opensearch:painless[index_name]
  rake elasticsearch:painless[index_name]