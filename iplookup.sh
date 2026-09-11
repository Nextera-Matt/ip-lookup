#!/bin/bash

# File and Log Paths
CACHE_DIR="${CACHE_DIR:-/tmp/ip_lookup_cache}"  # Allow overriding with env var
LOGFILE="${LOGFILE:-$HOME/ip_lookup.log}"
CACHE_EXPIRATION="${CACHE_EXPIRATION:-86400}"   # Default 24 hours
CSV_MODE=false
VERBOSE=false
CLEAR_CACHE=false
CLEAR_ALL_CACHE=false  # New option to clear entire cache
BASIC=false
DEBUG=false
RDNS=false  # Reverse DNS lookup flag
API="ip-api"  # Default API

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Function to display usage information
display_help() {
    echo -e "Usage: $0 <IP_ADDRESS or DOMAIN_NAME or FILE> [options]"
    echo -e "Options:"
    echo -e "  --api <ip-api|ipinfo>   Choose the API to use (default: ip-api)"
    echo -e "  --basic                 Display basic information (country, city, ISP)"
    echo -e "  --verbose               Show additional details and open location in Google Maps"
    echo -e "  --rdns                  Perform reverse DNS lookup"
    echo -e "  --clear-cache           Clear cached results for the specified IP/Domain"
    echo -e "  --clear-all-cache       Clear the entire cache directory"
    echo -e "  --debug                 Enable debug output for troubleshooting"
    echo -e "  --csv                   Output results in CSV format"
    echo -e "  --cache-expiration <s>  Set custom cache expiration time in seconds"
    echo -e "Example:"
    echo -e "  $0 8.8.8.8 --api ipinfo --basic --verbose"
}

# Function to log messages with color and timestamp
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    case "$level" in
        INFO)    echo -e "$timestamp \033[1;34m[$level]\033[0m $message" ;;
        WARNING) echo -e "$timestamp \033[1;33m[$level]\033[0m $message" ;;
        ERROR)   echo -e "$timestamp \033[1;31m[$level]\033[0m $message" ;;
        DEBUG)   [[ "$DEBUG" = true ]] && echo -e "$timestamp \033[1;36m[$level]\033[0m $message" ;;
        *)       echo "$timestamp [$level] $message" ;;
    esac
}

# Check if curl and jq are installed
for cmd in curl jq dig; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Function to parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --api) API="$2"; shift ;;
            --verbose) VERBOSE=true ;;
            --rdns) RDNS=true ;;  # Enable reverse DNS
            --clear-cache) CLEAR_CACHE=true ;;
            --clear-all-cache) CLEAR_ALL_CACHE=true ;;  # New option
            --basic) BASIC=true ;;
            --debug) DEBUG=true ;;
            --csv) CSV_MODE=true ;;
            --cache-expiration) CACHE_EXPIRATION="$2"; shift ;;
            --help) display_help; exit 0 ;;
            *) QUERY="$1" ;;
        esac
        shift
    done

    if [ -z "$QUERY" ] && [ "$CLEAR_ALL_CACHE" = false ]; then
        log "ERROR" "No IP address, domain, or file specified."
        display_help
        exit 1
    fi
}

# Validate the query (IP or domain)
validate_query() {
    # If query is not an IP, domain, or file, show an error and display the manual
    if [[ -n "$QUERY" && ! "$QUERY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && ! "$QUERY" =~ ^[a-zA-Z0-9.-]+$ && ! -f "$QUERY" ]]; then
        log "ERROR" "Invalid query: $QUERY"
        display_help
        exit 1
    fi

    # Additional validation for ipinfo (only accepts IPs)
    if [[ "$API" == "ipinfo" && ! "$QUERY" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        log "ERROR" "ipinfo.io does not support domain lookups. Please provide a valid IP address."
        display_help
        exit 1
    fi
}

# Parse the provided arguments
parse_args "$@"
validate_query

# Function to clear cache for a specific query
clear_cache() {
    local query="$1"
    local cache_file="$CACHE_DIR/${query}_${API}.json"
    if [ -f "$cache_file" ]; then
        rm -f "$cache_file"
        log "INFO" "Cache cleared for $query"
    else
        log "WARNING" "No cache found for $query to clear."
    fi
}

# Function to clear all cache files
clear_all_cache() {
    if [ -d "$CACHE_DIR" ]; then
        rm -rf "$CACHE_DIR"/*  # Remove all files in the cache directory
        log "INFO" "Entire cache directory cleared."
    else
        log "WARNING" "Cache directory does not exist."
    fi
}

# Handle cache clearing options
if [ "$CLEAR_ALL_CACHE" = true ]; then
    clear_all_cache
    exit 0
fi

if [ "$CLEAR_CACHE" = true ]; then
    clear_cache "$QUERY"
    exit 0
fi

# Check if the input is a file and if it exists
if [ -f "$QUERY" ]; then
    if [ ! -e "$QUERY" ]; then
        log "ERROR" "File $QUERY does not exist. Please check the filename and try again."
        exit 1
    fi
    # Run the script for each IP in the file without printing usage or extra output
    while IFS= read -r line; do
        "$0" "$line" "${@:2}"
    done < "$QUERY"
    exit 0  # Exit the script after processing all lines in the file
fi

# Define cache file for this query
CACHE_FILE="$CACHE_DIR/${QUERY}_${API}.json"

# Function to fetch from cache if available and valid
fetch_from_cache() {
    if [ -f "$CACHE_FILE" ]; then
        CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
        if [ "$CACHE_AGE" -le "$CACHE_EXPIRATION" ]; then
            CACHE_HOURS=$((CACHE_AGE / 3600))
            CACHE_MINUTES=$(( (CACHE_AGE % 3600) / 60 ))
            log "INFO" "Fetching cached result for $QUERY (Cache Age: ${CACHE_HOURS}h ${CACHE_MINUTES}m)"
            JSON_RESPONSE=$(cat "$CACHE_FILE")
            log "DEBUG" "Cached JSON Response: ${JSON_RESPONSE:0:100}... (truncated)"
        else
            log "INFO" "Cache expired for $QUERY. Fetching new data."
            rm -f "$CACHE_FILE"
        fi
    fi
}

# Function to fetch data dynamically and implement failover
fetch_data() {
    # Try fetching from the primary API (ip-api or ipinfo)
    if [ "$API" = "ip-api" ]; then
        if ! fetch_from_ip_api; then
            log "WARNING" "Primary API ip-api failed, falling back to ipinfo"
            API="ipinfo"  # Switch to ipinfo
            fetch_from_ipinfo || {
                log "ERROR" "Both APIs failed. Exiting."
                exit 1
            }
        fi
    elif [ "$API" = "ipinfo" ]; then
        if ! fetch_from_ipinfo; then
            log "WARNING" "Primary API ipinfo failed, falling back to ip-api"
            API="ip-api"  # Switch to ip-api
            fetch_from_ip_api || {
                log "ERROR" "Both APIs failed. Exiting."
                exit 1
            }
        fi
    else
        log "ERROR" "Invalid API specified. Use either 'ip-api' or 'ipinfo'."
        exit 4
    fi
}

# Updated API fetch functions to return a status code for success/failure
fetch_from_ip_api() {
    RESPONSE=$(curl -s -w "\n%{http_code}" "http://ip-api.com/json/$QUERY")
    HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
    JSON_RESPONSE=$(echo "$RESPONSE" | sed '$d')

    log "DEBUG" "HTTP Status from ip-api: $HTTP_STATUS"
    if [ "$HTTP_STATUS" -eq 429 ]; then
        log "WARNING" "Rate limit exceeded for ip-api. Retrying with fallback API."
        return 1  # Failure (indicates a fallback is necessary)
    elif [ "$HTTP_STATUS" -ne 200 ]; then
        log "ERROR" "Failed to retrieve data from ip-api (HTTP $HTTP_STATUS)"
        return 1  # Failure (fallback)
    else
        JSON_RESPONSE=$(echo "$JSON_RESPONSE" | jq '. + {loc: "\(.lat),\(.lon)"}')
        echo "$JSON_RESPONSE" > "$CACHE_FILE"
        return 0  # Success
    fi
}

fetch_from_ipinfo() {
    TOKEN=${IPINFO_TOKEN:-"e26000e849ea98"}
    RESPONSE=$(curl -s -w "\n%{http_code}" "ipinfo.io/$QUERY?token=$TOKEN")
    HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
    JSON_RESPONSE=$(echo "$RESPONSE" | sed '$d')

    log "DEBUG" "HTTP Status from ipinfo: $HTTP_STATUS"
    if [ "$HTTP_STATUS" -eq 429 ]; then
        log "WARNING" "Rate limit exceeded on ipinfo.io. Retrying with fallback API."
        return 1  # Failure (indicates fallback necessary)
    elif [ "$HTTP_STATUS" -ne 200 ]; then
        log "ERROR" "Failed to retrieve data from ipinfo.io (HTTP $HTTP_STATUS)"
        return 1  # Failure (fallback)
    else
        echo "$JSON_RESPONSE" > "$CACHE_FILE"
        return 0  # Success
    fi
}

# Function to perform reverse DNS lookup
perform_rdns_lookup() {
    REVERSE_DNS=$(host "$QUERY" | awk '/domain name pointer/ {print $5}')
    if [ -z "$REVERSE_DNS" ]; then
        log "INFO" "Reverse DNS lookup failed or not available."
        REVERSE_DNS="N/A"
    fi
}

# Fetch data (choose API dynamically)
fetch_from_cache
if [ -z "$JSON_RESPONSE" ]; then
    fetch_data
fi

# Reverse DNS lookup (add result to JSON)
if [ "$RDNS" = true ]; then
    perform_rdns_lookup
    JSON_RESPONSE=$(echo "$JSON_RESPONSE" | jq --arg rdns "$REVERSE_DNS" '. + {reverse_dns: $rdns}')
    if [ "$BASIC" = false ] && [ "$VERBOSE" = false ]; then
        echo "$JSON_RESPONSE" | jq . --color-output
        exit 0  # Exit after displaying reverse DNS only if no other flags (basic/verbose)
    fi
fi

# Log the lookup with status
STATUS=$(echo "$JSON_RESPONSE" | jq -r '.status // "success"')
log "INFO" "Logging lookup for $QUERY with status: $STATUS"
echo -e "$(date)\t$QUERY\t$STATUS\t$API" >> "$LOGFILE"

# Output Based on --basic Flag or CSV Mode
if [ "$CSV_MODE" = true ]; then
    COUNTRY=$(echo "$JSON_RESPONSE" | jq -r '.country // "N/A"')
    CITY=$(echo "$JSON_RESPONSE" | jq -r '.city // "N/A"')
    ISP=$(echo "$JSON_RESPONSE" | jq -r '.org // "N/A"')
    echo "$QUERY,$COUNTRY,$CITY,$ISP"
else
    if [ "$BASIC" = true ]; then
        COUNTRY=$(echo "$JSON_RESPONSE" | jq -r '.country // "Not Available"')
        CITY=$(echo "$JSON_RESPONSE" | jq -r '.city // "Not Available"')
        ISP=$(echo "$JSON_RESPONSE" | jq -r '.org // "Not Available"')
        echo "Country: $COUNTRY"
        echo "City: $CITY"
        echo "ISP: $ISP"
    else
        echo "$JSON_RESPONSE" | jq . --color-output || echo "Error parsing JSON with jq."
    fi
fi

# Open Location in Google Maps if Verbose Flag is Set
LOC=$(echo "$JSON_RESPONSE" | jq -r '.loc // empty')
if [ "$VERBOSE" = true ] && [ -n "$LOC" ]; then
    LAT=$(echo "$LOC" | cut -d ',' -f1)
    LON=$(echo "$LOC" | cut -d ',' -f2)
    if command -v xdg-open &> /dev/null; then
        log "INFO" "Opening location in Google Maps: $LAT, $LON"
        xdg-open "https://maps.google.com/?q=$LAT,$LON"
    else
        log "INFO" "Google Maps link: https://maps.google.com/?q=$LAT,$LON"
    fi
fi
