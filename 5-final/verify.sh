#!/usr/bin/env bash

function curl_and_assert() {
  local from_ns=$1
  local url=$2
  local expected_http_status=$3
  local expect_ssl=$4

  printf "\nCalling %s\n" "$url"

  curl_result=$(kubectl exec deployment/curl -n "$from_ns" -it -- curl --write-out "%{http_code} | %{ssl_verify_result}" -siv --cacert /tmp/ca.crt --output /dev/null "${url}")

  if [[ $curl_result != *"$expected_http_status"* ]]; then
    echo "⛔️  Call to ${url} did not respond as expected_http_status. Got: ${curl_result}, want: ${expected_http_status}"
    exit 1
  else

    if [[ $expect_ssl == "true" ]]; then
      if [[ $curl_result != *"SSL certificate verify ok"* ]]; then
        echo "⛔️  Call to ${url} could not verify SSL certificate. Got: ${curl_result}, wanted it to contain 'SSL certificate verify ok'"
        exit 1
      fi
      echo "# SSL result is:"
      echo "$curl_result" | grep "subjectAltName"
    fi

    printf "Call to %s succeeded\n" "$url"
  fi
}

echo "📝 Verifying internal encryption"

echo "📝 Checking form same namespace"
curl_and_assert "default" "http://helloworld" "404 Not Found" "false"
curl_and_assert "default" "http://helloworld.default" "200 OK" "false"
curl_and_assert "default" "http://helloworld.default.svc" "200 OK" "false"
curl_and_assert "default" "http://helloworld.default.svc.cluster.local" "200 OK" "false"

curl_and_assert "default" "https://helloworld" "Closing connection" "false"
curl_and_assert "default" "https://helloworld.default" "HTTP/2 200" "true"
curl_and_assert "default" "https://helloworld.default.svc" "HTTP/2 200" "true"
curl_and_assert "default" "https://helloworld.default.svc.cluster.local" "HTTP/2 200" "true"

echo "📝 Checking form other namespace"
curl_and_assert "second" "http://helloworld" "Could not resolve host" "false"
curl_and_assert "second" "http://helloworld.default" "200 OK" "false"
curl_and_assert "second" "http://helloworld.default.svc" "200 OK" "false"
curl_and_assert "second" "http://helloworld.default.svc.cluster.local" "200 OK" "false"

curl_and_assert "second" "https://helloworld" "Could not resolve host" "false"
curl_and_assert "second" "https://helloworld.default" "HTTP/2 200" "true"
curl_and_assert "second" "https://helloworld.default.svc" "HTTP/2 200" "true"
curl_and_assert "second" "https://helloworld.default.svc.cluster.local" "HTTP/2 200" "true"

echo ""
echo "✅  All tests completed successfully"
