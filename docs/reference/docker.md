# Docker Functions

Docker container and image management.

```bash
source "${MAINFRAME_ROOT:-$HOME/.mainframe}/lib/common.sh"
```

---

## Docker Functions (docker.sh)

### Docker Status

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_running` | `docker_running` | `docker_running && echo "OK"` | (returns 0/1) |
| `docker_version` | `docker_version` | `docker_version` | `24.0.7` |

### Container Status

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_container_exists` | `docker_container_exists "name"` | `docker_container_exists "nginx"` | (returns 0/1) |
| `docker_container_running` | `docker_container_running "name"` | `docker_container_running "nginx"` | (returns 0/1) |
| `docker_container_status` | `docker_container_status "name"` | `docker_container_status "nginx"` | `running` |
| `docker_container_id` | `docker_container_id "name"` | `docker_container_id "nginx"` | Full container ID |

### Container Control

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_container_start` | `docker_container_start "name"` | `docker_container_start "nginx"` | (returns 0/1) |
| `docker_container_stop` | `docker_container_stop "name" [timeout]` | `docker_container_stop "nginx" 30` | (returns 0/1) |
| `docker_container_restart` | `docker_container_restart "name"` | `docker_container_restart "nginx"` | (returns 0/1) |
| `docker_container_remove` | `docker_container_remove "name" [force]` | `docker_container_remove "nginx" true` | (returns 0/1) |
| `docker_containers_running` | `docker_containers_running` | `docker_containers_running` | Container names |
| `docker_containers_all` | `docker_containers_all` | `docker_containers_all` | All container names |

### Container Operations

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_exec` | `docker_exec "name" "cmd"` | `docker_exec "nginx" "cat /etc/nginx/nginx.conf"` | Command output |
| `docker_logs` | `docker_logs "name" [lines]` | `docker_logs "nginx" 100` | Container logs |

### Container Stats

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_stats_json` | `docker_stats_json "name"` | `docker_stats_json "nginx"` | JSON stats |
| `docker_cpu` | `docker_cpu "name"` | `docker_cpu "nginx"` | `2.50%` |
| `docker_memory` | `docker_memory "name"` | `docker_memory "nginx"` | `150MiB / 16GiB` |

### Container Info

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_container_ip` | `docker_container_ip "name"` | `docker_container_ip "nginx"` | `172.17.0.2` |
| `docker_container_ports` | `docker_container_ports "name"` | `docker_container_ports "nginx"` | Port mappings |
| `docker_container_env` | `docker_container_env "name"` | `docker_container_env "nginx"` | Environment vars |
| `docker_container_image` | `docker_container_image "name"` | `docker_container_image "nginx"` | `nginx:latest` |

### Image Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_image_exists` | `docker_image_exists "image:tag"` | `docker_image_exists "nginx:latest"` | (returns 0/1) |
| `docker_image_pull` | `docker_image_pull "image:tag"` | `docker_image_pull "nginx:alpine"` | (returns 0/1) |
| `docker_image_remove` | `docker_image_remove "image:tag"` | `docker_image_remove "nginx:old"` | (returns 0/1) |
| `docker_images` | `docker_images` | `docker_images` | Image:tag list |

### Port Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_port_used` | `docker_port_used "port"` | `docker_port_used 8080` | (returns 0/1) |
| `docker_port_container` | `docker_port_container "port"` | `docker_port_container 8080` | Container name |

### Docker Compose

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `compose_running` | `compose_running "service"` | `compose_running "web"` | (returns 0/1) |
| `compose_exec` | `compose_exec "service" "cmd"` | `compose_exec "web" "ls -la"` | Command output |
| `compose_up` | `compose_up [file] [detached]` | `compose_up` | (returns 0/1) |
| `compose_down` | `compose_down [file] [rm_volumes]` | `compose_down` | (returns 0/1) |
| `compose_logs` | `compose_logs "service" [lines]` | `compose_logs "web" 50` | Service logs |
| `compose_services` | `compose_services [file]` | `compose_services` | Service names |

### Volume Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_volume_exists` | `docker_volume_exists "name"` | `docker_volume_exists "data"` | (returns 0/1) |
| `docker_volume_create` | `docker_volume_create "name"` | `docker_volume_create "data"` | (returns 0/1) |
| `docker_volumes` | `docker_volumes` | `docker_volumes` | Volume names |

### Network Management

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_network_exists` | `docker_network_exists "name"` | `docker_network_exists "app-net"` | (returns 0/1) |
| `docker_network_create` | `docker_network_create "name"` | `docker_network_create "app-net"` | (returns 0/1) |
| `docker_networks` | `docker_networks` | `docker_networks` | Network names |

### Cleanup

| Function | Signature | Example | Output |
|----------|-----------|---------|--------|
| `docker_prune_containers` | `docker_prune_containers` | `docker_prune_containers` | Removes stopped |
| `docker_prune_images` | `docker_prune_images` | `docker_prune_images` | Removes dangling |
| `docker_prune_all` | `docker_prune_all [volumes]` | `docker_prune_all true` | Full cleanup |

---

## Quick Patterns

### Check Docker Status
```bash
if docker_running; then
    echo "Docker is running: $(docker_version)"
else
    echo "Docker daemon not available"
fi
```

### Container Management
```bash
# Check and start container
if ! docker_container_running "myapp"; then
    docker_container_start "myapp"
fi

# Get stats
echo "CPU: $(docker_cpu "myapp")"
echo "Memory: $(docker_memory "myapp")"
```

### Docker Compose Workflow
```bash
# Start services
compose_up

# Check service
if compose_running "web"; then
    compose_exec "web" "npm run migrate"
fi

# Get logs
compose_logs "web" 100
```

### Port Conflict Check
```bash
if docker_port_used 8080; then
    container=$(docker_port_container 8080)
    echo "Port 8080 used by: $container"
fi
```

### Cleanup Workflow
```bash
# Remove stopped containers
docker_prune_containers

# Remove unused images
docker_prune_images

# Full cleanup (including volumes)
docker_prune_all true
```
