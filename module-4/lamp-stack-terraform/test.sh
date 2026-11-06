for port in $(seq 8080 8089); do
  curl -s http://localhost:$port | head -1
  echo ""
done
