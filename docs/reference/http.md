# HTTP Functions

HTTP client, downloads, and URL handling.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## HTTP Functions (http.sh)

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `http_get` | `http_get "url"` | `http_get "http://api.example.com/data"` | Response body |
| `http_post` | `http_post "url" "data"` | `http_post "http://api.example.com" "name=test"` | Response body |
| `http_put` | `http_put "url" "data"` | `http_put "http://api.example.com/1" "{}"` | Response body |
| `http_delete` | `http_delete "url"` | `http_delete "http://api.example.com/1"` | Response body |
| `http_head` | `http_head "url"` | `http_head "http://example.com"` | Headers only |
| `http_json_get` | `http_json_get "url"` | `http_json_get "http://api.example.com"` | JSON response |
| `http_json_post` | `http_json_post "url" "json"` | `http_json_post "$url" '{"name":"test"}'` | JSON response |
| `url_parse` | `url_parse "url"` | `url_parse "http://host:8080/path?q=1"` | Sets URL_* vars |
| `url_encode` | `url_encode "string"` | `url_encode "hello world"` | `hello%20world` |
| `url_decode` | `url_decode "string"` | `url_decode "hello%20world"` | `hello world` |
| `query_string` | `query_string "k=v" "k2=v2"` | `query_string "a=1" "b=2"` | `a=1&b=2` |
| `http_header` | `http_header "name" "value"` | `http_header "Accept" "application/json"` | Header line |
| `http_auth_basic` | `http_auth_basic "user" "pass"` | `http_auth_basic "admin" "secret"` | Auth header |
| `http_auth_bearer` | `http_auth_bearer "token"` | `http_auth_bearer "abc123"` | Auth header |
| `http_status` | `http_status` | `http_status` | `200` (last response) |
| `http_body` | `http_body` | `http_body` | Response body |
| `http_header_get` | `http_header_get "name"` | `http_header_get "Content-Type"` | Header value |
| `http_is_success` | `http_is_success` | `http_is_success && echo "OK"` | (returns 0/1) |

**Note**: Pure bash HTTP only. HTTPS requires openssl.

---

## Download Functions (download.sh)

Universal download helper with fallback chain: burl -> curl -> wget -> fetch

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `download_backend` | `download_backend` | `download_backend` | `curl`, `wget`, `burl`, `fetch`, or `none` |
| `download` | `download "url" [output] [options]` | `download "https://x.com/f.tar.gz"` | `{"ok":true,"file":"f.tar.gz","size":N,"time_ms":N}` |
| `download_stdout` | `download_stdout "url"` | `download_stdout "https://x.com/data"` | (file contents to stdout) |
| `download_progress` | `download_progress "url" "output" [callback]` | `download_progress "https://x.com/f" "/tmp/f" fn` | Calls fn with progress JSON |
| `download_batch` | `download_batch "url_file" "output_dir" [max_parallel]` | `download_batch "urls.txt" "/tmp" 4` | `{"ok":true,"downloaded":N,"failed":N}` |
| `download_resume` | `download_resume "url" "partial_file"` | `download_resume "https://x.com/f" "/tmp/f"` | `{"ok":true,"resumed":true}` |
| `download_verify` | `download_verify "file" "sha256"` | `download_verify "/tmp/f" "abc..."` | `{"ok":true,"valid":true}` |
| `download_extract` | `download_extract "url" "output_dir"` | `download_extract "https://x.com/a.tar.gz" "/opt"` | `{"ok":true,"extracted_to":"/opt","files":N}` |

**Options JSON**: `{"timeout":30,"retries":3,"quiet":true}`

**Supported archive formats** (download_extract): `.tar.gz`, `.tgz`, `.tar.bz2`, `.tbz2`, `.tar.xz`, `.txz`, `.tar`, `.zip`, `.gz`

---

## Quick Patterns

### Simple GET
```bash
response=$(http_get "http://api.example.com/data")
```

### POST JSON
```bash
result=$(http_json_post "http://api.example.com" '{"name":"test"}')
```

### Check Status
```bash
if http_is_success; then
    echo "Request succeeded"
fi
```

### Download Files
```bash
# Simple download (auto-detects curl/wget/fetch)
result=$(download "https://example.com/file.tar.gz")
echo "$result"  # {"ok":true,"file":"file.tar.gz","size":1234,"time_ms":500}

# Download to specific path with options
download "https://example.com/data.zip" "/tmp/data.zip" '{"timeout":60,"retries":5}'

# Download to stdout (pipe-friendly)
download_stdout "https://example.com/config.json" | jq .

# Download with progress callback
download_progress "https://example.com/large.iso" "/tmp/large.iso" my_progress_fn

# Batch download (parallel)
echo "https://a.com/1.txt" > urls.txt
echo "https://b.com/2.txt" >> urls.txt
download_batch "urls.txt" "/tmp/downloads" 4  # 4 parallel

# Resume interrupted download
download_resume "https://example.com/big.file" "/tmp/partial.file"

# Verify checksum after download
download_verify "/tmp/file.tar.gz" "a1b2c3d4e5f6..."

# Download and extract archive
download_extract "https://example.com/app.tar.gz" "/opt/app"
```

---

## Network Scanning (netscan.sh)

Pure-bash network utilities for port checking, host discovery, and banner grabbing.

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `port_check` | `port_check "host" port [timeout]` | `port_check "localhost" 8080` | (returns 0 if open, 1 if closed) |
| `host_alive` | `host_alive "host" [timeout]` | `host_alive "192.168.1.1" 5` | (returns 0 if reachable) |
| `banner_grab` | `banner=$(banner_grab "host" port [timeout])` | `banner_grab "192.168.1.1" 22` | `SSH-2.0-OpenSSH_9.0` |
| `http_headers` | `json=$(http_headers "url" [timeout])` | `http_headers "http://localhost:8080"` | `{"Content-Type":"text/html",...}` |
| `monitor_port` | `json=$(monitor_port "host" port [timeout])` | `monitor_port "localhost" 5432` | `{"host":"localhost","port":5432,"state":"open",...}` |
| `scan_range` | `json=$(scan_range "host" "ports" [timeout])` | `scan_range "localhost" "22,80,443,8080"` | `[{"port":22,"state":"open"},...]` |
| `parse_nmap` | `json=$(parse_nmap < scan.gnmap)` | `nmap -oG - 192.168.1.0/24 \| parse_nmap` | `[{"ip":"192.168.1.1","ports":[...]}]` |

**Port Specifications**: `"22,80,443"` (comma-separated list) or `"1-1024"` (range).

### Quick Patterns (Network)
```bash
# Check if service is ready
if port_check "localhost" 5432; then
    echo "PostgreSQL is accepting connections"
fi

# Wait for service startup
for i in {1..30}; do
    port_check "localhost" 8080 1 && break
    sleep 1
done

# Service discovery
if host_alive "db.internal" 2; then
    banner=$(banner_grab "db.internal" 5432 2)
    echo "Database banner: $banner"
fi

# Quick security scan
result=$(scan_range "server.example.com" "22,80,443,3306,5432,8080")
echo "$result"
```
