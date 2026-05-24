import urllib.request
import json
import time

url = "http://localhost:8080/api/checkout"
data = {
    "items": [
        {
            "item_id": "item-1",
            "quantity": 1
        }
    ]
}
headers = {
    "Content-Type": "application/json",
    "X-Request-Id": "python-load-test"
}

print("Starting python load generator...")
success_count = 0
fail_count = 0

for i in range(50):
    try:
        req = urllib.request.Request(
            url, 
            data=json.dumps(data).encode('utf-8'), 
            headers=headers,
            method='POST'
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            res_body = response.read().decode('utf-8')
            success_count += 1
            print(f"Request {i+1} sent successfully. Response: {res_body}")
    except Exception as e:
        fail_count += 1
        print(f"Request {i+1} failed: {e}")
    time.sleep(0.1)

print(f"Finished. Success: {success_count}, Failures: {fail_count}")
