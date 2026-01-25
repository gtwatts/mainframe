#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/docker.sh - Docker Helper Functions
# =============================================================================
# Description: Docker container, image, and compose operations via docker CLI
# Requires: docker CLI (not Docker SDK/API)
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_DOCKER_LOADED:-}" ]] && return 0
readonly _MAINFRAME_DOCKER_LOADED=1

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Check if docker CLI is available
_docker_has_cli() {
    command -v docker &>/dev/null
}

# Check if docker-compose or docker compose is available
_docker_has_compose() {
    docker compose version &>/dev/null 2>&1 || command -v docker-compose &>/dev/null
}

# Run docker compose (handles both v1 and v2)
_docker_compose_cmd() {
    if docker compose version &>/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose &>/dev/null; then
        docker-compose "$@"
    else
        return 1
    fi
}

# =============================================================================
# DAEMON STATUS
# =============================================================================

# Check if Docker daemon is running
# Usage: docker_running
# Returns: 0 if Docker daemon is responsive, 1 if not
docker_running() {
    _docker_has_cli || return 1
    docker info &>/dev/null
}

# Get Docker version
# Usage: docker_version
# Returns: Docker version string (e.g., "24.0.7")
docker_version() {
    _docker_has_cli || return 1
    docker version --format '{{.Server.Version}}' 2>/dev/null || \
        docker version 2>/dev/null | grep -m1 'Version:' | awk '{print $2}'
}

# =============================================================================
# CONTAINER OPERATIONS
# =============================================================================

# Check if container exists (running or stopped)
# Usage: docker_container_exists "container_name"
# Returns: 0 if container exists, 1 if not
docker_container_exists() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1
    docker container inspect "$name" &>/dev/null
}

# Check if container is running
# Usage: docker_container_running "container_name"
# Returns: 0 if running, 1 if not
docker_container_running() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    local status
    status=$(docker container inspect -f '{{.State.Running}}' "$name" 2>/dev/null)
    [[ "$status" == "true" ]]
}

# Get container status string
# Usage: docker_container_status "container_name"
# Returns: Status string (running, exited, paused, restarting, dead, created)
docker_container_status() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker container inspect -f '{{.State.Status}}' "$name" 2>/dev/null
}

# Get container ID from name
# Usage: docker_container_id "container_name"
# Returns: Container ID (full or short based on name lookup)
docker_container_id() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker container inspect -f '{{.Id}}' "$name" 2>/dev/null
}

# Get container short ID (12 chars)
# Usage: docker_container_id_short "container_name"
# Returns: 12-character container ID
docker_container_id_short() {
    local name="$1"
    local full_id
    full_id=$(docker_container_id "$name") || return 1
    printf '%s\n' "${full_id:0:12}"
}

# Start a container
# Usage: docker_container_start "container_name"
# Returns: 0 on success, 1 on failure
docker_container_start() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker container start "$name" &>/dev/null
}

# Stop a container
# Usage: docker_container_stop "container_name" [timeout_secs]
# Returns: 0 on success, 1 on failure
docker_container_stop() {
    local name="$1"
    local timeout="${2:-10}"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker container stop -t "$timeout" "$name" &>/dev/null
}

# Restart a container
# Usage: docker_container_restart "container_name" [timeout_secs]
# Returns: 0 on success, 1 on failure
docker_container_restart() {
    local name="$1"
    local timeout="${2:-10}"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker container restart -t "$timeout" "$name" &>/dev/null
}

# Remove a container
# Usage: docker_container_remove "container_name" [force]
# Returns: 0 on success, 1 on failure
docker_container_remove() {
    local name="$1"
    local force="${2:-false}"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    if [[ "$force" == "true" || "$force" == "1" ]]; then
        docker container rm -f "$name" &>/dev/null
    else
        docker container rm "$name" &>/dev/null
    fi
}

# List running containers
# Usage: docker_containers_running
# Returns: Newline-separated list of running container names
docker_containers_running() {
    docker_running || return 1
    docker container ls --format '{{.Names}}' 2>/dev/null
}

# List all containers (including stopped)
# Usage: docker_containers_all
# Returns: Newline-separated list of all container names
docker_containers_all() {
    docker_running || return 1
    docker container ls -a --format '{{.Names}}' 2>/dev/null
}

# =============================================================================
# CONTAINER EXECUTION
# =============================================================================

# Execute command in running container
# Usage: docker_exec "container_name" "command" [args...]
# Returns: Exit code of executed command
docker_exec() {
    local name="$1"
    shift
    local cmd="$*"

    [[ -z "$name" || -z "$cmd" ]] && return 1
    docker_container_running "$name" || return 1

    # Security: use -- separator to prevent option injection
    docker exec -- "$name" sh -c "$cmd"
}

# Execute command interactively in container
# Usage: docker_exec_it "container_name" "command" [args...]
# Returns: Exit code of executed command
docker_exec_it() {
    local name="$1"
    shift
    local cmd="$*"

    [[ -z "$name" || -z "$cmd" ]] && return 1
    docker_container_running "$name" || return 1

    # Security: use -- separator to prevent option injection
    docker exec -it -- "$name" sh -c "$cmd"
}

# =============================================================================
# CONTAINER LOGS
# =============================================================================

# Get container logs
# Usage: docker_logs "container_name" [lines]
# Returns: Container logs (last N lines if specified)
docker_logs() {
    local name="$1"
    local lines="${2:-}"

    [[ -z "$name" ]] && return 1
    docker_container_exists "$name" || return 1

    if [[ -n "$lines" ]]; then
        docker logs --tail "$lines" "$name" 2>&1
    else
        docker logs "$name" 2>&1
    fi
}

# Follow container logs
# Usage: docker_logs_follow "container_name" [lines_to_show_first]
# Note: This blocks - use in background or with timeout
docker_logs_follow() {
    local name="$1"
    local lines="${2:-10}"

    [[ -z "$name" ]] && return 1
    docker_container_running "$name" || return 1

    docker logs -f --tail "$lines" "$name" 2>&1
}

# =============================================================================
# CONTAINER STATS
# =============================================================================

# Get container stats as JSON (snapshot, not streaming)
# Usage: docker_stats_json "container_name"
# Returns: JSON with CPU, memory, network, and I/O stats
docker_stats_json() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_running "$name" || return 1

    docker stats --no-stream --format '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","memory":"{{.MemUsage}}","memory_percent":"{{.MemPerc}}","network":"{{.NetIO}}","block_io":"{{.BlockIO}}","pids":"{{.PIDs}}"}' "$name" 2>/dev/null
}

# Get container CPU usage percentage
# Usage: docker_cpu "container_name"
# Returns: CPU percentage (e.g., "2.50%")
docker_cpu() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_running "$name" || return 1

    docker stats --no-stream --format '{{.CPUPerc}}' "$name" 2>/dev/null
}

# Get container memory usage
# Usage: docker_memory "container_name"
# Returns: Memory usage string (e.g., "150.4MiB / 16GiB")
docker_memory() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_running "$name" || return 1

    docker stats --no-stream --format '{{.MemUsage}}' "$name" 2>/dev/null
}

# Get container memory percentage
# Usage: docker_memory_percent "container_name"
# Returns: Memory percentage (e.g., "1.50%")
docker_memory_percent() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_running "$name" || return 1

    docker stats --no-stream --format '{{.MemPerc}}' "$name" 2>/dev/null
}

# =============================================================================
# CONTAINER INSPECTION
# =============================================================================

# Get container IP address
# Usage: docker_container_ip "container_name" [network]
# Returns: IP address of container
docker_container_ip() {
    local name="$1"
    local network="${2:-bridge}"

    [[ -z "$name" ]] && return 1
    docker_container_running "$name" || return 1

    docker container inspect -f "{{.NetworkSettings.Networks.${network}.IPAddress}}" "$name" 2>/dev/null
}

# Get container ports
# Usage: docker_container_ports "container_name"
# Returns: Port mapping string (e.g., "0.0.0.0:8080->80/tcp")
docker_container_ports() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_exists "$name" || return 1

    docker container inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{$p}}->{{(index $conf 0).HostPort}} {{end}}' "$name" 2>/dev/null
}

# Get container environment variables
# Usage: docker_container_env "container_name"
# Returns: Newline-separated KEY=VALUE pairs
docker_container_env() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_exists "$name" || return 1

    docker container inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$name" 2>/dev/null
}

# Get container labels
# Usage: docker_container_labels "container_name"
# Returns: Newline-separated key=value pairs
docker_container_labels() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_exists "$name" || return 1

    docker container inspect -f '{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println ""}}{{end}}' "$name" 2>/dev/null
}

# Get container image name
# Usage: docker_container_image "container_name"
# Returns: Image name used by container
docker_container_image() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_container_exists "$name" || return 1

    docker container inspect -f '{{.Config.Image}}' "$name" 2>/dev/null
}

# =============================================================================
# IMAGE OPERATIONS
# =============================================================================

# Check if image exists locally
# Usage: docker_image_exists "image:tag"
# Returns: 0 if image exists, 1 if not
docker_image_exists() {
    local image="$1"
    [[ -z "$image" ]] && return 1
    docker_running || return 1

    docker image inspect "$image" &>/dev/null
}

# Get image ID
# Usage: docker_image_id "image:tag"
# Returns: Image ID
docker_image_id() {
    local image="$1"
    [[ -z "$image" ]] && return 1
    docker_running || return 1

    docker image inspect -f '{{.Id}}' "$image" 2>/dev/null
}

# Get image size in bytes
# Usage: docker_image_size "image:tag"
# Returns: Size in bytes
docker_image_size() {
    local image="$1"
    [[ -z "$image" ]] && return 1
    docker_running || return 1

    docker image inspect -f '{{.Size}}' "$image" 2>/dev/null
}

# Get image size (human readable)
# Usage: docker_image_size_human "image:tag"
# Returns: Size string (e.g., "150MB")
docker_image_size_human() {
    local image="$1"
    [[ -z "$image" ]] && return 1
    docker_running || return 1

    docker images --format '{{.Size}}' "$image" 2>/dev/null | head -1
}

# Pull image
# Usage: docker_image_pull "image:tag"
# Returns: 0 on success, 1 on failure
docker_image_pull() {
    local image="$1"
    [[ -z "$image" ]] && return 1
    docker_running || return 1

    docker pull "$image" &>/dev/null
}

# Remove image
# Usage: docker_image_remove "image:tag" [force]
# Returns: 0 on success, 1 on failure
docker_image_remove() {
    local image="$1"
    local force="${2:-false}"
    [[ -z "$image" ]] && return 1
    docker_running || return 1

    if [[ "$force" == "true" || "$force" == "1" ]]; then
        docker rmi -f "$image" &>/dev/null
    else
        docker rmi "$image" &>/dev/null
    fi
}

# List images
# Usage: docker_images
# Returns: Newline-separated list of image:tag strings
docker_images() {
    docker_running || return 1
    docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -v '<none>'
}

# =============================================================================
# PORT OPERATIONS
# =============================================================================

# Check if port is used by Docker (any container)
# Usage: docker_port_used "port"
# Returns: 0 if port is used by Docker, 1 if not
docker_port_used() {
    local port="$1"
    [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]] && return 1
    docker_running || return 1

    docker container ls --format '{{.Ports}}' 2>/dev/null | grep -qE ":${port}->"
}

# Find container using a port
# Usage: docker_port_container "port"
# Returns: Container name using the port
docker_port_container() {
    local port="$1"
    [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]] && return 1
    docker_running || return 1

    docker container ls --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | \
        grep -E ":${port}->" | cut -f1
}

# =============================================================================
# DOCKER COMPOSE OPERATIONS
# =============================================================================

# Check if compose service is running
# Usage: compose_running "service_name" [compose_file]
# Returns: 0 if service is running, 1 if not
compose_running() {
    local service="$1"
    local compose_file="${2:-docker-compose.yml}"

    [[ -z "$service" ]] && return 1
    _docker_has_compose || return 1

    local status
    status=$(_docker_compose_cmd -f "$compose_file" ps -q "$service" 2>/dev/null)
    [[ -n "$status" ]] && docker_container_running "$status"
}

# Get compose service status
# Usage: compose_status "service_name" [compose_file]
# Returns: Status string (running, exited, etc.)
compose_status() {
    local service="$1"
    local compose_file="${2:-docker-compose.yml}"

    [[ -z "$service" ]] && return 1
    _docker_has_compose || return 1

    local container_id
    container_id=$(_docker_compose_cmd -f "$compose_file" ps -q "$service" 2>/dev/null)
    [[ -n "$container_id" ]] && docker_container_status "$container_id"
}

# Execute command in compose service
# Usage: compose_exec "service_name" "command" [compose_file]
# Returns: Exit code of executed command
compose_exec() {
    local service="$1"
    local cmd="$2"
    local compose_file="${3:-docker-compose.yml}"

    [[ -z "$service" || -z "$cmd" ]] && return 1
    _docker_has_compose || return 1

    # Security: use -- separator to prevent option injection
    _docker_compose_cmd -f "$compose_file" exec -T -- "$service" sh -c "$cmd"
}

# Start compose services
# Usage: compose_up [compose_file] [detached]
# Returns: 0 on success, 1 on failure
compose_up() {
    local compose_file="${1:-docker-compose.yml}"
    local detached="${2:-true}"

    _docker_has_compose || return 1

    if [[ "$detached" == "true" || "$detached" == "1" ]]; then
        _docker_compose_cmd -f "$compose_file" up -d &>/dev/null
    else
        _docker_compose_cmd -f "$compose_file" up
    fi
}

# Stop compose services
# Usage: compose_down [compose_file] [remove_volumes]
# Returns: 0 on success, 1 on failure
compose_down() {
    local compose_file="${1:-docker-compose.yml}"
    local remove_volumes="${2:-false}"

    _docker_has_compose || return 1

    if [[ "$remove_volumes" == "true" || "$remove_volumes" == "1" ]]; then
        _docker_compose_cmd -f "$compose_file" down -v &>/dev/null
    else
        _docker_compose_cmd -f "$compose_file" down &>/dev/null
    fi
}

# Get compose logs
# Usage: compose_logs "service_name" [lines] [compose_file]
# Returns: Service logs
compose_logs() {
    local service="$1"
    local lines="${2:-}"
    local compose_file="${3:-docker-compose.yml}"

    [[ -z "$service" ]] && return 1
    _docker_has_compose || return 1

    if [[ -n "$lines" ]]; then
        _docker_compose_cmd -f "$compose_file" logs --tail "$lines" "$service" 2>&1
    else
        _docker_compose_cmd -f "$compose_file" logs "$service" 2>&1
    fi
}

# List compose services
# Usage: compose_services [compose_file]
# Returns: Newline-separated list of service names
compose_services() {
    local compose_file="${1:-docker-compose.yml}"

    _docker_has_compose || return 1
    [[ -f "$compose_file" ]] || return 1

    _docker_compose_cmd -f "$compose_file" config --services 2>/dev/null
}

# =============================================================================
# VOLUME OPERATIONS
# =============================================================================

# Check if volume exists
# Usage: docker_volume_exists "volume_name"
# Returns: 0 if volume exists, 1 if not
docker_volume_exists() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker volume inspect "$name" &>/dev/null
}

# Create volume
# Usage: docker_volume_create "volume_name"
# Returns: 0 on success, 1 on failure
docker_volume_create() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker volume create "$name" &>/dev/null
}

# Remove volume
# Usage: docker_volume_remove "volume_name" [force]
# Returns: 0 on success, 1 on failure
docker_volume_remove() {
    local name="$1"
    local force="${2:-false}"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    if [[ "$force" == "true" || "$force" == "1" ]]; then
        docker volume rm -f "$name" &>/dev/null
    else
        docker volume rm "$name" &>/dev/null
    fi
}

# List volumes
# Usage: docker_volumes
# Returns: Newline-separated list of volume names
docker_volumes() {
    docker_running || return 1
    docker volume ls --format '{{.Name}}' 2>/dev/null
}

# =============================================================================
# NETWORK OPERATIONS
# =============================================================================

# Check if network exists
# Usage: docker_network_exists "network_name"
# Returns: 0 if network exists, 1 if not
docker_network_exists() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker network inspect "$name" &>/dev/null
}

# Create network
# Usage: docker_network_create "network_name" [driver]
# Returns: 0 on success, 1 on failure
docker_network_create() {
    local name="$1"
    local driver="${2:-bridge}"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker network create --driver "$driver" "$name" &>/dev/null
}

# Remove network
# Usage: docker_network_remove "network_name"
# Returns: 0 on success, 1 on failure
docker_network_remove() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    docker_running || return 1

    docker network rm "$name" &>/dev/null
}

# List networks
# Usage: docker_networks
# Returns: Newline-separated list of network names
docker_networks() {
    docker_running || return 1
    docker network ls --format '{{.Name}}' 2>/dev/null
}

# =============================================================================
# CLEANUP OPERATIONS
# =============================================================================

# Remove all stopped containers
# Usage: docker_prune_containers
# Returns: 0 on success
docker_prune_containers() {
    docker_running || return 1
    docker container prune -f &>/dev/null
}

# Remove dangling images
# Usage: docker_prune_images
# Returns: 0 on success
docker_prune_images() {
    docker_running || return 1
    docker image prune -f &>/dev/null
}

# Remove unused volumes
# Usage: docker_prune_volumes
# Returns: 0 on success
docker_prune_volumes() {
    docker_running || return 1
    docker volume prune -f &>/dev/null
}

# Full system prune (containers, images, networks, volumes)
# Usage: docker_prune_all [include_volumes]
# Returns: 0 on success
docker_prune_all() {
    local include_volumes="${1:-false}"
    docker_running || return 1

    if [[ "$include_volumes" == "true" || "$include_volumes" == "1" ]]; then
        docker system prune -af --volumes &>/dev/null
    else
        docker system prune -af &>/dev/null
    fi
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

MAINFRAME_DOCKER_EXPORTS=(
    # Daemon
    docker_running
    docker_version
    # Container operations
    docker_container_exists
    docker_container_running
    docker_container_status
    docker_container_id
    docker_container_id_short
    docker_container_start
    docker_container_stop
    docker_container_restart
    docker_container_remove
    docker_containers_running
    docker_containers_all
    # Container execution
    docker_exec
    docker_exec_it
    # Container logs
    docker_logs
    docker_logs_follow
    # Container stats
    docker_stats_json
    docker_cpu
    docker_memory
    docker_memory_percent
    # Container inspection
    docker_container_ip
    docker_container_ports
    docker_container_env
    docker_container_labels
    docker_container_image
    # Image operations
    docker_image_exists
    docker_image_id
    docker_image_size
    docker_image_size_human
    docker_image_pull
    docker_image_remove
    docker_images
    # Port operations
    docker_port_used
    docker_port_container
    # Docker Compose
    compose_running
    compose_status
    compose_exec
    compose_up
    compose_down
    compose_logs
    compose_services
    # Volume operations
    docker_volume_exists
    docker_volume_create
    docker_volume_remove
    docker_volumes
    # Network operations
    docker_network_exists
    docker_network_create
    docker_network_remove
    docker_networks
    # Cleanup
    docker_prune_containers
    docker_prune_images
    docker_prune_volumes
    docker_prune_all
)
