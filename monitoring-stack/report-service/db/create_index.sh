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
      "report_body": {
        "type": "text"
      },
      "report_title": {
        "type": "text"
      },
      "report_type": {
        "type": "keyword"
      },
      "status": {
        "type": "keyword"
      },
      "severity": {
        "type": "keyword"
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
' -u "elastic:t9chq8axfZXZmPp72yclJXM3"
