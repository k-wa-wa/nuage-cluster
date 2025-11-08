curl -k -i -X PUT "https://localhost:9200/reports_index?pretty" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "index.default_pipeline": "_none"
  },
  "mappings": {
    "properties": {
      "report_id": {
        "type": "keyword"
      },
      "report_text": {
        "type": "text"
      },
      "user_id": {
        "type": "keyword"
      },
      "created_at": {
        "type": "date"
      },
      "report_vector": {
        "type": "dense_vector",
        "dims": 768,
        "index": true,
        "similarity": "cosine"
      }
    }
  }
}
' -u "elastic:${ES_PASSWORD}"
